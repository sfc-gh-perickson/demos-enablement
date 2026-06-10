# Speaker Notes: Versioning & A/B Testing Cortex Agents

## Account Context Summary

This presentation is an internal enablement session covering the full lifecycle of Cortex Agent versioning in Snowflake. It targets a mixed audience of engineers, data scientists, and engineering managers who are either building agents today or planning to. The goal is to establish a shared understanding of how to safely promote agents through environments (dev/uat/prod), implement A/B testing at the application layer, and leverage Snowflake's native monitoring and evaluation capabilities. This is not customer-facing — it's meant to upskill the team on best practices before agents reach production.

---

## Slide 1: Overview (Hero)

**Talking Points:**
- Frame the session: "We're going to cover how to take an agent from a prototype to a production-grade deployment with proper versioning, testing gates, and observability."
- The four stats on the hero slide summarize the value proposition: three version types give you flexibility, rollback is a single command, promotions require zero client changes, and monitoring is built-in.
- Set expectations: ~25 minutes, interactive, questions welcome throughout.

**Internal Context:**
- Agent versioning is GA as of early 2025. Some teams may still be using the "stateless" API pattern (passing config in every request). This deck should motivate them to move to the agent object model.
- If anyone asks about multi-agent orchestration (agent-to-agent), that's a separate topic — agent versioning applies to individual agent objects.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-versioning
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents

---

## Slide 2: The Problem

**Talking Points:**
- Walk through each card as a pain point they've likely experienced or will experience:
  - "Has anyone had an agent config change break something in production?"
  - "How do you roll back today? Manual edits? Hope you remember what it looked like?"
- Emphasize that these aren't hypothetical — they're the default state without versioning.
- The highlight box is the punchline: Cortex Agent versioning addresses all four problems natively.

**Internal Context:**
- The "blind in production" card is the strongest motivator for managers. Engineers care about rollback; managers care about monitoring.
- If someone asks "can't I just use Git for versioning?" — yes, and that's supported (slide 7), but aliases + immutable snapshots give you runtime routing that Git alone doesn't provide.

---

## Slide 3: Versioning Model

**Talking Points:**
- Three concepts to internalize: Live, Named, Alias.
- Live = your scratchpad. You iterate freely. Only one live version at a time.
- Named = the committed snapshot. Immutable. Can't change it. This is your safety net.
- Alias = a human-friendly pointer. This is how you route traffic without hardcoding version numbers.
- The key insight box is the most important takeaway: "Your app targets aliases, not versions. Promotion = moving a pointer."

**Internal Context:**
- Common question: "Can I have multiple live versions?" No. One per agent. If you need parallel development tracks, use separate agent objects or branches in Git.
- Aliases are case-sensitive when created with double-quoted identifiers. Best practice: use lowercase unquoted aliases (they'll be stored uppercase).

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-versioning

---

## Slide 4: Version Lifecycle

**Talking Points:**
- Walk through the flow diagram left to right.
- Emphasize that after commit, the live version is NOT auto-recreated. You must explicitly create one when you want to resume development. This is intentional — it prevents accidental edits.
- The two cards clarify what happens at creation vs. commit.
- Show the SQL: two commands to know — `ALTER AGENT ... COMMIT` and `ALTER AGENT ... ADD LIVE VERSION FROM LAST`.

**Internal Context:**
- "FROM LAST" is the most common pattern. You can also create a live version from a specific named version if you want to branch from an older state.
- If someone asks about version limits — there's no documented hard cap on named versions, but best practice is to drop old ones you'll never roll back to.

---

## Slide 5: Aliases & Shortcuts

**Talking Points:**
- Left column: show how aliases work in practice. Two commands — assign and reassign. The reassignment IS the promotion.
- Right column: built-in shortcuts are useful for CI/CD where you don't know the version number. `LAST` is the most commonly used.
- The API endpoint box shows that versions, aliases, and shortcuts are all accepted in the same URL path parameter.

**Internal Context:**
- DEFAULT version: if not explicitly set, it resolves to LAST. You can override this for safety (e.g., set DEFAULT to a known-good version so unversioned API calls don't automatically get the latest).
- Each alias must be unique within an agent. You can't have two versions with the same alias — assigning an alias that exists on another version will error (not silently reassign).

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-versioning
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-run

---

## Slide 6: Promotion Pipeline

**Talking Points:**
- This is the core workflow slide. Walk through the SQL top to bottom:
  1. Dev: assign `dev` alias to live version for testing
  2. UAT: commit, assign `uat` alias, run evaluations
  3. Prod: reassign `production` alias after UAT passes
- Emphasize "zero client changes" — the application always calls the `production` alias. You never touch application code to promote.

**Internal Context:**
- The UAT gate is where evaluations (slide 11) come in. You should have a passing evaluation suite before promoting to production.
- Some teams may want separate agents per environment (dev agent vs prod agent). That works too, but adds complexity. Single agent with aliases is simpler and maintains version lineage in one place.
- If someone asks about RBAC: the role that creates the agent owns it. Grant USAGE to other roles that need to query it. Grant MODIFY to roles that need to commit/promote.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-versioning

---

## Slide 7: CI/CD Integration

**Talking Points:**
- Two models: interactive (live version) and import (Git-connected stage).
- The Git model is more mature for teams: edit YAML in a repo, PR review, merge, CI imports the version.
- `ADD VERSION FROM @stage` bypasses the live version entirely. This is the preferred path for automated deployments.
- You can also `CREATE AGENT ... FROM @stage` for infrastructure-as-code first deploys.

**Internal Context:**
- The stage URI format is `snow://agent/<name>/versions/<version>/`. You can LIST and GET files from any version for auditing.
- Git integration requires a Git repository stage (`CREATE GIT REPOSITORY`). If the team isn't using Git stages yet, this is a good reason to set one up.
- The `LAST` shortcut in CI scripts avoids hardcoding version numbers: `ALTER AGENT my_agent MODIFY VERSION LAST SET ALIAS = production;`

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-versioning

---

## Slide 8: A/B Testing Approaches

**Talking Points:**
- Be upfront: Snowflake doesn't have native traffic splitting for agents. This is an application-layer concern.
- Three patterns, each with trade-offs:
  - **App-layer routing**: simplest, most common. You control the split percentage.
  - **Shadow testing**: safest. Users always get production. Candidate is logged for comparison.
  - **Cohort-based**: deterministic per user. Same user always sees same version. Better for measuring long-term effects.
- The warning box is important — don't let anyone think there's a Snowflake-native traffic split feature.

**Internal Context:**
- If someone asks "will Snowflake add native A/B testing?" — it's a reasonable feature request but not on any published roadmap as of this writing. The alias model makes app-layer routing straightforward.
- Shadow testing doubles your agent costs (two calls per request). Consider running it on a sample rather than 100% of traffic.
- For regulated environments, cohort-based is preferred because you can demonstrate which version served which user.

---

## Slide 9: A/B Testing Implementation

**Talking Points:**
- Walk through the code example:
  - Hash-based deterministic routing ensures the same user always gets the same version (no flicker)
  - Logging is critical — you need version + query + response + user_id to do meaningful analysis
- Emphasize: "The secret sauce isn't the routing — it's the logging. Without correlating version to outcomes, you can't make data-driven promotion decisions."

**Internal Context:**
- The code uses MD5 for simplicity. In production, any consistent hash works. Some teams use feature flag services (LaunchDarkly, etc.) to manage the split externally.
- Thread IDs help here too — if you're using threads with your agent, you can tag the thread with the version for later analysis.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-run
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-threads

---

## Slide 10: Monitoring

**Talking Points:**
- Four monitoring capabilities available out of the box — no setup required.
- Conversation history: full thread logs, accessible in Snowsight.
- Execution traces: spans for every step (planning, tool calls, response generation). This is where you debug "why did the agent choose the wrong tool?"
- User feedback: thumbs up/down + free text. Surface this in your monitoring dashboard.
- The storage location is `SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS`. Query it with SQL for custom dashboards.

**Internal Context:**
- The event table is append-only — you can't modify entries. Admins with `AI_OBSERVABILITY_ADMIN` can delete entries if needed (e.g., PII removal).
- Access requires `MONITOR` privilege on the agent object.
- Snowsight UI path: AI & ML > Agents > [select agent] > Monitoring tab.
- If someone asks about retention: check the docs — there may be account-level retention policies.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-monitor

---

## Slide 11: Evaluations

**Talking Points:**
- Two built-in metrics:
  - Answer correctness: requires a ground-truth dataset (question + expected answer pairs). Uses LLM judging.
  - Logical consistency: reference-free. No ground truth needed. Checks if the agent's planning, instructions, and tool calls are internally consistent.
- Custom metrics: define your own LLM-judged criteria. Great for brand/tone, domain-specific accuracy, citation quality.
- Evaluations trace the full pipeline — you can see where in the agent's reasoning quality drops off.

**Internal Context:**
- The evaluation system uses an LLM judge. There's a Snowflake engineering blog post ("What's Your Agent's GPA?") that explains the methodology.
- Building a ground-truth dataset is the hard part. Start small — 50-100 representative queries with expected answers. Grow over time.
- Custom metrics are powerful for domain-specific quality (e.g., "Does the response cite the correct policy document?" for a legal agent).
- Run evaluations as part of your CI/CD gate: commit → run eval against `uat` alias → promote only if scores exceed threshold.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations

---

## Slide 12: Rollback

**Talking Points:**
- One command. That's it. `ALTER AGENT ... MODIFY VERSION VERSION$3 SET ALIAS = production;`
- Immediate effect — all traffic routes to the previous version.
- Why it works: named versions are immutable. VERSION$3 is exactly what it was when you committed it. No drift.
- Best practice: keep 2-3 previous versions around. Only drop versions you're certain about.

**Internal Context:**
- You can only drop named versions (not the live version). Dropping a version that has an alias assigned will error — remove the alias first.
- If you need to inspect what's in a version before rolling back: `LIST snow://agent/my_agent/versions/VERSION$3/;` and `GET` individual files.
- Rollback time is essentially instant — it's a metadata operation, not a redeployment.

---

## Slide 13: SQL Reference

**Talking Points:**
- This is the "cheat sheet" slide. Reference it when you need a quick reminder.
- Call out the most commonly used commands: COMMIT, ADD LIVE VERSION FROM LAST, MODIFY VERSION ... SET ALIAS.
- The `LIST snow://` command is underrated — great for auditing what's actually in a version.

**Internal Context:**
- `SHOW VERSIONS IN AGENT` is your first debug command when something looks wrong. It shows all versions, their aliases, comments, and creation timestamps.
- The `snow://agent/` URI scheme only works for read operations (LIST, GET). You can't write to it.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-versioning

---

## Slide 14: Next Steps (Closing)

**Talking Points:**
- Four concrete action items for the team:
  1. Set up aliases on existing agents — this is the lowest-effort, highest-value first step.
  2. Build an evaluation suite — start with 50 Q&A pairs, add custom metrics for your domain.
  3. Implement A/B routing — even a simple 90/10 split with logging is valuable.
  4. Monitor and iterate — query the observability table, set up feedback collection.
- Close with the key mental model: "Aliases are your environment abstraction."

**Internal Context:**
- If the team is just starting with agents, prioritize steps 1 and 4 (aliases + monitoring). Evaluation suites and A/B testing can come once they have a baseline.
- Offer to help teams set up their first evaluation dataset — it's often the biggest blocker to adoption.
- Follow-up sessions to consider: "Building evaluation datasets for agents" and "Custom tools deep dive."

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-versioning
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-monitor
