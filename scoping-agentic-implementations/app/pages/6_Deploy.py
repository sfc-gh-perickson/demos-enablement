import streamlit as st
import json
import tempfile
from utils.snowflake_conn import get_session

st.header("Step 6: Deploy & Export")

tab_ddl, tab_eval, tab_export = st.tabs(["Agent DDL", "Deploy Eval Dataset", "Export to Git"])

# --- Helpers ---
def build_agent_ddl():
    personas = st.session_state.get("personas", [])
    phase1_idx = st.session_state.get("phase1_persona_idx", 0)
    phase1 = personas[phase1_idx] if personas else {}
    intents = st.session_state.get("business_intents", [])
    type_dist = st.session_state.get("type_distribution", {})
    tenancy = st.session_state.get("tenancy_spec", {})
    
    # Build instructions from persona + intents + scope
    persona_desc = f"You are an AI assistant for {phase1.get('role', 'business users')}."
    if phase1.get("responsibility"):
        persona_desc += f" They are responsible for {phase1['responsibility']}."
    if phase1.get("data_literacy"):
        persona_desc += f" Their data literacy: {phase1['data_literacy']}."
    
    intent_scope = ""
    if intents:
        intent_names = [i["name"] for i in intents]
        intent_scope = f"\n\nYou help with these business areas: {', '.join(intent_names)}."
    
    out_of_scope = "\n\nBOUNDARIES:\n- Do NOT generate content (emails, proposals, presentations)\n- Do NOT provide competitor information\n- Do NOT modify data or take actions in external systems\n- If asked something outside your scope, politely explain your boundaries"
    
    response_format = "\n\nRESPONSE FORMAT:\n- Lead with the direct answer\n- Include relevant context (time period, filters applied)\n- Note any caveats or data limitations"
    
    instructions = persona_desc + intent_scope + out_of_scope + response_format
    
    # Determine tools from type distribution
    tools_comment = "-- Tools: configure based on your data sources\n"
    has_structured = type_dist.get("lookup", 0) + type_dist.get("aggregation", 0) > 0
    has_unstructured = type_dist.get("policy", 0) > 0
    
    tools_lines = []
    if has_structured:
        tools_lines.append("    -- SEMANTIC_VIEW = 'YOUR_DB.YOUR_SCHEMA.YOUR_SEMANTIC_VIEW'")
    if has_unstructured:
        tools_lines.append("    -- CORTEX_SEARCH = 'YOUR_DB.YOUR_SCHEMA.YOUR_SEARCH_SERVICE'")
    
    tools_block = "\n".join(tools_lines) if tools_lines else "    -- (add tools here)"
    
    agent_name = st.session_state.get("eval_agent_name", "YOUR_AGENT_NAME")
    
    ddl = f"""CREATE OR REPLACE CORTEX AGENT {agent_name}
  COMMENT = 'Phase 1: {phase1.get("role", "business user")} assistant'
  MODEL = 'claude-sonnet-4-5'
  TOOLS = (
{tools_block}
  )
  INSTRUCTIONS = $${instructions}$$;"""
    
    return ddl


def build_eval_sql():
    eval_dataset = st.session_state.get("eval_dataset", [])
    if not eval_dataset:
        return "-- No eval dataset generated yet. Complete Step 4 first."
    
    lines = [
        "CREATE OR REPLACE TABLE EVAL_QUESTIONS (\n    INPUT_QUERY VARCHAR,\n    GROUND_TRUTH VARIANT\n);\n",
    ]
    
    for q in eval_dataset:
        gt_obj = {
            "ground_truth_output": q["ground_truth_output"],
            "intent": q["intent"],
            "process": q["process"],
        }
        gt_json = json.dumps(gt_obj).replace("$$", "$ $")
        query = q["input_query"].replace("$$", "$ $")
        lines.append(f"INSERT INTO EVAL_QUESTIONS SELECT $${query}$$, PARSE_JSON($${gt_json}$$);")
    
    lines.append("")
    lines.append("-- Register as evaluation dataset")
    lines.append("""CALL SYSTEM$CREATE_EVALUATION_DATASET(
  'Cortex Agent',
  'EVAL_QUESTIONS',
  'SCOPING_EVAL_DATASET',
  OBJECT_CONSTRUCT('query_text', 'INPUT_QUERY', 'expected_tools', 'GROUND_TRUTH')
);""")
    
    return "\n".join(lines)


def build_spec_markdown():
    personas = st.session_state.get("personas", [])
    phase1_idx = st.session_state.get("phase1_persona_idx", 0)
    phase1 = personas[phase1_idx] if personas else {}
    intents = st.session_state.get("business_intents", [])
    type_dist = st.session_state.get("type_distribution", {})
    intent_dist = st.session_state.get("intent_distribution", {})
    tenancy = st.session_state.get("tenancy_spec", {})
    expanded = st.session_state.get("expanded_questions", [])
    
    md = f"""# Agent Specification

## Overview
- **Agent Name:** {st.session_state.get("eval_agent_name", "YOUR_AGENT_NAME")}
- **Phase 1 Persona:** {phase1.get("role", "TBD")}
- **Success Signal:** {phase1.get("success_signal", "TBD")}

## Personas
"""
    for i, p in enumerate(personas):
        marker = " (Phase 1)" if i == phase1_idx else ""
        md += f"\n### {p.get('role', f'Persona {i+1}')}{marker}\n"
        md += f"- Responsibility: {p.get('responsibility', '')}\n"
        md += f"- Data Literacy: {p.get('data_literacy', '')}\n"
        md += f"- Frequency: {p.get('frequency', '')}\n"
        md += f"- Stakes: {p.get('stakes', '')}\n"
    
    md += "\n## Business Intents\n"
    for i in intents:
        pct = intent_dist.get(i["name"], 0)
        md += f"- **{i['name']}** ({pct}%): {i.get('description', '')}\n"
    
    md += "\n## Technical Type Distribution\n"
    for t, pct in type_dist.items():
        md += f"- {t}: {pct}%\n"
    
    md += f"\n## Eval Dataset\n- Total questions: {len(expanded)}\n"
    
    if tenancy:
        md += f"\n## Multi-Tenancy\n"
        md += f"- Model: {tenancy.get('tenant_model', 'N/A')}\n"
        md += f"- Tenants: {tenancy.get('tenant_count', 'N/A')}\n"
        md += f"- Identity: {tenancy.get('identity_mechanism', 'N/A')}\n"
        md += f"- Session Attributes: {tenancy.get('session_attributes', 'N/A')}\n"
        md += f"- RAP Tables: {tenancy.get('rap_tables', 'N/A')}\n"
    
    return md


# --- Tab 1: Agent DDL ---
with tab_ddl:
    st.subheader("Agent DDL")
    st.markdown("Generated from your personas, intents, and scope boundaries.")
    
    ddl = build_agent_ddl()
    edited_ddl = st.text_area("Agent DDL (editable)", value=ddl, height=400, key="ddl_editor")
    st.session_state.agent_ddl = edited_ddl
    
    if st.button("Execute DDL in Snowflake", type="primary"):
        try:
            session = get_session()
            session.sql(edited_ddl).collect()
            st.success("Agent created successfully!")
        except Exception as e:
            st.error(f"Error: {e}")


# --- Tab 2: Deploy Eval Dataset ---
with tab_eval:
    st.subheader("Deploy Eval Dataset")
    
    eval_dataset = st.session_state.get("eval_dataset", [])
    if not eval_dataset:
        st.warning("Generate ground truth on the Eval Config page first.")
    else:
        st.metric("Questions to deploy", len(eval_dataset))
        
        if st.button("Create Table + Register Dataset", type="primary"):
            try:
                session = get_session()
                
                # Create table
                session.sql("CREATE OR REPLACE TABLE EVAL_QUESTIONS (INPUT_QUERY VARCHAR, GROUND_TRUTH VARIANT)").collect()
                
                # Insert rows
                for q in eval_dataset:
                    gt_obj = json.dumps({
                        "ground_truth_output": q["ground_truth_output"],
                        "intent": q["intent"],
                        "process": q["process"],
                    })
                    query = q["input_query"]
                    session.sql(f"INSERT INTO EVAL_QUESTIONS SELECT $${query}$$, PARSE_JSON($${gt_obj}$$)").collect()
                
                # Register dataset
                session.sql("DROP DATASET IF EXISTS SCOPING_EVAL_DATASET").collect()
                session.sql("""
                    CALL SYSTEM$CREATE_EVALUATION_DATASET(
                      'Cortex Agent', 'EVAL_QUESTIONS', 'SCOPING_EVAL_DATASET',
                      OBJECT_CONSTRUCT('query_text', 'INPUT_QUERY', 'expected_tools', 'GROUND_TRUTH')
                    )
                """).collect()
                
                st.success("Eval dataset registered as SCOPING_EVAL_DATASET")
            except Exception as e:
                st.error(f"Error: {e}")
        
        # Upload eval config YAML
        st.markdown("---")
        yaml_content = st.session_state.get("eval_config_yaml", "")
        if yaml_content:
            if st.button("Upload Eval Config to Stage"):
                try:
                    session = get_session()
                    session.sql("CREATE STAGE IF NOT EXISTS EVAL_STAGE").collect()
                    
                    with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as f:
                        f.write(yaml_content)
                        path = f.name
                    
                    session.sql(f"PUT 'file://{path}' @EVAL_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE").collect()
                    st.success("Config uploaded to @EVAL_STAGE/eval_config.yaml")
                except Exception as e:
                    st.error(f"Error: {e}")


# --- Tab 3: Export to Git ---
with tab_export:
    st.subheader("Export Artifacts")
    st.markdown("Download files for version control.")
    
    col1, col2 = st.columns(2)
    
    with col1:
        # Agent DDL
        st.download_button(
            "Download Agent DDL (.sql)",
            data=st.session_state.get("agent_ddl", build_agent_ddl()),
            file_name="agent.sql",
            mime="text/plain",
        )
        
        # Eval config YAML
        yaml = st.session_state.get("eval_config_yaml", "")
        if yaml:
            st.download_button(
                "Download Eval Config (.yaml)",
                data=yaml,
                file_name="eval_config.yaml",
                mime="text/yaml",
            )
    
    with col2:
        # Eval questions CSV (for dbt seed)
        eval_dataset = st.session_state.get("eval_dataset", [])
        if eval_dataset:
            import pandas as pd
            csv_df = pd.DataFrame([{
                "input_query": q["input_query"],
                "ground_truth_output": q["ground_truth_output"],
                "intent": q["intent"],
                "process": q["process"],
            } for q in eval_dataset])
            st.download_button(
                "Download Eval Questions (.csv)",
                data=csv_df.to_csv(index=False),
                file_name="eval_questions.csv",
                mime="text/csv",
            )
        
        # Distribution targets JSON
        dist_data = {
            "type_distribution": st.session_state.get("type_distribution", {}),
            "intent_distribution": st.session_state.get("intent_distribution", {}),
        }
        st.download_button(
            "Download Distribution Targets (.json)",
            data=json.dumps(dist_data, indent=2),
            file_name="distribution_targets.json",
            mime="application/json",
        )
    
    # Full spec markdown
    st.markdown("---")
    spec_md = build_spec_markdown()
    st.download_button(
        "Download Full Agent Spec (.md)",
        data=spec_md,
        file_name="agent_spec.md",
        mime="text/markdown",
    )
    
    with st.expander("Preview spec"):
        st.markdown(spec_md)
