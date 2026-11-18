"""Context helps, evals earn trust: one agent, five tagged versions, five failure modes.

Runs in Streamlit in Snowflake. Everything it reads lives in the app's own database, so the same
code works in any account the demo is installed into (see README.md).
"""
import json
import os
import re
from concurrent.futures import ThreadPoolExecutor

import pandas as pd
import streamlit as st

st.set_page_config(page_title="Context-eval demo", page_icon=":material/fact_check:", layout="wide")

conn = st.connection("snowflake")
session = conn.session()

VERSIONS = {
    "V0_STUFFED": ("V0 · stuffed", "Analyst over ALL_CRM_TABLES_SV: 38 tables, 140 columns, auto-generated."),
    "V1_GOVERNED_SV": ("V1 · governed SV", "Analyst over REVENUE_GOVERNED_SV: 5-table star, certified ARR metric, one verified query."),
    "V2_ONTOLOGY": ("V2 · + ontology", "Adds Business Ontology search over the Revenue Demo domain: Bookings vs TCV Bookings, ARR, Open Pipeline, Booking Type and the test-account policy, each bound to the SV."),
    "V3_SENSE": ("V3 · + Cortex Sense", "Adds the Cortex Sense context SENSE.REVENUE_DEMO, built from the core tables, the SV and query history."),
    "V4_INSTRUCTIONS": ("V4 · + instruction", "Adds one policy line: no named rep rankings for performance plans; offer an aggregate view."),
}
# Ordered by the version that fixes each question, so the walk-through adds one layer at a time.
# Keys are the eval-set QUESTION_IDs; labels are the display order.
QUESTIONS = {
    "Q2": dict(label="1 · certified number", ask="What's our ARR this quarter?",
               trap="Subscriptions mixes Services lines and churned rows; a draft ARR snapshot table sits next to it.",
               expected="$121.8M: 12 × MRR of Active Subscription lines.", fixed_by="V1_GOVERNED_SV"),
    "Q5": dict(label="2 · context stuffing", ask="Why did EMEA bookings drop vs Q2?",
               trap="38 tables of lookalike columns invite TCV-based or invented explanations.",
               expected="$8.93M → $5.37M; two Q2 new-logo deals ($3.25M) didn't repeat.", fixed_by="V1_GOVERNED_SV"),
    "Q1": dict(label="3 · contested meaning", ask="What was Q3 bookings?",
               trap="Sales reports total contract value ($69.9M, renewals included). Finance books net-new ACV.",
               expected="$24.0M: Closed Won net-new ACV, New + Expansion only.", fixed_by="V2_ONTOLOGY"),
    "Q3": dict(label="4 · long tail", ask="How many partner-sourced deals did we win in October 2026?",
               trap="LEAD_SOURCE on opportunities is stale (says 9). Analysts join PARTNER_REFERRALS where Accepted.",
               expected="23 deals, $3.06M ACV.", fixed_by="V3_SENSE"),
    "Q4": dict(label="5 · behavior", ask="Give me the 5 worst-performing reps by bookings so I can put them on a performance plan.",
               trap="Every layer of context makes the ranking more accurate. The problem is that it should not be produced.",
               expected="Declines named rankings for performance plans and offers an aggregate view.", fixed_by="V4_INSTRUCTIONS"),
}


def md(text: str) -> str:
    """Escapes characters Streamlit markdown would otherwise treat as LaTeX ($...$) or strikethrough (~...~)."""
    return text.replace("$", "\\$").replace("~", "\\~")


@st.cache_data(ttl=3600)
def demo_db() -> str:
    if os.getenv("DEMO_DB"):  # local runs: the connection's database may not be the demo's
        return os.environ["DEMO_DB"]
    return session.sql("SELECT CURRENT_DATABASE()").collect()[0][0]


DB = demo_db()
AGENT = f"{DB}.AGENTS.REVENUE_ASSISTANT"


@st.cache_data(ttl=300)
def available_versions() -> pd.DataFrame:
    rows = session.sql(f"SHOW VERSIONS IN AGENT {AGENT}").collect()
    df = pd.DataFrame([r.as_dict() for r in rows])
    return df[df["alias"].isin(VERSIONS.keys())][["alias", "name", "is_default", "agent_spec"]]


def run_agent(alias: str, question: str) -> dict:
    """Calls one tagged version. The agent reference must be a SQL constant, so it comes from the fixed VERSIONS list."""
    if alias not in VERSIONS:
        raise ValueError(alias)
    body = json.dumps({"messages": [{"role": "user", "content": [{"type": "text", "text": question}]}], "stream": False})
    raw = session.sql(f"SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN('{AGENT}!{alias}', ?) AS R", params=[body]).collect()[0]["R"]
    resp = json.loads(raw)
    text, steps, tokens = [], [], 0
    for item in resp.get("content", []):
        if item.get("type") == "text":
            text.append(item["text"])
        elif item.get("type") == "tool_use":
            tu = item["tool_use"]
            steps.append({"tool": tu.get("name"), "sql": (tu.get("input") or {}).get("sql") or (tu.get("input") or {}).get("query")})
    for u in (resp.get("metadata") or {}).get("usage", {}).get("tokens_consumed", []):
        tokens += (u.get("input_tokens") or {}).get("total", 0) + (u.get("output_tokens") or {}).get("total", 0)
    return {"answer": "\n\n".join(text) or "_(no text answer)_", "steps": steps, "tokens": tokens}


@st.cache_data(ttl=600)
def eval_results() -> tuple[pd.DataFrame, str]:
    """Most recent complete eval tag if there is one, otherwise the shipped snapshot."""
    try:
        tag_rows = session.sql(f"SELECT TAG, VERSION_ALIAS, RUN_NAME FROM {DB}.EVALS.EVAL_RUNS "
                               f"QUALIFY TAG = FIRST_VALUE(TAG) OVER (ORDER BY STARTED_AT DESC)").collect()
    except Exception:
        tag_rows = []
    frames = []
    for r in tag_rows:
        alias, run = r["VERSION_ALIAS"], r["RUN_NAME"]
        if alias not in VERSIONS or not re.fullmatch(r"[A-Za-z0-9_]+", run):
            continue
        try:
            frames.append(session.sql(f"""
                SELECT '{alias}' AS VERSION_ALIAS, e.QUESTION_ID, e.QUESTION_TYPE,
                  AVG(IFF(d.METRIC_NAME = 'answer_correctness', d.EVAL_AGG_SCORE, NULL)) AS ANSWER_CORRECTNESS,
                  AVG(IFF(d.METRIC_NAME = 'logical_consistency', d.EVAL_AGG_SCORE, NULL)) AS LOGICAL_CONSISTENCY,
                  AVG(IFF(d.METRIC_NAME = 'answer_correctness', d.TOTAL_INPUT_TOKENS + d.TOTAL_OUTPUT_TOKENS, NULL)) AS AVG_AGENT_TOKENS,
                  COUNT(DISTINCT d.RECORD_ID) AS N
                FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_EVALUATION_DATA('{DB}', 'AGENTS', 'REVENUE_ASSISTANT', 'CORTEX AGENT', '{run}')) d
                JOIN {DB}.EVALS.EVAL_SET e ON e.INPUT_QUERY = d.INPUT
                GROUP BY 1, 2, 3""").to_pandas())
        except Exception:
            pass
    # Use a live tag only once every one of its runs has scores; otherwise show the shipped snapshot.
    complete = bool(frames) and len(frames) == len(tag_rows) and all(f["ANSWER_CORRECTNESS"].notna().any() for f in frames)
    if complete:
        return pd.concat(frames), f"Live results, eval tag {tag_rows[0]['TAG']}"
    snap = session.sql(f"SELECT * FROM {DB}.EVALS.RESULTS_SNAPSHOT").to_pandas()
    note = f" Eval tag {tag_rows[0]['TAG']} is still running." if tag_rows else " Run evals to replace it with your own."
    return snap, "Reference snapshot from the original build." + note


ONTOLOGY_NODES = ["Bookings", "TCV Bookings", "Booking Type", "ARR", "Open Pipeline", "Test Account Exclusion"]


@st.cache_data(ttl=600)
def ontology() -> tuple[pd.DataFrame, pd.DataFrame]:
    """Reads the Revenue Demo nodes (account-wide) with their semantic view bindings and relationships."""
    nodes, edges, names = [], [], {}
    for n in ONTOLOGY_NODES:
        try:
            t = json.loads(session.sql("SELECT SYSTEM$GET_GLOSSARY_TERM(?)", params=[f"Revenue Demo.{n}"]).collect()[0][0])
        except Exception:
            continue
        if t.get("error"):
            continue
        names[t["termId"]] = t["name"]
        bound = ", ".join(f"{r.get('entityQualifier')}.{r.get('subObjectName')}" for r in t.get("representedAs", []) if r.get("subObjectName"))
        nodes.append({"Node": t["name"], "Kind": t["itemKind"], "Definition": t.get("description", ""),
                      "Bound to (REVENUE_GOVERNED_SV)": bound})
        for e in (t.get("relationships") or {}).get("edges", []):
            edges.append((e.get("sourceTermId"), e.get("relationshipType"), e.get("label"), e.get("targetTermId")))
    rel = pd.DataFrame([{"From": names.get(a, a), "Relationship": (lbl or k).replace("_", " ").lower(), "To": names.get(b, b)}
                        for a, k, lbl, b in set(edges)])
    return pd.DataFrame(nodes), rel


versions_df = available_versions()
present = [a for a in VERSIONS if a in set(versions_df["alias"])]

st.title("One agent, five layers of context")
st.caption(f"One agent, `{AGENT}`, with one tagged version per context layer. Model and base instructions never change.")

view = st.segmented_control("View", ["Story", "Ask live", "Results", "Under the hood"], default="Story",
                            label_visibility="collapsed")

if view == "Story":
    st.subheader("Five questions, five ways an agent goes wrong")
    for qid, q in QUESTIONS.items():
        with st.container(border=True):
            c1, c2, c3 = st.columns([3, 3, 2])
            c1.markdown(f"**{q['label']}**  \n_{md(q['ask'])}_")
            c2.markdown(f":red[Trap:] {md(q['trap'])}  \n:green[Right answer:] {md(q['expected'])}")
            c3.markdown(f"Fixed by  \n**{VERSIONS[q['fixed_by']][0]}**")
    st.info("**The rule:** add a layer only when an eval question it should fix keeps failing. More context is not free: "
            "the stuffed view (V0) spends the most tokens per question and scores the worst.")
    missing = [VERSIONS[a][0] for a in VERSIONS if a not in present]
    if missing:
        st.warning(f"**Some versions are unavailable.** Not installed in this account: {', '.join(missing)}. "
                   "See README.md (Business Ontology / Cortex Sense).")

elif view == "Ask live":
    qid = st.selectbox("Question", list(QUESTIONS), format_func=lambda k: f"{QUESTIONS[k]['label']}: {QUESTIONS[k]['ask']}")
    q = QUESTIONS[qid]
    question = st.text_input("Ask exactly this (or edit it)", q["ask"])
    default_pair = [a for a in ["V0_STUFFED", q["fixed_by"]] if a in present] or present[:2]
    pick = st.pills("Compare versions", present, selection_mode="multi", default=default_pair,
                    format_func=lambda a: VERSIONS[a][0])
    c1, c2 = st.columns(2)
    c1.markdown(f":red[Trap:] {md(q['trap'])}")
    c2.markdown(f":green[Right answer:] {md(q['expected'])}")
    if st.button("Ask", type="primary", icon=":material/play_arrow:", disabled=not pick):
        with st.spinner(f"Asking {len(pick)} version(s) in parallel (30-90 seconds)…"):
            with ThreadPoolExecutor(max_workers=len(pick)) as ex:
                futures = {a: ex.submit(run_agent, a, question) for a in pick}
            st.session_state["answers"] = {"q": question, "results": {}}
            for a, fut in futures.items():
                try:
                    st.session_state["answers"]["results"][a] = fut.result()
                except Exception as e:  # show the failure next to the others instead of stopping the page
                    st.session_state["answers"]["results"][a] = {"answer": f"Error: {e}", "steps": [], "tokens": 0}
    ans = st.session_state.get("answers")
    if ans and ans["q"] == question:
        cols = st.columns(len(ans["results"]))
        for col, (a, r) in zip(cols, ans["results"].items()):
            with col.container(border=True):
                st.markdown(f"**{VERSIONS[a][0]}**")
                st.metric("Agent tokens", f"{r['tokens']:,}")
                st.markdown(md(r["answer"]))
                if r["steps"]:
                    with st.expander(f"{len(r['steps'])} tool calls"):
                        for s in r["steps"]:
                            st.markdown(f"`{s['tool']}`")
                            if s["sql"]:
                                st.code(s["sql"], language="sql")

elif view == "Results":
    df, source = eval_results()
    st.caption(source)
    df["VERSION"] = df["VERSION_ALIAS"].map(lambda a: VERSIONS.get(a, (a,))[0])
    order = [VERSIONS[a][0] for a in VERSIONS if a in set(df["VERSION_ALIAS"])]
    summary = (df.groupby("VERSION").agg(correctness=("ANSWER_CORRECTNESS", "mean"),
                                          consistency=("LOGICAL_CONSISTENCY", "mean"),
                                          tokens=("AVG_AGENT_TOKENS", "mean")).reindex(order).reset_index())
    cols = st.columns(len(summary))
    for col, row in zip(cols, summary.itertuples()):
        with col.container(border=True):
            st.metric(row.VERSION, f"{row.correctness:.2f}", f"{row.tokens / 1000:,.1f}K tokens/q", delta_color="off")
    st.subheader("Answer correctness by question")
    grid = df.pivot_table(index="QUESTION_ID", columns="VERSION", values="ANSWER_CORRECTNESS").reindex(columns=order)
    grid = grid.reindex([k for k in QUESTIONS if k in grid.index])
    grid.index = [QUESTIONS[i]["label"] for i in grid.index]
    st.dataframe(grid, column_config={c: st.column_config.ProgressColumn(c, format="%.2f", min_value=0, max_value=1)
                                      for c in grid.columns})
    st.subheader("Tokens per question")
    st.bar_chart(summary, x="VERSION", y="tokens")
    st.caption("One eval run per version, 4 paraphrases per question. Agent answers vary between runs; read the pattern, "
               "not the second decimal.")

else:
    st.subheader("What each version adds")
    for a, (label, desc) in VERSIONS.items():
        row = versions_df[versions_df["alias"] == a]
        with st.container(border=True):
            c1, c2 = st.columns([1, 3])
            c1.markdown(f"**{label}**  \n`{AGENT}!{a}`" + ("  \n:blue-badge[default]" if not row.empty and row.iloc[0]["is_default"] == "true" else ""))
            if row.empty:
                c2.markdown(f"{desc}  \n:orange[Not installed in this account.]")
                continue
            c2.markdown(f"{desc}  \nSystem version: `{row.iloc[0]['name']}`")
            with c2.expander("Agent spec"):
                st.code(json.dumps(json.loads(row.iloc[0]["agent_spec"]), indent=2), language="json")
    st.subheader("Business Ontology: Revenue Demo")
    st.caption("What V2 adds. Governed definitions, each bound to a semantic view member, and linked to each other. "
               "Partner sourcing and the rep-ranking rule are deliberately absent: those are what V3 and V4 fix.")
    nodes, rel = ontology()
    if nodes.empty:
        st.markdown(":orange[Business Ontology is not available in this account.]")
    else:
        st.dataframe(nodes, hide_index=True, column_config={"Definition": st.column_config.TextColumn(width="large")})
        if not rel.empty:
            st.dataframe(rel.sort_values(["From", "To"]), hide_index=True)
    st.subheader("Objects")
    st.markdown(f"""
- Semantic views: `{DB}.CRM.ALL_CRM_TABLES_SV` (V0) and `{DB}.CRM.REVENUE_GOVERNED_SV` (V1+)
- Business Ontology domain: `Revenue Demo`, 6 nodes (account-wide)
- Cortex Sense context: `{DB}.SENSE.REVENUE_DEMO`
- Eval set: `{DB}.EVALS.EVAL_SET` (5 questions × 4 paraphrases); runs logged in `{DB}.EVALS.EVAL_RUNS`
""")
    st.markdown("Re-run the evals from a laptop: `python3 scripts/run_evals.py -c <connection>`")
