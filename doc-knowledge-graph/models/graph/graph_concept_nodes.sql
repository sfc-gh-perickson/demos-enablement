{{
  config(
    materialized = 'dynamic_table',
    target_lag = '1 hour',
    snowflake_warehouse = 'KV_WH'
  )
}}

-- =============================================================================
-- Canonical Concept Nodes
-- =============================================================================
-- Aggregates resolved entities into canonical graph nodes. Each unique concept
-- (metric, dimension, persona, etc.) becomes one node regardless of how many
-- notes reference it.
-- =============================================================================

WITH aggregated AS (
    SELECT
        c.canonical_cluster_id AS entity_id,
        c.entity_type,
        COUNT(*) AS type_mention_count
    FROM {{ ref('stg_entity_resolved') }} c
    GROUP BY c.canonical_cluster_id, c.entity_type
),

dominant_types AS (
    SELECT entity_id, entity_type
    FROM aggregated
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY entity_id
        ORDER BY type_mention_count DESC
    ) = 1
)

SELECT
    c.canonical_cluster_id AS entity_id,
    MODE(c.raw_entity_name) AS entity_name,
    UPPER(TRIM(MODE(c.raw_entity_name))) AS entity_name_normalized,
    dt.entity_type,
    MAX_BY(c.entity_description, LENGTH(c.entity_description)) AS description,
    ARRAY_AGG(DISTINCT c.raw_entity_name) AS name_variants,
    COUNT(*) AS mention_count,
    COUNT(DISTINCT c.note_id) AS note_count,
    ARRAY_AGG(DISTINCT c.note_id) AS source_notes,
    ARRAY_AGG(DISTINCT c.slug) AS source_slugs
FROM {{ ref('stg_entity_resolved') }} c
JOIN dominant_types dt ON dt.entity_id = c.canonical_cluster_id
GROUP BY c.canonical_cluster_id, dt.entity_type
