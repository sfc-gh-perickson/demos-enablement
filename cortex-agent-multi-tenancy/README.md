# Cortex Agent Multi-Tenancy: RBAC for External Users

[View Presentation](https://sfc-gh-perickson.github.io/demos-enablement/cortex-agent-multi-tenancy/presentations/cortex-agent-multi-tenancy.html)

An enablement module covering how to implement row-level and column-level access control for thousands of external users (without Snowflake accounts) through a single Cortex Agent using session attributes, row access policies, and masking policies.

## Audience

SEs, solution architects, and developers building multi-tenant agentic applications on Snowflake where end users don't have direct Snowflake accounts.

## Topics Covered

**Concepts:**
- The multi-tenancy problem: external users, no role explosion, agent-generated SQL
- Architecture: app layer → agent:run API → session attributes → policies → filtered results
- Immutable session attributes and the `is_immutable_session_attribute` guarantee

**Implementation:**
- Row access policies with `SYS_CONTEXT('SNOWFLAKE$SESSION_ATTRIBUTES', 'key')`
- Column masking policies (direct attribute check and secure UDF patterns)
- Entitlements table design as the RBAC control plane
- The `agent:run` API call with variables block

**Operations:**
- Scaling: add/change/remove users with INSERT/UPDATE/DELETE — no DDL
- Best practices (immutable attributes, narrow scoping, policy testing, Cortex Search limitations)
- Audit and observability via CORTEX_AGENT_USAGE_HISTORY

## Contents

| File | Description |
|------|-------------|
| `presentations/cortex-agent-multi-tenancy.html` | Slide deck (12 slides) |
| `presentations/cortex-agent-multi-tenancy-speaker-notes.md` | Per-slide speaker notes with talking points, Q&A, and references |
| `lab/setup.sql` | SQL setup script (database, tables, policies, semantic view, agent) |
| `lab/cortex-agent-multi-tenancy-lab.ipynb` | Hands-on lab notebook (30-45 min) |

## Hands-On Lab

The lab walks participants through building a multi-tenant sales analytics agent that serves 4 different companies, with per-tenant row filtering and per-user column masking — all controlled by a simple entitlements table.

### Prerequisites

- A Snowflake account with Cortex AI features enabled
- A role with CREATE DATABASE, CREATE WAREHOUSE, CREATE ROW ACCESS POLICY privileges
- `SNOWFLAKE.CORTEX_USER` database role granted to your role
- Cross-region inference enabled (for agent LLM calls)

### Setup

Run `lab/setup.sql` in your Snowflake account. This creates:

- `MULTI_TENANCY_LAB` database
- `MULTI_TENANCY_WH` warehouse (XS, auto-suspend 60s)
- `SALES_DATA` table — 120 rows across 4 tenants with PII columns
- `USER_ENTITLEMENTS` table — 20 users with varying access levels (full/summary/restricted)
- Row access policy `RAP_TENANT_FILTER` — filters by tenant_id session attribute
- Masking policies `MASK_CUSTOMER_EMAIL` and `MASK_CUSTOMER_NAME` — mask based on access_level
- Secure UDF `GET_USER_ACCESS_LEVEL()` — entitlements lookup
- Semantic view over sales data
- Cortex Agent `TENANT_SALES_AGENT`

### Lab Sections

1. Setup & verify environment
2. Explore the data and entitlements table
3. Understand the policies (RAP + masking)
4. Test row access policy manually with session attributes
5. Test column masking manually
6. Call the agent with tenant context — observe row filtering
7. Column masking through the agent — observe field masking
8. Add a new user (just INSERT!) — demonstrate zero-DDL scaling
9. Audit trail — query usage history
10. Summary and next steps

## Key Concepts

- **No Snowflake accounts needed**: One service account calls the API; user identity is passed as a session attribute
- **Immutable session attributes**: `is_immutable_session_attribute: true` prevents the agent from bypassing policies
- **RAPs apply to Cortex Analyst** (SQL generation) but NOT to Cortex Search (use pre-filtered search services per tenant)
- **Entitlements table = RBAC control plane**: Add/change/remove users with DML, not DDL

## References

- [Multi-tenancy for Cortex Agents](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-multi-tenancy)
- [Agent Access Control & Authentication](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-setup)
- [CREATE ROW ACCESS POLICY](https://docs.snowflake.com/en/sql-reference/sql/create-row-access-policy)
- [Column-level Security (Masking Policies)](https://docs.snowflake.com/en/user-guide/security-column-intro)
- [SYS_CONTEXT Function](https://docs.snowflake.com/en/sql-reference/functions/sys_context)
