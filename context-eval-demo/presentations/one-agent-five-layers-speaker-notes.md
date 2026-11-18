# One agent, five layers of context: speaker notes

**Context.** Internal enablement material for SEs and AFEs. It goes with the deck *Context Helps, Evals Earn Trust: Ontology, Cortex Sense & Evaluating Cortex Agents* and the live demo in `~/enablement/context-eval-demo/`.

The point is not "add every feature". The point is to show a customer how to decide *which* context layer to add, using Agent Evaluations as the referee.
- The data is synthetic revenue CRM data, and every trap is deliberate.
- The numbers come from one eval run (tag `e1118b`, 2026-11-18) against a single agent, `CONTEXT_EVAL_DEMO.AGENTS.REVENUE_ASSISTANT`, which has five aliased versions.
- Use it for data or analytics leaders who are building their first Cortex Agent, and for teams who have already stuffed a giant semantic view behind one and are wondering why it's slow and wrong.

---

## 1. One agent, five layers of context

- Open with the claim: context helps, but only the right context, and you find out which with evals, not intuition.
- The four stats are the whole story in miniature:
  - one agent
  - five questions
  - correctness from 0.30 to 0.87
  - an 18% token drop from the cheapest fix (a small governed semantic view)
- **Internal:** if someone asks "is 0.87 good?", the honest answer is that the absolute number means little on a 20-question synthetic set. The *deltas per layer* are the point.

**References**
- Cortex Agent evaluations: https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations

## 2. The setup

- Stress the controlled experiment: same model setting, same base instructions, one layer added per version. That is why a version-level score change can be attributed to the layer.
- Versions are immutable named versions with aliases. This is the same mechanism a customer would use for dev → canary → production promotion, so it doubles as a versioning demo.
- **Internal:**
  - The orchestration model is `auto`, so it isn't strictly pinned. For a tighter story, pin a model in `agent/specs/*/agent_spec.yaml` and redeploy.
  - Expect the question "did the model change between runs?"
  - `VERSION$2` is a leftover duplicate of V0. Creating an agent from a stage always creates a LIVE copy, and LIVE must be committed before `ADD VERSION FROM` works. If anyone opens `SHOW VERSIONS`, call it out before they ask.

**References**
- Cortex Agent versioning: https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-versioning
- Agent versioning and promotion (cookbook): https://docs.snowflake.com/en/developer-guide/cortex-ai-cookbook/agent-versioning-and-promotion

## 3. Five questions, in fix order

- Walk the table top to bottom. The order is the narrative: each row needs one more layer than the one above it.
- The **failure mode** column is the reusable framework. Ask the customer which of these five they're seeing today. Most will say "certified number" and "contested meaning".
- **Internal:**
  - The test-account trap (excluding sandbox accounts from pipeline) was in the original design but didn't reproduce. V1 excluded test accounts on its own.
  - It now lives in the ontology as a policy node instead of a question.
  - If someone asks whether the traps are rigged: yes. Real customer data is messier, which makes the point stronger, not weaker.

## 4. Correctness by question

- Read it by diagonals: the bold cell in each row is where the fix lands, and everything to its right should hold.
- Call out the honest wrinkles; they build credibility:
  - **Bookings on V1 scored 0.92 this run (0.67 the run before).** V1 sometimes picks the Finance definition by luck. V2 gets it right because the definition is governed. That's the difference between correct and *reliably* correct.
  - **EMEA drop dips on V3/V4 (0.84, 0.67).** Each extra tool is another path the agent can wander down. This is what a regression check catches. In practice you'd scope Sense or tighten the instruction and re-run.
- **Internal:** four paraphrases per question means five questions × four paraphrases = 20 records per version. Don't over-claim statistical significance. Say "directional".

**References**
- Evaluate and promote Cortex Agent versions (cookbook): https://docs.snowflake.com/en/developer-guide/cortex-ai-cookbook/agent-evaluations

## 5. More context isn't free

- This is the "bite" slide.
  - V0's 38-table view costs more tokens than V1 and is wrong 70% of the time.
  - V3 is the most expensive version. Sense is worth it for the long-tail question and costs you on every other question.
- Land the rule: **add a layer only when an eval question it should fix keeps failing.**
- Tie it to the documented semantic view guidance:
  - start with 5–10 tables in a star schema
  - keep a view under roughly 100K tokens
  - avoid "all CRM tables" style views
  - lookalike descriptions hurt selection accuracy
- **Internal:**
  - The token numbers are agent tokens from eval data, not billed credits. For a billing view, run `evals/token_cost.sql` against `CORTEX_AGENT_USAGE_HISTORY`.
  - All versions share one agent, so billing can't split credits by version. Version-level cost comes from the eval token columns.

**References**
- Best practices for modeling semantic views: https://docs.snowflake.com/en/user-guide/views-semantic/best-practices-modeling
- Best practices for semantic views: https://docs.snowflake.com/en/user-guide/views-semantic/best-practices

## 6. Why each layer moved the score

- One mechanism per card. If you only have time for one, do V4. "No amount of context fixes behavior" is the line that lands with executives.
- **V3 detail:**
  - Sense found the partner-referral join because the demo seeds analyst queries into query history (`setup/04_seed_query_history.sql`, run six times).
  - In a real account, this is the strongest argument for Sense: it learns from how people already query.
  - It needs query history to exist, and `ACCOUNT_USAGE` lags about 45 minutes.
- **Internal:** V3 reached 0.67, not 1.00, on partner deals. Some paraphrases still fell back to the lead-source field. Be candid: Sense raises the odds, it doesn't make it deterministic.

## 7. What the ontology holds

- Show that the ontology is more than a glossary:
  - typed nodes (metric, dimension, policy)
  - bindings to specific semantic view members
  - typed relationships
- The "is not the same as" edge between Bookings and TCV Bookings is the contested-meaning fix made explicit.
- Explain the deliberate omissions: partner sourcing and the rep-ranking rule. This keeps the attribution clean, and it's also good advice. Put stable, contested definitions in the ontology, not every join.
- **Internal:**
  - Business Ontology and Cortex Sense are preview features, enabled on this demo account. Check availability in the customer's account before promising either.
  - I couldn't find a public docs page for either feature to link here. Don't send customers a URL you haven't verified.
  - The ontology is account-wide. A second install in the same account reuses the same nodes.

## 8. Run it yourself

- **Field ask:** install it in a demo account before a customer meeting and pre-run the live pairs in the app, because each live call takes 30–90 seconds.
- **Without preview features:** if Ontology or Sense isn't enabled, the installer skips V2 and/or V3. V4 is rebuilt without the missing tool, and the app marks the gaps instead of failing.
- **Internal:**
  - The Sense build is the only manual step. It runs offline and can take hours, so do it the day before.
  - Ontology creation from scratch hasn't been exercised in a fresh account yet; this account already had the nodes. Allow a few minutes to debug on the first install in a new account.

## 9. Takeaways

- Three lines to leave behind:
  - start small and governed
  - match the layer to the failure
  - let evals decide
- **Close with an offer:** pick five of the customer's real questions, tag them by failure mode, and run the same version-by-version eval on their data. That turns the deck into a workshop.

**References**
- Cortex Agent evaluations: https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations
