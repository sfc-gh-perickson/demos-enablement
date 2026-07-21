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
    data_sources = st.session_state.get("data_sources", {})

    # Build instructions
    response_instr = f"You are an AI assistant for {phase1.get('role', 'business users')}."
    if phase1.get("responsibility"):
        response_instr += f" They are responsible for {phase1['responsibility']}."
    if phase1.get("data_literacy"):
        response_instr += f" Their data literacy: {phase1['data_literacy']}."
    response_instr += " Lead with the direct answer. Include relevant context. Note any caveats."
    response_instr += " Do NOT generate content (emails, proposals). Do NOT provide competitor information."
    response_instr += " If asked something outside your scope, politely explain your boundaries."

    orchestration_instr = ""
    if intents:
        intent_names = [i["name"] for i in intents]
        orchestration_instr = f"You help with these business areas: {', '.join(intent_names)}."

    # Determine tools from distribution + discovered data sources
    has_structured = type_dist.get("lookup", 0) + type_dist.get("aggregation", 0) > 0
    has_unstructured = type_dist.get("policy", 0) > 0
    sv_list = data_sources.get("semantic_views", [])
    search_list = data_sources.get("search_services", [])

    # Build YAML specification
    spec_lines = []
    spec_lines.append("models:")
    spec_lines.append("  orchestration: claude-opus-4-5")
    spec_lines.append("")
    spec_lines.append("orchestration:")
    spec_lines.append("  budget:")
    spec_lines.append("    seconds: 600")
    spec_lines.append("    tokens: 16000")
    spec_lines.append("")
    spec_lines.append("instructions:")

    # Escape quotes for YAML string values
    escaped_response = response_instr.replace('"', '\\"')
    spec_lines.append(f'  response: "{escaped_response}"')
    if orchestration_instr:
        escaped_orch = orchestration_instr.replace('"', '\\"')
        spec_lines.append(f'  orchestration: "{escaped_orch}"')

    # Tools — include tools when a resource is specified (manual or discovered)
    sv_resource = st.session_state.get("_sv_resource", "")
    ss_resource = st.session_state.get("_ss_resource", "")
    
    tools_added = []
    if sv_resource:
        tools_added.append("Analyst1")
    if ss_resource:
        tools_added.append("Search1")
    
    if tools_added:
        spec_lines.append("")
        spec_lines.append("tools:")
        if "Analyst1" in tools_added:
            spec_lines.append("  - tool_spec:")
            spec_lines.append('      type: "cortex_analyst_text_to_sql"')
            spec_lines.append('      name: "Analyst1"')
            spec_lines.append('      description: "Queries structured data using natural language"')
        if "Search1" in tools_added:
            spec_lines.append("  - tool_spec:")
            spec_lines.append('      type: "cortex_search"')
            spec_lines.append('      name: "Search1"')
            spec_lines.append('      description: "Searches documents and policy content"')

        spec_lines.append("")
        spec_lines.append("tool_resources:")
        if "Analyst1" in tools_added:
            spec_lines.append("  Analyst1:")
            spec_lines.append(f'    semantic_view: "{sv_resource}"')
            spec_lines.append('    execution_environment:')
            spec_lines.append('      type: "warehouse"')
            spec_lines.append('      warehouse: "' + st.session_state.get('agent_warehouse', 'COMPUTE_WH') + '"')
        if "Search1" in tools_added:
            spec_lines.append("  Search1:")
            spec_lines.append(f'    name: "{ss_resource}"')
            spec_lines.append('    max_results: "5"')

    spec_yaml = "\n".join(spec_lines)
    agent_name = st.session_state.get("eval_agent_name", "MY_AGENT")
    agent_db = st.session_state.get("agent_db", "")
    agent_schema = st.session_state.get("agent_schema", "")
    
    # Use fully qualified name if db/schema are set
    if agent_db and agent_schema:
        fq_name = f"{agent_db}.{agent_schema}.{agent_name}"
    else:
        fq_name = agent_name
    
    comment = f"Phase 1: {phase1.get('role', 'business user')} assistant"

    ddl = f"""CREATE OR REPLACE AGENT {fq_name}
  COMMENT = '{comment}'
  FROM SPECIFICATION
  $$
{spec_yaml}
  $$;"""

    return ddl


def build_eval_sql():
    eval_dataset = st.session_state.get("eval_dataset", [])
    if not eval_dataset:
        return "-- No eval dataset generated yet. Complete Step 4 first."
    
    agent_name = st.session_state.get("eval_agent_name", "MY_AGENT")
    table_name = f"{agent_name}_EVAL_QUESTIONS"
    dataset_name = f"{agent_name}_EVAL_DATASET"
    
    lines = [
        f"CREATE OR REPLACE TABLE {table_name} (\n    INPUT_QUERY VARCHAR,\n    GROUND_TRUTH VARIANT\n);\n",
    ]
    
    for q in eval_dataset:
        gt_obj = {
            "ground_truth_output": q["ground_truth_output"],
            "intent": q["intent"],
            "process": q["process"],
        }
        gt_json = json.dumps(gt_obj).replace("$$", "$ $")
        query = q["input_query"].replace("$$", "$ $")
        lines.append(f"INSERT INTO {table_name} SELECT $${query}$$, PARSE_JSON($${gt_json}$$);")
    
    lines.append("")
    lines.append("-- Register as evaluation dataset")
    lines.append(f"""CALL SYSTEM$CREATE_EVALUATION_DATASET(
  'Cortex Agent',
  '{table_name}',
  '{dataset_name}',
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
    
    col_db, col_schema, col_name = st.columns(3)
    with col_db:
        agent_db = st.text_input("Database", value=st.session_state.get("data_sources", {}).get("database", ""), key="agent_db", placeholder="MY_DATABASE")
    with col_schema:
        agent_schema = st.text_input("Schema", value=st.session_state.get("data_sources", {}).get("schema", "PUBLIC"), key="agent_schema", placeholder="PUBLIC")
    with col_name:
        agent_name_input = st.text_input("Agent name", value=st.session_state.get("eval_agent_name", "MY_AGENT"), key="agent_name_input")
    
    # Tool resources — manual override or auto-populated from discovery
    st.markdown("**Tool Resources** (leave blank to omit from spec)")
    data_sources = st.session_state.get("data_sources", {})
    sv_default = data_sources.get("semantic_views", [{}])[0].get("fq_name", "") if data_sources.get("semantic_views") else ""
    ss_default = data_sources.get("search_services", [{}])[0].get("fq_name", "") if data_sources.get("search_services") else ""
    
    col_sv, col_ss, col_wh = st.columns(3)
    with col_sv:
        sv_resource = st.text_input("Semantic View (for Cortex Analyst)", value=sv_default, key="sv_resource", placeholder="DB.SCHEMA.MY_SEMANTIC_VIEW")
    with col_ss:
        ss_resource = st.text_input("Cortex Search Service", value=ss_default, key="ss_resource", placeholder="DB.SCHEMA.MY_SEARCH_SERVICE")
    with col_wh:
        wh_resource = st.text_input("Warehouse (for Analyst queries)", value="COMPUTE_WH", key="agent_warehouse", placeholder="MY_WAREHOUSE")
    
    # Store for build_agent_ddl
    st.session_state.eval_agent_name = agent_name_input
    st.session_state._sv_resource = sv_resource
    st.session_state._ss_resource = ss_resource
    
    ddl = build_agent_ddl()
    edited_ddl = st.text_area("Agent DDL (editable)", value=ddl, height=400)
    st.session_state.agent_ddl = edited_ddl
    
    if st.button("Execute DDL in Snowflake", type="primary"):
        if not agent_db or not agent_schema:
            st.error("Database and Schema are required to deploy the agent.")
        else:
            try:
                session = get_session()
                session.sql(f"USE DATABASE {agent_db}").collect()
                session.sql(f"USE SCHEMA {agent_schema}").collect()
                session.sql(edited_ddl).collect()
                st.success(f"Agent `{agent_db}.{agent_schema}.{agent_name_input}` created successfully!")
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
                
                agent_name_for_eval = st.session_state.get("eval_agent_name", "MY_AGENT")
                table_name = f"{agent_name_for_eval}_EVAL_QUESTIONS"
                dataset_name = f"{agent_name_for_eval}_EVAL_DATASET"
                
                # Deduplicate by input_query (keep first occurrence)
                seen = set()
                unique_dataset = []
                for q in eval_dataset:
                    if q["input_query"] not in seen:
                        seen.add(q["input_query"])
                        unique_dataset.append(q)
                
                if len(unique_dataset) < len(eval_dataset):
                    st.info(f"Removed {len(eval_dataset) - len(unique_dataset)} duplicate question(s).")
                
                # Create table
                session.sql(f"CREATE OR REPLACE TABLE {table_name} (INPUT_QUERY VARCHAR, GROUND_TRUTH VARIANT)").collect()
                
                # Insert rows
                for q in unique_dataset:
                    gt_obj = json.dumps({
                        "ground_truth_output": q["ground_truth_output"],
                        "intent": q["intent"],
                        "process": q["process"],
                    })
                    query = q["input_query"]
                    session.sql(f"INSERT INTO {table_name} SELECT $${query}$$, PARSE_JSON($${gt_obj}$$)").collect()
                
                # Register dataset
                session.sql(f"DROP DATASET IF EXISTS {dataset_name}").collect()
                session.sql(f"""
                    CALL SYSTEM$CREATE_EVALUATION_DATASET(
                      'Cortex Agent', '{table_name}', '{dataset_name}',
                      OBJECT_CONSTRUCT('query_text', 'INPUT_QUERY', 'expected_tools', 'GROUND_TRUTH')
                    )
                """).collect()
                
                st.success(f"Eval dataset registered: {dataset_name} ({len(unique_dataset)} questions)")
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
