# Agent Pareto Lab: Speaker Notes

**Context.** This is an internal enablement deck for SEs and AFEs. It introduces the
`agent-pareto-lab` Cortex Code skill, the optimize step that follows `eval-rubric-builder` in the
agent development lifecycle. The skill exists because customers change models and prompts by feel and
can't say what a correct answer costs. It turns one agent config into several committed versions,
evaluates each once on a fixed dataset, joins billed credits, and shows the cost/quality frontier.
The deck can also be shown to customers; keep the candid notes below to yourself.

---

## 1. Agent Pareto Lab (hero)
- One line: "We test your agent's candidate versions on the same questions and show you what each
  correct answer costs."
- Five stopping points: intake, before creating versions, after the pilot, after the frontier, before
  teardown. The customer approves each.
- Candid: this is a CoCo skill run by us, not a Snowflake product feature. Position it as a
  methodology on top of Cortex Agent versions and evaluations.

**References:** https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations

## 2. Why "which version do we ship?" stalls
- Most customers have all four problems. Cost is the one they can't answer at all.
- "Edits in place" is common: `CREATE OR REPLACE AGENT` destroys the baseline they want to compare to.
- Candid: if the customer has no evaluation dataset, stop here and pitch `eval-rubric-builder` first.

## 3. Where it lives in the lifecycle
- The skill owns Optimize and feeds the Release gate. Same lifecycle as the eval-rubric-builder deck.
- Each round can start from production findings: failures become new eval cases and a new round.

## 4. Where it plugs in
- Inputs: an agent and a dataset registered with `SYSTEM$CREATE_EVALUATION_DATASET`. If only a table
  exists, the skill offers to register it. If no ground truth exists, it stops.
- The live spec is often not the DEFAULT/FIRST version. Intake compares them before picking the base.
- Candid: tool selection/execution metrics are public preview and need `ground_truth_invocations` in
  the dataset.

**References:** https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations

## 5. Variants are patches on one base spec
- The example is fictional (`examples/ecommerce_orders/`). Run `generate.py --diff` live to show the
  diffs; it's offline and takes a second.
- Naming matters: the alias and eval run name are the same string, `<run_prefix>_<name>`, so Snowsight
  and the frontier table line up without a mapping.
- Candid: check model availability in the customer's region before proposing a model swap.

## 6. The workflow
- Walk the stops. Step 2 creates real objects (warehouses, versions), so the approval there is the
  important one.
- Smoke tests go through SQL `DATA_AGENT_RUN` with the alias after `!` in upper case. Watch latency
  per version: a much slower model dominates eval wall time.
- Candid: cost scales with variants × questions. Agree the variant count before Step 2.

## 7. Preflight and pilot
- The `expected_tools` vs `ground_truth_invocations` mismatch is the real-world example. It scores
  every row as "expected 0 tools" and looks like the agent is terrible.
- One pilot run costs one run. The same bug found after launch costs all of them.
- A FAILED run status can mean one metric failed on one record. Don't throw away the rest of the scores.

## 8. Cost attribution per request
- The per-variant warehouse is the key design choice: without it, Analyst SQL cost can't be split
  between versions.
- Billing lag is hours. Set expectations: results the same day, final cost the next morning.
- Candid: only convert to dollars with a credit price the customer gives you. Don't quote list price.

**References:** https://docs.snowflake.com/en/sql-reference/account-usage

## 9. Reading the frontier
- The chart is illustrative, not real results. Say so.
- The typical story: the long production prompt is dominated by a lean one; a model swap buys some
  correctness at higher cost; the cheapest model fails the constraint.
- Phrase frontier trade-offs as decisions for the customer, not a single winner.

## 10. One run per variant
- This is deliberate. Repeats don't add options; more variants do.
- With one run there's no confidence interval. A 2–3 point gap is noise. Say it before the customer asks.
- Ground-truth errors found here go back as a new dataset version and a new `run_prefix`.

## 11. Outputs and guardrails
- Everything is additive, so previous rounds stay comparable.
- Teardown drops only the lab warehouses, after billing is final. Versions that pointed at them won't
  run again; promote the winner as a new version on a permanent warehouse.

## 12. Next steps
- Ask for one agent with a reviewed dataset and one concrete decision (model, prompt, or cost).
- Agree constraints up front: e.g. correctness ≥ 0.85, no cost increase per request.
