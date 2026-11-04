---
name: eval-rubric-builder
description: Run an onsite workshop that turns the business questions a customer cares about into a reviewed Cortex Agent evaluation dataset, a metric/rubric spec, and calibrated ground-truth-free LLM judges. Covers intake interview, question taxonomy, ground-truth drafting with literal values, CSV/Google Sheet review round-trip, ground-truth (Tier A) and ground-truth-free (Tier B) metrics including reference-free variants of the built-in agent metrics, judge calibration and prompt optimization against human scores with AI Function Studio, preflight lint, and hand-off to agent-pareto-lab / benchmark-report. Triggers: build eval dataset, eval rubric, design metrics for customer questions, onsite eval workshop, ground truth for agent, calibrate LLM judge, ground-truth-free metrics, reference-free judge, LLM-as-judge calibration, eval spec for customer.
---

# Eval Rubric Builder

Goal: in one onsite session, go from "the questions this customer cares about" to
(1) a reviewed eval dataset, (2) a metric spec the customer signs off on, and
(3) ground-truth-free judges calibrated to human scores so most future scoring needs no human.

`<SKILL>` = this skill's directory. Scripts need Python 3.10+ with `pyyaml` and `jinja2`
(`scipy` optional). Work in a per-customer workshop dir: `<cwd>/<customer>_evals/`.

## Hard rules
- **Judge model is fixed.** Every LLM judge — Tier A custom metrics, Tier B judges, calibration
  functions, and studio optimization — uses `judge_model` from `intake.yaml`
  (default `claude-sonnet-4-6`, the Sonnet model supported by current Cortex Agent evaluations).
  Never compare or switch judge models; studio optimization tunes the **prompt only**
  (`optimization.models` = `[judge_model]`, `reflection_model` = `judge_model`).
  If the account's agent evals support a different Sonnet, change `judge_model` once in intake and
  re-calibrate everything.
- Ground truth contains literal values or explicit rubric rules, never placeholders (`X`, `TBD`, `<n>`).
- Relative-date questions ("yesterday", MTD, last week) are pinned to explicit dates for the
  ground-truth set; keep at most a small rubric-only relative set, scored only by Tier B.
- Datasets and judges are versioned, never edited in place: a change = `_v<N+1>` table/dataset or
  `judges/<metric>@v<N+1>.md`.
- Only **frozen** (calibrated) Tier B judges go into eval configs or production scoring.
- No real customer data values go into `examples/`.

## Workflow

### 1. Intake: scoping interview (≈30 min with the customer)
Follow the scoping funnel: **Vision → Personas → Questions → Tools → Agent spec**.
Anti-pattern: going straight from "talk to your data" to tools and metrics. Without personas and
their real questions, you get an eval that looks good in a demo and misses the failures users hit.

Copy `<SKILL>/templates/intake.yaml` to the workshop dir. Run the rounds below in order.
Round A asks open questions. Rounds B–D are **maker/checker**: you draft from evidence, the user
reviews, you revise, and the round is locked.

**Checker rules (all rounds):**
- Write a value to `intake.yaml` only after the user confirms it. Drafts have `status: drafted`;
  confirmed values have `status: confirmed`. Values the user typed in have `status: user`.
- Tag every drafted item with its evidence (`from agent instructions`, `from VQR #3`,
  `from logs: 14 similar asks`), or `assumption` when there is no evidence.
- Present drafts as text first: a card or table the user can read. Then call `ask_user_question`
  with concrete options (Accept / Edit / Drop / Add another) and leave room for free-text edits.
- Revise and re-present until the user accepts. After every round, show the diff written to `intake.yaml`.

**Round A: Vision and agent (ask).** Use one `ask_user_question` call covering:
- the business vision in one sentence ("what should change for users?")
- the agent under test (FQN; offer the agents found with `cortex agents list` as options)
- anything the agent must never do

Then run the **maker evidence pass**, with no questions to the user:
`DESCRIBE AGENT` and `SHOW VERSIONS IN AGENT` for instructions, tools and orchestration notes;
`DESCRIBE SEMANTIC VIEW` for each tool for metrics, dimensions, synonyms and verified queries;
and agent observability logs or query history if accessible (frequent asks, roles of the askers,
rephrases). `python <SKILL>/scripts/build.py draft-personas <dir>` prints a checklist of the
evidence to collect and the persona fields to draft.

**Round B: Personas (draft → review).** Draft 2–4 persona cards from the evidence. Each card has:

| field | prompt |
|---|---|
| role / decisions | what decisions do they make with this data? |
| data_literacy | `sql` / `dashboards` / `narrative`: can they read raw numbers or do they need a story? |
| workflow | how do they get answers today, and how long does it take? |
| frequency | daily power user, or occasional explorer (asks per week)? |
| stakes | what happens if the answer is wrong? |
| success_signal | their definition of "right", in their words ("I got the answer without filing a ticket") |
| data_scope | what they may see (row access, region, own team) |

Present all cards, then ask once per card: Accept / Edit / Drop, plus "Add a persona I missed".
The success signal is the north-star metric for that persona. Score against their definition of
right, not SQL correctness.

**Round C: Questions and taxonomy (draft → review).** For each confirmed persona, propose 5–10
questions from VQRs, logs and the agent instructions, written the way that persona talks. Tag
each with a `category` from `intake.yaml > taxonomy` (lookup / aggregation / reasoning /
policy_process / out_of_scope) and a wrong-answer cost. Show them as a table and ask:
Accept all / Edit some / Replace. Also ask for the user's own questions: "What did they ask their
analyst last week?" Other good sources are Slack/Teams data channels, dashboards people
already use, and a PM brainstorm.
Then show the persona × category matrix (`build.py coverage <dir>`) and propose fillers for empty
cells: at least one out-of-scope question per persona, and hallucination bait for missing fields.
The user accepts or rejects each filler. Confirmed questions go to `seed_questions` and to `questions.csv`.

**Round D: Rules and boundaries (draft → review).** Draft each group from the agent instructions,
semantic-view descriptions and Round B/C answers:
- metric, date and entity definitions
- out-of-scope topics with the expected refusal wording
- `missing_fields`
- format rules, defaulting from data literacy (`narrative` personas get a summary before numbers;
  `sql` personas get exact figures and the filters used)
- pass criteria, with priority set by wrong-answer cost
Show one group at a time; the user confirms or corrects each.

**⛔ STOP:** read back the full spec: vision, persona cards, taxonomy counts, definitions and
out-of-scope. The customer confirms it. `lint.py` warns if any `status: drafted` value is still there.

### 2. Question taxonomy
Put questions in `questions.csv` (columns: see `templates/questions_header.csv`). Tag each with
`category` (from Round C), `intent`, `process` (`single_tool` / `multi_tool` / `refusal`), `date_type` (`pinned` / `relative`),
`persona`, `risk` (`hallucination` when it asks for fields not in the semantic view).
Then propose additions to cover gaps: at least one refusal per out-of-scope topic, one
hallucination-bait question per known missing field, every persona × category cell the customer cares about, multi-tool cases.
`python <SKILL>/scripts/build.py coverage <dir>` prints the coverage matrix.

### 3. Draft ground truth
For each question:
- pin dates (`date_type=relative` → add a pinned twin with an explicit date),
- run the SQL against the semantic view (`SELECT * FROM SEMANTIC_VIEW(...)`) or base tables to get
  literal values; show the SQL with the answer,
- write `ground_truth_output` as a short rubric with the numbers
  ("Net revenue for 2026-04 = $18.4M; must state net, not gross; must exclude cancelled orders"),
- `expected_tools` (`ground_truth_invocations`), `min_data_calls`.
Never guess values: if the query can't run, leave `ground_truth_output` empty and mark
`reviewer_status=needs_value`.

### 4. Export for review
`python <SKILL>/scripts/build.py export <dir>` writes `candidate_dataset.csv`,
`rules.csv`, and `calibration_template.csv`, and `sheet_payload.json`.
- **If the Google Drive MCP is available** (`mcp__google-drive-natoma__*`): create a spreadsheet
  `<Customer> Agent Eval – candidate v<N>` with tabs `Questions`, `Rules`, `Calibration`
  (`create_spreadsheet` with `sheetNames`), then write each tab from `sheet_payload.json` with
  `modify_sheet_values` using `valueInputOption=RAW` (never evaluate formulas). Share only if the
  user asks. Give the user the link.
- Otherwise hand over the CSVs.
Reviewers set `reviewer_status` = `approve` / `edit` / `drop` and fill `reviewer_notes`.

Re-import: read the sheet back (`read_sheet_values` → save as CSV) or take the edited CSV, then
`python <SKILL>/scripts/sheet_sync.py <dir> <edited.csv>`. It prints a diff vs the draft and writes
`dataset_v<N>.csv` with approved/edited rows only. **⛔ STOP:** show the diff.

### 5. Metric design (two tiers)
Choose metrics in `intake.yaml > metrics`. Templates are in `<SKILL>/templates/judges/`.

**Tier A – ground-truth based** (curated dataset only):
| metric | type | needs |
|---|---|---|
| `answer_correctness` | built-in | `ground_truth_output` |
| `tool_selection_accuracy`, `tool_execution_accuracy` | built-in | `ground_truth_invocations` on every scored row |
| `logical_consistency` | built-in (reference-free) | – |
| `business_rules` | custom | rules + `ground_truth` |
| `efficiency` | custom | `min_data_calls` |

**Tier B – ground-truth free** (prompts see only `{{input}}`, `{{output}}`, `{{tool_info}}` plus the
intake rules baked into the prompt; runnable on any question and on production logs):
| metric | reference-free variant of |
|---|---|
| `answer_correctness_rf` – answer supported by tool results, answers the asked metric/grain/window, complete, no fabricated numbers | `answer_correctness` |
| `tool_selection_rf` – right tools given tool descriptions + routing rules; right to answer vs refuse | `tool_selection_accuracy` |
| `tool_execution_rf` – SQL/tool input matches question filters, dates, formulas; results usable | `tool_execution_accuracy` |
| `logical_consistency` – reuse built-in as is | – |
| `groundedness`, `business_rules_rf`, `scope_refusal`, `date_interpretation`, `efficiency_rf`, `persona_fit`, `brand_format` | custom |

**Scoring scale (all metrics).** Built-in metrics report `normalized_score` in [0.0, 1.0], so every
custom judge uses the same 0–1 scale and the same five bands, `0 / 0.25 / 0.5 / 0.75 / 1`. Each band
has a written anchor, and the judge returns one band plus one reason sentence. This keeps built-in
and custom columns comparable in the Evaluations tab and lets calibration use one band set.
`intake.yaml > scoring` holds:
- `builtin_version: v3`: pins the built-ins. The v3 judge is `claude-sonnet-4-6`, the same as `judge_model`.
- `score_ranges`, written into every custom metric: low `[0, 0.4)`, medium `[0.4, 0.7]`, high `(0.7, 1]`.

Snowflake doesn't publish the built-ins' own quality thresholds, so treat these ranges as ours.
Don't use 1–10 scales, even though the docs example does.

**Business and persona metrics (create when necessary).** The standard judges cover generic
quality. Add a dedicated metric in `intake.yaml > custom_metrics` when any of these hold:
- a persona's `success_signal` is not measured by an existing metric (e.g. "board-ready one-liner"),
- a persona has a restricted `data_scope` and leaking it would be a serious failure,
- a taxonomy category has `very_high` or `reputational` wrong-answer cost (policy, compliance),
- one business definition causes most of the wrong answers, or the costliest ones, and deserves its
  own trend line instead of being one line in `business_rules_rf` (net vs gross, ARR as-of date).

Don't add one when an existing judge already scores the same failure. Prefer 2–4 sharp custom
metrics over many vague ones; each Tier B metric needs its own calibration.

Maker/checker: run `python <SKILL>/scripts/build.py suggest-metrics <dir>`, which drafts
`custom_metrics` from persona cards, taxonomy costs and definitions. Present each draft as name,
why, criteria and anchors. The user Accepts, Edits or Drops each one. Write the confirmed metrics
into intake and write domain-specific anchors where you can; the default anchors are generic.

Each entry has these fields:
- `kind`: `persona` or `business`
- `tier`: `A` may use `{{ground_truth}}`; `B` is reference-free and needs calibration
- optional `persona` / `categories`: limit where the metric applies. Rows outside that scope score 1
  with a reason starting `N/A:`; filter those rows out when reading per-metric averages.
- `criteria`, `intent`, optional `anchors`, and `rules_from_intake`

Render the judge prompts: `python <SKILL>/scripts/build.py judges <dir>` →
`judges/<metric>@v1.md`, covering the standard templates and the custom metrics, with rules
filled from intake.

**⛔ STOP:** customer reviews the metric list and pass criteria (`spec.md` draft from
`build.py spec <dir>`).

### 6. Calibrate and optimize Tier B judges (AI Function Studio, judge model fixed)
1. **Collect responses**: 20–50 per judge, stratified across category/persona/process (oversample
   categories with high or very-high wrong-answer cost), with known
   failures included. Sources: a pilot eval run (`GET_AI_EVALUATION_DATA`), earlier runs, or agent
   observability logs. Save as `calibration_responses.csv` (`id, input, output, tool_info`).
2. **Human labels**: export the `Calibration` tab (step 4 mechanism); 2 raters where possible
   score each judge's band with a reason. Tier A scores on the curated rows can serve as extra
   reference labels for the matching Tier B judge (`answer_correctness` → `answer_correctness_rf`).
3. **Split**: `python <SKILL>/scripts/calibrate.py split <dir> --holdout 0.3` → train/holdout CSVs,
   stratified by human band. Load both into tables
   `<DB>.<SCHEMA>.JUDGE_CAL_<METRIC>_{TRAIN,HOLDOUT}` (columns `INPUT, OUTPUT, TOOL_INFO, HUMAN_SCORE`).
4. **Create the judge function** from `templates/studio/judge_function.sql.j2`
   (`build.py studio <dir> <metric>` renders all studio SQL): an AI function whose body is a single
   `AI_COMPLETE(<judge_model>, <judge prompt>)` returning `{score, reason}` — the studio optimizer
   requires an `AI_COMPLETE` body. Also create the deterministic agreement metric UDF
   `JUDGE_AGREEMENT` (studio custom metrics must not call LLMs): 1 when bands match, 0.5 when one band
   apart, else 0, with feedback naming the direction of the miss — the feedback drives the
   optimizer.
5. **Baseline evaluation**: studio `AI_FUNCTION_EVALUATION` experiment on the holdout set with
   `custom_udf: JUDGE_AGREEMENT`, `ground_truth: HUMAN_SCORE`.
6. **Optimize** the prompt: studio `AI_FUNCTION_OPTIMIZATION` on train with holdout,
   `models: [<judge_model>]`, `reflection_model: <judge_model>`, budget `light` unless the user asks
   otherwise. Follow the studio's own optimize sub-skill for status and results
   (`SHOW RUNS IN EXPERIMENT`). Do not add models.
7. **Score agreement**: pull per-row predictions for the winning run (and baseline) from
   `eval_detail.json`, save to CSV, then
   `python <SKILL>/scripts/calibrate.py report <dir> <metric> <predictions.csv>` → kappa
   (quadratic-weighted), exact-band agreement, Spearman, MAE, confusion table, disagreements.
   Pass gate (configurable in intake): weighted kappa ≥ 0.6 **and** exact-band agreement ≥ 0.8 on
   holdout. If it fails: add few-shots from disagreements, tighten rule wording, re-optimize.
   Also check human-vs-human agreement: if raters disagree with each other more than with the
   judge, fix the rubric, not the prompt.
8. **Freeze**: `python <SKILL>/scripts/calibrate.py freeze <dir> <metric> --prompt-file <optimized.txt>
   --experiment <name> --run <run>` → `judges/<metric>@vN.md` (frozen header with model, agreement,
   experiment/run, date) + `calibration_report.md`. The optimized prompt comes from
   `SHOW RUN PARAMETERS IN EXPERIMENT ... RUN <winner>`. Convert the studio's argument names back to
   agent-eval slots (`{{input}}`, `{{output}}`, `{{tool_info}}`).

**⛔ STOP:** show the calibration report per judge; customer accepts the frozen judges.

Re-calibrate when the agent instructions, semantic view, tools, or `judge_model` change. Plan a
~10% human spot check per production scoring batch.

### 7. Preflight lint
`python <SKILL>/scripts/lint.py <dir>`. Fix every ERROR. It checks placeholders, ground-truth keys
vs selected metrics, unpinned relative dates in ground truth, duplicate/near-duplicate questions,
persona and refusal coverage, unfrozen Tier B judges in the config, judge model consistency, and
prints a credit estimate.

### 8. Materialize and hand off
`python <SKILL>/scripts/build.py sql <dir>` → `dataset.sql` (table, insert, `SYSTEM$CREATE_EVALUATION_DATASET`)
and `eval_config.yaml` (Tier A + frozen Tier B custom metrics; compatible with `agent-pareto-lab`).
Compile first (`sql_execute only_compile=true`), then **⛔ STOP** before running. After creation:
- 3-question pilot run; every metric must score (see `agent-pareto-lab` pilot checks).
- Hand off to `agent-pareto-lab` (variants, cost/quality frontier) and `benchmark-report` (deck).
- Production scoring: frozen judge functions can score observability logs directly in SQL
  (`templates/studio/score_logs.sql.j2`); offer a `cortex automation` for a recurring run.

### 9. Customer artifact
`python <SKILL>/scripts/build.py spec <dir>` → `spec.md`: questions by persona, metric definitions,
calibration agreement, pass criteria, how to re-run. Optionally render with `presentation-generator`.

## Stopping points
After intake · after the review diff · after metric design · after calibration.

## Outputs (workshop dir)
`intake.yaml`, `questions.csv`, `candidate_dataset.csv` (+ Sheet), `dataset_v<N>.csv`,
`judges/*.md`, `calibration_report.md`, `dataset.sql`, `eval_config.yaml`, `spec.md`.
