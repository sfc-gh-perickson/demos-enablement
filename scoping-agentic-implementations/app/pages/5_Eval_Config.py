import streamlit as st
import pandas as pd
import json
from utils.snowflake_conn import get_session
from utils.ai_complete import ai_complete

st.header("Step 4: Eval Configuration")
st.markdown("""
Generate ground-truth descriptions for your expanded dataset and configure the evaluation metrics.
The output is a registered eval dataset + YAML config ready for `EXECUTE_AI_EVALUATION`.
""")

TYPE_TO_PROCESS = {
    "lookup": "single_tool",
    "aggregation": "single_tool",
    "reasoning": "multi_tool",
    "policy": "single_tool",
    "out_of_scope": "refusal",
}

expanded = st.session_state.get("expanded_questions", [])
if not expanded:
    st.warning("Complete the Synthetic Expansion step first.")
    st.stop()

# --- Ground Truth Generation ---
st.subheader("Generate Ground Truth")
st.markdown(f"Dataset has **{len(expanded)}** questions. AI_COMPLETE will draft ground-truth descriptions for each.")

if st.button("Generate Ground Truth", type="primary"):
    session = get_session()
    eval_dataset = []
    progress = st.progress(0)
    
    # Build data profile context if available
    profile = st.session_state.get("_data_profile", {})
    profile_context = ""
    if profile:
        lines = []
        for tbl_name, cols in profile.items():
            for col_name, info in cols.items():
                if info["type"] == "categorical":
                    lines.append(f"- {col_name}: {', '.join(info['values'][:8])}")
                elif info["type"] == "date_range":
                    lines.append(f"- {col_name} date range: {info['min']} to {info['max']}")
                elif info["type"] == "numeric_range":
                    lines.append(f"- {col_name} range: {info['min']} to {info['max']}")
        profile_context = "\n".join(lines[:20])
    
    for idx, q in enumerate(expanded):
        progress.progress((idx + 1) / len(expanded), text=f"Processing {idx + 1}/{len(expanded)}...")
        
        process = TYPE_TO_PROCESS.get(q["technical_type"], "single_tool")
        source = q.get("source", "manual")
        is_unanswerable = source == "synthetic_unanswerable" or q["technical_type"] == "out_of_scope"
        
        data_section = ""
        if profile_context and not is_unanswerable:
            data_section = f"\nActual data available:\n{profile_context}\nUse real values to make ground truth specific."
        elif profile_context and is_unanswerable:
            data_section = f"\nData boundaries:\n{profile_context}\nThis question asks OUTSIDE these boundaries. Ground truth should state the agent cannot answer."
        
        prompt = f"""Generate a ground-truth description for evaluating an AI agent's response.

Question: {q['question']}
Category: {q['business_intent']}
Technical type: {q['technical_type']} (process: {process})
Source: {source}{data_section}

Write 2-3 sentences describing:
- What a correct answer SHOULD contain (or why it should refuse)
- What it should NOT contain or do
- Be specific enough to validate but flexible for non-deterministic responses

Return ONLY the description text."""

        gt_text = ai_complete(session, prompt)
        
        eval_dataset.append({
            "input_query": q["question"],
            "ground_truth_output": gt_text,
            "intent": q["business_intent"],
            "process": process,
            "technical_type": q["technical_type"],
            "risk": q["risk"],
        })
    
    progress.progress(1.0, text="Done!")
    st.session_state.eval_dataset = eval_dataset
    st.rerun()

# Display and edit ground truth
eval_dataset = st.session_state.get("eval_dataset", [])
if eval_dataset:
    st.markdown("---")
    st.subheader("Review Ground Truth")
    st.markdown("Edit ground-truth descriptions as needed:")
    
    df = pd.DataFrame(eval_dataset)
    edited = st.data_editor(
        df[["input_query", "ground_truth_output", "intent", "process"]],
        column_config={
            "input_query": st.column_config.TextColumn("Question", width="medium", disabled=True),
            "ground_truth_output": st.column_config.TextColumn("Ground Truth", width="large"),
            "intent": st.column_config.TextColumn("Intent", disabled=True),
            "process": st.column_config.TextColumn("Process", disabled=True),
        },
        use_container_width=True,
        key="gt_editor",
    )
    
    # Update ground truth from edits
    for i, row in edited.iterrows():
        if i < len(st.session_state.eval_dataset):
            st.session_state.eval_dataset[i]["ground_truth_output"] = row["ground_truth_output"]

    # --- Eval Config YAML ---
    st.markdown("---")
    st.subheader("Evaluation Metrics")
    
    agent_name = st.text_input("Agent name (for eval config)", value="YOUR_AGENT_NAME", key="eval_agent_name")
    
    st.markdown("**Built-in metrics:**")
    col1, col2 = st.columns(2)
    with col1:
        use_correctness = st.checkbox("answer_correctness", value=True)
        use_consistency = st.checkbox("logical_consistency", value=True)
    with col2:
        use_tool_selection = st.checkbox("tool_selection (custom)", value=True)
    
    # --- Custom Metric Builder ---
    st.markdown("---")
    st.markdown("**Custom Metrics**")
    st.markdown("Define domain-specific metrics with custom scoring prompts. Available template variables: `{{input}}`, `{{output}}`, `{{tool_info}}`, `{{ground_truth}}`.")
    
    if "custom_metrics" not in st.session_state:
        st.session_state.custom_metrics = []
    
    # Add new custom metric
    with st.expander("Add Custom Metric"):
        cm_name = st.text_input("Metric name (snake_case)", key="cm_name", placeholder="brand_compliance")
        cm_description = st.text_input(
            "What does this metric measure?", key="cm_desc",
            placeholder="e.g., Check if response cites source documents and avoids speculation"
        )
        
        cm_prompt = ""
        if cm_description and st.button("Generate Scoring Prompt from Description"):
            session = get_session()
            gen_prompt = f"""Write a scoring rubric prompt for an LLM-as-Judge evaluation metric.

Metric name: {cm_name or "custom_metric"}
What it measures: {cm_description}

The prompt will be used to score an AI agent's response on a 1-10 scale.
Available template variables (include ALL of these in your prompt):
- {{{{input}}}} = the user's original question
- {{{{output}}}} = the agent's response
- {{{{tool_info}}}} = which tools the agent called
- {{{{ground_truth}}}} = expected behavior description

Write the scoring prompt with:
1. Clear description of what to evaluate
2. The template variables placed where relevant
3. Score ranges: 1-3 = poor, 4-6 = acceptable, 7-10 = excellent
4. Specific criteria for each range

Return ONLY the prompt text, no wrapping."""
            
            with st.spinner("Generating scoring prompt..."):
                cm_prompt = ai_complete(session, gen_prompt)
            st.session_state.cm_prompt_area = cm_prompt
            st.rerun()
        
        cm_prompt_final = st.text_area(
            "Scoring prompt (edit as needed)", height=200, key="cm_prompt_area",
            placeholder="Evaluate whether the response...\n\nUser query: {{input}}\nAgent response: {{output}}\n..."
        )
        
        def _add_metric():
            st.session_state.custom_metrics.append({
                "name": st.session_state.cm_name,
                "description": st.session_state.cm_desc,
                "prompt": st.session_state.cm_prompt_area,
            })
            st.session_state.cm_prompt_area = ""
            st.session_state.cm_name = ""
            st.session_state.cm_desc = ""

        st.button("Add Metric", on_click=_add_metric, disabled=not (cm_name and cm_prompt_final))
    
    # Display existing custom metrics
    if st.session_state.custom_metrics:
        st.markdown(f"**{len(st.session_state.custom_metrics)} custom metric(s) defined:**")
        for i, cm in enumerate(st.session_state.custom_metrics):
            with st.expander(f"{cm['name']} — {cm['description'][:60]}"):
                st.code(cm["prompt"], language="text")
                if st.button(f"Remove", key=f"remove_cm_{i}"):
                    st.session_state.custom_metrics.pop(i)
                    st.rerun()
    
    # --- Build YAML ---
    st.markdown("---")
    st.subheader("Eval Config Preview")

    def _indent_prompt(text, spaces=6):
        """Indent each line of a prompt for YAML block scalar."""
        lines = text.rstrip().split("\n")
        return "\n".join((" " * spaces) + line if line.strip() else "" for line in lines)

    metrics_lines = []
    if use_correctness:
        metrics_lines.append('  - "answer_correctness"')
    if use_consistency:
        metrics_lines.append('  - "logical_consistency"')
    if use_tool_selection:
        metrics_lines.append("""  - name: "tool_selection"
    score_ranges:
      min_score: [1, 3]
      median_score: [4, 6]
      max_score: [7, 10]
    prompt: |
      Evaluate whether the agent selected the correct tool(s) for the user's query.

      User query: {{input}}
      Tools used: {{tool_info}}
      Expected behavior: {{ground_truth}}
      Agent response: {{output}}

      Rate from 1-10:
      1-3 = Wrong tool selected or unnecessary tool calls
      4-6 = Partially correct (right primary tool but missed secondary, or redundant calls)
      7-10 = Optimal tool selection for the query intent

      For out-of-scope questions, score 7-10 only if the agent refused without calling tools.""")

    for cm in st.session_state.custom_metrics:
        prompt_block = _indent_prompt(cm["prompt"])
        metrics_lines.append(f"""  - name: "{cm['name']}"
    score_ranges:
      min_score: [1, 3]
      median_score: [4, 6]
      max_score: [7, 10]
    prompt: |
{prompt_block}""")

    metrics_block = "\n".join(metrics_lines)

    yaml_content = f"""evaluation:
  agent_params:
    agent_name: "{agent_name}"
    agent_type: "CORTEX AGENT"
  run_params:
    label: "Scoping workshop baseline"
  source_metadata:
    type: "dataset"
    dataset_name: "{agent_name}_EVAL_DATASET"

metrics:
{metrics_block}
"""

    st.session_state.eval_config_yaml = yaml_content
    st.code(yaml_content, language="yaml")
