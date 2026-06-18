# Server-Side Agent Routing

[View Presentation](https://sfc-gh-perickson.github.io/demos-enablement/agent-routing/presentations/server-side-agent-routing.html)

An enablement module covering the server-side agent routing pattern — using a supervisor Cortex Agent to deterministically route requests to specialist agents via stored procedure wrappers. Eliminates cross-surface tool-selection variance by centralizing routing logic inside Snowflake.

## Audience

Solutions engineers, platform engineers, and technical leaders building multi-agent systems on Snowflake — particularly those exposing agents via MCP to external LLM-powered clients.

## Topics Covered

- The problem: cross-surface routing variance when multiple agents are exposed via MCP
- Root cause: client-side tool-selection is controlled by the client harness, not the server
- The solution: platform-side orchestration via a supervisor agent
- Architecture: specialist agents → stored procedure wrappers → supervisor agent
- Implementation: CREATE AGENT with `type: generic` tools pointing to procedures
- Evaluation: `tool_selection_accuracy` metric validates routing correctness
- Scaling: linear pattern for N specialists, hierarchical routing for large agent fleets
- Production considerations: latency, cost, evaluation cadence

## Contents

| File | Description |
|------|-------------|
| `presentations/server-side-agent-routing.html` | Slide deck (10 slides) |
| `presentations/server-side-agent-routing-speaker-notes.md` | Per-slide speaker notes with talking points, internal context, and references |
| `lab/setup.sql` | SQL setup script (database, agents, procedures, supervisor, eval data) |
| `lab/server-side-agent-routing-lab.ipynb` | Hands-on lab notebook (30 min) |

## Hands-On Lab

The lab walks participants through testing a supervisor agent that routes to three domain specialists, then running evaluations to measure routing accuracy.

### Prerequisites

- A Snowflake account with Cortex Agents enabled
- A role with CREATE DATABASE, CREATE WAREHOUSE, CREATE AGENT privileges
- Cross-region inference enabled (for agent orchestration models)
- SNOWFLAKE.CORTEX_USER database role granted to your role

### Setup

Run `lab/setup.sql` in your Snowflake account. This creates:

- `ROUTING_DEMO` database with `ROUTING` schema
- `ROUTING_DEMO_WH` warehouse (XS, auto-suspend 60s)
- 3 specialist agents: `SALES_ANALYST`, `PRODUCT_SUPPORT`, `SUPPLY_CHAIN`
- 3 stored procedure wrappers (RUN_SALES_AGENT, RUN_PRODUCT_AGENT, RUN_SUPPLY_CHAIN_AGENT)
- `SUPERVISOR` agent with tools pointing to the wrapper procedures
- `EVAL_DATA` table with 6 ground-truth evaluation rows
- Evaluation config on internal stage

### Lab Sections

1. Connect & verify setup (confirm agents and procedures exist)
2. Test routing (send domain-specific queries, verify correct specialist is invoked)
3. Test edge cases (ambiguous queries that require reasoning)
4. Run evaluation (EXECUTE_AI_EVALUATION with tool_selection_accuracy)
5. Inspect results (per-query scores, identify routing failures)
6. Iterate (adjust instructions, re-run evaluations)

## Key Concepts

- **Supervisor Agent** — A single Cortex Agent whose tools are stored procedures that invoke specialist agents. Clients make one call to the supervisor; routing happens server-side.
- **Stored Procedure Wrappers** — `EXECUTE AS OWNER` Python procedures that call `DATA_AGENT_RUN()` on a specialist agent. This enables agent-to-agent invocation within Snowflake.
- **Tool Selection Accuracy** — An evaluation metric that measures whether the supervisor called the correct tool (specialist) for a given query. Makes routing CI/CD-testable.
- **Zero Variance** — Whether a user calls from any LLM-powered client, routing is identical because it's executed server-side by one model (the supervisor's orchestrator).

## References

- [Cortex Agents](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents)
- [Create and Manage Agents](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-manage)
- [DATA_AGENT_RUN Function](https://docs.snowflake.com/en/sql-reference/functions/data_agent_run-snowflake-cortex)
- [Inter-App Agents (Agent-to-Agent)](https://docs.snowflake.com/en/developer-guide/native-apps/inter-app-agents)
- [Cortex Agent Evaluations](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations)
