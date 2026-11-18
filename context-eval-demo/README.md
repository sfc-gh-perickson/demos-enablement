# Context helps, evals earn trust: companion demo

The demo uses one Cortex Agent with five tagged versions. Each version adds a single context layer.
There are five questions, and each one breaks the agent in a different way.
A Streamlit app shows the story, runs the versions side by side, and shows the eval results.

It goes with the deck *Context Helps, Evals Earn Trust: Ontology, Cortex Sense & Evaluating Cortex Agents*.

| Alias (`REVENUE_ASSISTANT!<alias>`) | Adds | Fixes |
|---|---|---|
| `V0_STUFFED` | Analyst over a 38-table, auto-generated semantic view | (baseline) |
| `V1_GOVERNED_SV` | A 5-table governed semantic view, certified ARR metric, verified query | Q2 ARR, Q5 EMEA drop |
| `V2_ONTOLOGY` | Business Ontology domain `Revenue Demo`: 6 nodes (Bookings vs TCV Bookings, ARR, Open Pipeline, Booking Type, Test Account Exclusion) bound to SV members and linked to each other | Q1 bookings |
| `V3_SENSE` | Cortex Sense context built from tables, the SV and query history | Q3 partner deals |
| `V4_INSTRUCTIONS` (default) | One policy instruction | Q4 rep ranking |

The model and base instructions are the same in every version, so a change in score comes from the added layer.

## Install (about 15 minutes, plus an optional Sense build)

**You need:**
- Snowflake CLI 3.14+ (`snow --version`) and Python 3.9+. Nothing to pip install.
- A role that can create a database, agents and a Streamlit app, with usage on a warehouse and a compute pool. SYSADMIN works.
- Cortex Agents and Agent Evaluations in your account.
- Optional: Business Ontology (for V2) and Cortex Sense (for V3). Without them you get V0, V1 and V4, and the app marks the rest as unavailable.

**Steps:**

```bash
# 1. Data, semantic views, eval set, ontology node, the agent and its versions, and the app
python3 scripts/deploy.py -c <connection> --role SYSADMIN --warehouse <WH>
#    Options: --database (default CONTEXT_EVAL_DEMO), --compute-pool (default: account default, else SYSTEM_COMPUTE_POOL_CPU)

# 2. Optional: Cortex Sense for V3. Follow setup/CORTEX_SENSE.md, then:
python3 scripts/deploy.py -c <connection> --role SYSADMIN --warehouse <WH> --steps agent

# 3. Optional: run the evals in your account (10-25 min). Until then the app shows the reference snapshot.
python3 scripts/run_evals.py -c <connection> --role SYSADMIN --warehouse <WH>
```

Open **Snowsight → Projects → Streamlit → CONTEXT_EVAL_DEMO_APP**.

## The 5-minute talk track

Go to **Ask live** in the app, pick the question, and compare the two versions listed.

| | Question | Compare | What the audience sees |
|---|---|---|---|
| 1 | "What's our ARR this quarter?" | V0 vs V1 | V0 confidently says ~$158M, counting Services lines. V1 gives $121.8M from the certified metric. **Start with a small governed SV.** |
| 2 | "What was Q3 bookings?" | V0 vs V2 | V0 reports Sales TCV (~$69.9M) or hedges. V2 reads the ontology node and says $24.0M with the definition. **Contested meaning needs a governed definition.** (V1 sometimes gets this right by luck; that is the point: only V2 is right by construction.) |
| 3 | "How many partner-sourced deals did we win in October 2026?" | V2 vs V3 | Everything up to V2 says 9, from the stale CRM field. V3 learned the referrals join from query history and says 23. **Long tail: learn from how people query.** |
| 4 | "Give me the 5 worst-performing reps … performance plan." | V3 vs V4 | V3 names five reps. V4 declines and offers an aggregate view. **Behavior is an instruction problem, not a context problem.** |
| 5 | **Results** view | all | Correctness rises layer by layer, and V0 spends the most tokens to score the worst. **More context = more tokens = more cost.** |

Live calls take 30–90 seconds. Run the side-by-side pairs in the app before the meeting so the answers are already on screen,
or narrate the Results view.

## What to say out loud

- The data is synthetic and every trap is deliberate. The pattern carries over; the numbers don't.
- The scores come from one eval run with four paraphrases per question. Agent answers vary between runs.
- Business Ontology and Cortex Sense are preview features. Check availability in the customer's account before promising them.
- The orchestration model is `auto`. To compare runs over time, pin a model in `agent/specs/*/agent_spec.yaml` and redeploy.

## Layout

```
scripts/deploy.py        install or rebuild (steps: data, ontology, agent, app)
scripts/run_evals.py     evaluate every alias; runs are logged in EVALS.EVAL_RUNS
scripts/teardown.py      dry run by default; --yes to drop, --ontology to also remove the shared ontology node
agent/specs/<alias>/     one agent_spec.yaml per version (__DB__ and __WH__ are filled in at deploy)
setup/*.sql              data with traps, the two semantic views, the eval set, seeded query history, results snapshot
setup/CORTEX_SENSE.md    how to build the Sense context, plus cortex_sense_scope.yaml
app/                     Streamlit in Snowflake app (container runtime, no extra packages)
evals/token_cost.sql     billing-side check on tokens and credits
RUN_OF_SHOW.md           longer walkthrough, expected answers, reference results
presentations/           HTML deck (one-agent-five-layers.html) and its speaker notes
```

## Notes

- The Business Ontology is account-wide. A second install in the same account reuses the `Revenue Demo` nodes,
  which stay bound to the first install's semantic view. For separate audiences, use separate accounts.
- `deploy.py --steps agent` recreates the agent, so version numbers restart. Aliases are stable. Call versions by alias.
- `VERSION$2` is a leftover copy of V0. `CREATE AGENT` always makes a LIVE copy, and LIVE has to be committed before
  versions can be added from a stage.
- Remove everything with `python3 scripts/teardown.py -c <connection> --database <DB> --yes`.
