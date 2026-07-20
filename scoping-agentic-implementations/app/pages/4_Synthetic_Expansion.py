import streamlit as st
import pandas as pd
import math
from collections import Counter
from utils.snowflake_conn import get_session
from utils.ai_complete import ai_complete_json

st.header("Step 3: Synthetic Expansion")
st.markdown("""
Expand your seed dataset guided by the distribution targets you set in Step 2.
The system generates more questions for underrepresented (type x intent) cells.
""")

TECHNICAL_TYPES = ["lookup", "aggregation", "reasoning", "policy", "out_of_scope"]

seed_questions = st.session_state.get("seed_questions", [])
type_dist = st.session_state.get("type_distribution", {})
intent_dist = st.session_state.get("intent_distribution", {})
intents = [i["name"] for i in st.session_state.get("business_intents", [])]

if not seed_questions:
    st.warning("Add seed questions on the Question Taxonomy page first.")
    st.stop()

if not intents:
    st.warning("Add business intents on the Question Taxonomy page first.")
    st.stop()

# --- Configuration ---
col_size, col_refusal = st.columns(2)
with col_size:
    target_size = st.number_input(
        "Target total dataset size", min_value=10, max_value=200, value=50, step=10
    )
with col_refusal:
    refusal_pct = st.slider(
        "Unanswerable/refusal %", min_value=0, max_value=30, value=10, step=5,
        help="Percentage of questions that intentionally ask about data outside what exists (to test graceful refusal)"
    )

# --- Data Profiling ---
st.markdown("---")
st.subheader("Data Profile")

data_sources = st.session_state.get("data_sources", {})
tables = data_sources.get("tables", [])

if not tables:
    st.info("No data sources configured (Step 2). Questions will be generated without data validation. Skip or go back to add data sources.")
    profile = {}
else:
    if "_data_profile" not in st.session_state:
        st.session_state._data_profile = {}

    if st.button("Profile Data"):
        session = get_session()
        db = data_sources.get("database", "")
        schema = data_sources.get("schema", "")
        if db:
            session.sql(f"USE DATABASE {db}").collect()
            session.sql(f"USE SCHEMA {schema}").collect()

        profile_result = {}
        progress = st.progress(0)

        for idx, tbl in enumerate(tables):
            progress.progress((idx + 1) / len(tables), text=f"Profiling {tbl['name']}...")
            tbl_name = tbl["fq_name"]
            tbl_profile = {}

            for col in tbl.get("columns", []):
                col_name = col["name"]
                col_type = col["type"].upper()

                try:
                    if "VARCHAR" in col_type or "TEXT" in col_type or "STRING" in col_type:
                        count_row = session.sql(f"SELECT COUNT(DISTINCT {col_name}) FROM {tbl_name}").collect()
                        distinct_count = count_row[0][0]
                        if distinct_count <= 50:
                            vals = session.sql(f"SELECT DISTINCT {col_name} FROM {tbl_name} WHERE {col_name} IS NOT NULL LIMIT 30").collect()
                            tbl_profile[col_name] = {
                                "type": "categorical",
                                "values": [str(r[0]) for r in vals],
                            }
                    elif "DATE" in col_type or "TIMESTAMP" in col_type:
                        range_row = session.sql(f"SELECT MIN({col_name}), MAX({col_name}) FROM {tbl_name}").collect()
                        tbl_profile[col_name] = {
                            "type": "date_range",
                            "min": str(range_row[0][0]),
                            "max": str(range_row[0][1]),
                        }
                    elif "NUMBER" in col_type or "INT" in col_type or "FLOAT" in col_type or "DECIMAL" in col_type:
                        range_row = session.sql(f"SELECT MIN({col_name}), MAX({col_name}) FROM {tbl_name}").collect()
                        tbl_profile[col_name] = {
                            "type": "numeric_range",
                            "min": str(range_row[0][0]),
                            "max": str(range_row[0][1]),
                        }
                except Exception:
                    pass

            if tbl_profile:
                profile_result[tbl["name"]] = tbl_profile

        progress.empty()
        st.session_state._data_profile = profile_result
        st.rerun()

    profile = st.session_state.get("_data_profile", {})

    if profile:
        with st.expander(f"Data profile ({len(profile)} tables profiled)"):
            for tbl_name, cols in profile.items():
                st.markdown(f"**{tbl_name}**")
                for col_name, info in cols.items():
                    if info["type"] == "categorical":
                        st.markdown(f"- `{col_name}`: {', '.join(info['values'][:10])}{'...' if len(info['values']) > 10 else ''}")
                    elif info["type"] == "date_range":
                        st.markdown(f"- `{col_name}`: {info['min']} to {info['max']}")
                    elif info["type"] == "numeric_range":
                        st.markdown(f"- `{col_name}`: {info['min']} to {info['max']}")

# --- Coverage Heatmap ---
st.markdown("---")
st.subheader("Coverage Heatmap")

current_counts = Counter((q["technical_type"], q["business_intent"]) for q in seed_questions)
heatmap_data = []

for t in TECHNICAL_TYPES:
    row = {}
    t_pct = type_dist.get(t, 0) / 100.0
    for intent in intents:
        i_pct = intent_dist.get(intent, 0) / 100.0
        target_count = max(1, math.ceil(target_size * t_pct * i_pct)) if t_pct > 0 and i_pct > 0 else 0
        current = current_counts.get((t, intent), 0)
        deficit = max(0, target_count - current)
        row[intent] = f"{current}/{target_count}" if deficit == 0 else f"{current}/{target_count} (-{deficit})"
    heatmap_data.append({"technical_type": t, **row})

heatmap_df = pd.DataFrame(heatmap_data).set_index("technical_type")
st.dataframe(heatmap_df, use_container_width=True)

# --- Expansion ---
st.markdown("---")
if st.button("Expand to Target", type="primary"):
    session = get_session()
    generated = []
    profile = st.session_state.get("_data_profile", {})

    # Build profile context string for answerable questions
    profile_context = ""
    if profile:
        lines = []
        for tbl_name, cols in profile.items():
            for col_name, info in cols.items():
                if info["type"] == "categorical":
                    lines.append(f"- {col_name} values: {', '.join(info['values'][:8])}")
                elif info["type"] == "date_range":
                    lines.append(f"- Date range for {col_name}: {info['min']} to {info['max']}")
                elif info["type"] == "numeric_range":
                    lines.append(f"- {col_name} range: {info['min']} to {info['max']}")
        profile_context = "\n".join(lines[:20])

    # Build anti-profile context for unanswerable questions
    anti_profile_context = ""
    if profile:
        anti_lines = []
        for tbl_name, cols in profile.items():
            for col_name, info in cols.items():
                if info["type"] == "categorical":
                    anti_lines.append(f"- {col_name} does NOT include values outside: {', '.join(info['values'][:5])}")
                elif info["type"] == "date_range":
                    anti_lines.append(f"- Data only exists between {info['min']} and {info['max']} — ask about dates outside this range")
                elif info["type"] == "numeric_range":
                    anti_lines.append(f"- No data exists outside {col_name} range {info['min']} to {info['max']}")
        anti_profile_context = "\n".join(anti_lines[:15])

    # Calculate cells to fill
    answerable_target = math.ceil(target_size * (1 - refusal_pct / 100.0))
    unanswerable_target = target_size - answerable_target

    cells_to_fill = []
    for t in TECHNICAL_TYPES:
        if t == "out_of_scope":
            continue
        t_pct = type_dist.get(t, 0) / 100.0
        for intent in intents:
            i_pct = intent_dist.get(intent, 0) / 100.0
            if t_pct == 0 or i_pct == 0:
                continue
            target_count = max(1, round(answerable_target * t_pct * i_pct))
            current = current_counts.get((t, intent), 0)
            deficit = target_count - current
            if deficit > 0:
                cells_to_fill.append((t, intent, deficit))

    progress = st.progress(0)
    total_steps = len(cells_to_fill) + 2

    # --- Generate ANSWERABLE questions ---
    phase1_persona = st.session_state.get("personas", [{}])[st.session_state.get("phase1_persona_idx", 0)]
    persona_desc = f"{phase1_persona.get('role', 'business user')} who {phase1_persona.get('responsibility', 'needs data insights')}"
    persona_literacy = phase1_persona.get('data_literacy', 'non-technical business user')

    for idx, (t, intent, deficit) in enumerate(cells_to_fill):
        progress.progress((idx + 1) / total_steps, text=f"Generating answerable: {t} x {intent}...")

        existing_in_cell = [q["question"] for q in seed_questions if q["technical_type"] == t and q["business_intent"] == intent]
        existing_str = "\n".join(f"  - {e}" for e in existing_in_cell) if existing_in_cell else "  (none yet)"

        intent_desc = next((i.get("description", "") for i in st.session_state.get("business_intents", []) if i["name"] == intent), "")

        # Include data profile for answerable questions
        data_section = ""
        if profile_context:
            data_section = f"""
Data available in the system (use these real values in your questions):
{profile_context}

Generate questions that reference REAL values from this data profile."""

        prompt = f"""Generate {min(deficit, 5)} questions for an AI agent evaluation dataset.

Persona: {persona_desc}
Data literacy: {persona_literacy}
Technical type: {t} ({"simple fact retrieval" if t == "lookup" else "comparisons/trends" if t == "aggregation" else "multi-step reasoning" if t == "reasoning" else "policy/process retrieval" if t == "policy" else "agent should refuse"})
Business intent: {intent} ({intent_desc})
{data_section}
IMPORTANT: Write questions exactly as this persona would naturally ask them.
- Use business vocabulary, not column names.
- Questions MUST be answerable by the data that exists.
- Keep questions conversational, specific, and grounded in their daily work.

Existing questions in this category:
{existing_str}

Generate questions that are DISTINCT from existing ones.
Return a "questions" array of strings."""

        questions_schema = {
            "type": "object",
            "properties": {"questions": {"type": "array", "items": {"type": "string"}}},
            "required": ["questions"]
        }
        result = ai_complete_json(session, prompt, schema=questions_schema)
        if result and isinstance(result, dict) and "questions" in result:
            for q in result["questions"][:deficit]:
                generated.append({
                    "question": q,
                    "technical_type": t,
                    "business_intent": intent,
                    "risk": "medium",
                    "source": "synthetic_answerable",
                })

    # --- Generate UNANSWERABLE/REFUSAL questions ---
    if unanswerable_target > 0:
        progress.progress((len(cells_to_fill) + 1) / total_steps, text="Generating unanswerable questions...")

        refusal_prompt_data = ""
        if anti_profile_context:
            refusal_prompt_data = f"""
The data has these boundaries — generate questions that ask OUTSIDE them:
{anti_profile_context}"""

        refusal_prompt = f"""Generate {unanswerable_target} questions that a {persona_desc} might ask, but that CANNOT be answered by the available data.

These test whether the agent gracefully handles questions it cannot answer.
{refusal_prompt_data}
Types of unanswerable questions to generate:
- Questions about time periods outside the data range
- Questions about categories/segments that don't exist in the data
- Questions about metrics the system doesn't track
- Questions requiring external data the agent doesn't have access to

Write them naturally as this persona would ask. They should sound reasonable (not obviously absurd).
Return a "questions" array of strings."""

        result = ai_complete_json(session, refusal_prompt, schema=questions_schema)
        if result and isinstance(result, dict) and "questions" in result:
            for q in result["questions"][:unanswerable_target]:
                generated.append({
                    "question": q,
                    "technical_type": "out_of_scope",
                    "business_intent": intents[0] if intents else "unknown",
                    "risk": "medium",
                    "source": "synthetic_unanswerable",
                })

    # --- Generate variations ---
    progress.progress((len(cells_to_fill) + 2) / total_steps, text="Generating rephrasings...")
    variation_source = seed_questions[:min(10, len(seed_questions))]
    for q in variation_source:
        prompt = f"""Rephrase this question 2 different ways with different wording but same meaning.
Original: {q['question']}
Return a "questions" array of 2 strings."""

        variations_schema = {
            "type": "object",
            "properties": {"questions": {"type": "array", "items": {"type": "string"}}},
            "required": ["questions"]
        }
        result = ai_complete_json(session, prompt, schema=variations_schema)
        if result and isinstance(result, dict) and "questions" in result:
            for v in result["questions"][:2]:
                generated.append({
                    "question": v,
                    "technical_type": q["technical_type"],
                    "business_intent": q["business_intent"],
                    "risk": q["risk"],
                    "source": "variation",
                })

    progress.progress(1.0, text="Done!")

    # Combine seed + generated
    all_qs = [{**q, "source": q.get("source", "manual")} for q in seed_questions] + generated
    st.session_state.expanded_questions = all_qs
    st.rerun()

# Display expanded dataset if available
expanded = st.session_state.get("expanded_questions", [])
if expanded:
    st.markdown("---")
    st.subheader(f"Expanded Dataset ({len(expanded)} questions)")
    st.markdown("Review and delete unwanted questions below.")

    df = pd.DataFrame(expanded)
    edited = st.data_editor(
        df,
        column_config={
            "question": st.column_config.TextColumn("Question", width="large"),
            "technical_type": st.column_config.SelectboxColumn("Type", options=TECHNICAL_TYPES),
            "business_intent": st.column_config.SelectboxColumn("Intent", options=intents),
            "risk": st.column_config.SelectboxColumn("Risk", options=["low", "medium", "high", "very_high", "reputational"]),
            "source": st.column_config.TextColumn("Source", disabled=True),
        },
        num_rows="dynamic",
        use_container_width=True,
        key="expanded_editor",
    )

    valid = edited[edited["question"].str.strip() != ""].to_dict("records")
    st.session_state.expanded_questions = valid

    # Final distribution
    st.markdown("**Final distribution:**")
    col1, col2 = st.columns(2)
    with col1:
        st.markdown("*By source:*")
        source_counts = Counter(q["source"] for q in valid)
        st.dataframe(pd.DataFrame(source_counts.items(), columns=["source", "count"]), hide_index=True)
    with col2:
        st.markdown("*By type x intent:*")
        final_counts = Counter((q["technical_type"], q["business_intent"]) for q in valid)
        summary = []
        for t in TECHNICAL_TYPES:
            for intent in intents:
                c = final_counts.get((t, intent), 0)
                if c > 0:
                    summary.append({"type": t, "intent": intent, "count": c})
        if summary:
            st.dataframe(pd.DataFrame(summary), hide_index=True, use_container_width=True)
