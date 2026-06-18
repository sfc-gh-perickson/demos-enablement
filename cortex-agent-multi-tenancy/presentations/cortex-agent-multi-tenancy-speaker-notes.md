# Speaker Notes: Cortex Agent Multi-Tenancy — RBAC for External Users

## Presentation Context

This is an SE enablement presentation covering how to build multi-tenant Cortex Agents that serve thousands of external users without creating individual Snowflake accounts. It targets Snowflake SEs who need to help customers implement per-user data isolation using session attributes, row access policies, and masking policies.

The presentation is structured in four sections: Concepts (slides 1-3) covers the "why" and architecture; Implementation (slides 4-7) covers the mechanics of session attributes, RAPs, masking, and entitlements; Operations (slides 8-10) covers scaling, the API, and best practices; Production (slides 11-12) covers audit and takeaways.

---

## Slide 1: Hero / Overview

**Talking Points:**
- Frame the session: "We're going to cover how to serve 10,000+ external users from a single Cortex Agent without creating a single Snowflake user account."
- The four stat cards represent the key properties: 10K+ external users with zero Snowflake account overhead, row + column level filtering, immutable session attributes that can't be bypassed by prompt injection, and no DDL required for user lifecycle management.
- Set expectations: Part 1 explains why traditional RBAC fails, Part 2 shows the implementation mechanics, Part 3 covers operational scaling, Part 4 covers audit and production readiness.
- This feature is GA. Customers can use it today in production.

**Key Insight:**
Multi-tenancy decouples user identity from Snowflake infrastructure. Your application authenticates users (via your IdP), passes their identity as immutable session attributes when calling the agent API, and Snowflake's policy engine enforces data boundaries on every query. The agent never needs to know about user permissions — the platform handles it transparently.

**Common Questions:**
- *Q: Is this feature GA or preview?*
  A: GA. Customers can use immutable session attributes with row access policies and masking policies in production today.
- *Q: Does this work with Cortex Search too?*
  A: No — row access policies apply to SQL queries only. Cortex Search bypasses RAPs because it uses a vector index. For search-based agents, you need per-tenant search services or pre-filtered source tables. This is covered in slide 10.
- *Q: How is this different from using multiple Snowflake roles?*
  A: Traditional RBAC requires one Snowflake user + role per person. At 10K users, that's 10K users, 10K roles, and tens of thousands of GRANT statements. Multi-tenancy uses one service account and one set of policies — user identity is a session variable, not a Snowflake object.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-multi-tenancy

---

## Slide 2: The Problem

**Talking Points:**
- Walk through each card as a distinct constraint that makes traditional RBAC fail. The combination of these four factors is what drives the multi-tenancy pattern.
- "External users" is the key differentiator — these are your customer's customers. They interact with an AI agent through a web app, mobile app, or API. They never see Snowflake.
- "Agent-generated SQL" is the security argument. You can't rely on the agent to add WHERE clauses or avoid sensitive columns — it generates unpredictable SQL. Security must be enforced at the platform level, not the application level.
- The highlight box is the punchline: traditional RBAC couples identity to infrastructure. Multi-tenancy decouples them.

**Key Insight:**
The "agent-generated SQL" constraint is the most important one to emphasize. Even if you could somehow create 10K roles, you still couldn't guarantee the agent would use them correctly. An LLM generating SQL will sometimes forget WHERE clauses, join to wrong tables, or request columns it shouldn't. Row access policies and masking policies are the only mechanism that guarantees correct filtering regardless of what SQL the agent produces.

**Common Questions:**
- *Q: Can't we just put instructions in the agent's system prompt to filter data?*
  A: Never rely on prompt-based security. Prompt injection can override instructions. The agent might hallucinate or ignore constraints. Policies enforce boundaries at the query execution layer — they cannot be bypassed by any SQL the agent generates.
- *Q: What about using views per tenant instead?*
  A: Views per tenant work but create the same DDL explosion problem. 10K tenants = 10K views per table. Multi-tenancy gives you one table, one policy, N tenants — with zero per-tenant DDL.
- *Q: Is there a user count where this approach stops making sense?*
  A: No practical upper limit on user count since it's just rows in a table. The pattern stops being necessary below ~50 users with stable roles, where traditional RBAC is simpler to reason about.

---

## Slide 3: Architecture Overview

**Talking Points:**
- Walk through the flow diagram step by step. Emphasize the separation of concerns at each stage.
- Your app handles authentication (step 1) — this is your IdP, OAuth, SAML, whatever you already use. Snowflake never sees user credentials.
- The agent:run API call (step 2) is where your app bridges authentication to authorization. You translate your user identity into Snowflake session attributes.
- Steps 3-6 are entirely within Snowflake. The session attributes are set, the agent generates SQL, policies filter, and only authorized data comes back.
- The "shared responsibility model" framing is important for customer conversations. It clarifies that Snowflake doesn't authenticate external users — your app does. Snowflake enforces data boundaries based on what your app tells it.

**Key Insight:**
The architecture creates a clean separation: your app owns identity/authentication, the agent:run API is the bridge, and Snowflake policies own authorization/enforcement. This means you can change your IdP, change your user model, or add new attributes without touching Snowflake policies. Conversely, you can change policies without touching your app — as long as the attribute names stay the same.

**Common Questions:**
- *Q: What happens if the app passes wrong variables?*
  A: The user sees wrong data — either too much or too little. This is why testing is critical (slide 10). Your app is the trusted source of identity. If it passes the wrong tenant_id, the policy will faithfully filter to the wrong tenant. Input validation happens in your app layer.
- *Q: Can the agent call tools that modify session attributes?*
  A: Not if you use `is_immutable_session_attribute: true`. Immutable attributes cannot be modified by any operation within the session — not by SQL, not by tool invocations, not by code execution. That's the whole point of immutability.
- *Q: Does the service account need special privileges?*
  A: The service account needs the standard permissions to run the agent (USAGE on the agent, SELECT on tables, etc.). The policies apply to the service account's session, but they evaluate based on the session attributes — not the service account's role.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-multi-tenancy
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-setup

---

## Slide 4: Session Attributes

**Talking Points:**
- This slide shows the exact API payload. Walk through the JSON structure — emphasize that `is_immutable_session_attribute: true` is the critical flag.
- Explain the three properties: immutable (can't be changed), session-scoped (persist for the interaction), and multiple (pass as many as you need).
- The warning box is the most important point on this slide. Without immutability, a sophisticated prompt injection could trick the agent into running `ALTER SESSION SET tenant_id = 'other_tenant'` — which would escalate access. Immutability prevents this entirely.
- "Session-scoped" means the attributes are set for the duration of that single agent:run call. The next call can have completely different attributes. There's no persistent state between calls.

**Key Insight:**
Immutability is the security primitive that makes this entire pattern trustworthy. Without it, you're relying on the agent not to modify its own context — which is a bet against prompt injection. With immutability, the platform guarantees that no operation within the session can change the attributes. This moves security from "the agent should behave correctly" to "the platform enforces correctness regardless of agent behavior."

**Common Questions:**
- *Q: What happens if I forget `is_immutable_session_attribute`?*
  A: The attribute is still set, but it's mutable. This means generated SQL could potentially run `ALTER SESSION SET` to change it. In practice, this is unlikely without prompt injection — but prompt injection is a real and growing threat. Always use immutable.
- *Q: Can I mix immutable and mutable variables?*
  A: Yes. You might pass tenant_id as immutable (security-critical) and a preference like `language` as mutable (the agent could change it based on user interaction). But any variable used in a security policy should always be immutable.
- *Q: Is there a limit on number of variables?*
  A: No hard documented limit. In practice, keep it to the minimum needed — typically 2-4 attributes (tenant_id, user_id, access_level, region). More attributes means more complexity in your policies.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/sys_context
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-multi-tenancy

---

## Slide 5: Row Access Policies

**Talking Points:**
- This is the core enforcement mechanism. Walk through both code blocks: the policy definition, then the application to a table.
- The `SYS_CONTEXT('SNOWFLAKE$SESSION_ATTRIBUTES', 'tenant_id')` call is what reads the immutable variable set during agent:run. It's evaluated at query time for every row.
- Emphasize "regardless of SQL shape" — if the agent generates a complex JOIN with CTEs and subqueries, the RAP still filters. If it does `SELECT *` with no WHERE, the RAP still filters. The policy is evaluated at the scan level.
- The compound policy example shows how to combine tenant-level AND user-level isolation — e.g., within a tenant, each user only sees their own records.

**Key Insight:**
Row access policies are the "always-on" security layer. Unlike WHERE clauses (which the agent might forget), unlike views (which might be bypassed), unlike role grants (which are static), RAPs evaluate dynamically on every single query against the protected table. They're the only mechanism that provides guaranteed row-level isolation regardless of how the query is constructed.

**Common Questions:**
- *Q: What's the performance impact?*
  A: Minimal for simple equality checks (like `col = SYS_CONTEXT(...)`). Snowflake can push these predicates into partition pruning, so they perform similarly to a WHERE clause. Complex policies with UDF calls may have more overhead — test with representative query patterns.
- *Q: Can I apply multiple RAPs to one table?*
  A: No — one RAP per table. If you need multiple filtering dimensions, combine them in a single policy (like the compound example shown).
- *Q: Do RAPs apply to INFORMATION_SCHEMA or SHOW commands?*
  A: RAPs apply to DML queries (SELECT, INSERT...SELECT, etc.). They don't apply to metadata commands like SHOW TABLES or INFORMATION_SCHEMA queries.

**References:**
- https://docs.snowflake.com/en/sql-reference/sql/create-row-access-policy
- https://docs.snowflake.com/en/sql-reference/functions/sys_context

---

## Slide 6: Column Masking

**Talking Points:**
- Two patterns side by side: simple (direct attribute check) and complex (UDF + entitlements lookup). Let the customer's complexity drive which they choose.
- The simple pattern works when access rules map to a fixed set of levels. "Admin sees SSN, everyone else sees masked" — clean, fast, no extra tables needed.
- The complex pattern works when different users in the same access level have different column visibility. The UDF checks an entitlements table to determine per-user, per-column access.
- Important: masking policies complement RAPs. RAPs filter rows (you don't see the record at all). Masking policies filter columns (you see the record but sensitive fields are masked). Use both together for defense in depth.

**Key Insight:**
Column masking addresses the "partial visibility" use case that RAPs can't solve alone. A support agent should see a customer's name and ticket details, but not their SSN or payment info. A manager should see team performance metrics but not individual salary data. Masking gives you this column-level granularity without creating separate views or tables per access level.

**Common Questions:**
- *Q: Can a masking policy reference SYS_CONTEXT directly?*
  A: Yes — as shown in the simple pattern. The masking policy body can call SYS_CONTEXT to read session attributes and make conditional decisions.
- *Q: What data types can be masked?*
  A: Any data type. The masking policy's return type must match the column's data type. You can mask VARCHAR (replace with asterisks), NUMBER (replace with 0 or NULL), TIMESTAMP (replace with epoch), VARIANT (replace with empty object), etc.
- *Q: Does the agent know the column is masked?*
  A: The agent sees the masked value in query results. It has no indication that masking was applied. If it asks "what is the user's SSN?" and gets '***-**-****', it will report that value. This is by design — the agent shouldn't know what it can't see.

**References:**
- https://docs.snowflake.com/en/user-guide/security-column-intro

---

## Slide 7: Entitlements Table Design

**Talking Points:**
- This is the operational heart of the system. Policies define the rules; the entitlements table defines who gets what. It's just a regular Snowflake table.
- Walk through the schema: external_user_id (maps to your app's user ID), tenant_id (organizational isolation), access_level (permission tier), allowed_regions and allowed_columns (fine-grained dimensions).
- The INSERT examples show the operational simplicity: adding a user is a single INSERT. Bulk onboarding is a COPY INTO. No CREATE USER, no GRANT, no DDL.
- This table becomes the source of truth for "who can see what." Audit it, version it, sync it from your IdP on a schedule.

**Key Insight:**
The entitlements table is what makes this pattern operationally scalable. It converts security administration from DDL operations (which require admin privileges and are hard to automate) to DML operations (which can be done by any application with INSERT privileges). Your IdP sync job, your admin UI, your onboarding automation — they all just write rows to this table.

**Common Questions:**
- *Q: How do I keep this in sync with my IdP?*
  A: Common patterns: (1) Scheduled task that runs a stored procedure to MERGE from a stage where your IdP exports, (2) Snowpipe Streaming from your IdP's webhook events, (3) A nightly COPY INTO from an S3 bucket where your IdP writes. Choose based on your latency requirements.
- *Q: What if the entitlements table is corrupted or truncated?*
  A: If using the UDF pattern, a missing entitlements row means the UDF returns FALSE, which means masking policies mask everything. This is a safe default — users see nothing rather than everything. For RAPs using direct SYS_CONTEXT comparison, corruption of the entitlements table doesn't affect the RAP (it doesn't reference the table directly).
- *Q: Should this table be in a separate schema/database?*
  A: Yes — best practice is to put entitlements in a separate schema with restricted access. The service account's role needs SELECT on this table, but the agent itself shouldn't be able to query or modify it. Use a secure UDF as the access layer.

---

## Slide 8: Scaling Simply

**Talking Points:**
- The comparison table is the "aha moment" for most customers. Walk through each row and let them feel the operational difference at scale.
- Key emphasis: the multi-tenancy column uses standard DML (INSERT, UPDATE, DELETE). The traditional column uses DDL (CREATE, GRANT, REVOKE, DROP). This distinction matters for automation, auditing, and speed.
- "Bulk onboard 1000 users" is often the clincher. COPY INTO from a CSV vs. 1000 individual DDL statements. One takes seconds; the other takes minutes and can hit rate limits.
- The right-hand cards acknowledge that traditional RBAC is sometimes better. This isn't a "never use roles" talk — it's a "use the right tool for the right scale."

**Key Insight:**
The operational model shift from DDL to DML is the key scaling enabler. DDL operations are privileged, serialized, logged differently, and harder to automate. DML operations are fast, parallelizable, auditable via standard queries, and trivial to automate. At 100 users, the difference is minor. At 10K users, it's the difference between a sustainable system and operational debt.

**Common Questions:**
- *Q: What about cost? Are we saving on Snowflake user licenses?*
  A: Snowflake doesn't charge per-user for the platform, but there's operational cost in managing user objects, role hierarchies, and grant maintenance. Multi-tenancy eliminates this operational overhead entirely. The service account is the only Snowflake user that needs to exist.
- *Q: Can I migrate from traditional RBAC to this pattern?*
  A: Yes. The typical migration: (1) Create the entitlements table, (2) Populate it based on current role-to-user mappings, (3) Create policies referencing session attributes, (4) Update your app to pass variables, (5) Remove per-user roles once validated. You can run both patterns simultaneously during migration.
- *Q: What about the entitlements table growing huge?*
  A: 10K rows is tiny for Snowflake. Even 1M rows (10K users x 100 entitlement dimensions) is negligible. The secure UDF approach can use micro-partitioning and caching effectively.

---

## Slide 9: The agent:run API Call

**Talking Points:**
- This slide connects the architecture to code. Walk through the full HTTP request, then show the Python application layer that constructs it.
- The HTTP example shows the raw API call — useful for customers testing with curl or Postman. The Python example shows the production pattern — looking up entitlements from your own store, then passing them to Snowflake.
- Emphasize the `service_token` — this is a single service account that serves all users. The token authenticates to Snowflake; the variables determine what data is visible.
- The context box makes the key architectural point: one connection, N users. The session attributes create logical isolation within a shared physical connection.

**Key Insight:**
The application layer is the trust boundary. It's responsible for: (1) authenticating the user via your IdP, (2) looking up their entitlements, (3) passing the correct variables to agent:run. If this layer is compromised, multi-tenancy breaks — because the attacker could pass any variables they want. Secure this code path like you'd secure any authentication-critical service.

**Common Questions:**
- *Q: Can I reuse connections/sessions across users?*
  A: Each agent:run call is stateless. You don't manage sessions — Snowflake handles it. Each call gets its own session with the variables you pass. No connection pooling concerns.
- *Q: What authentication does the service account use?*
  A: OAuth, key-pair authentication, or any standard Snowflake auth method. OAuth with client credentials is the most common pattern for service accounts in production.
- *Q: Is there latency overhead from setting session attributes?*
  A: Negligible. The attributes are set as part of the session initialization for the agent:run call. There's no extra round-trip — they're embedded in the request payload.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-setup

---

## Slide 10: Best Practices

**Talking Points:**
- Walk through each card as a hard-won lesson from production deployments. These aren't theoretical — they're patterns that prevent real security gaps.
- "Always use immutable attributes" — non-negotiable. This is the #1 mistake customers make when first implementing multi-tenancy.
- "Cortex Search filtering" — this is the most common surprise. RAPs apply to SQL execution; Cortex Search uses a vector index that bypasses the SQL engine entirely. If an agent uses both Cortex Search and SQL queries, the SQL queries are filtered but search results are not.
- "Policy on every table" — one unprotected table is a data leak. The agent might discover and query any table it has SELECT on. If even one table lacks a RAP, the agent could return data from it without filtering.
- The warning box emphasizes the Cortex Search limitation because it's the most frequently missed gap in multi-tenant agent deployments.

**Key Insight:**
The Cortex Search limitation is the single most important nuance for SEs to understand and communicate. Customers often assume that if they set up RAPs, all agent data access is filtered. But agents that use Cortex Search as a tool bypass RAPs for the search phase. The fix is either: (1) create separate Cortex Search services per tenant (each indexing only that tenant's data), or (2) pre-filter the source table before the search service indexes it. Neither is automatic — the customer must architect for it.

**Common Questions:**
- *Q: How do I test that policies are working correctly?*
  A: Use `ALTER SESSION SET SNOWFLAKE$SESSION_ATTRIBUTES = '{"tenant_id": "test_tenant"}'` and run queries manually. Verify you only see the expected rows. Then switch the attribute value and confirm isolation. Do this BEFORE deploying to the agent.
- *Q: What happens if I forget to apply a RAP to a new table?*
  A: The agent can query it without filtering. Use `SELECT * FROM TABLE(INFORMATION_SCHEMA.POLICY_REFERENCES(...))` to audit which tables have policies and which don't. Automate this check as part of your CI/CD for schema changes.
- *Q: Can I use this with streaming data (Snowpipe)?*
  A: Yes. RAPs apply regardless of how data arrives. New rows ingested via Snowpipe, streaming, or COPY INTO are immediately subject to the policy. No reprocessing needed.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-multi-tenancy
- https://docs.snowflake.com/en/sql-reference/sql/create-row-access-policy

---

## Slide 11: Audit & Observability

**Talking Points:**
- Multi-tenancy creates a unique audit challenge: all requests run under one service account. How do you attribute usage to specific external users? The answer is correlating request_ids between your app logs and Snowflake's usage views.
- Walk through both queries: the first shows raw Snowflake usage history; the second shows the JOIN pattern that links Snowflake data to your app's user identity.
- The two cards show what to log and where to look. Your app logs the request_id + user context; Snowflake logs the cost + query details. JOIN them for full attribution.
- This ties into the observability module — if they've seen that presentation, this is the multi-tenancy-specific extension of those patterns.

**Key Insight:**
Without explicit correlation logging, you lose per-user attribution in a multi-tenant setup. All queries run as the service account, so Snowflake's built-in USER_NAME attribution shows the same user for every request. The request_id bridge is the only way to answer "which external user drove this cost?" Log it in your app layer, or you'll never be able to attribute costs or audit access patterns per user.

**Common Questions:**
- *Q: Can I see which session attributes were used for each request?*
  A: Session attributes are not currently logged in CORTEX_AGENT_USAGE_HISTORY. You must log them in your application layer when you make the agent:run call. Store the request_id alongside the variables you passed.
- *Q: How do I detect if someone is abusing the system?*
  A: Monitor request volume per external_user_id in your app logs. Join with Snowflake usage to find users generating outsized token/credit costs. Set alerts for anomalous patterns (e.g., a user making 10x their normal request volume).
- *Q: Can I implement per-user cost limits?*
  A: Not natively in Snowflake (resource budgets are per-agent, not per-session-attribute). Implement rate limiting and cost caps in your application layer based on the accumulated usage you track via request_id correlation.

**References:**
- https://docs.snowflake.com/en/sql-reference/account-usage/cortex_agent_usage_history

---

## Slide 12: Key Takeaways

**Talking Points:**
- Walk through the 5-step flow: authenticate in your app, pass immutable variables, policies enforce filtering, agent generates SQL, filtered results returned. Each step builds on the previous.
- The Summary card captures the 5 key points customers must internalize. Emphasize the Cortex Search caveat — it catches people off guard.
- The Getting Started steps are the exact actions a customer should take in their first implementation sprint. They're ordered to build confidence progressively: create the data model, test manually, then connect to the agent.
- Close with the framing: multi-tenancy is not optional for external-facing agents. Without it, you have a data breach waiting to happen. With it, you have production-ready per-user isolation.

**Key Insight:**
The #1 takeaway: session attributes + policies give you per-user data isolation without per-user infrastructure. The second takeaway: immutability is non-negotiable — it's what makes this pattern resistant to prompt injection. The third takeaway: RAPs don't apply to Cortex Search — plan for this gap explicitly. These three points cover 90% of what SEs need to communicate to customers evaluating multi-tenancy.

**Common Questions:**
- *Q: What's the minimum viable implementation?*
  A: One session attribute (tenant_id), one RAP on each table, immutable flag set. That's three components and gives you tenant-level isolation. Add user_id and masking policies for finer-grained control in a second iteration.
- *Q: Can I demo this to a customer?*
  A: Yes. Set up a demo agent, create a simple RAP, and show two agent:run calls with different tenant_id values returning different data from the same query. The contrast is immediately compelling.
- *Q: What's the roadmap for Cortex Search + RAP integration?*
  A: This is a known limitation the product team is aware of. No public commitment on timeline. For now, the recommended patterns are per-tenant search services or pre-filtered source tables. Communicate this clearly to customers planning search-heavy multi-tenant agents.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-multi-tenancy
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-setup
- https://docs.snowflake.com/en/sql-reference/sql/create-row-access-policy
- https://docs.snowflake.com/en/user-guide/security-column-intro
- https://docs.snowflake.com/en/sql-reference/functions/sys_context
