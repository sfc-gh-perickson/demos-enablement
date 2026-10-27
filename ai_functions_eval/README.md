# AI Functions Lifecycle: Evaluate → Optimize → Monitor

Customer enablement deck and demo for taking Snowflake AI functions (`AI_COMPLETE` with structured output) from prototype to production.

**Use case:** support-ticket triage. One call extracts `product`, `issue_type`, `sentiment`, `requested_action`, `order_id`, and an `escalation_flag`.

## Contents

| File | Purpose |
|---|---|
| `presentations/ai-functions-evaluate-optimize-monitor.html` | 18-slide deck (self-contained HTML; open in a browser) |
| `presentations/ai-functions-evaluate-optimize-monitor-speaker-notes.md` | Talk track, internal context, doc links |
| `setup.sql` | Creates `AI_FUNCTIONS_EVAL_DEMO` (RAW/EVAL/PROD) and 300 synthetic labeled tickets (50 train / 50 holdout / 200 prod) |
| `01_baseline_function.sql` | Naive baseline `CREATE AI FUNCTION` (claude-sonnet-4-6) |
| `03_optimized_function_v2.sql` | Optimized body (experiment run ITER_21) + explicit escalation rule, i.e. the deployed version |
| `04_production_monitoring.sql` | Stream + task pipeline, cost/health/drift/quality views, sampled-judge task, alert |
| `ai_functions_lifecycle.ipynb` | Snowflake Workspace notebook walking the whole lifecycle |

## Run order

1. `setup.sql` (≈5 min; generates ticket text with AI_COMPLETE)
2. `01_baseline_function.sql`
3. Notebook `ai_functions_lifecycle.ipynb`
   - `RUN_LIVE = False` (default) reads the pre-run experiments, so the demo is instant
   - `RUN_LIVE = True` launches new evaluation and optimization experiments (the optimization takes ≈25 min on the `light` budget)
4. `03_optimized_function_v2.sql` with the name changed to `PROD.TRIAGE_TICKET` (or `CREATE AI FUNCTION ... FROM EXPERIMENT ... RUN ...`)
5. `04_production_monitoring.sql`

## Prerequisites

- Role with CREATE DATABASE, plus Cortex access (`SNOWFLAKE.CORTEX_USER`)
- `IMPORTED PRIVILEGES` on the `SNOWFLAKE` database, needed for the usage-history cost views
- **`GRANT EXECUTE ALERT ON ACCOUNT TO ROLE <owner>`** (run as ACCOUNTADMIN). This hasn't been granted on `parker_demo` yet, so `TRIAGE_QUALITY_ALERT` fails until it is.
- AI Function Studio / evaluation / optimization experiments are in **preview**

## Results from the reference run (holdout, reviewed labels v2)

| Function | Relative cost | LLM judge | All fields correct |
|---|---|---|---|
| Baseline (Sonnet, naive prompt) | 1.0× | 0.30 | 0% |
| Optimized gpt-5-nano | ~0.08× | 0.52 | 56% |
| Optimized ministral-3-8b | ~0.03× | 0.56 | 50% |
| Optimized Sonnet | ~1.9× | 0.66 | 68% |
| **Optimized Sonnet + explicit rule (deployed)** | ~1.9× | **0.80** | **82%** |

## Gotchas found while building

- An evaluation spec needs a top-level `evaluation:` block, or the run fails right after `EXECUTE`.
- `llm_judge` didn't accept `task_description` / `metric_options` in the spec on this account.
- `mistral-small2` wasn't an allowed optimization model; `ministral-3-8b` was used instead.
- Holdout scores are only recorded for frontier runs. Deploy each model's best run and evaluate it separately.
- The optimizer added an `"other"` category to the enum. Production health monitoring caught it (4.5% of rows); remove it in the next version.

## Cleanup

```sql
ALTER TASK AI_FUNCTIONS_EVAL_DEMO.PROD.TRIAGE_TICKETS_TASK SUSPEND;
ALTER TASK AI_FUNCTIONS_EVAL_DEMO.PROD.JUDGE_SAMPLE_TASK SUSPEND;
ALTER ALERT AI_FUNCTIONS_EVAL_DEMO.PROD.TRIAGE_QUALITY_ALERT SUSPEND;
DROP DATABASE AI_FUNCTIONS_EVAL_DEMO;
```
