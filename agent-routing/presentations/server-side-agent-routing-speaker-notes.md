# Server-Side Agent Routing — Speaker Notes

## Account Context Summary

This presentation covers the server-side agent routing pattern for organizations running multiple Cortex Agents exposed to external LLM-powered clients via MCP. It demonstrates how a supervisor agent eliminates cross-surface tool-selection variance by centralizing routing logic inside Snowflake.

---

## Slide: Overview (Hero)

**Talking Points:**
- Open with: "This session demonstrates a supported pattern for server-side routing — an agent invoking another agent as a tool, so routing logic executes inside Snowflake rather than in each client."
- The four stats set the frame: multiple agents, multiple surfaces causing variance, 1 supervisor to unify routing, 0 routing variance after.
- This is not a future roadmap item — it works today using GA primitives (CREATE AGENT, stored procedures, DATA_AGENT_RUN).

**Internal Context:**
- Agent-to-agent delegation is documented in the inter-app agents pattern. It's not a first-class "CREATE SUPERVISOR" primitive, but the stored-procedure-wrapper approach achieves the same result.
- Competitive note: If customers evaluate moving agents off Snowflake to get better orchestration (e.g., LangGraph, CrewAI), this demo shows Snowflake already supports the pattern natively — no external orchestration framework needed.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents
- https://docs.snowflake.com/en/developer-guide/native-apps/inter-app-agents

---

## Slide: The Problem — Inconsistent Agent Selection

**Talking Points:**
- Walk through each client surface's behavior:
  - Some surfaces defer tool loading; agents compete with every other connector the user has installed.
  - Others use toggle-based access (auto vs on-demand). Algorithms aren't published.
  - Still others have no published docs on tool loading behavior.
- Emphasize: "You control descriptions but not the ranking algorithm. And each user's environment is different."
- The result: same question, different routing, depending on surface + user config.

**Internal Context:**
- This is fundamentally a client-layer problem, not a Snowflake problem. But customers experience it as "our agents don't work consistently" — so we need to own the solution even though the root cause is client behavior.
- If the audience pushes back on "why doesn't Snowflake fix this at the MCP layer?" — the answer is: MCP is a transport standard, not an orchestration layer. MCP exposes tools; it doesn't rank or select them. That's always the client's job.
- The mitigations (tool search opt-out, always-load settings, managed MCP config) are per-surface, per-install, and none transfer across all client products.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents (MCP connectors section)

---

## Slide: Root Cause

**Talking Points:**
- Two-column layout makes the point visually: we control tool metadata, we don't control client behavior.
- The key insight (highlight box): variance affects discovery, not execution. Once an agent is invoked, it runs identically everywhere.
- This means the fix is purely about making discovery deterministic — which is exactly what a server-side supervisor does.

**Internal Context:**
- The "we don't control" column is a deliberate product boundary. Snowflake won't (and shouldn't) try to control how client products rank tools. Instead, we collapse the problem: one tool = one supervisor = no ranking needed.
- If the audience asks "can't you just make MCP servers have priority?" — the answer is no, and it wouldn't solve the problem even if we could, because the user's other connectors would still compete.

---

## Slide: The Solution — Platform-Side Orchestration

**Talking Points:**
- Three cards: Single Entry Point, Server-Side Routing, Testable & Measurable.
- "Instead of N tools visible to the client (which it may or may not rank well), there's now ONE. The supervisor handles everything else inside Snowflake."
- The testability angle is key for enterprise: you can now CI/CD your routing logic.

**Internal Context:**
- Product gap acknowledgment: there is no first-class `CREATE SUPERVISOR AGENT` command. The pattern uses stored procedures as the glue. It works, but it's a composition pattern, not a built-in feature. If asked "will this become a native primitive?" — the honest answer is "it's being considered, but the current approach is production-ready and supported."

---

## Slide: Architecture

**Talking Points:**
- Walk through the diagram top-to-bottom: client makes one call -> supervisor reasons -> routes to correct specialist via stored procedure.
- Emphasize the stored procedure wrapper: it's EXECUTE AS OWNER, so each specialist runs with its own identity and grants. No privilege escalation.
- The pattern box at the bottom is the "recipe": agent -> proc -> supervisor.

**Internal Context:**
- Latency: the supervisor adds one LLM reasoning call (~1-3 seconds) before routing. For most use cases (analyst questions, not real-time), this is fine. If the audience pushes on latency, note that simple keyword routing could be done in a UDF instead of an agent call, but they'd lose the fuzzy reasoning that handles ambiguous queries.
- Token cost: supervisor uses ~500-1500 tokens for routing. At 15+ specialists, the orchestration instructions are ~200 words. This is well within budget.

**References:**
- https://docs.snowflake.com/en/developer-guide/native-apps/inter-app-agents (agent-to-agent via stored procedure pattern)
- https://docs.snowflake.com/en/sql-reference/functions/data_agent_run-snowflake-cortex

---

## Slide: Implementation Pattern

**Talking Points:**
- Show the code. The wrapper is ~15 lines of Python. It's trivial to replicate for all specialists.
- Key details: EXECUTE AS OWNER resets caller context. The specialist doesn't inherit the calling user's privileges — it uses the procedure owner's.
- The `DATA_AGENT_RUN` function is the SQL equivalent of the REST API. Non-streaming. Returns JSON.

**Internal Context:**
- Watch for the question: "Can't we just have the supervisor call the REST API directly?" Yes, but DATA_AGENT_RUN is simpler from inside Snowflake and doesn't require auth token management. The procedure approach keeps everything server-side.
- If asked about error handling: the current pattern returns raw error JSON if the specialist fails. In production, they'd want to add try/catch and surface a friendly message.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/data_agent_run-snowflake-cortex
- https://docs.snowflake.com/en/developer-guide/native-apps/inter-app-agents#agent-to-agent-historical-analysis

---

## Slide: Supervisor Agent Specification

**Talking Points:**
- Show the CREATE AGENT spec — tools are `type: generic` with `type: procedure` in tool_resources.
- The orchestration instructions are where routing keywords live. This is the "routing table" — they can tune this without changing any code.
- Point out: descriptions are still important (the supervisor's LLM reads them), but now they're consumed by ONE model (the supervisor's orchestrator), not multiple different client runtimes.

**Internal Context:**
- The supervisor's quality depends on the orchestration model. `auto` currently selects the best available model. If deterministic behavior is needed, pin to a specific model, but `auto` improves over time.
- With 15+ tools, the supervisor's context window needs ~2000 tokens just for tool descriptions. Keep descriptions concise. Routing keywords at the front of each description matter more than long explanations.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-manage

---

## Slide: Evaluating Routing Quality

**Talking Points:**
- This is the "measurable" part. Cortex Agent Evaluations (GA March 2026) + tool metrics (Preview June 2026).
- `tool_selection_accuracy`: Did the supervisor call the correct specialist? This directly measures routing correctness.
- `answer_correctness`: Did the specialist actually answer well? Catches downstream quality issues.
- `logical_consistency`: Reference-free, no ground truth needed. Catches reasoning contradictions.
- Show the dataset row — ground_truth_invocations defines expected routing.

**Internal Context:**
- The tool metrics (`tool_selection_accuracy`, `tool_execution_accuracy`) are in Preview as of June 11, 2026. They work but may evolve. Flag this as "Preview" if the audience asks about GA timeline.
- Evaluation runs cost tokens (supervisor + specialist per query + LLM judge). For a small dataset (~6 queries) this is ~$0.50. For full coverage across many specialists (30-50 queries), expect ~$5-10 per eval run.
- Evaluation limitation: MCP connector agents can't be evaluated yet. But since the supervisor uses stored procedure tools (not MCP), this doesn't apply here.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations
- https://docs.snowflake.com/en/release-notes/2026/other/2026-06-11-cortex-agent-tool-metrics

---

## Slide: Before vs After

**Talking Points:**
- Walk the table row by row. The green/red visual makes the point immediately.
- Emphasize "Regression detection" row: without this pattern, there's no way to know if a routing change made things worse. After, you run evals on every change.
- "Zero variance" means: whether a user calls from one client surface with many other MCP servers installed, or from another surface with nothing else, routing is identical.

**Internal Context:**
- Be prepared for the question: "What if we still want users to be able to call specialists directly?" Answer: They can. The supervisor is an additional entry point, not a replacement. Keep the MCP server with all tools for power users who know exactly which agent they want. The supervisor is for the default/uniform experience.

---

## Slide: Scaling to Many Agents

**Talking Points:**
- Linear scaling: each new specialist is agent + procedure + supervisor tool entry + eval coverage. No exponential complexity.
- Production considerations callout: latency (~1-3s added), cost (monitor via CORTEX_AI_USAGE), eval cadence (after every instruction change).
- Stress that the eval dataset is the living documentation of routing requirements.

**Internal Context:**
- At 15+ specialists, the supervisor's tool list gets long. If quality degradation occurs with many tools, two options:
  1. Hierarchical routing: supervisor -> domain supervisors -> specialists (e.g., supervisor picks a domain, then a domain-supervisor picks the specific specialist).
  2. Tool choice narrowing: use the `tool_choice` parameter to constrain available tools based on metadata.
- Pricing: The supervisor adds ~$0.002-0.005 per routed query in orchestration tokens. At typical scale, this is negligible vs. the specialist cost.

---

## Slide: Next Steps

**Talking Points:**
- Four concrete actions. Frame as "we can do step 1 together right now."
- Step 1 (run the notebook) is the immediate CTA.
- Step 2 (connect real tools) is where real semantic views and search services get plugged in.
- Step 3 (expand to all specialists) is the rollout.
- Step 4 (eval baseline) is the ongoing quality gate.

**Internal Context:**
- The end-state callout is the key message: "One Supervisor Agent exposed via MCP. Every client makes a single call. Routing is consistent, testable, and owned by your team."
- The supervisor will also appear in Snowflake Intelligence and be callable there — SI is another surface that benefits from this pattern.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents (tutorials section)
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations
