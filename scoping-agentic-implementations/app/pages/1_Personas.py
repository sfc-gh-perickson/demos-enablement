import streamlit as st

st.header("Step 1: Persona Mapping")
st.markdown("Define the personas who will use your agent. Pick **one** as your Phase 1 target.")

PERSONA_FIELDS = [
    ("role", "Role", "e.g., Regional Sales Manager"),
    ("responsibility", "Responsibility", "e.g., Territory allocation, quota decisions"),
    ("data_literacy", "Data Literacy", "e.g., Reads dashboards, doesn't write SQL"),
    ("current_workflow", "Current Workflow", "e.g., Asks analyst team, 2-day turnaround"),
    ("frequency", "Question Frequency", "e.g., 5-10 questions/week"),
    ("stakes", "Stakes (cost of wrong answer)", "e.g., Quota misallocation costs $500K/quarter"),
    ("success_signal", "Success Signal", "e.g., I got the answer without filing a ticket"),
]

if "personas" not in st.session_state:
    st.session_state.personas = []

num_personas = st.number_input("Number of personas", min_value=1, max_value=5, value=max(1, len(st.session_state.personas)))

personas = []
for i in range(num_personas):
    with st.expander(f"Persona {i + 1}", expanded=(i == 0)):
        existing = st.session_state.personas[i] if i < len(st.session_state.personas) else {}
        persona = {}
        for key, label, placeholder in PERSONA_FIELDS:
            persona[key] = st.text_input(
                label, value=existing.get(key, ""), placeholder=placeholder, key=f"persona_{i}_{key}"
            )
        personas.append(persona)

st.session_state.personas = personas

st.markdown("---")
st.subheader("Select Phase 1 Persona")

persona_labels = [p.get("role", f"Persona {i+1}") or f"Persona {i+1}" for i, p in enumerate(personas)]
phase1_idx = st.radio(
    "Which persona should the agent serve first?",
    range(len(persona_labels)),
    format_func=lambda i: persona_labels[i],
    index=st.session_state.get("phase1_persona_idx", 0),
)
st.session_state.phase1_persona_idx = phase1_idx

if personas[phase1_idx].get("role"):
    st.success(f"Phase 1 target: **{personas[phase1_idx]['role']}**")
