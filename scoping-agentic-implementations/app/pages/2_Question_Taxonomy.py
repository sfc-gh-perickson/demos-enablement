import streamlit as st
import pandas as pd
from utils.snowflake_conn import get_session
from utils.ai_complete import ai_complete_json

st.header("Step 2: Question Taxonomy")

TECHNICAL_TYPES = ["lookup", "aggregation", "reasoning", "policy", "search", "out_of_scope"]

# --- Section A: Business Intent Categories ---
st.subheader("A. Business Intent Categories")
st.markdown("""
Define the business intents your persona cares about. These are domain-specific question themes
that go beyond technical type (lookup vs aggregation) to capture *what business area* the question targets.
""")

if "business_intents" not in st.session_state:
    st.session_state.business_intents = []

col1, col2 = st.columns([2, 1])

with col1:
    if st.button("Generate Intent Suggestions from Personas"):
        personas = st.session_state.get("personas", [])
        if not personas or not any(p.get("role") for p in personas):
            st.warning("Add at least one persona with a role on the Personas page first.")
        else:
            with st.spinner("Generating intent categories..."):
                session = get_session()
                persona_descriptions = "\n".join(
                    f"- {p.get('role', 'Unknown')}: {p.get('responsibility', '')}. "
                    f"Asks about: {p.get('current_workflow', '')}. Stakes: {p.get('stakes', '')}"
                    for p in personas if p.get("role")
                )
                prompt = f"""Based on these personas for an AI data assistant, suggest 6-8 business intent categories.
Each category represents a recurring business question theme these personas would ask.

Personas:
{persona_descriptions}

Return a JSON array of objects with "name" (snake_case, short) and "description" (one sentence).
Example: [{{"name": "pipeline_health", "description": "Questions about deal pipeline status, velocity, and conversion"}}]"""
                
                result = ai_complete_json(session, prompt)
                if result:
                    st.session_state.business_intents = result
                    st.rerun()
                else:
                    st.error("Could not parse AI response. Try again.")

with col2:
    st.metric("Current intents", len(st.session_state.business_intents))

# Display and edit intents
if st.session_state.business_intents:
    st.markdown("**Generated intents** (toggle off to remove, edit names below):")
    
    kept_intents = []
    for i, intent in enumerate(st.session_state.business_intents):
        col_a, col_b = st.columns([1, 4])
        with col_a:
            keep = st.checkbox("Keep", value=True, key=f"keep_intent_{i}")
        with col_b:
            name = st.text_input(
                "Name", value=intent.get("name", ""), key=f"intent_name_{i}", label_visibility="collapsed"
            )
            st.caption(intent.get("description", ""))
        if keep:
            kept_intents.append({"name": name, "description": intent.get("description", "")})
    
    st.session_state.business_intents = kept_intents

# Add custom intent
with st.expander("Add custom intent"):
    new_name = st.text_input("Intent name (snake_case)", key="new_intent_name")
    new_desc = st.text_input("Description", key="new_intent_desc")
    if st.button("Add Intent") and new_name:
        st.session_state.business_intents.append({"name": new_name, "description": new_desc})
        st.rerun()

# --- Section B: Distribution Targets ---
st.markdown("---")
st.subheader("B. Distribution Targets")
st.markdown("Set the expected percentage breakdown for each dimension. These guide synthetic expansion.")

col_type, col_intent = st.columns(2)

with col_type:
    st.markdown("**Technical Type %**")
    type_dist = {}
    for t in TECHNICAL_TYPES:
        current = st.session_state.get("type_distribution", {}).get(t, 20)
        type_dist[t] = st.number_input(
            t, min_value=0, max_value=100, value=current, step=5, key=f"type_pct_{t}"
        )
    type_total = sum(type_dist.values())
    if type_total != 100:
        st.warning(f"Total: {type_total}% (must be 100%)")
    else:
        st.success(f"Total: 100%")
    st.session_state.type_distribution = type_dist

with col_intent:
    st.markdown("**Business Intent %**")
    intent_names = [i["name"] for i in st.session_state.business_intents]
    if not intent_names:
        st.info("Generate or add business intents above first.")
        st.session_state.intent_distribution = {}
    else:
        intent_dist = {}
        default_pct = 100 // len(intent_names) if intent_names else 0
        for name in intent_names:
            current = st.session_state.get("intent_distribution", {}).get(name, default_pct)
            intent_dist[name] = st.number_input(
                name, min_value=0, max_value=100, value=current, step=5, key=f"intent_pct_{name}"
            )
        intent_total = sum(intent_dist.values())
        if intent_total != 100:
            st.warning(f"Total: {intent_total}% (must be 100%)")
        else:
            st.success(f"Total: 100%")
        st.session_state.intent_distribution = intent_dist

# --- Section C: Question Brainstorming ---
st.markdown("---")
st.subheader("C. Seed Questions")
st.markdown("Brainstorm questions your Phase 1 persona would ask. Tag each with technical type and business intent.")

intent_options = [i["name"] for i in st.session_state.business_intents] or ["(add intents above)"]

# Initialize with example data if empty
if not st.session_state.seed_questions:
    st.session_state.seed_questions = []

# Data editor
existing_df = pd.DataFrame(
    st.session_state.seed_questions if st.session_state.seed_questions
    else [{"question": "", "technical_type": "lookup", "business_intent": intent_options[0], "risk": "medium"}]
)

edited_df = st.data_editor(
    existing_df,
    column_config={
        "question": st.column_config.TextColumn("Question", width="large"),
        "technical_type": st.column_config.SelectboxColumn("Technical Type", options=TECHNICAL_TYPES),
        "business_intent": st.column_config.SelectboxColumn("Business Intent", options=intent_options),
        "risk": st.column_config.SelectboxColumn("Risk", options=["low", "medium", "high", "very_high", "reputational"]),
    },
    num_rows="dynamic",
    use_container_width=True,
    key="question_editor",
)

# Store non-empty rows
valid_questions = edited_df[edited_df["question"].str.strip() != ""].to_dict("records")
st.session_state.seed_questions = valid_questions

# Distribution comparison
if valid_questions:
    st.markdown("---")
    st.markdown("**Current distribution vs. targets:**")
    
    df = pd.DataFrame(valid_questions)
    
    col_c1, col_c2 = st.columns(2)
    with col_c1:
        st.markdown("*By Technical Type*")
        type_counts = df["technical_type"].value_counts().to_dict()
        total = len(df)
        comparison_data = []
        for t in TECHNICAL_TYPES:
            actual_pct = round(type_counts.get(t, 0) / total * 100, 1) if total else 0
            target_pct = st.session_state.type_distribution.get(t, 0)
            comparison_data.append({"type": t, "actual%": actual_pct, "target%": target_pct})
        st.dataframe(pd.DataFrame(comparison_data), use_container_width=True, hide_index=True)
    
    with col_c2:
        st.markdown("*By Business Intent*")
        intent_counts = df["business_intent"].value_counts().to_dict()
        comparison_data = []
        for name in intent_options:
            if name == "(add intents above)":
                continue
            actual_pct = round(intent_counts.get(name, 0) / total * 100, 1) if total else 0
            target_pct = st.session_state.intent_distribution.get(name, 0)
            comparison_data.append({"intent": name, "actual%": actual_pct, "target%": target_pct})
        if comparison_data:
            st.dataframe(pd.DataFrame(comparison_data), use_container_width=True, hide_index=True)

st.caption(f"Total seed questions: {len(valid_questions)}")
