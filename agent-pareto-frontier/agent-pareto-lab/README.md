# agent-pareto-lab

A Cortex Code skill for answering "which version of this agent should we ship?" with numbers. From one
existing Cortex Agent config it:

1. creates **N committed agent versions** (model × prompt × tools × budget), each with its own alias and
   its own tool warehouse,
2. runs **one Cortex Agent evaluation per version** on the same fixed dataset and metrics,
3. joins **billed credits per request** (agent usage + per-variant warehouse metering), and
4. reports which variants are on the **cost/quality Pareto frontier**, which are dominated, and which
   fail a hard constraint (e.g. `answer_correctness >= 0.85`).

Nothing is replaced in place: every change is a new version and alias, every round a new `run_prefix`.

## Where it fits

```
 build agent ──► define "good" ──────────► [ agent-pareto-lab ] ──► roll out ──► monitor
 (agent-studio)  (eval-rubric-builder:      variants, one eval       release      score prod logs
                  dataset + metrics)        each, cost frontier      winner
```

Use it when:
- **Choosing an orchestration model**: `auto` vs a named model vs a cheaper one, on your questions.
- **Proving a lean prompt is cheaper** without introducing new wrong answers.
- **Changing tools or budgets**: a new tool, a different semantic view, lower `max_tokens`/time limits.
- **Someone asks "what does this agent cost per answer?"**: `credits_per_correct_answer` is reported
  per variant.

Don't use it for:
- building ground truth or metrics (use `eval-rubric-builder`; this skill stops if no dataset exists);
- building the agent itself (use `agent-studio`);
- the customer-facing HTML deck (hand the run names to `benchmark-report`).

## Example workflow

Fictional customer: an online retailer's orders agent (`examples/ecommerce_orders/`). Production uses a
long "think step by step, check every tool" prompt on `claude-sonnet-4-6`. Question: can a lean prompt,
or a different model, be cheaper with no loss of correctness?

```
> $agent-pareto-lab compare production vs a lean prompt vs lean + claude-sonnet-5-5 for EXAMPLE_DB.AGENTS.ORDERS_AGENT
```

| Step | What CoCo does | Stops for you? |
|---|---|---|
| 1. Intake | `DESCRIBE AGENT`, `SHOW VERSIONS`, checks the dataset and its ground-truth keys vs metrics, fills `lab.yaml` | yes: variant matrix, metrics, objectives |
| 2. Generate | `generate.py --diff` per-variant spec diffs, renders `versions.sql`; on approval `--apply` + SQL smoke test per version | yes: before `--apply` |
| 3. Preflight + pilot | `preflight.py`, then one eval run on the cheapest variant; checks every metric scored | yes: pilot coverage |
| 4. Run | `run_evals.py` starts and polls the remaining runs (background) | |
| 5. Billing | `wait_billing.py` waits for `CORTEX_AGENT_USAGE_HISTORY` (lags hours) | |
| 6. Frontier | `frontier.py` builds `PARETO_<PREFIX>_*` views, writes `frontier.{md,json,svg}` | |
| 7. Report | reads low-scored records, separates ground-truth errors / judge variance / agent failures, writes `RESULTS.md` | yes: recommendation, next round |
| 8. Teardown | drops the lab warehouses only | yes: confirm the list |

## What you get

| Output | Purpose |
|---|---|
| `lab.yaml` | agent, dataset, variants (JSON merge patches on the base spec), metrics, objectives, constraints |
| agent versions + aliases `<run_prefix>_<name>` | one committed version per variant, visible in Snowsight |
| eval runs `<run_prefix>_<name>` | one per variant, in Snowsight > agent > Evaluations |
| `PARETO_<PREFIX>_*` views | requests, request cost, run scorecard, run metrics, warehouse credits |
| `pareto_out/<run_prefix>/frontier.{md,json,svg}` | frontier / dominated / excluded per variant + chart |
| `RESULTS.md` | setup, version table, frontier, findings, next variants |

## Hard rules (summary)

- Never `CREATE OR REPLACE` the agent or edit a committed version; a change is a new alias.
- Never overwrite an eval config or reuse a run name; a changed dataset/judge/config is a new `run_prefix`.
- One eval run per variant. Spend budget on more variants, not repeats; treat small gaps as noise.
- A pilot run must score every metric before the rest launch.
- Don't call the frontier final while billing is incomplete.

Full workflow and troubleshooting: [`SKILL.md`](SKILL.md).

## Install

From `agent-pareto-frontier/` in a clone of this repository:
```
ln -s "$PWD/agent-pareto-lab" ~/.snowflake/cortex/skills/agent-pareto-lab
```
If you already have a copy at that path, move it aside first. Then invoke it in Cortex Code with
`$agent-pareto-lab`. Requires Python 3.10+ with `pyyaml`, `jinja2` and `snowflake-connector-python`. Live
steps need a role that can modify the agent, read the evaluation dataset, run Cortex Agent evaluations,
create warehouses, and read `SNOWFLAKE.ACCOUNT_USAGE` (billing).

## Try it offline

Renders variant specs, `versions.sql` and eval YAMLs for the fictional example; nothing touches Snowflake:
```
d=agent-pareto-lab/examples/ecommerce_orders
python agent-pareto-lab/scripts/generate.py $d/lab.yaml --diff                 # per-variant spec diff
python agent-pareto-lab/scripts/generate.py $d/lab.yaml --assume-existing 3    # writes $d/pareto_out/r1/
```
`preflight.py`, `run_evals.py`, `wait_billing.py` and `frontier.py` need a live connection.
