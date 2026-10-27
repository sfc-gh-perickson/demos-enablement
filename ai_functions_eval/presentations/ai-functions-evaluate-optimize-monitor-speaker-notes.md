# Speaker Notes: From Prompt to Production (AI Functions: Evaluate, Optimize, Monitor)

## Context

This customer-facing enablement session is for data, ML, and analytics teams moving Cortex AI functions (especially `AI_COMPLETE` with structured output) from prototype to production. It argues that LLM features need the same engineering discipline as code (a test suite, versioning, gated changes, and monitoring), and shows that Snowflake now provides those pieces natively: AI functions, versioned DATASETs, evaluation and optimization experiments, `CREATE AI FUNCTION ... FROM EXPERIMENT`, the Cortex usage-history views, tasks, and alerts. Every number in the deck comes from a real end-to-end run of the companion demo (`AI_FUNCTIONS_EVAL_DEMO` on the `parker_demo` account, 2026-10-27) over 300 synthetic support tickets. Lean on the honesty of the results: the run surfaced overfitting, label errors, and a schema regression, and those are the most persuasive parts of the story.

**Feature maturity (be upfront):** AI Function Studio, `CREATE AI FUNCTION`, and the evaluation and optimization experiments were in **preview** at the time of the run (see release notes below). Position them as "available to try now", and check current status before committing to production timelines with a customer.

---

## 1. From Prompt to Production (hero)
- Frame: "Most teams can build a great LLM demo in an afternoon. Getting the same thing safe, accurate, and cost-controlled in production is the hard part, and that's today's topic."
- The four stats are the arc of the talk. Don't explain them yet; tease that the 0% isn't a typo.
- **References:** https://docs.snowflake.com/en/user-guide/snowflake-cortex/ai-function-studio

## 2. A great demo is not a production system
- Ask the room how they validate prompts today. Typical answers: "we eyeball 10 rows" or "the PM tries it". That's the pain we're addressing.
- "Plausible but wrong" is the key idea. LLM failures rarely look like errors; they look like reasonable answers that break a downstream `CASE` statement or dashboard filter.
- Cost: customers often default to the biggest model. Don't promise a smaller model will work; promise a *measured* answer.
- **Internal:** if a customer is comparing against an external eval stack (LangSmith, Braintrust, homegrown), the pitch is not "we have more metrics". It's that the data, functions, evals, and monitoring all live under the same governance and RBAC with no data movement. Ours is younger, so don't overclaim feature parity.

## 3. One lifecycle, native to Snowflake
- Walk through the five boxes. Each is one SQL object or statement, which is the point: it's code-reviewable and CI-friendly.
- **References:** https://docs.snowflake.com/en/sql-reference/sql/create-ai-function, https://docs.snowflake.com/en/user-guide/snowflake-cortex/ai-function-studio

## 4. Support-ticket triage with structured output
- The use case mixes three kinds of output on purpose: taxonomy fields (classification), extraction fields, and a business-rule flag. Most real use cases mix these too.
- Emphasize: `response_format` guarantees the **shape** (valid JSON, required keys, types) but not the **values**, unless you constrain them with `enum`, which the optimizer later does on its own.
- **References:** https://docs.snowflake.com/en/sql-reference/functions/ai_complete-structured-outputs

## 5. Build a golden dataset, then freeze it
- 50/50 train/holdout is small but realistic for a first pass. Experiments cap at 1,000 rows.
- DATASET versions are immutable. That's a feature: a score from three months ago still points at exactly the data it was measured on.
- Gotchas worth mentioning: version names are case-sensitive, and there's no `ADD VERSION IF NOT EXISTS`.
- **Internal:** in the demo, labels were generated *first* and ticket text generated *to match*. That's a good trick for bootstrapping when customers have no labeled data, but as slide 12 shows, the generator doesn't always obey. Recommend pseudo-labeling plus human review for customers with real data.
- **References:** https://docs.snowflake.com/en/developer-guide/snowflake-ml/dataset, https://docs.snowflake.com/en/sql-reference/sql/alter-dataset-add-version

## 6. Pick metrics that match the task
- Our recommendation: an LLM judge for the headline score, deterministic per-field SQL for diagnosis.
- The llm_judge was noticeably more lenient than exact match (baseline: 0.30 judge vs 0% all-fields exact). That's fine as long as you know it; per-field checks keep you honest.
- **Internal / gotchas from the run:**
  - The evaluation spec **requires a top-level `evaluation:` block**. Without it, `EXECUTE` succeeds but the run immediately fails with "specification must contain a top-level 'evaluation' or 'optimization' section".
  - The spec schema rejected `task_description` / `metric_options` for llm_judge on this account, so the judge only sees expected vs predicted. If a customer needs rubric-aware judging, use a custom metric UDF (deterministic only) or run a separate `AI_COMPLETE` judge like our production sampler.
  - Custom metric UDFs must be deterministic and can't call LLMs.
- **References:** https://docs.snowflake.com/en/sql-reference/functions/ai_function_evaluation

## 7. The baseline: valid JSON, wrong values
- This is the "aha" slide. A premium model, 100% valid JSON, and zero rows fully correct.
- Read the judge feedback aloud; it's specific and actionable. Make the point that this feedback text is what the optimizer consumes in the next step.

## 8. Let the optimizer search prompts and models
- GEPA is the default and best-tested algorithm. CoCoEvolve is research preview.
- One experiment, multiple models, run concurrently. Don't create one experiment per model.
- The "light" budget took ~25 minutes for three models in the run (34 candidate runs). Set expectations accordingly.
- **Internal:** `mistral-small2` was rejected as an optimization model on this account (it isn't in the allowed list); we substituted `ministral-3-8b`. The error message lists allowed models, so check it for the customer's region. Also, the skill's cost-table script failed because frontier runs lacked an `estimated_cost` metric. The experiment records `cost_compared_to_seed` instead, and that's what the deck uses.
- **References:** https://docs.snowflake.com/en/sql-reference/functions/ai_function_optimization

## 9. What the optimizer changed
- The `enum` constraints are the single biggest win. They make out-of-taxonomy values impossible rather than unlikely.
- The escalation rule is the teachable moment: optimizers infer policy from examples, and inferred policy is approximately right. If you *know* the rule, write it down.
- Point at `"other"` now; it pays off on slide 16.

## 10. Never ship on the validation score
- Validation scores of 0.84–0.90 dropped to 0.42–0.60 on unseen holdout data. With 50 training rows and many iterations, overfitting is expected. The fix is a holdout set plus more diverse training data, not a different optimizer.
- **Internal:** the optimizer only scored *frontier* candidates on the holdout (all ministral in this run, because the frontier is cost-weighted). We deployed the best candidate per model with `FROM EXPERIMENT` and ran separate evaluation experiments to compare fairly. Recommend that workflow to customers.

## 11. Make the cost/quality trade-off explicit
- Relative cost is per call versus the original naive Sonnet function. The optimized Sonnet prompt is much longer, hence ~1.9x.
- Be balanced: ministral and nano at 0.03–0.08x are attractive for high-volume, lower-risk fields, and a hybrid (cheap model for taxonomy fields, premium for the escalation decision) is a legitimate design. We didn't test the hybrid in this run.
- **Internal:** don't quote dollar figures. Credit rates vary by contract and model, so point to the consumption table and usage history for the customer's actual numbers.
- **References:** https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql-cost

## 12. Some "model errors" are label errors
- We found this in the run itself. Adding the explicit rule didn't move escalation accuracy (0.76 → 0.76), which was the clue.
- 24 disputed rows were adjudicated by `claude-opus-4-7` against the written rule; 19 were corrected, 12 of them escalation flags.
- **Caveat (say it if challenged):** we only reviewed rows where the Sonnet variants disagreed with the label, which slightly favors Sonnet in the v2 re-score. In a real engagement, review all disagreements across all candidates, and have a human approve the corrections.

## 13. Before vs after, field by field
- Final = optimized Sonnet body + explicit escalation rule (`03_optimized_function_v2.sql`). It isn't a pure experiment run, because we hand-edited the escalation section. Say so if asked; it's the "write the rule down" lesson.
- The LLM judge on the same data: 0.30 → 0.80.

## 14. Deploy patterns that keep you in control
- `FROM EXPERIMENT ... RUN` means no prompt copy-paste and no drift between what was measured and what shipped.
- The `function_version` column on every output row is cheap and invaluable when quality questions come up later.
- `QUERY_TAG` on the task is how cost attribution works in usage history.
- **References:** https://docs.snowflake.com/en/sql-reference/sql/create-ai-function

## 15. Four signals, no ground truth required
- Health and drift checks are plain SQL and nearly free. Run them often.
- Sampled LLM review costs tokens, so keep the sample small (we use 20 rows a day) and tag it.
- **Internal:** the demo alert initially failed with "EXECUTE ALERT privilege must be granted to owner role". The owning role needs `GRANT EXECUTE ALERT ON ACCOUNT` (ACCOUNTADMIN). Mention it in setup conversations.
- **References:** https://docs.snowflake.com/en/sql-reference/account-usage/cortex_ai_functions_usage_history, https://docs.snowflake.com/en/user-guide/snowflake-cortex/ai-func-cost-management, https://docs.snowflake.com/en/user-guide/alerts

## 16. Monitoring in action: day one
- The `"other"` finding is the best evidence for monitoring: a regression introduced by the optimizer that the holdout eval didn't make obvious. The eval measured accuracy, not taxonomy conformance; health checks measure conformance directly.
- The 55% sampled-review score is lower than the 0.80 eval score. Be candid: the production reviewer is reference-free (no label) and audits stricter, rubric-based criteria, so the two numbers aren't directly comparable. Treat the reviewer as a *triage queue* for human labeling, not a ground-truth accuracy number.
- ~6.2 credits per 1K tickets is the tagged workload's credits from usage history on day one. Usage history can lag by up to a few minutes, so totals settle after the run.

## 17. Close the loop
- This slide is the operating model. Ask who would own each cadence on their team.

## 18. Production-readiness checklist
- Leave the checklist up. Offer the demo (`setup.sql` + notebook) and a working session on one real use case with ~50 labeled examples.
- **References:** https://docs.snowflake.com/en/release-notes/2026/other/2026-09-21-ai-function-evaluation-preview, https://docs.snowflake.com/en/release-notes/2026/other/2026-09-21-ai-function-optimization-preview, https://docs.snowflake.com/en/release-notes/2026/other/2026-05-20-cortex-ai-function-studio-public-preview
