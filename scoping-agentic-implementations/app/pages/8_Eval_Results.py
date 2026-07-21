import streamlit as st
import pandas as pd
from utils.snowflake_conn import get_session

st.header("Step 8: Eval Results")
st.markdown("Enter a run name to load evaluation results, broken down by metric, business intent, and technical type.")

col_db, col_schema, col_agent = st.columns(3)
with col_db:
    agent_db = st.text_input("Database", value=st.session_state.get("agent_db", ""), key="eval_results_db", placeholder="MY_DATABASE")
with col_schema:
    agent_schema = st.text_input("Schema", value=st.session_state.get("agent_schema", "PUBLIC"), key="eval_results_schema", placeholder="PUBLIC")
with col_agent:
    agent_name = st.text_input("Agent name", value=st.session_state.get("eval_agent_name", ""), key="eval_results_agent", placeholder="MY_AGENT")

if not agent_db or not agent_name:
    st.warning("Enter the database and agent name above to continue.")
    st.stop()

# --- Run name input ---
run_name = st.text_input("Eval run name", value="baseline-v1", placeholder="e.g., baseline-v1, improved-v2")

if not run_name:
    st.stop()

# --- Actions ---
col_run, col_load = st.columns(2)

with col_run:
    if st.button("Start Evaluation"):
        try:
            import tempfile
            session = get_session()
            session.sql(f"USE DATABASE {agent_db}").collect()
            session.sql(f"USE SCHEMA {agent_schema}").collect()
            
            # Ensure stage and config exist
            session.sql("CREATE STAGE IF NOT EXISTS EVAL_STAGE").collect()
            yaml_content = st.session_state.get("eval_config_yaml", "")
            if yaml_content:
                import os
                tmp_dir = tempfile.gettempdir()
                config_filename = f"{agent_name.lower()}_eval_config.yaml"
                tmp_path = os.path.join(tmp_dir, config_filename)
                with open(tmp_path, "w") as f:
                    f.write(yaml_content)
                session.sql(f"PUT 'file://{tmp_path}' @EVAL_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE").collect()
            
            config_stage_path = f"@{agent_db}.{agent_schema}.EVAL_STAGE/{agent_name.lower()}_eval_config.yaml"
            session.sql(f"""
                CALL EXECUTE_AI_EVALUATION(
                    'START',
                    OBJECT_CONSTRUCT('run_name', '{run_name}'),
                    '{config_stage_path}'
                )
            """).collect()
            st.success(f"Evaluation '{run_name}' started. Wait a few minutes, then click Load Results.")
        except Exception as e:
            st.error(f"Error: {e}")

with col_load:
    if st.button("Load Results", type="primary"):
        st.session_state._eval_results_loaded = run_name

if st.session_state.get("_eval_results_loaded") != run_name:
    st.info("Enter a run name and click **Load Results**.")
    st.stop()

# --- Query results ---
try:
    session = get_session()
    session.sql(f"USE DATABASE {agent_db}").collect()
    session.sql(f"USE SCHEMA {agent_schema}").collect()

    results_df = session.sql(f"""
        SELECT
            r.INPUT,
            r.METRIC_NAME,
            r.METRIC_TYPE,
            r.EVAL_AGG_SCORE,
            r.OUTPUT,
            r.METRIC_CALLS
        FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_EVALUATION_DATA(
            '{agent_db}', '{agent_schema}', '{agent_name}', 'CORTEX AGENT', '{run_name}'
        )) r
    """).to_pandas()

    breakdown_df = session.sql(f"""
        SELECT
            e.GROUND_TRUTH:process::VARCHAR AS PROCESS,
            e.GROUND_TRUTH:intent::VARCHAR AS INTENT,
            r.INPUT,
            r.METRIC_NAME,
            r.EVAL_AGG_SCORE,
            r.METRIC_CALLS[0]:explanation::VARCHAR AS EXPLANATION
        FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_EVALUATION_DATA(
            '{agent_db}', '{agent_schema}', '{agent_name}', 'CORTEX AGENT', '{run_name}'
        )) r
        JOIN {agent_name}_EVAL_QUESTIONS e ON r.INPUT = e.INPUT_QUERY
    """).to_pandas()

except Exception as e:
    st.error(f"Error loading results: {e}")
    st.stop()

if results_df.empty:
    st.warning("No results found. The evaluation may still be running or the run name may be incorrect.")
    st.stop()

# --- Overall Scores by Metric ---
st.markdown("---")
st.markdown("### Overall Scores by Metric")

overall = results_df.groupby("METRIC_NAME").agg(
    AVG_SCORE=("EVAL_AGG_SCORE", "mean"),
    MIN_SCORE=("EVAL_AGG_SCORE", "min"),
    MAX_SCORE=("EVAL_AGG_SCORE", "max"),
    COUNT=("EVAL_AGG_SCORE", "count"),
).round(3).reset_index()

st.dataframe(overall, use_container_width=True, hide_index=True)

# Normalize scores to 0-1 using metric scale from config
# Built-in metrics: 0-1 scale. Custom metrics: max from score_ranges config.
metric_scales = {"answer_correctness": 1.0, "logical_consistency": 1.0}
# tool_selection hardcoded in eval config as max_score [7, 10]
metric_scales["tool_selection"] = 10.0
# Custom metrics from session state
for cm in st.session_state.get("custom_metrics", []):
    # score_ranges.max_score is [lower_bound, upper_bound] — upper is the scale max
    metric_scales[cm["name"]] = 10.0  # default; override if we parse ranges later

chart_data = overall.copy()
chart_data["NORMALIZED_SCORE"] = chart_data.apply(
    lambda row: row["AVG_SCORE"] / metric_scales.get(row["METRIC_NAME"], row["MAX_SCORE"]),
    axis=1,
)
st.bar_chart(chart_data.set_index("METRIC_NAME")["NORMALIZED_SCORE"])

# --- Breakdown by Business Intent ---
if not breakdown_df.empty:
    st.markdown("---")
    st.markdown("### Scores by Business Intent")

    intent_pivot = breakdown_df.pivot_table(
        index="INTENT",
        columns="METRIC_NAME",
        values="EVAL_AGG_SCORE",
        aggfunc="mean",
    ).round(3)

    st.dataframe(intent_pivot, use_container_width=True)

    # --- Breakdown by Technical Type ---
    st.markdown("---")
    st.markdown("### Scores by Technical Type (Process)")

    process_pivot = breakdown_df.pivot_table(
        index="PROCESS",
        columns="METRIC_NAME",
        values="EVAL_AGG_SCORE",
        aggfunc="mean",
    ).round(3)

    st.dataframe(process_pivot, use_container_width=True)

    # --- Full Pivot (Process x Intent x Metric) ---
    st.markdown("---")
    st.markdown("### Full Breakdown: Process x Intent")

    full_pivot = breakdown_df.pivot_table(
        index=["PROCESS", "INTENT"],
        columns="METRIC_NAME",
        values="EVAL_AGG_SCORE",
        aggfunc="mean",
    ).round(3)

    st.dataframe(full_pivot, use_container_width=True)

    # --- Lowest-Scoring Questions ---
    st.markdown("---")
    st.markdown("### Lowest-Scoring Questions")
    st.markdown("Questions where the agent performed worst — candidates for iteration.")

    lowest = breakdown_df.nsmallest(10, "EVAL_AGG_SCORE")[
        ["INPUT", "METRIC_NAME", "EVAL_AGG_SCORE", "PROCESS", "INTENT", "EXPLANATION"]
    ].rename(columns={
        "INPUT": "Question",
        "METRIC_NAME": "Metric",
        "EVAL_AGG_SCORE": "Score",
        "PROCESS": "Type",
        "INTENT": "Intent",
        "EXPLANATION": "Judge Explanation",
    })

    st.dataframe(lowest, use_container_width=True, hide_index=True)
