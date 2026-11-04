# Eval Rubric Builder: Speaker Notes

**Context.** This is an internal enablement deck for SEs and AFEs. It introduces the
`eval-rubric-builder` Cortex Code skill and shows where it fits in the agent development
lifecycle described in the "Scoping, Evaluating, Deploying: The Data Flywheel for AI Agents" deck.
The skill exists because most Cortex Agent projects stall between demo and production. Customers
have no fixed eval set, no agreed definition of "right", and LLM judges nobody has checked. The
skill gives a repeatable onsite workshop. You leave with a reviewed dataset, a signed-off metric
spec, and judges calibrated to human scores, ready for `agent-pareto-lab` and production scoring.
The deck can also be shown to customers; keep the candid notes below to yourself.

---

## 1. Eval Rubric Builder (hero)
- One line: "We turn the questions your users actually ask into a test suite you can gate releases on."
- The four numbers are the shape of the workshop. Four rounds = Round A (open questions) plus three
  rounds where we draft and the customer reviews.
- Candid: the skill is a CoCo skill run by us. It is not a Snowflake product feature. Position it as
  our methodology on top of Cortex Agent evaluations and AI Function Studio.

**References:** https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations

## 2. Why agent evaluation stalls
- Map each card to a pain the customer has said out loud. Most have all four.
- "Untrusted judges" is the one teams underestimate. An uncalibrated LLM judge can move 0.2 between
  prompt tweaks and nobody notices.
- Candid: if the customer already has a large curated eval set, skip to slide 8 and position the
  skill for Tier B judges and calibration only.

## 3. Where it lives in the lifecycle
- Highlighted stages are the ones the skill owns or feeds: Scope, Golden-set evals, Release gate,
  Production flywheel. Building the agent and optimizing it belong to sibling skills.
- Key message: the dataset and judges built here are reused at every later stage. They are not
  thrown away after one eval.
- Candid: the production-flywheel stage needs agent observability logs. If the customer hasn't
  enabled monitoring, that stage is aspirational for now.

**References:** https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-monitor ·
https://docs.snowflake.com/en/user-guide/snowflake-cortex/ai-observability

## 4. Where it plugs in
- Upstream: `agent-studio` builds the agent. We read its instructions, tools and semantic views
  (including verified queries) to draft personas and questions.
- Downstream: `agent-pareto-lab` consumes `eval_config.yaml` unchanged; `benchmark-report` makes the
  customer deck; `automation` schedules log scoring.
- Candid: AI Function Studio is in public preview. Say so if the customer asks; calibration is the
  only step that depends on it.

**References:** https://docs.snowflake.com/en/user-guide/snowflake-cortex/ai-function-studio ·
https://docs.snowflake.com/en/sql-reference/functions/ai_function_evaluation

## 5. The workflow
- Walk the four stopping points. They are what make this a workshop and not a script that runs
  on its own: the customer confirms intake, the reviewed dataset, the metric list, and the
  calibrated judges.
- Steps 1–5 fit in one onsite session. Calibration (Step 6) usually needs a follow-up because
  human labeling takes time.
- Candid: ground truth (Step 3) needs SQL access to the semantic view or base tables. Confirm the
  role before the session, or Step 3 stalls on `needs_value` rows.

## 6. Step 1: maker/checker scoping interview
- The funnel is from the Data Flywheel deck. Call out the anti-pattern: going straight from "talk
  to your data" to tools.
- "Maker/checker" means we never ask the customer to fill in a blank form. We draft from evidence
  (agent config, verified queries, logs) and they correct it. That is faster and gets better answers.
- Every drafted value carries its evidence, or "assumption". Lint flags anything left unconfirmed.

## 7. Persona cards and the taxonomy
- The success signal is the line to land: the customer's definition of "right", in their words.
  It later becomes a persona metric.
- Wrong-answer cost drives priority: more questions, stricter metrics and oversampling in
  calibration for high- and very-high-cost categories.
- Candid: customers often name 6+ personas. Push to 2–4 that differ in data scope or literacy;
  the rest are usually the same persona with different titles.

## 8. Two tiers of metrics
- Tier A needs ground truth, so it only runs on the curated set. Tier B runs on anything, which is
  how we reach production traffic.
- Every judge uses one judge model (`claude-sonnet-4-6`). We never compare judge models; the
  optimizer only tunes the prompt.
- Candid: built-in tool selection/execution metrics are public preview and only score some tool
  types. Their Tier B variants (`tool_selection_rf`, `tool_execution_rf`) fill that gap.

**References:** https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations

## 9. One scoring scale
- Built-in metrics report `normalized_score` from 0 to 1. Custom metrics require explicit
  `score_ranges` and have no default; the docs example uses 1–10. We standardize on 0–1 with five
  bands so every column in the Evaluations tab reads the same way.
- Built-ins are pinned to `v3`. Unversioned built-ins default to `v1`, whose judge
  (`claude-4-sonnet`) is legacy. Pinning v3 also aligns the built-in judge with ours.
- Candid: the low/medium/high cut-offs (0.4 / 0.7) are our convention. Snowflake doesn't publish
  the built-ins' internal thresholds. Be clear about that if asked.

## 10. Business and persona metrics
- These come from the intake. `build.py suggest-metrics` drafts them from success signals, data
  scopes, high-cost categories and definitions; the customer accepts or edits.
- The four examples come from the two example workshops in the skill (e-commerce orders, SaaS
  subscriptions). All data in them is fictional.
- Candid caveat: the evaluation scores every metric on every row. Rows outside a scoped metric
  score 1 with an "N/A:" reason, which inflates averages unless you filter them out. There is no
  automatic filter yet. Calibration guidance for scoped metrics (label only applicable rows) is
  also still to be written into Step 6.

## 11. Calibrating judges
- The gate: quadratic-weighted kappa ≥ 0.6 and exact-band agreement ≥ 0.8 on holdout. Both
  thresholds are configurable in intake.
- If raters disagree with each other more than with the judge, fix the rubric, not the prompt.
- Candid: 20–50 labels per judge is the hidden cost. Budget a customer SME for an hour per
  2–3 judges. This is the main reason to keep custom metrics to 2–4.

**References:** https://docs.snowflake.com/en/user-guide/snowflake-cortex/ai-function-studio

## 12. Outputs and guardrails
- Everything is versioned files in a per-customer directory. Nothing is edited in place.
- Lint is the safety net before `dataset.sql` and `eval_config.yaml` touch Snowflake.
- Candid: lint still prints a rough credit estimate, but the skill no longer stops to ask about
  credit spend. Set expectations on eval cost with the account team beforehand.

## 13. Next steps
- Ask for one live agent and 2–3 persona owners for a workshop slot.
- Offer to schedule production log scoring with frozen judges as a recurring automation once
  calibration passes.

**References:** https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations
