# Document Knowledge Graph

A graph-structured knowledge base in Snowflake that turns curated concept notes into a searchable knowledge graph, powered by Cortex AI and served via a Cortex Agent.

## Prerequisites

- Snowflake account with Cortex AI functions enabled (COMPLETE, EMBED_TEXT_1024, Cortex Search)
- `ACCOUNTADMIN` role (or equivalent with CREATE DATABASE/WAREHOUSE privileges)
- dbt-core >= 1.6 with dbt-snowflake adapter (dynamic table support)
- `snow` CLI (Snowflake CLI) for running SQL scripts

## Environment Setup

Set these environment variables for the dbt profile:

```bash
export SNOWFLAKE_ACCOUNT=your_account_identifier
export SNOWFLAKE_USER=your_username
export SNOWFLAKE_TOKEN=your_programmatic_access_token
```

The profile uses `programmatic_access_token` authentication by default. Edit `profiles.yml` to switch to `externalbrowser` or key-pair auth if needed.

## Deployment (First Time)

Run these steps in order. Each step depends on the previous one completing.

### 1. Create Snowflake infrastructure

```bash
snow sql -f scripts/00_setup_infrastructure.sql
```

This creates:
- `DOC_KNOWLEDGE_GRAPH_DEMO` database with `RAW`, `PIPELINE`, and `SERVING` schemas
- `DKG_WH` warehouse (X-Small, auto-suspend 60s)
- `NOTES_RAW` base table and `NOTES_STAGE` stage
- `PROMOTION_FRAGMENTS` table

### 2. Install dbt packages

```bash
dbt deps
```

### 3. Load the ontology

```bash
dbt seed --full-refresh
```

This loads `entity_types.csv` and `relationship_types.csv` into `DOC_KNOWLEDGE_GRAPH_DEMO.SERVING`.

### 4. Load concept notes into the base table

You have two options:

**Option A: Manual load (for testing)**

Insert notes directly:

```sql
INSERT INTO DOC_KNOWLEDGE_GRAPH_DEMO.RAW.NOTES_RAW (slug, title, kind, body_markdown, see_also_edges, applicable_orgs)
VALUES (
  'activation-rate',
  'Activation Rate',
  'Metric',
  'Activation Rate measures the percentage of...',
  ARRAY_CONSTRUCT('cohort', 'conversion-rate'),
  ARRAY_CONSTRUCT('Analytics', 'Marketing')
);
```

**Option B: CI deploy (production)**

Build a `notes_manifest.json` from your git markdown files and stage it:

```bash
# Transform markdown+frontmatter → JSON array
python compile_notes.py ./notes > notes_manifest.json

# Upload to stage
snow stage copy notes_manifest.json @DOC_KNOWLEDGE_GRAPH_DEMO.RAW.NOTES_STAGE/

# Run the deploy merge
snow sql -f scripts/04_deploy_notes.sql
```

The manifest JSON format per note:

```json
{
  "slug": "activation-rate",
  "title": "Activation Rate",
  "kind": "Metric",
  "body_markdown": "Activation Rate measures the percentage of...",
  "frontmatter": {"owner": "analytics-team", "status": "active"},
  "see_also": ["cohort", "conversion-rate"],
  "applicable_orgs": ["Analytics", "Marketing"]
}
```

### 5. Build the dynamic table pipeline

```bash
dbt run
```

This creates all dynamic tables:
- **Staging**: `STG_NOTES_PARSED`, `STG_NOTES_EMBEDDED`, `STG_ENTITIES_EXTRACTED`, `STG_ENTITY_RESOLVED`
- **Ontology**: `ONT_ENTITY_TYPES_EMBEDDED`, `ONT_RELATIONSHIP_TYPES_EMBEDDED`
- **Graph**: `GRAPH_CONCEPT_NODES`, `GRAPH_CONCEPT_RELATIONSHIPS`

Dynamic tables refresh automatically based on `TARGET_LAG`. No manual refresh needed after initial build.

### 6. Create Cortex Search services

```bash
snow sql -f scripts/01_create_search_services.sql
```

Wait a few minutes for the initial indexing to complete.

### 7. Create agent tool functions

```bash
snow sql -f scripts/02_create_agent_tools.sql
```

### 8. Create the Cortex Agent

```bash
snow sql -f scripts/03_create_agent.sql
```

## Calling the Agent

The agent is available at `DOC_KNOWLEDGE_GRAPH_DEMO.SERVING.DOC_KNOWLEDGE_GRAPH_AGENT`.

### Via REST API (with org context for disambiguation)

Include the user's team in the system prompt so the agent can disambiguate shared abbreviations:

```json
{
  "model": "DOC_KNOWLEDGE_GRAPH_DEMO.SERVING.DOC_KNOWLEDGE_GRAPH_AGENT",
  "messages": [
    {
      "role": "system",
      "content": "The user is on the Analytics team."
    },
    {
      "role": "user",
      "content": "What is CR?"
    }
  ]
}
```

The agent will prefer the concept note tagged with `applicable_orgs` matching "Analytics" and explicitly state its interpretation:

> I'm interpreting 'CR' as 'Completion Rate' based on your Analytics team context. If you meant 'Credit Rating' (used by the Finance team), let me know.

### Via SQL

```sql
SELECT SNOWFLAKE.CORTEX.INVOKE_AGENT(
  'DOC_KNOWLEDGE_GRAPH_DEMO.SERVING.DOC_KNOWLEDGE_GRAPH_AGENT',
  'What metrics depend on the Cohort dimension?'
);
```

## Day-to-Day Operations

### Adding or updating concept notes

1. Edit markdown files in git (frontmatter includes `applicable_orgs`, `see_also`, `kind`)
2. Open a PR — CI validates against the ontology
3. On merge, CI runs `scripts/04_deploy_notes.sql` to upsert into `NOTES_RAW`
4. Dynamic tables auto-refresh within their `TARGET_LAG` (staging: downstream, graph: 1 hour)

### Evolving the ontology

1. Edit `seeds/ontology/entity_types.csv` or `relationship_types.csv`
2. Run `dbt seed --full-refresh`
3. The ontology embedding tables refresh, and the next extraction cycle uses the updated types

### Checking pipeline health

```sql
-- Verify note count
SELECT COUNT(*) FROM DOC_KNOWLEDGE_GRAPH_DEMO.PIPELINE.STG_NOTES_PARSED;

-- Check entity extraction success rate
SELECT
  COUNT(*) AS total_notes,
  COUNT(extraction_result) AS successful_extractions
FROM DOC_KNOWLEDGE_GRAPH_DEMO.PIPELINE.STG_ENTITIES_EXTRACTED;

-- See the knowledge graph stats
SELECT entity_type, COUNT(*) AS node_count
FROM DOC_KNOWLEDGE_GRAPH_DEMO.SERVING.GRAPH_CONCEPT_NODES
GROUP BY entity_type
ORDER BY node_count DESC;

SELECT relationship_type, COUNT(*) AS edge_count
FROM DOC_KNOWLEDGE_GRAPH_DEMO.SERVING.GRAPH_CONCEPT_RELATIONSHIPS
GROUP BY relationship_type
ORDER BY edge_count DESC;
```

## Project Structure

```
doc-knowledge-graph/
├── dbt_project.yml
├── profiles.yml
├── packages.yml
├── compile_notes.py
├── seeds/ontology/
│   ├── _ontology__seeds.yml
│   ├── entity_types.csv              # 9 entity types
│   └── relationship_types.csv        # 14 relationship types
├── models/
│   ├── sources.yml
│   ├── staging/
│   │   ├── stg_notes_parsed.sql      # normalize raw notes
│   │   ├── stg_notes_embedded.sql    # vector embeddings
│   │   ├── stg_entities_extracted.sql # ontology-guided LLM extraction
│   │   └── stg_entity_resolved.sql   # name dedup
│   ├── ontology/
│   │   ├── ont_entity_types_embedded.sql
│   │   └── ont_relationship_types_embedded.sql
│   └── graph/
│       ├── graph_concept_nodes.sql
│       └── graph_concept_relationships.sql
├── notes/                             # 13 concept notes (SaaS analytics domain)
├── examples/
│   └── thread_activation_rate.md      # example agent conversation
└── scripts/
    ├── 00_setup_infrastructure.sql   # DB, schemas, warehouse, tables
    ├── 01_create_search_services.sql # Cortex Search (concept + entity)
    ├── 02_create_agent_tools.sql     # graph traversal stored procs
    ├── 03_create_agent.sql           # Cortex Agent spec
    └── 04_deploy_notes.sql           # CI merge script
```

## Concept Note Frontmatter Format

```yaml
---
slug: activation-rate
title: Activation Rate
kind: Metric              # One of: Metric, Dimension, Business Rule, Persona, Data Source, Glossary
see_also:
  - cohort
  - conversion-rate
applicable_orgs:          # Optional — teams this concept is most relevant to
  - Analytics
  - Marketing
---

Activation Rate measures the percentage of trial users who...
```

## Cost Considerations

- **LLM extraction** (`stg_entities_extracted`): Runs once per note via `llama3.1-70b`. With 13 notes, this is ~13 Cortex COMPLETE calls on initial build, then only for new/changed notes.
- **Embeddings** (`stg_notes_embedded`, ontology models): Arctic Embed is lightweight; cost is negligible.
- **Cortex Search**: Billed per indexed row. At 13 notes + a few hundred entities, this is minimal.
- **Warehouse**: `DKG_WH` at X-Small with 60s auto-suspend keeps costs low during idle periods.
