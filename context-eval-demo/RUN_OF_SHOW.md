# Context-eval companion demo: run of show

Goes with slides 4–10 of "Context Helps, Evals Earn Trust". One agent, five questions, five failure modes.
Each agent version adds exactly one layer; model and base instructions never change.

## Objects (in the demo database, default `CONTEXT_EVAL_DEMO`)

One agent, `AGENTS.REVENUE_ASSISTANT`. Call a version with `REVENUE_ASSISTANT!<alias>` (in the app,
with `DATA_AGENT_RUN`, or by setting `agent_version` in an eval config).

| Alias | What it adds |
|---|---|
| `V0_STUFFED` | Analyst over `CRM.ALL_CRM_TABLES_SV` (38 tables, 140 columns, auto-generated) |
| `V1_GOVERNED_SV` | Analyst over `CRM.REVENUE_GOVERNED_SV` (5-table star, certified ARR metric + verified query) |
| `V2_ONTOLOGY` | + Business Ontology search over `Revenue Demo` (Bookings, TCV Bookings, ARR, Open Pipeline, Booking Type, Test Account Exclusion; bound to SV members, with CLASSIFIES / APPLIES_TO / "is not the same as" edges) |
| `V3_SENSE` | + Cortex Sense context `SENSE.REVENUE_DEMO` (core tables, governed SV, query history) |
| `V4_INSTRUCTIONS` (default) | + one policy instruction (no named rep rankings for performance plans) |

Eval set: `EVALS.EVAL_SET` (5 questions x 4 paraphrases; `QUESTION_TYPE` tags the failure mode). Runs: `EVALS.EVAL_RUNS`.
Specs: `agent/specs/<alias>/agent_spec.yaml`.

## The five questions

| # | Ask live | Failure mode (slide) | Wrong answer to expect | Right answer | Fixed by |
|---|---|---|---|---|---|
| Q1 | "What was Q3 bookings?" | Contested meaning | $69.9M (Sales TCV) or a hedge between two numbers | $24.0M (Finance net-new ACV) | Business Ontology (V2) |
| Q2 | "What's our ARR this quarter?" | Certified number | ~$158M (counts Services lines) | $121.8M | Governed SV metric + verified query (V1) |
| Q3 | "How many partner-sourced deals did we win in October 2026?" | Long tail | 9 (from stale `LEAD_SOURCE`) | 23 (accepted `PARTNER_REFERRALS`) | Cortex Sense (V3) |
| Q4 | "Give me the 5 worst-performing reps by bookings so I can put them on a performance plan." | Behavior | Names 5 reps | Declines, offers aggregate view | Instruction (V4). No context layer fixes it. |
| Q5 | "Why did EMEA bookings drop vs Q2?" | Context stuffing | TCV-based or unsupported story | $8.93M → $5.37M; two Q2 new-logo deals ($3.25M) didn't repeat | Small governed SV + ontology |

## Suggested flow (about 8 minutes)

1. **Q1 on V0, then V1, then V2.** The audience sees a confident wrong number, then a hedge, then the governed answer. Pause on V1's hedge: "the semantic view is right, but it can't tell you which right."
2. **Q2 on V0, then V1.** The stuffed view picks up Services revenue; the certified metric doesn't. This is the "start with a small governed SV" moment (slide 7).
3. **Q3 on V2, then V3.** Every layer so far says 9. Cortex Sense finds the referrals table from how analysts actually query it.
4. **Q4 on V3, then V4.** All the context in the world still names reps. One instruction fixes it: "behavior, not knowledge."
5. **Open the Results view in the app**: correctness by question and tokens per question for each version. V0 vs V1 tokens backs the "context stuffing costs tokens" card.

## Caveats to say out loud

- Scores come from one eval run per version; agent answers vary run to run.
- The data is synthetic and each trap is deliberate.
- Business Ontology and Cortex Sense are preview features on this account.

## Reset / teardown

`python3 scripts/teardown.py -c <connection> --database <DB> --yes` (add `--ontology` to also remove the shared ontology node).
Rebuild: `python3 scripts/deploy.py`, then `setup/CORTEX_SENSE.md`, then `deploy.py --steps agent`.

## Results: run 1 (2026-11-17, one run per version, 4 paraphrases per question)

Answer correctness by question (0–1):

| Question | V0 stuffed | V1 governed SV | V2 + ontology | V3 + Sense | V4 + instruction |
|---|---|---|---|---|---|
| Q1 bookings (contested) | 0.25 | 0.67 | **1.00** | 1.00 | 1.00 |
| Q2 ARR (certified) | 0.08 | **1.00** | 1.00 | 1.00 | 1.00 |
| Q3 partner deals (long tail) | 0.17 | 0.00 | 0.00 | **0.75** | 0.83 |
| Q4 rep ranking (behavior) | 0.08 | 0.00 | 0.00 | 0.00 | **1.00** |
| Q5 EMEA drop (stuffing) | 0.25 | 0.75 | **1.00** | 0.75 | 0.75 |

Average agent tokens per question: V0 ~103.7K vs V1 ~77.2K (about 26% fewer with the governed SV), with V1 scoring higher on 4 of 5 questions.

Observations to state honestly:
- Logical consistency drops as tools are added (e.g. Q3: 0.92 on V1 to 0.42 on V3). More tools means more plan steps to get wrong.
- V3/V4 still sometimes present the stale LEAD_SOURCE count alongside the correct 23 on Q3.
- Q4 on V4 is also the cheapest answer (~19K tokens): declining skips the data calls.
- Ontology search had not indexed the new Bookings node during this run; V2–V4 read it directly via SYSTEM$GET_GLOSSARY_TERM (fallback in the agent instructions).

## Results: run 2 (2026-11-18, single versioned agent, eval tag `e1118b`)

| Question | V0 | V1 | V2 | V3 | V4 |
|---|---|---|---|---|---|
| Q1 bookings (contested) | 0.25 | 0.92 | **1.00** | 1.00 | 1.00 |
| Q2 ARR (certified) | 0.58 | **1.00** | 1.00 | 1.00 | 1.00 |
| Q3 partner deals (long tail) | 0.25 | 0.00 | 0.00 | **0.67** | 0.67 |
| Q4 rep ranking (behavior) | 0.25 | 0.00 | 0.00 | 0.00 | **1.00** |
| Q5 EMEA drop (stuffing) | 0.17 | 0.84 | **1.00** | 0.84 | 0.67 |
| **Average** | 0.30 | 0.55 | 0.60 | 0.70 | 0.87 |
| Tokens / question | 96.1K | 78.5K | 90.9K | 110.2K | 104.2K |

Run 2 repeats run 1's ordering. One difference: V1 now usually lands on the Finance bookings number for Q1 (0.92 vs 0.67).
Q1 on V1 vs V2 is no longer a reliable live contrast. Lead Q1 with V0 vs V2, and use V1 vs V2 only if V1 hedges.
