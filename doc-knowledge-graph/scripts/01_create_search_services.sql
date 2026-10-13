-- =============================================================================
-- Cortex Search Services for the Knowledge Vault
-- =============================================================================
-- Two search services:
--   1. CONCEPT_SEARCH: Full-text search over concept note prose
--   2. ENTITY_SEARCH: Search over the extracted knowledge graph entities
-- =============================================================================

USE DATABASE DOC_KNOWLEDGE_GRAPH_DEMO;
USE SCHEMA SERVING;
USE WAREHOUSE KV_WH;

-- 1. Concept Search: search over concept note prose with graph-enriched metadata
CREATE OR REPLACE CORTEX SEARCH SERVICE SERVING.CONCEPT_SEARCH_SERVICE
  ON search_text
  ATTRIBUTES kind, title, related_concepts, applicable_orgs
  WAREHOUSE = KV_WH
  TARGET_LAG = '1 hour'
AS
WITH note_relationships AS (
    SELECT
        gn.entity_name AS note_title,
        LISTAGG(DISTINCT r.target_entity_name, ', ') AS related
    FROM DOC_KNOWLEDGE_GRAPH_DEMO.SERVING.GRAPH_CONCEPT_RELATIONSHIPS r
    JOIN DOC_KNOWLEDGE_GRAPH_DEMO.SERVING.GRAPH_CONCEPT_NODES gn
        ON r.source_entity_id = gn.entity_id
    GROUP BY gn.entity_name
)
SELECT
    n.note_id,
    n.slug,
    n.title,
    n.kind,
    n.search_text,
    ARRAY_TO_STRING(n.applicable_orgs, ', ') AS applicable_orgs,
    COALESCE(nr.related, '') AS related_concepts
FROM DOC_KNOWLEDGE_GRAPH_DEMO.PIPELINE.STG_NOTES_PARSED n
LEFT JOIN note_relationships nr ON UPPER(nr.note_title) = UPPER(n.title);


-- 2. Entity Search: search over knowledge graph entities
CREATE OR REPLACE CORTEX SEARCH SERVICE SERVING.ENTITY_SEARCH_SERVICE
  ON search_text
  ATTRIBUTES entity_type, entity_name
  WAREHOUSE = KV_WH
  TARGET_LAG = '1 hour'
AS
SELECT
    e.entity_id,
    e.entity_name,
    e.entity_type,
    e.entity_name || ': ' || COALESCE(e.description, '') AS search_text,
    e.mention_count,
    e.note_count
FROM DOC_KNOWLEDGE_GRAPH_DEMO.SERVING.GRAPH_CONCEPT_NODES e;
