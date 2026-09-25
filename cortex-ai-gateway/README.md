# Cortex AI Gateway + LangChain Agent + MCP

[View Presentation](https://sfc-gh-perickson.github.io/demos-enablement/cortex-ai-gateway/cortex-ai-gateway-presentation.html)

An enablement module demonstrating Snowflake's Cortex AI Gateway as a centralized LLM inference layer, combined with a LangChain agent that queries Snowflake data through the Model Context Protocol (MCP).

## Audience

SEs, Solution Architects, Platform Engineers, and customers evaluating centralized AI governance and observability.

## Topics Covered

- **AI Gateway fundamentals** — auto-provisioned per account, OpenAI-compatible API, model allowlists, logging and payload capture
- **LangChain integration** — `ChatOpenAI` pointed at the gateway inference endpoint with PAT authentication
- **MCP Server** — Snowflake-native MCP server exposing Cortex Analyst, Cortex Search, and SQL execution as tools (no Cortex Agent wrapper needed)
- **Agent tool chaining** — Cortex Analyst generates SQL, `execute_sql` runs it and returns data, Cortex Search provides RAG over documents
- **Observability** — `AGENT_TRACE_TABLE('SNOWFLAKE')` for per-request OpenTelemetry traces with full conversation chain reconstruction; `AI_GATEWAY_USAGE_HISTORY` for token/credit metering
- **Admin controls** — model restriction (`'*'` vs `'claude-*'`), role grants (USAGE vs MONITOR), usage quotas with block enforcement

## Contents

| File | Description |
|------|-------------|
| `setup.sql` | SQL setup script — database, tables, semantic view, Cortex Search service, MCP server, grants, gateway spec |
| `cortex-ai-gateway-langchain-mcp.ipynb` | Hands-on notebook — gateway + LangChain + MCP end-to-end with observability queries |
| `cortex-ai-gateway-presentation.html` | 10-slide presentation covering architecture, benefits, and demo walkthrough |
| `gateway-analyzer/` | Streamlit app — Cortex AI Gateway trace analysis: traffic, per-model latency, trace grouping, and rule-based recommendations ([README](gateway-analyzer/README.md)) |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   LangChain Agent (ReAct)                    │
│                                                              │
│  LLM: ChatOpenAI → AI Gateway → GPT-5.4 (Snowflake-hosted) │
│                                                              │
│  Tools: MCP Client → Snowflake MCP Server (MARKETING_MCP)   │
│         ├── query_campaigns  (Cortex Analyst → SQL)          │
│         ├── execute_sql      (runs the SQL, returns rows)    │
│         └── search_strategy_docs (Cortex Search → RAG)       │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
          AGENT_TRACE_TABLE('SNOWFLAKE')  — per-request traces
          AI_GATEWAY_USAGE_HISTORY       — token/credit metering
```

## Key URLs

The AI Gateway uses two distinct URL paths:

| Path | Purpose |
|------|---------|
| `/api/v2/aigateways/snowflake/v1/chat/completions` | Inference (OpenAI-compatible) |
| `/api/v2/aigateways/snowflake/v1/messages` | Inference (Anthropic-compatible) |
| `/api/v2/aigateways/SNOWFLAKE` | Admin (spec management, SHOW, ALTER) |
| `/api/v2/databases/<db>/schemas/<schema>/mcp-servers/<name>` | MCP (streamable HTTP) |

**Note:** Hostnames must use hyphens, not underscores, for valid SSL certificates (e.g., `perickson-aws1` not `perickson_aws1`). This applies to the `base_url` reported by `SHOW AI GATEWAYS` too — it echoes the account name verbatim, so the value it hands you may need the transform before it will pass TLS verification.

**Do not use `/api/v2/cortex/v1/*` for inference.** That is the separate Cortex Inference REST API. It answers successfully, so pointing `base_url` there fails *silently* rather than erroring — but the calls bypass the gateway completely: nothing lands in `AI_GATEWAY_USAGE_HISTORY`, nothing appears in gateway traces, and the model allowlist, budgets, and quotas do not apply. Read the authoritative inference base off `SHOW AI GATEWAYS` rather than hardcoding a path.

## Hands-On Lab

### Prerequisites

- A Snowflake account with ACCOUNTADMIN (or CREATE DATABASE + CREATE WAREHOUSE privileges)
- A Personal Access Token (PAT) stored in `~/.snowflake/connections.toml` as the `password` key, or exported as `SNOWFLAKE_PAT`. The gateway and MCP endpoints are REST APIs, so an SSO / `externalbrowser` connection is not sufficient on its own.
- If you create the PAT with `ROLE_RESTRICTION`, run **section 8 of `setup.sql`** to grant that role access to the lab objects. Without it the MCP server returns `does not exist or not authorized` even though `SHOW MCP SERVERS` lists it.
- Python 3.11+ with `langchain-openai`, `langchain-mcp-adapters`, `langgraph`, `snowflake-connector-python`
- Cross-region inference enabled (`ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION'`). Model availability through the gateway varies by region **and over time** even with this on: a `503` means the gateway could not serve that model at that moment, which is frequently transient capacity rather than a misconfiguration. Confirm with a test request before building a demo around a specific model. Set `GATEWAY_MODEL` to override the default (`openai-gpt-5.4`).

### Steps

1. Run `setup.sql` in your Snowflake account to create all objects. Note that section 9 runs `ALTER AI GATEWAY`, which **replaces the account-level gateway spec** — run `SHOW AI GATEWAYS` and save the existing `specification` first if the account is shared. The default spec also enables `capture_payload.request_response`, which records full prompt and completion text for every caller on the account.
2. Verify: `SHOW AI GATEWAYS` and `SHOW MCP SERVERS IN SCHEMA CORTEX_GATEWAY_LAB.PUBLIC`
3. Open `cortex-ai-gateway-langchain-mcp.ipynb` and run cells sequentially
4. The notebook connects to the gateway, loads MCP tools, runs agent queries, and queries observability data

### What the notebook demonstrates

1. **Gateway inference** — `ChatOpenAI` pointed at `/api/v2/aigateways/snowflake/v1` with PAT auth
2. **MCP tool loading** — `MultiServerMCPClient` with streamable HTTP transport, no npx bridge
3. **Agent queries** — structured data (Analyst → execute_sql), unstructured search (Cortex Search), and hybrid questions using both
4. **Observability** — trace table queries showing per-span token counts, conversation chain reconstruction from `gen_ai.input.messages`/`gen_ai.output.messages`, and credit usage from `AI_GATEWAY_USAGE_HISTORY`

### Optional: Gateway Analyzer app

[`gateway-analyzer/`](gateway-analyzer/) is a Streamlit app over the same trace
data — traffic and error volume, per-model p50/p95 latency and throughput, trace
grouping, and rule-based recommendations. Useful as a visual close to the demo
after the notebook's SQL, or pointed at a customer account carrying real gateway
traffic.

It reads `AGENT_TRACE_TABLE('SNOWFLAKE')`, the same gateway object section 9
configures, and needs only `MONITOR ON AI GATEWAY` — not ACCOUNTADMIN. Run it
locally with `python3 -m streamlit run streamlit_app.py` or deploy it with
`snow streamlit deploy`. Note that this lab produces traces from a single user,
so the caller-oriented views come alive only against multi-service traffic; see
the app's [README](gateway-analyzer/README.md).

## Cleanup

The budget, quota, user tag, and gateway spec are **account-level** and survive a
`DROP DATABASE`. Section 9 of the notebook does this for you; the SQL equivalent is:

```sql
-- Release the quota first so nobody stays blocked
CALL CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_QUOTA!SET_BLOCK_ENFORCEMENT_ENABLED(FALSE);
DROP SNOWFLAKE.CORE.QUOTA  IF EXISTS CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_QUOTA;
DROP SNOWFLAKE.CORE.BUDGET IF EXISTS CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_BUDGET;

ALTER USER IDENTIFIER(CURRENT_USER()) UNSET TAG CORTEX_GATEWAY_LAB.PUBLIC.COST_CENTER;
DROP TAG IF EXISTS CORTEX_GATEWAY_LAB.PUBLIC.COST_CENTER;

DROP DATABASE  IF EXISTS CORTEX_GATEWAY_LAB;
DROP WAREHOUSE IF EXISTS GATEWAY_LAB_WH;

-- The AI Gateway is account-level and shared, so it is never dropped. Restore the
-- spec you captured before running setup.sql. At minimum, turn payload capture off:
-- ALTER AI GATEWAY SNOWFLAKE FROM SPECIFICATION $$
-- models:
--   - name: '*'
-- logging:
--   enabled: true
--   capture_payload:
--     request_response: false
-- $$;
```
