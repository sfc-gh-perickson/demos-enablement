## Creating an Evaluation Dataset
* Create a dataset that reflects the distribution of usage that you expect the agent to recieve from users
    - happy paths
    - bad paths
    - high-risk
    - low-risk
* Make sure to represent high-risk paths in the eval dataset, and keep track of the agent's performance across the different intents. We need to measure not only the macro correctness, etc, but also the intent-level to gain confidence that the agent will behave in high-value and high-stakes areas.

## What is a Rubric?
A **rubric** is a collection of **metrics** that we would want to score the AI agent's performance on. This may be things like:
1) Overall correctness: did the agent get a correct answer?
2) Brand compliance: is the agent speaking in the brand's voice, not recommending competitors, etc.?
3) Context relevance: did our RAG system retrieve the correct context in order for the agent to make a good decision?
4) Many, many more that align with specific business needs.

## How to Evaluate
* Most evaluation is done with an LLM as a Judge (LLMAJ), where another LLM recieves the agent's trace and determines if it successfully completed the task at hand. 

* There is both trace-level and step-level evaluations to be performed. E.g. we want to make sure we are getting the correct output, and that we got the correct output through using the correct tools with the correct parameters

* A downside of LLMAJ is that you are trusting the LLM to make the decisions that a human would when grading a response - this is where LLMAJ tuning comes in. This process looks like:
    1) Starting with a dataset containing question, trace, and response triples from the AI agent and a rubric defining the base set of metrics
    2) Asking humans to label the same dataset across the rubric
    3) Starting with basic LLMAJ prompts, ask the LLMAJ that cover the rubric to grade the triples as well
    4) In a dev/test split, calculate the correlation between the human-graded and LLMAJ-graded scores on each data point in the dataset. Use a metric like Cohen's Kappa for this. We are shooting for an 80+% correlation score at both the dataset level as well as within the intents that we identified in creating the dataset
    5) Iterate upon the LLMAJ prompts in order to get the correlation score on the dev and test sets into that 80+% range. This effectively reduces the error bars on your metrics coming from the LLMAJ as it becomes more in-line with human SME judgement.

## Translating Evaluations into Guardrails and Monitoring
Once an LLMAJ is aligned to SME judgement, we can utilize it in a variety of different ways. The most simple way is to utilize it in offline monitoring situations, where we can sample a subset of agent traffic (maybe prioritizing areas where we get thumbs-down feedback from the user, a proportional traffic split, etc.) and keep track of the judge's scores across those outputs. Another thing that can be done to add robustness to the agent is potentially distilling some critical LLMAJs into smaller ML models that can become guardrails for the agent.

## Iterating upon the Agent Using Evaluation Metrics
Evaluations are the #1 way to effectively understand the behavior of your AI agent. This means that they are also critical in understanding how to better improve your agent over time, and making sure that no regressions are introduced. Utilize agent versioning to confidently iterate, test, and promote new agents into production.

---

## Automated Evaluation Patterns

### Eval Dataset as a Version-Controlled Artifact
* Store eval questions as a dbt seed file (CSV with `input` and `ground_truth` columns) in your git repo
* On merge, `dbt seed` loads the questions into a Snowflake table that your eval YAML config references
* This makes the eval dataset PR-reviewable and collaboratively editable — any analyst or engineer can contribute questions via a pull request
* Complement the static seed with active sampling from production: query `SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS` for real user questions, prioritize those with negative feedback or high token cost, and periodically add representative samples to the seed file

### CI/CD Integration with dbt + GitHub Actions
The pattern extends the standard dbt CI/CD workflow (Snowflake CLI GitHub Action + OIDC service user):

**CI (on PR):**
1. `snow dbt deploy tester_agent --force -x` deploys a staging agent version
2. `snow dbt execute ... seed` loads the eval dataset into Snowflake
3. `snow sql -q "CALL EXECUTE_AI_EVALUATION('START', OBJECT_CONSTRUCT('run_name', 'pr-${PR_NUMBER}'), '@stage/eval_config.yaml')"` triggers the evaluation
4. Poll `EXECUTE_AI_EVALUATION('STATUS', ...)` until the run completes
5. Query `GET_AI_EVALUATION_DATA` to extract aggregate scores
6. Fail the PR check if scores fall below the defined threshold

**CD (on merge to main):**
1. `snow dbt deploy production_agent --default-target prod --force -x` updates the production agent
2. `ALTER AGENT ... SET ALIAS 'production'` promotes the new version
3. Optionally trigger a post-deploy eval run for validation

### Scheduled Regression Detection via Snowflake Tasks
* A Snowflake Task runs daily or weekly, calling `EXECUTE_AI_EVALUATION` against the production alias
* A downstream task queries `GET_AI_EVALUATION_DATA` and compares scores to the previous run's baseline
* If scores drop below a threshold, trigger a notification integration (Slack/email) to alert the team
* The team correlates the drop timestamp with agent version history (`SHOW VERSIONS IN AGENT`) and git commit log to identify which change caused the regression

### Human Feedback Integration
* Store user feedback (thumbs up/down, free-text comments) in a Snowflake table alongside the interaction's `request_id` from observability views
* Use `CORTEX.COMPLETE` for lightweight sentiment/intent classification on feedback text — provides an aggregate signal on which question types are underperforming
* Periodically sample interactions with negative feedback, have SMEs grade them, and use those graded samples to recalibrate the LLM judge
* Practical calibration: 50-100 representative samples scored by humans, calculate Cohen's Kappa against the LLM judge, trust the judge on unscored traffic if correlation is 80%+

### Cost Governance as an Adoption Enabler
* Organizations often restrict Cortex access to SQL-literate power users because they cannot predict or control per-query costs
* The combination of eval-backed quality confidence + cost governance (resource budgets, runaway query protection, tag-based attribution) unlocks org-wide access
* Progression: observability (understand cost baseline) → budgets (set guardrails) → evals (prove quality) → expand access (roll out to non-technical users with confidence)