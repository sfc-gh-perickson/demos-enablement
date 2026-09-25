"""AI Gateway Monitoring — Streamlit app with 4 tabs."""

import json
import streamlit as st
import plotly.express as px
import snowflake.connector
from pathlib import Path
import toml

import queries

# ---------------------------------------------------------------------------
# Connection
# ---------------------------------------------------------------------------

@st.cache_resource
def get_connection():
    cfg_path = Path.home() / ".snowflake" / "connections.toml"
    if not cfg_path.exists():
        cfg_path = Path.home() / ".snowflake" / "cortex" / "agent" / "connections.toml"
    cfg = toml.load(cfg_path)["parker_demo"]
    return snowflake.connector.connect(
        account=cfg["account"],
        user=cfg["user"],
        authenticator="externalbrowser",
        warehouse=cfg.get("warehouse", "GATEWAY_LAB_WH"),
        database=cfg.get("database", "CORTEX_GATEWAY_LAB"),
        schema=cfg.get("schema", "PUBLIC"),
    )

# ---------------------------------------------------------------------------
# Page config
# ---------------------------------------------------------------------------

st.set_page_config(page_title="AI Gateway Monitor", layout="wide")
st.title("AI Gateway Monitor")

conn = get_connection()

tab1, tab2, tab3, tab4 = st.tabs([
    "Overview Dashboard",
    "Agent Explorer",
    "Topic Mining & Search",
    "Conversation Inspector",
])

# ===== Tab 1: Overview Dashboard ==========================================
with tab1:
    days = st.slider("Lookback (days)", 1, 30, 7, key="overview_days")

    kpi = queries.kpi_summary(conn, days)
    credits_df = queries.estimated_credits(conn, days)

    if not kpi.empty:
        c1, c2, c3, c4, c5 = st.columns(5)
        c1.metric("Total Requests", f"{int(kpi.iloc[0]['TOTAL_REQUESTS']):,}")
        c2.metric("Unique Traces", f"{int(kpi.iloc[0]['UNIQUE_TRACES']):,}")
        c3.metric("Models Used", int(kpi.iloc[0]["MODELS_USED"]))
        c4.metric("Credits", f"{float(credits_df.iloc[0]['TOTAL_CREDITS']):.4f}")
        fb = queries.feedback_summary(conn, days)
        if not fb.empty:
            pos = int(fb["POSITIVE"].sum())
            neg = int(fb["NEGATIVE"].sum())
            c5.metric("Feedback", f"+{pos} / -{neg}")

    # Requests per hour
    rph = queries.requests_per_hour(conn, days)
    if not rph.empty:
        fig = px.line(
            rph, x="HOUR", y="REQUEST_COUNT", color="MODEL",
            title="Requests per Hour by Model",
        )
        st.plotly_chart(fig, use_container_width=True)

    # Requests by agent
    rba = queries.requests_by_agent(conn, days)
    if not rba.empty:
        col_left, col_right = st.columns(2)
        with col_left:
            fig2 = px.bar(
                rba, x="AGENT_NAME", y="REQUEST_COUNT", color="MODEL",
                title="Requests by Agent",
            )
            st.plotly_chart(fig2, use_container_width=True)
        with col_right:
            st.subheader("Per-Agent Summary")
            display_cols = [
                "AGENT_NAME", "MODEL", "REQUEST_COUNT",
                "AVG_INPUT_TOKENS", "AVG_OUTPUT_TOKENS",
                "TOTAL_INPUT_TOKENS", "TOTAL_OUTPUT_TOKENS",
            ]
            st.dataframe(rba[[c for c in display_cols if c in rba.columns]], hide_index=True)
    else:
        st.info("No agent data found. Run simulate.py first to populate gateway traces.")

# ===== Tab 2: Agent Explorer ===============================================
with tab2:
    agents_df = queries.agent_list(conn)
    if agents_df.empty:
        st.info("No agents registered. Run simulate.py to create agent mappings.")
    else:
        agent_name = st.selectbox(
            "Select Agent",
            agents_df["AGENT_NAME"].tolist(),
            key="agent_select",
        )
        days2 = st.slider("Lookback (days)", 1, 30, 7, key="explorer_days")

        # Model usage
        mu = queries.agent_model_usage(conn, agent_name, days2)
        if not mu.empty:
            col1, col2 = st.columns(2)
            with col1:
                fig = px.pie(mu, names="MODEL", values="REQUEST_COUNT", title="Model Usage")
                st.plotly_chart(fig, use_container_width=True)
            with col2:
                st.dataframe(mu, hide_index=True)

        # Token trend
        tt = queries.agent_token_trend(conn, agent_name, days2)
        if not tt.empty:
            fig = px.line(
                tt, x="HOUR", y=["INPUT_TOKENS", "OUTPUT_TOKENS"],
                title=f"Token Trend — {agent_name}",
            )
            st.plotly_chart(fig, use_container_width=True)

        # Tool usage
        tu = queries.agent_tool_usage(conn, agent_name, days2)
        if not tu.empty:
            fig = px.bar(tu, x="TOOL_NAME", y="CALL_COUNT", title="Tool Usage")
            st.plotly_chart(fig, use_container_width=True)
        else:
            st.caption("No tool calls recorded for this agent.")

        # Credit spend
        cs = queries.agent_credit_spend(conn, days2)
        if not cs.empty:
            st.subheader("Credit Spend (all agents)")
            st.dataframe(cs, hide_index=True)

        # Top users
        tu_users = queries.top_users(conn, days2)
        if not tu_users.empty:
            st.subheader("Top Users")
            st.dataframe(tu_users, hide_index=True)

        # Feedback
        fb_detail = queries.feedback_detail(conn, agent_name, days2)
        if not fb_detail.empty:
            st.subheader("Feedback")
            pos_count = int((fb_detail["IS_POSITIVE"] == True).sum())
            neg_count = int((fb_detail["IS_POSITIVE"] == False).sum())
            fc1, fc2 = st.columns(2)
            fc1.metric("Positive", pos_count)
            fc2.metric("Negative", neg_count)
            for _, row in fb_detail.iterrows():
                icon = "+" if row["IS_POSITIVE"] else "-"
                with st.expander(f"[{icon}] {row['USER_MESSAGE'][:100]}"):
                    st.markdown(f"**Feedback:** {row['FEEDBACK_MESSAGE']}")
                    st.markdown(f"**Trace:** `{row['TRACE_ID']}`")
                    st.markdown(f"**Time:** {row['CREATED_AT']}")
        else:
            st.caption("No feedback recorded for this agent.")

# ===== Tab 3: Topic Mining & Search ========================================
with tab3:
    days3 = st.slider("Lookback (days)", 1, 30, 7, key="topic_days")

    queries.ensure_topic_cache_table(conn)

    msgs = queries.all_user_messages(conn, days3)
    if msgs.empty:
        st.info("No user messages found in traces.")
    else:
        # De-duplicate: same trace may repeat the user message across spans
        msgs = msgs.drop_duplicates(subset=["TRACE_ID", "USER_MESSAGE"])

        # Load cached topics
        cached = queries.cached_topics(conn)
        cached_lookup = {}
        if not cached.empty:
            cached_lookup = dict(zip(
                zip(cached["TRACE_ID"], cached["USER_MESSAGE"]),
                cached["TOPIC"],
            ))

        # Classify button
        uncached = msgs[
            ~msgs.apply(lambda r: (r["TRACE_ID"], r["USER_MESSAGE"]) in cached_lookup, axis=1)
        ]
        if not uncached.empty:
            if st.button(f"Classify {len(uncached)} uncategorized messages"):
                bar = st.progress(0)
                for i, (_, row) in enumerate(uncached.iterrows()):
                    result = queries.classify_topic(conn, row["USER_MESSAGE"])
                    topic = result.iloc[0]["TOPIC"].strip().lower() if not result.empty else "out_of_scope"
                    queries.insert_topic_cache(conn, row["TRACE_ID"], row["USER_MESSAGE"], topic)
                    cached_lookup[(row["TRACE_ID"], row["USER_MESSAGE"])] = topic
                    bar.progress((i + 1) / len(uncached))
                st.rerun()

        # Merge topics into messages
        msgs["TOPIC"] = msgs.apply(
            lambda r: cached_lookup.get((r["TRACE_ID"], r["USER_MESSAGE"]), "unclassified"),
            axis=1,
        )

        # Topic distribution chart
        topic_counts = msgs.groupby(["AGENT_NAME", "TOPIC"]).size().reset_index(name="COUNT")
        if not topic_counts.empty:
            fig = px.bar(
                topic_counts, x="AGENT_NAME", y="COUNT", color="TOPIC",
                title="Topic Distribution by Agent", barmode="stack",
            )
            st.plotly_chart(fig, use_container_width=True)

        # Search box
        search = st.text_input("Search user messages", key="topic_search")
        filtered = msgs
        if search:
            filtered = msgs[msgs["USER_MESSAGE"].str.contains(search, case=False, na=False)]

        st.subheader(f"User Messages ({len(filtered)} rows)")
        for _, row in filtered.iterrows():
            with st.expander(f"[{row['AGENT_NAME']}] {row['USER_MESSAGE'][:120]}"):
                st.markdown(f"**Trace:** `{row['TRACE_ID']}`")
                st.markdown(f"**Topic:** {row['TOPIC']}")
                st.markdown(f"**Timestamp:** {row['TIMESTAMP']}")

# ===== Tab 4: Conversation Inspector =======================================
with tab4:
    agents_df2 = queries.agent_list(conn)
    if agents_df2.empty:
        st.info("No agents registered. Run simulate.py first.")
    else:
        agent4 = st.selectbox(
            "Select Agent",
            agents_df2["AGENT_NAME"].tolist(),
            key="inspector_agent",
        )
        days4 = st.slider("Lookback (days)", 1, 30, 7, key="inspector_days")

        traces = queries.agent_traces(conn, agent4, days4)
        if traces.empty:
            st.info("No traces found for this agent in the selected timeframe.")
        else:
            trace_options = [
                f"{row['TRACE_ID']} ({row['SPAN_COUNT']} spans, {row['FIRST_TS']})"
                for _, row in traces.iterrows()
            ]
            selected = st.selectbox("Select Trace", trace_options, key="trace_select")
            trace_id = selected.split(" ")[0]

            detail = queries.trace_detail(conn, trace_id)
            if not detail.empty:
                # Metadata sidebar
                with st.sidebar:
                    st.subheader("Trace Metadata")
                    st.markdown(f"**Trace ID:** `{trace_id}`")
                    st.markdown(f"**Spans:** {len(detail)}")
                    if len(detail) > 1:
                        st.markdown("*Multi-step reasoning detected*")
                    for _, span in detail.iterrows():
                        with st.expander(f"Span {span['SPAN_ID'][:8]}..."):
                            st.markdown(f"- Model: `{span['MODEL']}`")
                            st.markdown(f"- Tokens: {span['INPUT_TOKENS']} in / {span['OUTPUT_TOKENS']} out")
                            st.markdown(f"- Latency: {span['LATENCY_SEC']:.2f}s" if span["LATENCY_SEC"] else "- Latency: N/A")
                            st.markdown(f"- HTTP: {span['HTTP_STATUS']}")
                            st.markdown(f"- Status: {span['STATUS_CODE']}")

                # Conversation chain
                st.subheader(f"Conversation Chain — {len(detail)} gateway call(s)")
                for idx, (_, span) in enumerate(detail.iterrows()):
                    st.markdown(f"### Gateway Call {idx + 1}  ({span['INPUT_TOKENS']} in / {span['OUTPUT_TOKENS']} out)")

                    # Parse input messages
                    if span["INPUT_MESSAGES"]:
                        try:
                            in_msgs = json.loads(span["INPUT_MESSAGES"])
                            for m in in_msgs:
                                role = m.get("role", "?")
                                for p in m.get("parts", []):
                                    if "content" in p:
                                        icon = {"user": ":bust_in_silhouette:", "assistant": ":robot_face:", "tool": ":wrench:"}.get(role, ":grey_question:")
                                        st.markdown(f"{icon} **{role}**: {p['content'][:500]}")
                                    elif "name" in p:
                                        args = json.dumps(p.get("arguments", {}))[:200]
                                        st.code(f"tool_call: {p['name']}({args})", language="text")
                                    elif "response" in p:
                                        resp = str(p["response"])[:300]
                                        st.code(f"tool_response: {resp}", language="text")
                        except (json.JSONDecodeError, TypeError):
                            st.text(str(span["INPUT_MESSAGES"])[:500])

                    # Parse output messages
                    if span["OUTPUT_MESSAGES"]:
                        try:
                            out_msgs = json.loads(span["OUTPUT_MESSAGES"])
                            for m in out_msgs:
                                for p in m.get("parts", []):
                                    if "content" in p:
                                        st.markdown(f":robot_face: **assistant**: {p['content'][:500]}")
                                    elif "name" in p:
                                        args = json.dumps(p.get("arguments", {}))[:200]
                                        st.code(f"tool_call: {p['name']}({args})", language="text")
                        except (json.JSONDecodeError, TypeError):
                            st.text(str(span["OUTPUT_MESSAGES"])[:500])

                    st.divider()
