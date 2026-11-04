---
name: agent-pareto-lab
description: "Spin up Cortex Agent variants (model x prompt x tools x budget) from an existing agent config directory, run one evaluation per variant on a fixed dataset, attribute billed cost per request, and compute the cost/quality Pareto frontier. Use when: comparing agent versions or models on cost vs accuracy, choosing an orchestration model, proving a lean prompt is cheaper without new wrong answers, A/B/C agent eval with cost. Triggers: pareto frontier, agent cost vs accuracy, compare agent models, agent variant matrix, which model should my agent use, cheapest agent that is still correct, agent eval with cost, agent A/B test."
---

# Agent Pareto Lab

Turns one existing agent config into N committed versions, evaluates each version once on the same dataset,
joins billed credits per request, and reports which variants are on the cost/quality frontier.
Reporting/HTML is delegated to the `benchmark-report` skill.

Scripts live in this skill's `scripts/` dir (`<SKILL>` below). Run them with the user's Python
(`jinja2`, `pyyaml`, `snowflake-connector-python`). All Snowflake access uses `connection` from `lab.yaml`.

## Inputs (the user's lab directory)
- `specs/*.json`: the agent spec(s). Required: one base spec. Optional: a production replica spec.
- An eval dataset already registered with `SYSTEM$CREATE_EVALUATION_DATASET` (input query + ground truth).
  If only a table exists, offer to register it; if nothing exists, stop: building ground truth is out of scope.
- Optional judge prompts. Templates: `<SKILL>/templates/judges/`.

## Hard rules
- Never `CREATE OR REPLACE` the agent and never re-alias or edit a committed version. A change = a new alias.
- Never overwrite an uploaded eval config or restart an existing run name. A changed dataset, judge or config
  = a new `run_prefix`.
- Each variant gets its own tool warehouse (cost attribution); eval orchestration uses `eval_warehouse`.
- Don't report a frontier as final while billing is incomplete.
- Agent calls from this skill go through SQL (`DATA_AGENT_RUN`), not the REST API.
- Never launch all variants before a single pilot run has scored on every metric.
- One eval run per variant (`repeats: 1`). Do not propose or run repeats of the same version; spend the
  budget on more variants instead. Small score gaps between variants are within run-to-run noise: say so
  rather than declaring a winner on a gap of a few points.

## Workflow

### 1. Intake
1. Read the lab directory: spec files, existing eval YAMLs/SQL, any results notes.
2. `DESCRIBE AGENT <fqn>` and `SHOW VERSIONS IN AGENT <fqn>`: record existing versions/aliases and the owner.
   Set `role` in lab.yaml to a role that can modify the agent AND read the dataset (check `SHOW DATASETS` owner);
   a role that can't read the dataset fails with a misleading "does not exist".
   The DEFAULT/FIRST version is often an old spec: compare it with the live spec before choosing the base.
3. Confirm the dataset exists (`SHOW DATASETS IN SCHEMA`, the name the user gives may be misspelled) and inspect
   a few rows of the table behind it. Check the ground-truth VARIANT keys against the metrics (see the template):
   `tool_selection_accuracy` needs `ground_truth_invocations`; a dataset with only `expected_tools` (or any
   other key) scores every row as "expected 0 tools". Flag placeholder answers (`ROAS of X, Y`) and questions
   whose ground truth depends on "today" (today/yesterday/MTD/QTD/last week). If keys don't match, drop the
   metric or rebuild ground truth before running anything.
4. Copy `<SKILL>/templates/lab.yaml` into the lab dir and fill it in. Derive variants from what the user wants
   to compare; express each as a JSON merge patch on the base spec (e.g. `{models: {orchestration: X}}`).
   Check model availability in the region with `cortex search docs` if unsure.
   **Naming:** give each variant a short `name` that says what changed (`auto`, `sonnet55`, `haiku45_orch2`);
   never put the `run_prefix` in it. The scripts derive agent alias = eval run name = `<run_prefix>_<name>`
   (e.g. `r1_sonnet55`). Use a short round id as `run_prefix` (`r1`, `r2`, ...).

**⛔ STOP:** show the variant matrix, metrics and objectives (and constraints). Get approval.
Remind: cost scales with variants x questions.

### 2. Generate versions
```
python <SKILL>/scripts/generate.py lab.yaml --diff     # per-variant diff vs base spec
python <SKILL>/scripts/generate.py lab.yaml --assume-existing <N>   # offline render; N = committed versions today
```
(Omit `--assume-existing` only for a brand-new agent; otherwise the preview shows `CREATE AGENT` and maps the first
variant onto `VERSION$1`. `--apply` always adds new versions regardless.)
**⛔ STOP:** show the diffs and `versions.sql`. On approval:
```
CREATE WAREHOUSE IF NOT EXISTS <each variant warehouse + eval_warehouse> WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 INITIALLY_SUSPENDED = TRUE;
python <SKILL>/scripts/generate.py lab.yaml --apply    # creates missing versions + aliases, re-renders eval YAMLs
python <SKILL>/scripts/smoke.py lab.yaml "<one dataset question>"   # one question per version, in SQL
```
Smoke tests use SQL only: `SNOWFLAKE.CORTEX.DATA_AGENT_RUN('<db.schema.agent>!<ALIAS>', '<request json>')`.
The version goes after `!` in the name (`!VERSION$3`, `!R1_SONNET55`, `!LIVE`), never as a third argument (that is
`create_thread_if_not_present`). The alias must be UPPER case: lower case returns an error object
(`code`/`message`, no `content`) instead of raising. Don't use the REST run endpoint. Note per-version latency:
a model that is many times slower here will dominate eval wall time.

### 3. Preflight and pilot
```
python <SKILL>/scripts/preflight.py lab.yaml           # dataset/ground-truth keys vs metrics, placeholders, warehouses
python <SKILL>/scripts/run_evals.py lab.yaml --only <cheapest variant>   # pilot: one run, wait for it
```
Fix every preflight ERROR first. Then run ONE variant and check it before starting the rest: every metric must
score (`GET_AI_EVALUATION_DATA(...)` grouped by `METRIC_NAME`: `METRIC_STATUS` code 200, plausible `EVAL_AGG_SCORE`,
and `METRIC_CALLS` showing the expected ground truth, e.g. not "Expected: [] (0 tools)" on every row).
A broken metric found in the pilot costs 1 run; found after launch it costs all of them.
**⛔ STOP:** show the pilot's per-metric coverage; on approval start the rest.

### 4. Run evaluations
```
python <SKILL>/scripts/run_evals.py lab.yaml --dry-run # list run names/configs
python <SKILL>/scripts/run_evals.py lab.yaml           # upload configs, start runs, poll to terminal state
```
Long-running: run it in the background and check output. Resume polling with `--poll-only`.
Report any run that isn't COMPLETED; don't drop it silently. A run is FAILED when ANY metric fails on any record
(STATUS_DETAILS names it, e.g. `Metric 'answer_correctness$v3' failed`), even though the agent answered and the
other metrics scored. Check the per-metric data before discarding it; to use such runs pass them via `--runs` and
treat the failed metric as missing for that run. Cancel a run with
`CALL EXECUTE_AI_EVALUATION('CANCEL', OBJECT_CONSTRUCT('run_name', '<run>'), '<config stage path>')`.

### 5. Wait for billing
```
python <SKILL>/scripts/wait_billing.py lab.yaml        # exit 0 = every request billed; exit 2 = timeout
```
`CORTEX_AGENT_USAGE_HISTORY` lags hours. If the user won't wait, continue but label cost as partial.

### 6. Frontier
```
python <SKILL>/scripts/frontier.py lab.yaml
```
Creates `PARETO_<PREFIX>_*` views in the agent's schema (requests, request cost, run scorecard, run metrics,
warehouse credits), one run per variant, applies `constraints`, and marks each
variant `frontier`, `dominated` or `excluded` (no confidence intervals with a single run). Outputs `frontier.md`,
`frontier.json`, `frontier.svg` under `<out_dir>/<run_prefix>/`.
`credits_per_correct_answer` = credits per request x questions / answers with correctness >= `correct_threshold`.

### 7. Interpret and report
1. Read `frontier.md`. For each frontier variant state the trade-off in plain terms (cost/turn, correctness delta).
   Turn credits into dollars only with a credit price the user gives.
2. For dominated or low-scoring variants, read a few low-scored records
   (`GET_AI_EVALUATION_DATA(...)`: judge explanations are inside the `METRIC_CALLS` JSON, there is no
   `EXPLANATION` column) and separate ground-truth errors, judge variance and real
   agent failures. Ground-truth errors become a new dataset version + new `run_prefix`, never an edit.
3. Optionally hand the run names to `benchmark-report` for the HTML deck.
4. Write `RESULTS.md` in the lab dir: setup, version table, frontier table, findings, next variants.

**⛔ STOP:** present the frontier and recommendation; ask whether to run another round (new variants or prefix).

### 8. Teardown (warehouses)
When the user is done with the lab (no further rounds), drop the lab warehouses: every variant `warehouse` plus
`eval_warehouse` from `lab.yaml`. **⛔ STOP:** list them and confirm before dropping. Then:
```
SHOW WAREHOUSES LIKE '<lab warehouse prefix>%';          -- verify the exact set; never drop a shared warehouse
DROP WAREHOUSE IF EXISTS <each lab warehouse>;
```
- Do it after the frontier is final: dropping doesn't remove `WAREHOUSE_METERING_HISTORY`, but finish billing first.
- Committed agent versions still point at these warehouses and will fail if run again; only the versions
  promoted to production need a new version on a permanent warehouse.
- Teardown covers warehouses only; leave agent versions, eval runs, views and the config stage unless the
  user asks for more.

## Stopping points
- After intake (variant matrix + objectives)
- Before `--apply` (spec diffs)
- After the pilot run (every metric scored)
- After the frontier (recommendation, next round)
- Before teardown (list of warehouses to drop)

## Output
- New committed agent versions with aliases `<run_prefix>_<name>` (one per variant)
- Eval runs `<run_prefix>_<name>` visible in Snowsight > agent > Evaluations
- `PARETO_<PREFIX>_*` views; `frontier.{md,json,svg}`; `RESULTS.md`

## Troubleshooting
- `ADD LIVE VERSION` "already exists": expected right after `CREATE AGENT`; the script continues.
- Cost NULL: billing lag (step 5) or `since` set after the runs started.
- Legacy labs with explicit `alias:` still work (name = alias minus a leading `<run_prefix>_`). Runs started
  by older script versions were named `<run_prefix>_<alias>_r<k>`; point `frontier.py` at them with `runs.json`
  or `--runs` instead of relying on the default run list.
- Metric missing in the frontier: the metric name in `objectives` must match `METRIC_NAME` (lower-cased) or a
  scorecard column (`credits_per_request`, `p95_duration_s`, `avg_total_tokens`, ...).
