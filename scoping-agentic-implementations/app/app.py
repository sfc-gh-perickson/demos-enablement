import streamlit as st

st.set_page_config(
    page_title="Agent Scoping Workshop",
    page_icon="🎯",
    layout="wide",
    initial_sidebar_state="expanded",
)

# Initialize session state
defaults = {
    "personas": [],
    "phase1_persona_idx": 0,
    "business_intents": [],
    "type_distribution": {
        "lookup": 40,
        "aggregation": 25,
        "reasoning": 15,
        "policy": 10,
        "out_of_scope": 10,
    },
    "intent_distribution": {},
    "seed_questions": [],
    "expanded_questions": [],
    "eval_dataset": [],
    "eval_config_yaml": "",
    "tenancy_spec": {},
    "agent_ddl": "",
}

for key, val in defaults.items():
    if key not in st.session_state:
        st.session_state[key] = val

# Sidebar: progress summary
st.sidebar.title("Agent Scoping")
st.sidebar.markdown("---")

personas = st.session_state.personas
intents = st.session_state.business_intents
seed_qs = st.session_state.seed_questions
expanded_qs = st.session_state.expanded_questions

st.sidebar.metric("Personas", len(personas))
st.sidebar.metric("Business Intents", len(intents))
st.sidebar.metric("Seed Questions", len(seed_qs))
st.sidebar.metric("Expanded Dataset", len(expanded_qs) if expanded_qs else "—")

if st.session_state.eval_dataset:
    st.sidebar.metric("Eval Dataset", len(st.session_state.eval_dataset))

st.sidebar.markdown("---")
st.sidebar.caption("Navigate using the pages above.")

# Main page content
st.title("Scoping Agentic Implementations")
st.markdown("""
This app guides you through the scoping process for a Cortex Agent:

1. **Personas** — define who will use the agent
2. **Taxonomy** — categorize questions by type and business intent, set distribution targets
3. **Expansion** — synthetically grow the dataset guided by your distribution
4. **Eval Config** — generate ground truth and configure evaluation
5. **Multi-Tenancy** — scope access control requirements
6. **Deploy** — create the agent, register eval dataset, export to git

Use the sidebar to navigate between steps.
""")
