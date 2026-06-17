# Cortex AI Observability: Surface Identification & Cost Attribution

[View Presentation](https://sfc-gh-perickson.github.io/demos-enablement/cortex-ai-observability/presentations/cortex-ai-observability.html)

An enablement module covering how to identify which surfaces are driving Cortex AI usage (MCP, REST API, CoWork, Agent API, Cortex Code) and how to attribute costs to the right teams using Snowflake's built-in observability views.

## Audience

AI platform administrators, SEs, data engineers, and finance/governance teams responsible for managing Cortex AI adoption and spend.

## Topics Covered

**Surface Identification:**
- Architecture of Cortex AI surfaces (MCP, REST API, CoWork, Agent Admin UI, SQL functions)
- Using `CORTEX_AGENT_USAGE_HISTORY` and `interaction_interface` for surface routing
- Distinguishing CoWork traffic from direct Agent API calls
- MCP client identification patterns and current limitations

**Cost Attribution:**
- Token-level granularity via `TOKENS_GRANULAR` and `CREDITS_GRANULAR` columns
- Tag-based cost center grouping (USER_TAGS, AGENT_TAGS)
- Building unified cost views across all surfaces
- Resource budgets and threshold-based governance
- Query-level compute attribution via `QUERY_ATTRIBUTION_HISTORY`

## Contents

| File | Description |
|------|-------------|
| `presentations/cortex-ai-observability.html` | Slide deck (12 slides) |
| `presentations/cortex-ai-observability-speaker-notes.md` | Per-slide speaker notes with talking points, internal context, and references |
| `lab/setup.sql` | SQL setup script (database, warehouse, unified view, simulated fallback data) |
| `lab/cortex-ai-observability-lab.ipynb` | Hands-on lab notebook (30-45 min) |

## Hands-On Lab

The lab walks participants through querying real `SNOWFLAKE.ACCOUNT_USAGE` views to identify adoption patterns across Cortex AI surfaces and attribute costs by user, agent, model, and cost center.

### Prerequisites

- A Snowflake account with Cortex AI features enabled
- **RBAC requirements:**
  - `IMPORTED PRIVILEGES` on the SNOWFLAKE database (for ACCOUNT_USAGE views)
  - ACCOUNTADMIN or a custom role with SELECT on SNOWFLAKE.ACCOUNT_USAGE schema
  - `SNOWFLAKE.CORTEX_USER` database role (for Cortex functions)
- If ACCOUNT_USAGE access is unavailable, the setup script generates simulated fallback data

### Setup

Run `lab/setup.sql` in your Snowflake account. This creates:

- `OBSERVABILITY_LAB` database
- `OBSERVABILITY_LAB_WH` warehouse (XS, auto-suspend 60s)
- `V_UNIFIED_AI_USAGE` view — normalized UNION ALL across agent, intelligence, and code CLI usage views
- `SIMULATED_AI_USAGE` fallback table — ~120 rows of synthetic data for participants without ACCOUNT_USAGE access

### Lab Sections

1. Setup & verify RBAC access to ACCOUNT_USAGE views
2. Explore the usage views — column structures and key fields
3. Surface identification — group by `interaction_interface`, identify MCP traffic
4. Distinguish CoWork vs direct Agent API calls
5. Cost attribution by model — parse TOKENS_GRANULAR with LATERAL FLATTEN
6. Cost attribution by user & agent — top consumers, time-series trends
7. Tag-based cost center grouping — flatten USER_TAGS/AGENT_TAGS arrays
8. Build unified dashboard view — all surfaces in one query
9. Query-level attribution — warehouse compute costs via QUERY_TAG
10. Summary and next steps

## References

- [AI Cost Management and Governance](https://docs.snowflake.com/en/user-guide/snowflake-cortex/governance-and-availability/ai-cost-management-and-governance)
- [CORTEX_AGENT_USAGE_HISTORY](https://docs.snowflake.com/en/sql-reference/account-usage/cortex_agent_usage_history)
- [SNOWFLAKE_INTELLIGENCE_USAGE_HISTORY](https://docs.snowflake.com/en/sql-reference/account-usage/snowflake_intelligence_usage_history_view)
- [CORTEX_REST_API_USAGE_HISTORY](https://docs.snowflake.com/en/sql-reference/account-usage/cortex_rest_api_usage_history)
- [QUERY_ATTRIBUTION_HISTORY](https://docs.snowflake.com/en/sql-reference/organization-usage/query_attribution_history)
- [Cortex Analyst Admin Monitoring](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst/admin-observability)
