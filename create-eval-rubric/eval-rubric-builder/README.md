# eval-rubric-builder

A Cortex Code skill for running an evaluation workshop with a customer. It turns
"the questions our users actually ask" into:

1. a reviewed **Cortex Agent evaluation dataset** with literal, date-pinned ground truth,
2. a **metric spec** the customer signs off on (business rules, refusal behavior, persona scope), and
3. **ground-truth-free LLM judges calibrated to human scores**, so new questions and production
   traffic can be scored without anyone writing expected answers.

All judges use the single Sonnet model supported by Cortex Agent evaluations
(`judge_model` in `intake.yaml`, default `claude-sonnet-4-6`). Calibration uses AI Function Studio
to tune the judge **prompt only**; the model is never swapped.

## Where it fits

```
 build agent ──► [ eval-rubric-builder ] ──► compare versions ──► roll out ──► monitor
 (semantic view,   define "good", dataset,     A/B/C variants,      to users     score prod logs with
  tools, prompt)   calibrated judges           cost vs quality                   the frozen judges
```

Use it when:
- **An agent exists and is heading toward users**: you have a working prototype, and need agreement
  on what "correct" means before anyone tunes prompts or models.
- **"Is it good enough?" keeps stalling**: answers get judged by feel, or the existing eval set has
  vague ground truth ("should show revenue trends") that judges can't score consistently.
- **You're about to change something**: a new orchestration model, a leaner prompt, a new tool, or a
  semantic view change. You need a fixed dataset and trusted metrics to compare before and after.
- **After launch**: you want ongoing quality scores on real traffic without labeling every request.
  Calibrated Tier B judges cover this.

Don't use it for:
- building the agent or semantic view itself (use the agent / semantic view skills);
- generating large synthetic question sets from an agent config (use agent-studio dataset curation,
  then bring the questions here for ground truth and metrics);
- running a model × prompt variant sweep (hand the dataset and config to your comparison tooling).

## Example workflow: one onsite day

Fictional customer: an online retailer with an orders agent used by category managers and finance
(see `examples/ecommerce_orders/`).

**Before the session (SA, ~30 min)**
```
> $eval-rubric-builder set up a workshop for EXAMPLE_DB.AGENTS.ORDERS_AGENT
```
CoCo describes the agent, its tools and semantic view, then pre-fills `intake.yaml` with what it can
infer: the tool list, available metrics and dimensions, and fields that are *not* in the semantic
view (prime hallucination bait).

**Session part 1: what matters (customer + SA, ~45 min)**
- Walk through the intake: personas (category manager sees only their category; finance sees all),
  definitions ("revenue means net unless gross is asked", "exclude cancelled orders", "weeks start
  Monday"), out-of-scope topics (inventory, competitor pricing), and format rules.
- Collect the top 10–30 questions in the users' own words. CoCo tags them by intent, persona,
  single/multi-tool or refusal, relative vs pinned dates, and proposes the missing ones: a refusal per
  out-of-scope topic, a question about a missing field, one per persona.

**Session part 2: ground truth and metrics (~45 min)**
- CoCo runs SQL against the semantic view to draft each expected answer with real numbers and pins
  relative dates ("MTD" → "2026-06-01..06-02").
- It exports the candidate set to CSV, or to a Google Sheet when the Drive MCP is connected. The
  customer marks each row approve / edit / drop. CoCo re-imports it, shows the diff, and saves
  `dataset_v1`.
- Together you pick metrics:
  - **Tier A** (needs ground truth): answer correctness, tool selection, logical consistency,
    business rules, efficiency.
  - **Tier B** (ground-truth free): reference-free answer correctness, tool selection and tool
    execution, groundedness, scope/refusal, date interpretation, persona fit.

**Session part 3: calibrate the judges (~45 min, can run over lunch)**
- Run a short pilot to collect 20–50 agent responses. Customer and SA each score them in the
  Calibration tab using the same bands as the judge.
- For each Tier B judge, CoCo creates it as an AI function and measures agreement with the humans. It
  then runs an AI Function Studio optimization that rewrites the prompt and keeps the model fixed.
- `calibrate.py report` gives weighted kappa, exact-band agreement and the worst disagreements on a
  held-out split. Judges that pass (default kappa ≥ 0.6 and ≥ 80% agreement) are **frozen**;
  failing ones get rubric fixes and another round.

**Wrap-up (~15 min)**
- `lint.py` checks for placeholders, stale relative dates, missing tool expectations, unfrozen judges
  and model mismatches, and gives a credit estimate.
- CoCo generates `dataset.sql` and `eval_config.yaml`, compiles them, and (after you confirm) runs a
  3-question pilot evaluation.
- The customer leaves with `spec.md`: questions by persona, metric definitions, calibration results
  and pass criteria (e.g. "no new wrong answers", "no cost increase per request").

**After the onsite**
- Compare agent versions against the dataset and config.
- Score production requests with the frozen judges (`studio/<metric>/score_logs.sql`), optionally on
  a schedule with `cortex automation`. Spot-check ~10% with humans.
- Re-calibrate when the agent instructions, tools, semantic view, or judge model change.

## What you get

| File | Purpose |
|---|---|
| `intake.yaml` | agent, personas, definitions, scope, metrics, gates |
| `questions.csv` → `candidate_dataset.csv` / Google Sheet → `dataset_v<N>.csv` | the question set through review |
| `judges/<metric>@v<N>.md` | judge prompts; Tier B marked `status: frozen` once calibrated |
| `studio/<metric>/*.sql` | calibration tables, judge function, agreement metric, eval/optimize experiments, log scoring |
| `calibration_report.md` | agreement per judge, baseline vs optimized |
| `dataset.sql`, `eval_config.yaml` | ready-to-run Cortex Agent evaluation |
| `spec.md` | customer-facing evaluation spec |

## Install

```
ln -s "$PWD/eval-rubric-builder" ~/.snowflake/cortex/skills/eval-rubric-builder
```
Requires Python 3.10+ with `pyyaml` and `jinja2`. Live steps need a role that can run Cortex Agent
evaluations and AI Function Studio experiments (see each feature's access requirements).

## Try it offline

Uses the fictional example and synthetic labels; nothing touches Snowflake:
```
d=eval-rubric-builder/examples/ecommerce_orders
python eval-rubric-builder/scripts/build.py coverage $d      # question coverage + gaps
python eval-rubric-builder/scripts/build.py export $d        # review CSVs + Sheet payload
python eval-rubric-builder/scripts/build.py judges $d        # render judge prompts from intake
python eval-rubric-builder/scripts/calibrate.py split $d     # train/holdout from human labels
python eval-rubric-builder/scripts/calibrate.py report $d answer_correctness_rf \
  $d/synthetic_judge_predictions.csv --label baseline        # agreement report (this one fails the gate)
python eval-rubric-builder/scripts/lint.py $d                # preflight checks
```
These commands write output files into the example folder; run them on a copy if you want to keep it
clean.
