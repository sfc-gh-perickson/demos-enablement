# Cortex Agent Cost Observability

Understand and manage the cost of Cortex Agent deployments: token consumption, per-user attribution, Cortex Analyst credits, and warehouse compute.

## What You'll Learn

1. Query per-request token and credit consumption from `CORTEX_AGENT_USAGE_HISTORY`
2. Break down costs by model, service type, and token category (input/output/cache)
3. Identify top consumers by user and agent
4. Measure Cortex Analyst credits from `CORTEX_ANALYST_USAGE_HISTORY`
5. Attribute warehouse compute via `QUERY_ATTRIBUTION_HISTORY`
6. Calculate total cost per request (tokens + AI functions + compute)
7. Set up tag-based resource budgets for governance

## Prerequisites

- ACCOUNTADMIN role (or a role with access to `SNOWFLAKE.ACCOUNT_USAGE`)
- Snowflake account with Cortex Agent traffic (or use the simulated fallback data)
- Python environment with `snowflake-snowpark-python` installed (for local execution)

## Quickstart

1. Run `lab/setup.sql` in Snowsight or via SnowSQL to create lab objects and simulated data
2. Open `lab/cortex-agent-cost-observability-lab.ipynb` in Snowsight Notebooks or locally in Jupyter
3. The notebook auto-detects live data vs simulated fallback

### Local Connection (snowflake.toml)

For local Jupyter execution, configure `~/.snowflake/connections.toml`:

```toml
[default]
account = "your_account"
user = "your_user"
authenticator = "externalbrowser"
role = "ACCOUNTADMIN"
warehouse = "AGENT_COST_LAB_WH"
database = "AGENT_COST_LAB"
schema = "PUBLIC"
```

## Structure

```
cortex-agent-cost-observability/
  README.md                     # This file
  lab/
    setup.sql                   # Database/warehouse setup + simulated data
    cortex-agent-cost-observability-lab.ipynb  # Lab notebook
  presentations/
    cortex-agent-cost-observability.html       # HTML presentation
```

## Key Documentation Links

| Topic | Link |
|-------|------|
| CORTEX_AGENT_USAGE_HISTORY | https://docs.snowflake.com/en/sql-reference/account-usage/cortex_agent_usage_history |
| CORTEX_ANALYST_USAGE_HISTORY | https://docs.snowflake.com/en/sql-reference/account-usage/cortex_analyst_usage_history |
| QUERY_ATTRIBUTION_HISTORY | https://docs.snowflake.com/en/sql-reference/account-usage/query_attribution_history |
| METERING_DAILY_HISTORY | https://docs.snowflake.com/en/sql-reference/account-usage/metering_daily_history |
| Resource Budgets for Cortex Agents | https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-resource-budgets |
| AI Billing FAQ | https://community.snowflake.com/s/article/how-to-track-and-understand-cortex-ai-related-charges |
