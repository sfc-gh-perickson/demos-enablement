-- =============================================================================
-- Run Cortex Agent Evaluation
-- Prerequisites: Agent and eval dataset must exist in the target database
-- =============================================================================

-- Run evaluation against the agent
SELECT CORTEX.RUN_EVALUATION(
    MODEL => '<database>.SEMANTIC.RETAIL_ASSISTANT',
    DATASET => '<database>.EVALUATION.AGENT_EVAL_DATASET',
    METRICS => ['tool_selection_accuracy', 'answer_correctness', 'logical_consistency']
) AS eval_run_id;
