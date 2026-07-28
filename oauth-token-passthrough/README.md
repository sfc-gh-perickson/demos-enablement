# OAuth Token Passthrough for Cortex Agents

[View Presentation](https://sfc-gh-perickson.github.io/demos-enablement/oauth-token-passthrough/presentations/oauth-token-passthrough.html)

An enablement module covering how to pass an Entra ID OAuth token from an external application (e.g., Microsoft Teams via AWS AgentCore) through to a Snowflake Cortex Agent, enabling per-user RBAC without provisioning individual Snowflake accounts.

## Audience

SEs, solution architects, and developers building agentic applications where user identity originates from an external identity provider (Entra ID) and must be honored at the Snowflake data layer.

## Architecture

```
┌──────────────┐     ┌─────────────────┐     ┌─────────────────────────────────┐
│  End User    │     │  AWS AgentCore   │     │         Snowflake               │
│  (MS Teams)  │     │  (Orchestrator)  │     │                                 │
│              │     │                  │     │  ┌─────────────────────────┐    │
│  1. Login    │────▶│  2. Receives     │────▶│  │  External OAuth         │    │
│     (Entra)  │     │     user token   │     │  │  Security Integration   │    │
│              │     │                  │     │  │                         │    │
│              │     │  3. Relays token  │     │  │  • Validates JWT        │    │
│              │     │     as Bearer    │     │  │  • Maps to SF user      │    │
│              │     │     header       │     │  │  • Establishes session   │    │
│              │     │                  │     │  └────────────┬────────────┘    │
│              │     │                  │     │               │                 │
│              │     │                  │     │  ┌────────────▼────────────┐    │
│              │     │                  │     │  │  Cortex Agent           │    │
│              │     │                  │     │  │  (runs as mapped user)  │    │
│              │◀────│◀─────────────────│◀────│  │                         │    │
│  6. Response │     │  5. Returns      │     │  │  4. Queries data with   │    │
│              │     │     answer       │     │  │     user's privileges   │    │
│              │     │                  │     │  └─────────────────────────┘    │
└──────────────┘     └─────────────────┘     └─────────────────────────────────┘
```

## Topics Covered

**Concepts:**
- The token passthrough pattern: external IdP → orchestrator → Snowflake, no shared service account
- External OAuth security integrations: how Snowflake validates third-party JWTs
- User mapping: linking Entra ID identities to Snowflake users via `login_name`

**Implementation:**
- Configuring an External OAuth security integration for Entra ID
- Obtaining test tokens with MSAL device code flow (no client secret required)
- Calling the Cortex Agent REST API (`agent:run`) with a Bearer token
- Handling error cases: wrong audience, expired token, unmapped user

**Integration Patterns:**
- AWS AgentCore relay pattern (Python tool implementation)
- Combining token passthrough with session attributes for multi-tenancy
- Audit trail verification via `CORTEX_AGENT_USAGE_HISTORY`

## Contents

| File | Description |
|------|-------------|
| `presentations/oauth-token-passthrough.html` | Slide deck (~10 slides) |
| `presentations/oauth-token-passthrough-speaker-notes.md` | Per-slide speaker notes with talking points and references |
| `lab/setup.sql` | SQL setup script (security integration, database, semantic view, agent) |
| `lab/oauth-token-passthrough-lab.ipynb` | Hands-on lab notebook (45-60 min) |

## Hands-On Lab

The lab walks participants through configuring External OAuth and proving that a Cortex Agent respects the calling user's identity and privileges when an OAuth token is passed directly.

### Prerequisites

- A Snowflake account with Cortex AI features enabled
- A role with `CREATE DATABASE`, `CREATE SECURITY INTEGRATION`, and `CREATE USER` privileges (typically ACCOUNTADMIN for security integration setup)
- `SNOWFLAKE.CORTEX_USER` database role granted to your role
- Cross-region inference enabled (for agent LLM calls)
- An Azure Entra ID tenant with at least one user (free tier is sufficient)
- An Entra ID app registration configured as a Snowflake resource (audience)
- Python 3.8+ with `msal` and `requests` packages installed

### Setup

Run `lab/setup.sql` in your Snowflake account. This creates:

- `OAUTH_PASSTHROUGH_LAB` database
- External OAuth security integration `OAUTH_ENTRA_ID_PASSTHROUGH` (parameterized with your tenant ID)
- A demo table with sample data
- Semantic view over the demo table
- Cortex Agent `SUPPORT_ANALYTICS_AGENT`
- A Snowflake user mapped to your Entra ID email

### Lab Sections

1. Environment setup and prerequisite verification
2. Auth flow walkthrough (Teams → AgentCore → Cortex Agent)
3. Configure the External OAuth security integration
4. Obtain a test token from Entra ID (MSAL device code flow)
5. Call the Cortex Agent REST API with Bearer token
6. Demonstrate failure cases (wrong audience, expired token, unmapped user)
7. AgentCore relay pattern (Python tool implementation)
8. Combine with multi-tenancy session attributes
9. Audit trail — verify user identity in CORTEX_AGENT_USAGE_HISTORY

## Key Concepts

- **No shared service account**: Each API call carries the end user's own token — the agent runs with that user's privileges
- **External OAuth security integration**: Snowflake validates the JWT signature, issuer, audience, and expiry without contacting the IdP at runtime
- **User mapping**: Entra ID `upn` or `email` claim maps to a Snowflake user's `login_name` — the bridge between identities
- **Complementary to multi-tenancy**: Token passthrough handles *authentication*; the multi-tenancy module handles *authorization* via session attributes and policies

## References

- [External OAuth Overview](https://docs.snowflake.com/en/user-guide/oauth-ext-overview)
- [Create External OAuth for Microsoft Entra ID](https://docs.snowflake.com/en/user-guide/oauth-ext-microsoft-entra-id)
- [Cortex Agent Authentication & Access Control](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-setup)
- [Multi-tenancy for Cortex Agents](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-multi-tenancy)
- [MSAL Python Device Code Flow](https://learn.microsoft.com/en-us/entra/msal/python/getting-started/acquiring-tokens#device-code-flow)
- [Cortex Agent Multi-Tenancy Enablement Module](../cortex-agent-multi-tenancy/)
