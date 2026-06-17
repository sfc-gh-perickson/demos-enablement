# Speaker Notes: Cortex AI Observability — Surface Identification & Cost Attribution

## Presentation Context

This is an SE enablement presentation covering how to identify which surfaces are generating Cortex AI usage and how to attribute costs back to teams, projects, and applications. It targets Snowflake SEs who need to help customers understand their AI cost posture, set up monitoring, and implement governance guardrails across multi-surface Cortex deployments.

The presentation is structured in four sections: Concepts (slides 1-3) covers the "why" and maps the landscape; Surfaces (slides 4-6) covers identification techniques; Costs (slides 7-9) covers attribution mechanics; Governance (slides 10-12) covers budgets and takeaways.

---

## Slide 1: Hero / Overview

**Talking Points:**
- Frame the session: "We're going to cover how to answer two questions every AI platform team needs to answer: who is using our AI services, and what does it cost?"
- The four stat cards represent the key capabilities: 5+ distinct entry points into Cortex AI, token-level cost granularity per model per request, tag-based grouping for cost center attribution, and near-real-time data availability (1-2 min latency in the usage views).
- Set expectations: Part 1 maps the landscape, Part 2 shows how to identify traffic by surface, Part 3 shows how to attribute costs, Part 4 covers governance tooling.
- Emphasize that this is not just about cost control — it's about understanding adoption patterns. Which teams are using AI? Which surfaces drive the most value? Where is usage growing?

**Key Insight:**
Observability is the foundation of AI governance. You cannot set budgets, enforce policies, or measure ROI without first knowing who's using what, from where, and at what cost. This presentation gives SEs the building blocks to help customers stand up unified AI observability.

**Common Questions:**
- *Q: Is there a single view that captures all Cortex AI usage?*
  A: No. Usage is spread across surface-specific views. Slide 9 shows the UNION ALL pattern to create a unified view.
- *Q: How real-time is the data?*
  A: ACCOUNT_USAGE views have ~1-2 minute latency. ORGANIZATION_USAGE views (like QUERY_ATTRIBUTION_HISTORY) have up to 3-hour latency.
- *Q: Do customers need Snowflake Enterprise edition?*
  A: ACCOUNT_USAGE views require IMPORTED PRIVILEGES on the SNOWFLAKE database, which is available on all editions. Resource budgets require Enterprise+.

---

## Slide 2: The Multi-Surface Challenge

**Talking Points:**
- Walk through each card as a distinct entry point into Cortex AI. The key insight is that a single agent can be accessed from 4+ surfaces simultaneously, each generating usage that needs tracking.
- MCP is the fastest-growing surface — customers connecting Claude Desktop, ChatGPT, and Cursor to their Snowflake agents. But it's also the hardest to attribute (covered in slide 6).
- The highlight box frames the core problem: without unified observability, a customer might have great visibility into their Snowsight usage but be blind to API-driven consumption that's 3x larger.
- Real-world scenario: a customer's finance team uses CoWork, their engineering team uses MCP via Claude Desktop, and their data team uses SQL function calls. Three different cost centers, three different views, no single pane of glass unless you build one.

**Key Insight:**
The multi-surface challenge is new — 12 months ago, most Cortex usage came from Snowsight or direct SQL. MCP, REST API integrations, and Teams have exploded the surface area. Customers who set up monitoring only for the Snowsight surface are missing significant and growing usage from programmatic and MCP channels.

**Common Questions:**
- *Q: Which surface generates the most usage typically?*
  A: It varies by customer maturity. Early adopters tend to be heavy on agent_admin_ui (testing). Production deployments shift to external (API/MCP) and sql_function. CoWork usage scales with business-user adoption.
- *Q: Can I see all surfaces for a single agent?*
  A: Yes — CORTEX_AGENT_USAGE_HISTORY captures all interfaces for a given agent. Filter by AGENT_NAME and group by METADATA:'interaction_interface'.

---

## Slide 3: The Observability Landscape

**Talking Points:**
- This is the reference table — the "which view do I query?" cheat sheet. SEs should bookmark this.
- Key distinction: CORTEX_AGENT_USAGE_HISTORY captures agent orchestration costs (LLM tokens for planning, tool selection, response generation). QUERY_ATTRIBUTION_HISTORY captures the downstream warehouse compute costs of SQL the agent generates.
- CoWork has its own dedicated view because it's a distinct Snowflake product, even though it may use Cortex Agents under the hood. The intelligence-level view gives you per-instance attribution.
- RBAC callout: this is where many customers get stuck. Without IMPORTED PRIVILEGES on the SNOWFLAKE database, they can't see any of these views. The CORTEX_GOVERNANCE_VIEWER application role unlocks the granular token/credit columns.

**Key Insight:**
The view landscape is intentionally separated by surface because each surface has different metadata needs. Agents need interaction_interface and tool call details. REST API needs model name and request_id. CoWork needs intelligence instance identity. The unified view (slide 9) normalizes these differences for cross-surface analytics.

**Common Questions:**
- *Q: What's the difference between CORTEX_AGENT_USAGE_HISTORY and CORTEX_REST_API_USAGE_HISTORY?*
  A: Agent usage captures full agent orchestration (multi-turn, tool calls, planning). REST API captures individual LLM calls (single Complete/Embed invocations). If you call CORTEX.COMPLETE() directly, it appears in REST API history. If you invoke an agent, it appears in agent history.
- *Q: Where does Cortex Search usage appear?*
  A: Cortex Search has its own view (CORTEX_SEARCH_USAGE_HISTORY). It's not covered in detail here but follows the same ACCOUNT_USAGE pattern.
- *Q: What about Cortex Fine-tuning?*
  A: Fine-tuning jobs appear in CORTEX_FINE_TUNING_USAGE_HISTORY. Training costs are separate from inference costs.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/governance-and-availability/ai-cost-management-and-governance
- https://docs.snowflake.com/en/sql-reference/account-usage/cortex_agent_usage_history

---

## Slide 4: Surface Identification: Cortex Agents

**Talking Points:**
- This is the most important view for agent-heavy customers. CORTEX_AGENT_USAGE_HISTORY is the primary source of truth for all agent interactions regardless of how they were triggered.
- The METADATA column is a VARIANT/OBJECT type. The key field is `interaction_interface` — a string that tells you how the request arrived.
- Walk through each value: `external` is the catch-all for API-driven access (MCP, programmatic clients, curl). `sql_function` means someone called AGENT() in SQL. `agent_admin_ui` is the Snowsight testing playground. `microsoft_teams` is the Teams integration.
- Internal context: `interaction_interface` currently only has these 4 values. It's a known limitation that `external` doesn't distinguish between MCP clients. This is on the roadmap but no committed timeline.
- RBAC note: The METADATA column is always populated. No additional roles needed beyond IMPORTED PRIVILEGES to see it.

**Key Insight:**
The `interaction_interface` field is the first thing to look at when a customer asks "where is my agent usage coming from?" It immediately tells you if the traffic is from developers testing (agent_admin_ui), production applications (external), data pipelines (sql_function), or collaboration tools (microsoft_teams). This shapes the governance conversation — developer testing needs different controls than production API traffic.

**Common Questions:**
- *Q: Can I filter to just MCP traffic?*
  A: Not directly. MCP traffic appears as `external` alongside other API calls. The QUERY_TAG workaround (slide 6) is the current best practice for distinguishing MCP clients.
- *Q: Does interaction_interface appear in real-time?*
  A: Yes, with the standard ~1-2 minute ACCOUNT_USAGE latency.
- *Q: What about Cortex Code — does it show up here?*
  A: Cortex Code has its own dedicated view (CORTEX_CODE_CLI_USAGE_HISTORY). It does not appear in the agent usage history because it uses a different service path.

**References:**
- https://docs.snowflake.com/en/sql-reference/account-usage/cortex_agent_usage_history

---

## Slide 5: Surface Identification: CoWork & REST

**Talking Points:**
- Two-column layout shows the two other major surfaces with their own dedicated views.
- Left column (CoWork): Each Snowflake Intelligence instance is a named object. The view gives you per-instance, per-user attribution out of the box. This is the easiest surface to monitor because it's fully managed and named.
- Right column (REST API): Captures direct LLM calls — CORTEX.COMPLETE(), CORTEX.EMBED(), etc. These are not agent calls; they're single-shot inference requests. The key columns are MODEL_NAME (which model was invoked) and REQUEST_ID (for correlation).
- Distinction for customers: If they're building custom applications that call the Cortex REST API directly (not through an agent), this is where their usage lives. If they're using agents, even via REST API, it goes to CORTEX_AGENT_USAGE_HISTORY.
- RBAC note: Both views require IMPORTED PRIVILEGES. SNOWFLAKE_INTELLIGENCE_USAGE_HISTORY requires the user to have access to the intelligence object or be ACCOUNTADMIN.

**Key Insight:**
CoWork is often the highest-volume surface for business users but the easiest to govern because each Intelligence instance is a distinct, named Snowflake object with clear ownership. REST API usage is often the highest-volume for engineering teams building custom AI features, but harder to attribute because there's no "named object" — just raw API calls identified by model and user.

**Common Questions:**
- *Q: If CoWork uses Cortex Agents under the hood, does usage appear in both views?*
  A: Usage appears in SNOWFLAKE_INTELLIGENCE_USAGE_HISTORY for the CoWork-specific view. The underlying agent tokens may also appear in CORTEX_AGENT_USAGE_HISTORY depending on the implementation. Avoid double-counting in your unified view by choosing one source per surface.
- *Q: Can I see which model CoWork is using?*
  A: Yes — the SNOWFLAKE_INTELLIGENCE_USAGE_HISTORY view includes model information in its token granular columns.

**References:**
- https://docs.snowflake.com/en/sql-reference/account-usage/snowflake_intelligence_usage_history_view
- https://docs.snowflake.com/en/sql-reference/account-usage/cortex_rest_api_usage_history

---

## Slide 6: MCP Client Identification

**Talking Points:**
- This is the "known gap" slide. Be upfront with customers: if they need to distinguish between Claude Desktop and ChatGPT calling their agents via MCP, there's no platform-native solution today.
- The workaround uses QUERY_TAG — a session-level parameter that propagates to QUERY_ATTRIBUTION_HISTORY. If the customer controls the MCP server, they can set QUERY_TAG at connection time with a JSON payload identifying the client.
- Show the real-world example: Cortex Code CLI already does this automatically. Its queries appear in QUERY_ATTRIBUTION_HISTORY with `{"app":"cortex_code_cli"}`. Customers can follow the same pattern.
- Limitations of the workaround: QUERY_TAG only helps with downstream SQL attribution (warehouse costs). It does NOT appear in CORTEX_AGENT_USAGE_HISTORY. So you get compute-cost attribution but not token-cost attribution by MCP client.
- Internal context: Finer-grained MCP identification is a known feature gap. The product team is aware. No committed timeline. For now, recommend the QUERY_TAG pattern and structuring MCP servers to use distinct Snowflake users per client type as another attribution dimension.

**Key Insight:**
The QUERY_TAG workaround is imperfect but actionable today. For customers with strong cost attribution requirements across MCP clients, the recommended pattern is: (1) use distinct Snowflake service users per MCP client type for USER_NAME-based attribution, and (2) set QUERY_TAG JSON at session initialization for query-level compute attribution.

**Common Questions:**
- *Q: Will this be fixed? Is there a roadmap item?*
  A: It's a known gap the product team is tracking. No public commitment on timeline. For now, the QUERY_TAG + distinct-user pattern is the recommended approach.
- *Q: Can I set QUERY_TAG in the MCP server code?*
  A: Yes — if you control the MCP server implementation, execute `ALTER SESSION SET QUERY_TAG = '...'` at connection initialization. This tags all subsequent queries from that session.
- *Q: What if the customer doesn't control the MCP server?*
  A: If they're using a managed MCP server (like Snowflake's own MCP server), QUERY_TAG may already be set. Check QUERY_ATTRIBUTION_HISTORY to see what tags are being set automatically.

**References:**
- https://docs.snowflake.com/en/sql-reference/organization-usage/query_attribution_history

---

## Slide 7: Cost Attribution: Token-Level Granularity

**Talking Points:**
- This slide is about understanding the internal structure of cost data. TOKENS_GRANULAR and CREDITS_GRANULAR are VARIANT (JSON) columns that contain arrays of per-request, per-model breakdowns.
- Walk through the JSON structure: each element has a request_id, service_type, model, and a tokens object with four fields: input, cache_read_input, cache_write_input, and output.
- Cache economics are critical: cache_read_input tokens are billed at a significantly reduced rate (often 10-25% of standard input cost). A high cache_read ratio means the prompt prefix caching is saving money.
- The second code block shows the LATERAL FLATTEN pattern for extracting and aggregating across these nested structures. This is the pattern customers will use most often.
- RBAC note: The TOKENS_GRANULAR and CREDITS_GRANULAR columns require the CORTEX_GOVERNANCE_VIEWER application role for full detail. Without it, customers get aggregate TOKENS_USED and CREDITS_USED but not the per-model breakdown.

**Key Insight:**
Token-level granularity unlocks model-selection optimization. If a customer sees that 60% of their agent's credits go to a single expensive model for simple routing decisions, they can switch that step to a cheaper model. Without granular data, they'd only see the aggregate cost and not know where to optimize.

**Common Questions:**
- *Q: What's the difference between input and cache_write_input?*
  A: `input` is the total input tokens sent. `cache_write_input` is the subset that was written to the prompt cache for future reuse. `cache_read_input` is the subset that was served from cache (avoiding re-processing). cache_write has a small additional cost; cache_read has a large discount.
- *Q: Is CREDITS_GRANULAR in Snowflake credits or dollars?*
  A: Snowflake credits. To convert to dollars, multiply by the customer's credit rate (typically $2-4/credit depending on contract).
- *Q: How do I know which model my agent is using?*
  A: The `model` field in TOKENS_GRANULAR tells you exactly which model processed each request. This is especially useful for agents using `auto` model selection.

**References:**
- https://docs.snowflake.com/en/sql-reference/account-usage/cortex_agent_usage_history
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/governance-and-availability/ai-cost-management-and-governance

---

## Slide 8: Cost Attribution: Tag-Based Grouping

**Talking Points:**
- Tags solve the "who pays for this?" problem. Without tags, you can only attribute costs by user or by agent. Tags let you map costs to arbitrary organizational constructs: teams, projects, cost centers, business units.
- Two tag arrays: USER_TAGS (set on the user, identifies the consumer) and AGENT_TAGS (set on the agent, identifies the product/service).
- Multi-level inheritance: tags can be set at account level (applies to all), user level (applies to one person), schema level (applies to all agents in schema), or agent level (applies to one agent). Lower levels override higher levels.
- The LATERAL FLATTEN pattern is essential — since tags are arrays, you need to unnest them for GROUP BY operations.
- Real-world pattern: large enterprises set account-level tags for the business unit, user-level tags for team/role, and agent-level tags for the application or product line. This gives them a 3-dimensional cost cube.

**Key Insight:**
Tags are the mechanism that connects AI costs to finance's chart of accounts. Without tags, the best you can do is "User X spent Y credits." With tags, you can say "The Sales Analytics team's customer-insights agent spent Y credits on Project Z." This is the level of granularity finance teams need for chargeback and forecasting.

**Common Questions:**
- *Q: Can I set tags retroactively?*
  A: Tags apply going forward from when they're set. Historical data won't be re-tagged. Plan tag structure early.
- *Q: How many tags can I set?*
  A: Tags are string arrays. There's no hard limit on the number of tags per user or agent, but keep them structured (use key:value format) for parseable analytics.
- *Q: Do tags work with shared budgets?*
  A: Tags and budgets are complementary but separate. Tags help you analyze who's spending. Budgets help you limit spending. Use tags to understand your cost distribution, then set budgets based on that understanding.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/governance-and-availability/ai-cost-management-and-governance

---

## Slide 9: Building a Unified Cost View

**Talking Points:**
- This is the "bring it all together" slide. The UNION ALL pattern normalizes disparate views into a single queryable structure.
- Key design decisions: normalize column names (surface, user_name, agent_name, interface, tokens, credits, ts), handle NULLs for surfaces that don't have all fields (e.g., Cortex Code has no agent_name), and use literal strings for the interface column on surfaces that don't have dynamic interfaces.
- The view is intentionally simple — customers can extend it with JOINs to user tags, department mappings, or project assignments stored in their own tables.
- Caution about double-counting: if CoWork uses Cortex Agents under the hood, including both views could double-count. Recommend customers pick one view per surface and validate with their specific configuration.
- This view is the foundation for Streamlit dashboards, scheduled reports, and executive summaries of AI adoption.

**Key Insight:**
The unified view pattern is the single most valuable deliverable from this module. Customers who build it get immediate answers to "how much are we spending on AI?" and "which teams are adopting?" — questions that previously required manual correlation of multiple views and guesswork.

**Common Questions:**
- *Q: Should I materialize this as a table or keep it as a view?*
  A: Start with a view for real-time access. If query performance becomes an issue (unlikely for most accounts), consider a scheduled task that materializes daily aggregates.
- *Q: Can I add Cortex Search and Fine-tuning to this?*
  A: Absolutely. Add additional UNION ALL legs for CORTEX_SEARCH_USAGE_HISTORY and CORTEX_FINE_TUNING_USAGE_HISTORY. Normalize the columns the same way.
- *Q: How do I handle the ORGANIZATION_USAGE vs ACCOUNT_USAGE split?*
  A: QUERY_ATTRIBUTION_HISTORY is in ORGANIZATION_USAGE (cross-account). The other views are ACCOUNT_USAGE (single account). For the unified view, keep them separate or JOIN on query_id/time windows. Don't mix UNION ALL across different latency tiers without noting it.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/governance-and-availability/ai-cost-management-and-governance

---

## Slide 10: Resource Budgets for AI

**Talking Points:**
- Transition from reactive observability to proactive governance. Budgets prevent cost surprises.
- Walk through the table: Resource budgets are per-object hard limits. Shared budgets are pool-based limits across multiple objects. Credit limits are account-level caps.
- Not all surfaces support all budget types — this is important for customer planning. If a customer's primary concern is Cortex Code costs, they need account-level credit limits (not resource budgets). If it's agent costs, resource budgets per agent are the right tool.
- Threshold alerts are the early warning system. Best practice: set alerts at 50%, 75%, and 90% of budget. Use notification integrations to route to Slack/PagerDuty.
- Automated suspension at 100% is a hard stop — new requests are rejected. Customers need to understand this will impact users. Recommend setting budgets with headroom (e.g., 120% of expected usage) for the first month, then tightening based on actuals.

**Key Insight:**
Resource budgets are the only mechanism that provides hard cost enforcement for Cortex AI. Without them, a runaway automation or unexpected viral adoption can generate unlimited credits. With them, you have a safety net. The combination of tag-based visibility (who's spending) + resource budgets (how much can they spend) gives customers complete cost governance.

**Common Questions:**
- *Q: What happens when a budget is exhausted?*
  A: For resource budgets with suspend action, new requests are rejected with an error. Existing in-flight requests complete. The agent becomes available again when the budget resets (next period) or an admin raises the limit.
- *Q: Can I set budgets per user?*
  A: Not directly on per-user basis for agents. You can set account-level shared budgets, or use distinct agents per team with individual resource budgets. USER_TAGS help you monitor per-user consumption even without per-user budgets.
- *Q: Do budgets count only token credits or also warehouse compute?*
  A: Resource budgets for Cortex features count Cortex credits (token-based costs). Warehouse compute from agent-generated queries is governed separately via warehouse resource monitors. They're distinct cost pools.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/governance-and-availability/ai-cost-management-and-governance

---

## Slide 11: Query-Level Attribution

**Talking Points:**
- This slide covers the "hidden cost" of AI agents: warehouse compute. An agent generates SQL, that SQL runs on a warehouse, and that warehouse time costs credits. QUERY_ATTRIBUTION_HISTORY captures this.
- Walk through the flow diagram: user asks a question → agent generates SQL → warehouse executes → compute credits are logged with attribution data.
- The QUERY_TAG link is critical. Cortex services tag their generated queries automatically. Customers can parse this JSON to attribute compute costs back to the originating AI service.
- Total cost of an AI interaction = LLM tokens (from agent usage view) + warehouse compute (from query attribution) + storage (if Cortex Search is involved). Most customers only look at the first component and miss 30-50% of the true cost.
- RBAC note: QUERY_ATTRIBUTION_HISTORY is in SNOWFLAKE.ORGANIZATION_USAGE, which requires the ORGANIZATION_USAGE_VIEWER role. It also has higher latency (up to 3 hours) compared to ACCOUNT_USAGE views.

**Key Insight:**
Query-level attribution reveals the true cost of AI. A customer might think their agent costs $0.02/query in tokens, but the SQL it generates scans a 10TB table and costs $0.50 in warehouse compute. Without QUERY_ATTRIBUTION_HISTORY, this 25x multiplier is invisible. This insight often drives customers to optimize their agent's SQL generation (better instructions, query guards) or their data model (clustering, materialized views).

**Common Questions:**
- *Q: How do I correlate agent usage with query attribution?*
  A: Use QUERY_TAG JSON parsing. Agent-generated queries include the agent name in their tag. You can also correlate on USER_NAME + time window, though this is less precise.
- *Q: Does the latency difference matter?*
  A: For real-time monitoring, yes. ACCOUNT_USAGE views (agent tokens) are available in ~2 minutes. ORGANIZATION_USAGE (query compute) can take up to 3 hours. For daily/weekly reporting, it's not an issue.
- *Q: What if the agent runs many queries per interaction?*
  A: All generated queries are tagged and attributed. Sum CREDITS_ATTRIBUTED_COMPUTE across all queries with the same agent tag within a time window to get the full compute cost per interaction.

**References:**
- https://docs.snowflake.com/en/sql-reference/organization-usage/query_attribution_history

---

## Slide 12: Key Takeaways

**Talking Points:**
- Walk through the 5-step flow: Surface Routing → Token Parsing → Tag Attribution → Unified Views → Budget Governance. Each step builds on the previous.
- Emphasize the practical "Getting Started" steps — these are the exact actions a customer should take in their first week of AI observability setup.
- The "Feature to watch" callout is important for SE credibility. Acknowledging known gaps builds trust. Customers appreciate honesty about limitations more than vague promises.
- Close with the framing: observability enables governance, governance enables confidence, confidence enables scaling. Customers won't scale AI usage if they can't answer basic questions about cost and adoption.
- Call to action: build the unified view (slide 9), set up one resource budget on your highest-traffic agent, and create a weekly report showing credits by surface. That's the minimum viable observability for production AI.

**Key Insight:**
The #1 takeaway: surface identification and cost attribution are two sides of the same coin. You need both to govern AI effectively. Knowing "external" traffic is growing 3x month-over-month (surface identification) is only actionable if you can also say "...and it's costing $X attributed to Team Y's project Z" (cost attribution). Build both capabilities together.

**Common Questions:**
- *Q: What's the easiest win for a customer who's done nothing yet?*
  A: Query CORTEX_AGENT_USAGE_HISTORY grouped by interaction_interface for the last 30 days. This single query reveals their surface mix and often surprises them (e.g., "I didn't know 40% of our agent traffic was from external API calls").
- *Q: How does this relate to the cost-intelligence skill in Cortex Code?*
  A: The cost-intelligence skill can help customers explore these views interactively. It queries ACCOUNT_USAGE views and can break down Cortex AI costs by service type, model, and user. It's a great starting point for customers who want conversational access to this data.
- *Q: Should customers build a Streamlit dashboard for this?*
  A: Yes — for production deployments, a Streamlit-in-Snowflake dashboard backed by the unified view is the recommended end state. It gives non-technical stakeholders (finance, management) self-service access to AI cost and adoption data.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/governance-and-availability/ai-cost-management-and-governance
- https://docs.snowflake.com/en/sql-reference/account-usage/cortex_agent_usage_history
- https://docs.snowflake.com/en/sql-reference/account-usage/snowflake_intelligence_usage_history_view
- https://docs.snowflake.com/en/sql-reference/account-usage/cortex_rest_api_usage_history
- https://docs.snowflake.com/en/sql-reference/organization-usage/query_attribution_history
