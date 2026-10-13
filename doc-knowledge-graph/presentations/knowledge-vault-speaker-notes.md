# Knowledge Vault — Speaker Notes

This presentation covers the Knowledge Vault pattern: a graph-structured knowledge base in Snowflake that turns curated markdown concept notes into a searchable knowledge graph served by a Cortex Agent. The demo uses a SaaS analytics domain (activation rates, CLV, retention, revenue recognition) but the architecture is domain-agnostic. Use this deck for enablement sessions, customer discovery calls where knowledge management or metric governance is a pain point, or as a Cortex Agent + Cortex Search technical deep-dive.

---

## Overview (Hero)

Open with the four stats: 13 concept notes, 9 entity types, 14 relationship types, 5 agent tools. The point here is that this is a small, focused knowledge base — not a massive enterprise deployment — yet it produces a surprisingly capable agent. Emphasize that the entire thing deploys in under 30 minutes and costs almost nothing to run.

**Key message:** "This is what happens when you treat institutional knowledge as data and give it the same engineering rigor you'd give a data pipeline."

---

## The Problem

This is the discovery slide — use it to get the audience nodding. Every data team has these problems. The three cards map to three real failure modes:

- **Ambiguous Terms:** The "CR" example is a crowd favorite. Every organization has at least one abbreviation that means different things to different teams. Ask the audience: "What's your 'CR'?"
- **Hidden Relationships:** The LTV → Retention → Revenue Recognition chain is a good example because it crosses team boundaries (Finance, Analytics, Customer Success). The relationships exist but aren't documented anywhere searchable.
- **No Source of Truth:** The "billed vs recognized revenue" question is deliberately provocative. If Finance and Analytics give different LTV numbers, who's right? Usually neither, because they're using different definitions without knowing it.

---

## How It Works

Walk through the flow diagram left to right. The key architectural insight is that every step is a dbt dynamic table — there's no orchestrator, no airflow DAG, no cron job. You add a note, and the graph updates.

**Highlight the ontology-guided extraction:** Without the ontology, the LLM would hallucinate random entity types. By embedding the 9 entity types and retrieving the top-5 most relevant per note, we constrain the extraction to a consistent vocabulary. This is a transferable pattern — any RAG system that needs structured extraction can use this approach.

---

## Pipeline Architecture

This is the technical deep-dive slide. Walk through each layer:

- **Staging** is where the AI happens — embedding, extraction, resolution
- **Ontology** is the control plane — change the seed CSVs to change what the LLM looks for
- **Graph** is the output — canonical nodes and edges ready for traversal

Point out that `stg_entities_extracted` uses `llama3.1-70b` via `CORTEX.COMPLETE`. This is a single LLM call per note, not per entity — the prompt asks for all entities and relationships in one shot, constrained by the top-5 ontology types retrieved via cosine similarity.

**References:**
- Cortex COMPLETE: https://docs.snowflake.com/en/sql-reference/functions/complete-snowflake-cortex
- EMBED_TEXT_1024: https://docs.snowflake.com/en/sql-reference/functions/embed_text_1024-snowflake-cortex
- Dynamic Tables: https://docs.snowflake.com/en/user-guide/dynamic-tables-about

---

## Ontology Design

The three-card layout: entity types, relationship types, and the "why" card. The "why" card is the most important — it explains the design decision.

**Talking point:** "The ontology is the human's steering wheel. The LLM does the heavy lifting, but the ontology constrains what it looks for. If you add a new entity type to the seed CSV, the next extraction cycle will start finding that type in existing notes. If you remove one, it stops."

The 9 entity types and 14 relationship types are sufficient for a metrics/analytics knowledge base. For other domains (security, compliance, engineering), you'd extend the ontology — not the pipeline code.

---

## The Knowledge Graph

Two sources of edges: LLM-extracted and explicit `see_also`. The dual-source design is intentional — LLM extraction catches implicit relationships the author didn't think to declare, while `see_also` ensures critical connections survive even if the LLM misses them.

**Graph traversal example:** Walk through the 2-hop traversal from Activation Rate. This is the "aha moment" for most audiences — the agent doesn't just return a definition, it maps the entire context an analyst needs.

---

## Cortex Agent

Five tools, two types: Cortex Search for full-text search, stored procedures for graph traversal.

**Key design decision:** The agent has explicit tool routing instructions. Definitional questions go to search, relationship questions go to graph traversal. Without this routing, the agent would always default to search and miss the graph entirely.

**References:**
- Cortex Agents: https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agent
- Cortex Search: https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview

---

## Org-Based Disambiguation

This is the demo highlight. Show both cards side by side — same question, different answers, both correct for their context.

**How to demo this:** Run the notebook cells for the Analytics team and Finance team back-to-back. The visual contrast is immediate and compelling. Then show the correction flow — the user says "actually I meant Credit Rating" and the agent switches without pushback.

**Internal context:** The disambiguation uses `applicable_orgs` in frontmatter as a soft preference, not a hard filter. If a note has no `applicable_orgs`, it's treated as universally applicable. This means the system degrades gracefully — you don't need to tag every note for disambiguation to work on the ones that are tagged.

---

## Live Demo

Three demo patterns, ordered from simple to complex:

1. **Concept Lookup** — fastest path to "wow". Ask a question, get a precise, sourced answer.
2. **Disambiguation** — the "this is different" moment. Same question, different context, different answer.
3. **Graph Traversal** — the deep value. The agent maps an entire metric's context: data sources, business rules, dimensions, related metrics.

**If time is short:** Skip pattern 1 (everyone understands search) and go straight to disambiguation + graph traversal.

---

## Deployment

Walk through the 8 steps. Emphasize that they're all idempotent — you can re-run any step without breaking anything.

**Cost callout:** This is deliberately cheap. 13 COMPLETE calls on initial build (one per note), X-Small warehouse with 60s auto-suspend, minimal Cortex Search indexing. The ongoing cost is effectively zero until you add or change notes. This makes it easy to justify as a proof-of-concept.

---

## Next Steps (Closing)

Four cards, four directions. Read the room:

- **Add Your Domain** — for customers who want to try it with their own data
- **Scale the Vault** — for customers who are already convinced and want to go big
- **Promote to Analyst** — for customers who already have Cortex Analyst and want to improve it
- **Embed in Applications** — for customers who want to build on top of it

**Key closing message:** "The vault is a pattern, not a product. The 13 SaaS notes are a demo — your metrics, your rules, your graph. The pipeline doesn't change."
