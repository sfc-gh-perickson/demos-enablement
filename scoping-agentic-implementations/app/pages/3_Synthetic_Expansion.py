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

# Target dataset size
target_size = st.number_input(
    "Target total dataset size (questions)", min_value=10, max_value=200, value=50, step=10
)

# Calculate current coverage vs. target per cell
st.subheader("Coverage Heatmap")
st.markdown("Shows how many questions each (type x intent) cell needs to reach your distribution target.")

# Build target matrix
current_counts = Counter((q["technical_type"], q["business_intent"]) for q in seed_questions)
heatmap_data = []

for t in TECHNICAL_TYPES:
    row = {}
    t_pct = type_dist.get(t, 0) / 100.0
    for intent in intents:
        i_pct = intent_dist.get(intent, 0) / 100.0
        target_count = max(1, math.ceil(target_size * t_pct * i_pct))
        current = current_counts.get((t, intent), 0)
        deficit = max(0, target_count - current)
        row[intent] = f"{current}/{target_count}" if deficit == 0 else f"{current}/{target_count} (-{deficit})"
    heatmap_data.append({"technical_type": t, **row})

heatmap_df = pd.DataFrame(heatmap_data).set_index("technical_type")
st.dataframe(heatmap_df, use_container_width=True)

# Expansion
st.markdown("---")
if st.button("Expand to Target", type="primary"):
    session = get_session()
    generated = []
    
    progress = st.progress(0)
    cells_to_fill = []
    
    for t in TECHNICAL_TYPES:
        t_pct = type_dist.get(t, 0) / 100.0
        for intent in intents:
            i_pct = intent_dist.get(intent, 0) / 100.0
            target_count = max(1, math.ceil(target_size * t_pct * i_pct))
            current = current_counts.get((t, intent), 0)
            deficit = target_count - current
            if deficit > 0:
                cells_to_fill.append((t, intent, deficit))
    
    # Generate new questions for deficit cells
    total_cells = len(cells_to_fill)
    for idx, (t, intent, deficit) in enumerate(cells_to_fill):
        progress.progress((idx + 1) / (total_cells + 1), text=f"Generating for {t} x {intent}...")
        
        existing_in_cell = [q["question"] for q in seed_questions if q["technical_type"] == t and q["business_intent"] == intent]
        existing_str = "\n".join(f"  - {e}" for e in existing_in_cell) if existing_in_cell else "  (none yet)"
        
        phase1_persona = st.session_state.personas[st.session_state.phase1_persona_idx] if st.session_state.personas else {}
        persona_desc = f"{phase1_persona.get('role', 'business user')} who {phase1_persona.get('responsibility', 'needs data insights')}"
        
        intent_desc = next((i.get("description", "") for i in st.session_state.business_intents if i["name"] == intent), "")
        
        prompt = f"""Generate {min(deficit, 5)} questions for an AI agent evaluation dataset.

Persona: {persona_desc}
Technical type: {t} ({"simple fact retrieval" if t == "lookup" else "comparisons/trends" if t == "aggregation" else "multi-step reasoning" if t == "reasoning" else "policy/process retrieval" if t == "policy" else "agent should refuse"})
Business intent: {intent} ({intent_desc})

Existing questions in this category:
{existing_str}

Generate questions that are DISTINCT from existing ones. Cover different metrics, time periods, or dimensions.
Return ONLY a JSON array of strings."""

        result = ai_complete_json(session, prompt)
        if result and isinstance(result, list):
            for q in result[:deficit]:
                generated.append({
                    "question": q,
                    "technical_type": t,
                    "business_intent": intent,
                    "risk": "medium",
                    "source": "synthetic_new",
                })
    
    # Generate variations of seed questions
    progress.progress(0.9, text="Generating rephrasings...")
    variation_source = seed_questions[:min(10, len(seed_questions))]
    for q in variation_source:
        prompt = f"""Rephrase this question 2 different ways with different wording but same meaning.
Original: {q['question']}
Return ONLY a JSON array of 2 strings."""
        
        result = ai_complete_json(session, prompt)
        if result and isinstance(result, list):
            for v in result[:2]:
                generated.append({
                    "question": v,
                    "technical_type": q["technical_type"],
                    "business_intent": q["business_intent"],
                    "risk": q["risk"],
                    "source": "variation",
                })
    
    progress.progress(1.0, text="Done!")
    
    # Combine seed + generated
    all_qs = [{**q, "source": "manual"} for q in seed_questions] + generated
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
