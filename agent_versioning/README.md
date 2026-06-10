# Cortex Agent Versioning

[View Presentation](https://sfc-gh-perickson.github.io/demos-enablement/agent_versioning/presentations/cortex-agent-versioning.html)

An internal enablement module covering the full lifecycle of Cortex Agent versioning — from the core mental model through CI/CD integration, A/B testing, and rollback.

## Audience

Engineers, data scientists, and engineering managers who are building agents or planning to move agents to production.

## Topics Covered

- The problem: config drift, broken rollback, blind deployments
- The versioning model: Live, Named, and Alias
- Version lifecycle (create, iterate, commit, promote)
- Aliases and routing shortcuts
- Promotion pipelines (dev → UAT → prod)
- CI/CD integration with evaluation gates
- A/B testing patterns at the application layer
- Monitoring versioned agents
- Evaluation-driven promotion decisions
- Rollback (single-command revert via alias)

## Contents

| File | Description |
|------|-------------|
| `presentations/cortex-agent-versioning.html` | Slide deck (14 slides) |
| `presentations/cortex-agent-versioning-speaker-notes.md` | Speaker notes with internal context, common questions, and references |

## Key Concepts

- **Live version** — your active scratchpad; one per agent, freely mutable
- **Named version** — an immutable committed snapshot; your safety net
- **Alias** — a human-friendly pointer to a named version; how you route traffic without hardcoding version numbers

The core insight: applications target aliases, not versions. Promotion = moving a pointer. Rollback = pointing back.

## References

- [Cortex Agent Versioning Docs](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-versioning)
- [Cortex Agents Overview](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents)
