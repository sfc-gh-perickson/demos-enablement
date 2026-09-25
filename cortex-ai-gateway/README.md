# Cortex AI Gateway + LangChain Agent + MCP

[View Presentation](https://sfc-gh-perickson.github.io/demos-enablement/cortex-ai-gateway/cortex-ai-gateway-presentation.html)

An enablement module demonstrating Snowflake's Cortex AI Gateway as a centralized LLM inference layer, combined with a LangChain agent that queries Snowflake data through the Model Context Protocol (MCP). Includes a monitoring dashboard deployed as Streamlit-in-Snowflake for observability, cost management, topic mining, and agent improvement recommendations.

## Audience

SEs, Solution Architects, Platform Engineers, and customers evaluating centralized AI governance and observability.

## Topics Covered

- **AI Gateway fundamentals** — auto-provisioned per account, OpenAI-compatible API, model allowlists, logging and payload capture
- **Multi-model inference** — GPT-5.4, Claude Sonnet 4.6 (Anthropic API), and GPT-5.4 Mini routed through a single gateway
- **LangChain integration** — `ChatOpenAI` and `ChatAnthropic` pointed at the gateway inference endpoint with PAT authentication
- **MCP Server** — Snowflake-native MCP server exposing Cortex Analyst, Cortex Search, and SQL execution as tools (no Cortex Agent wrapper needed)
- **Agent tool chaining** — Cortex Analyst generates SQL, `execute_sql` runs it and returns data, Cortex Search provides RAG over documents
- **Multi-turn conversations** — follow-up questions within the same trace for richer interaction patterns
- **Observability** — `AGENT_TRACE_TABLE('SNOWFLAKE')` for per-request OpenTelemetry traces with full conversation chain reconstruction; `AI_GATEWAY_USAGE_HISTORY` for token/credit metering
- **Cost management** — shared resource budgets (team-level) and per-user quotas (individual hard blocks)
- **Monitoring dashboard** — Streamlit-in-Snowflake app with 4 tabs: Overview, Agent Explorer, Topic Mining, Conversation Inspector
- **Topic mining & recommendations** — LLM-powered classification of user questions + actionable suggestions for semantic view gaps, new skills, and workflow improvements
- **Feedback analytics** — positive/negative feedback tracking with per-agent drill-down
- **Latency analytics** — percentile distributions (P50/P90/P99), latency vs token scatter plots

## Contents

| File | Description |
|------|-------------|
| `setup.sql` | SQL setup script — database, tables, semantic view, Cortex Search service, MCP server, gateway spec |
| `cortex-ai-gateway-langchain-mcp.ipynb` | Hands-on notebook — gateway + LangChain + MCP end-to-end with observability and cost management |
| `cortex-ai-gateway-presentation.html` | 10-slide presentation covering architecture, benefits, and demo walkthrough |
| `monitoring/simulate.py` | Simulation script — 3 agents × 3 models × ~13 queries each (some multi-turn) with feedback |
| `monitoring/queries.py` | SQL query library for the local Streamlit app |
| `monitoring/app.py` | Local Streamlit app with 4 tabs |
| `monitoring_sis/streamlit_app.py` | Streamlit-in-Snowflake version (deployed to `CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_MONITOR`) |
| `monitoring_sis/queries.py` | SQL query library for the SiS app (uses Snowpark session) |
| `monitoring_sis/snowflake.yml` | SiS deployment manifest |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   LangChain Agents (ReAct)                   │
│                                                              │
│  CMO Assistant     → ChatOpenAI     → GPT-5.4               │
│  Finance Analyst   → ChatAnthropic  → Claude Sonnet 4.6     │
│  Strategy Advisor  → ChatOpenAI     → GPT-5.4 Mini          │
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
          GATEWAY_AGENT_TRACES           — trace → agent mapping
          GATEWAY_AGENT_FEEDBACK         — user feedback
                            │
                            ▼
          ┌─────────────────────────────────┐
          │  Streamlit-in-Snowflake App     │
          │  ├── Overview Dashboard         │
          │  ├── Agent Explorer             │
          │  ├── Topic Mining & Search      │
          │  └── Conversation Inspector     │
          └─────────────────────────────────┘
```

## Key URLs

The AI Gateway uses two distinct URL paths:

| Path | Purpose |
|------|---------|
| `/api/v2/aigateways/snowflake/v1/chat/completions` | Inference (OpenAI-compatible) |
| `/api/v2/aigateways/snowflake/v1/messages` | Inference (Anthropic-compatible) |
| `/api/v2/aigateways/SNOWFLAKE` | Admin (spec management, SHOW, ALTER) |
| `/api/v2/databases/<db>/schemas/<schema>/mcp-servers/<name>` | MCP (streamable HTTP) |

**Note:** Hostnames must use hyphens, not underscores, for valid SSL certificates (e.g., `perickson-aws1` not `perickson_aws1`).

## Hands-On Lab

### Prerequisites

- A Snowflake account with ACCOUNTADMIN (or CREATE DATABASE + CREATE WAREHOUSE privileges)
- A Personal Access Token (PAT) stored in `~/.snowflake/connections.toml`
- Python 3.11+ with `langchain-openai`, `langchain-anthropic`, `langchain-mcp-adapters`, `langgraph`, `snowflake-connector-python`
- Cross-region inference enabled (for model access)

### Steps

1. Run `setup.sql` in your Snowflake account to create all objects
2. Verify: `SHOW AI GATEWAYS` and `SHOW MCP SERVERS IN SCHEMA CORTEX_GATEWAY_LAB.PUBLIC`
3. Open `cortex-ai-gateway-langchain-mcp.ipynb` and run cells sequentially

### Populate the monitoring dashboard

4. Install dependencies: `pip install -r monitoring/requirements.txt`
5. Simulate multi-agent traffic: `python -m monitoring.simulate`
   - Sends ~39 queries across 3 agents (CMO Assistant on GPT-5.4, Finance Analyst on Claude Sonnet 4.6, Strategy Advisor on GPT-5.4 Mini)
   - Creates mapping tables (`GATEWAY_AGENTS`, `GATEWAY_AGENT_TRACES`, `GATEWAY_AGENT_FEEDBACK`)
   - Includes multi-turn conversations and contextual positive/negative feedback

### Deploy the Streamlit-in-Snowflake dashboard

6. Deploy: `cd monitoring_sis && snow streamlit deploy --replace`
7. Open in Snowsight: **Projects > Streamlit > GATEWAY_MONITOR** (or direct link from deploy output)

The SiS app uses warehouse runtime with `environment.yml` (plotly from Anaconda channel) — no EAI or compute pool needed.

To run locally instead: `streamlit run monitoring/app.py`

### What the notebook demonstrates

1. **Gateway inference** — `ChatOpenAI` pointed at `/api/v2/aigateways/snowflake/v1` with PAT auth
2. **MCP tool loading** — `MultiServerMCPClient` with streamable HTTP transport, no npx bridge
3. **Agent queries** — structured data (Analyst → execute_sql), unstructured search (Cortex Search), and hybrid questions using both
4. **Observability** — trace table queries showing per-span token counts, conversation chain reconstruction, and credit usage
5. **Cost management** — shared resource budgets and per-user quotas for gateway spend

### What the monitoring dashboard shows

1. **Overview** — KPIs, request volume by model, latency percentiles, tool usage across agents, feedback ratio
2. **Agent Explorer** — per-agent model usage, token trends, tool calls, top users, feedback detail, latency distribution, skill/workflow suggestions
3. **Topic Mining** — LLM-classified topics across all agents, thematic browsing, actionable recommendations for semantic view/search/agent improvements
4. **Conversation Inspector** — trace replay with paired tool call/response expanders, summary metrics

## Cleanup

```sql
DROP DATABASE IF EXISTS CORTEX_GATEWAY_LAB;
DROP WAREHOUSE IF EXISTS GATEWAY_LAB_WH;
-- The AI Gateway is account-level and shared; only reset if needed:
-- ALTER AI GATEWAY SNOWFLAKE FROM SPECIFICATION $$ models: [{name: '*'}] $$;
```
