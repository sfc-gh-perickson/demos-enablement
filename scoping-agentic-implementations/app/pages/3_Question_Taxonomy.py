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
                # Build optional data source context
                data_sources = st.session_state.get("data_sources", {})
                schema_context = ""
                sv_list = data_sources.get("semantic_views", [])
                if sv_list:
                    metrics_str = ", ".join(m["name"] for sv in sv_list for m in sv.get("metrics", []))[:500]
                    dims_str = ", ".join(d["name"] for sv in sv_list for d in sv.get("dimensions", []))[:500]
                    schema_context = f"\n\nAvailable data (from semantic views):\n- Metrics: {metrics_str}\n- Dimensions: {dims_str}"
                
                search_services = data_sources.get("search_services", [])
                if search_services:
                    ss_names = ", ".join(s["name"] for s in search_services)
                    schema_context += f"\n- Document search services: {ss_names}"

                prompt = f"""Based on these personas for an AI data assistant, suggest 6-8 business intent categories.
Each category represents a recurring business question theme these personas would ask.

Personas:
{persona_descriptions}{schema_context}

Return an "intents" array of objects with "name" (snake_case, short) and "description" (one sentence)."""
                schema = {
                    "type": "object",
                    "properties": {
                        "intents": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "properties": {
                                    "name": {"type": "string"},
                                    "description": {"type": "string"}
                                },
                                "required": ["name", "description"]
                            }
                        }
                    },
                    "required": ["intents"]
                }
                result = ai_complete_json(session, prompt, schema=schema)
                if isinstance(result, dict) and "intents" in result:
                    result = result["intents"]
                if isinstance(result, list) and all(isinstance(item, dict) for item in result):
                    st.session_state.business_intents = result
                    st.rerun()
                else:
                    st.error("Could not parse AI response. Try again.")

with col2:
    st.metric("Current intents", len(st.session_state.business_intents))

# Display and edit intents
if st.session_state.business_intents:
    st.markdown("**Business intents** — edit names or delete rows:")
    
    intents_df = pd.DataFrame(st.session_state.business_intents)
    if "name" not in intents_df.columns:
        intents_df["name"] = ""
    if "description" not in intents_df.columns:
        intents_df["description"] = ""
    
    edited_intents = st.data_editor(
        intents_df[["name", "description"]],
        column_config={
            "name": st.column_config.TextColumn("Intent Name", width="medium"),
            "description": st.column_config.TextColumn("Description", width="large"),
        },
        num_rows="dynamic",
        use_container_width=True,
        key="intents_editor",
    )
    
    # Store non-empty rows back
    valid_intents = edited_intents[edited_intents["name"].str.strip() != ""].to_dict("records")
    st.session_state.business_intents = valid_intents

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
st.markdown("Generate an initial set of questions, then review and adjust before expansion.")

intent_options = [i["name"] for i in st.session_state.business_intents] or ["(add intents above)"]

# Auto-generate seed questions respecting distribution
if intent_options[0] != "(add intents above)":
    col_gen, col_count = st.columns([2, 1])
    with col_gen:
        total_seed_target = st.number_input("Total seed questions to generate", min_value=10, max_value=100, value=20, step=5)
    with col_count:
        st.metric("Cells", f"{len(TECHNICAL_TYPES)} x {len(intent_options)} = {len(TECHNICAL_TYPES) * len(intent_options)}")

    if st.button("Generate Seed Questions", type="primary"):
        import math
        session = get_session()
        personas = st.session_state.get("personas", [])
        persona_context = "\n".join(
            f"- {p.get('role', 'User')}: {p.get('responsibility', '')}"
            for p in personas if p.get("role")
        ) or "- Business analyst needing data insights"

        # Calculate per-cell targets from distribution percentages
        type_dist_local = st.session_state.get("type_distribution", {})
        intent_dist_local = st.session_state.get("intent_distribution", {})
        
        cell_targets = {}
        for t in TECHNICAL_TYPES:
            t_pct = type_dist_local.get(t, 0) / 100.0
            for intent in intent_options:
                i_pct = intent_dist_local.get(intent, 0) / 100.0
                if t_pct == 0 or i_pct == 0:
                    continue
                target = max(1, round(total_seed_target * t_pct * i_pct))
                cell_targets[(t, intent)] = target

        generated_seeds = []
        progress = st.progress(0)
        cells_to_generate = [(k, v) for k, v in cell_targets.items() if v > 0]
        total_cells = len(cells_to_generate)

        seed_schema = {
            "type": "object",
            "properties": {
                "questions": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "question": {"type": "string"},
                            "risk": {"type": "string", "enum": ["low", "medium", "high", "very_high", "reputational"]}
                        },
                        "required": ["question", "risk"]
                    }
                }
            },
            "required": ["questions"]
        }

        type_descriptions = {
            "lookup": "simple fact retrieval (a specific number, name, or status)",
            "aggregation": "comparisons, trends, or summaries across multiple records",
            "reasoning": "multi-step analysis requiring joins or conditional logic",
            "policy": "policy, process, or definition retrieval",
            "search": "finding or filtering records by criteria (semantic or keyword search)",
            "out_of_scope": "questions the agent should refuse (inappropriate, off-topic, or dangerous)"
        }

        for cell_idx, ((t, intent), num_questions) in enumerate(cells_to_generate):
            progress.progress((cell_idx + 1) / total_cells, text=f"Generating {t} x {intent} ({num_questions} questions)...")
            intent_desc = next((i.get("description", "") for i in st.session_state.business_intents if i["name"] == intent), "")
            prompt = f"""Generate {num_questions} realistic questions a user would ask an AI data assistant.

Personas:
{persona_context}

Technical type: {t} — {type_descriptions.get(t, t)}
Business intent: {intent} — {intent_desc}

Each question should be specific and natural (like a real user would type it).
Assign a risk level based on how costly a wrong answer would be.
Return a "questions" array of objects with "question" and "risk" keys."""

            result = ai_complete_json(session, prompt, schema=seed_schema)
            if result and "questions" in result:
                for q in result["questions"][:num_questions]:
                    generated_seeds.append({
                        "question": q["question"],
                        "technical_type": t,
                        "business_intent": intent,
                        "risk": q.get("risk", "medium"),
                    })

        progress.empty()
        if generated_seeds:
            st.session_state.seed_questions = generated_seeds
            st.rerun()

    if st.session_state.get("seed_questions"):
        st.caption("Review the generated questions below — edit, delete, or add rows as needed.")


# Initialize with example data if empty
if not st.session_state.get("seed_questions"):
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
