{{
  config(
    materialized = 'dynamic_table',
    target_lag = 'DOWNSTREAM',
    snowflake_warehouse = 'KV_WH'
  )
}}

-- =============================================================================
-- Entity Normalization & Resolution
-- =============================================================================
-- Flattens extracted entities, normalizes names, and resolves duplicates.
-- Name normalization collapses variations like "Monthly Revenue" /
-- "monthly revenue" / "Monthly  Revenue" into a single canonical node.
-- =============================================================================

WITH raw_entities AS (
    SELECT
        e.note_id,
        e.slug,
        f.value:name::VARCHAR AS raw_entity_name,
        f.value:type::VARCHAR AS entity_type,
        f.value:description::VARCHAR AS entity_description
    FROM {{ ref('stg_entities_extracted') }} e,
        LATERAL FLATTEN(INPUT => e.extraction_result:entities) f
    WHERE e.extraction_result IS NOT NULL
      AND e.extraction_result:entities IS NOT NULL
      AND f.value:name::VARCHAR IS NOT NULL
      AND LENGTH(TRIM(f.value:name::VARCHAR)) > 0
),

normalized AS (
    SELECT
        *,
        UPPER(TRIM(REGEXP_REPLACE(raw_entity_name, '\\s+', ' '))) AS normalized_name
    FROM raw_entities
)

SELECT
    SHA2(normalized_name, 256) AS canonical_cluster_id,
    note_id,
    slug,
    raw_entity_name,
    normalized_name,
    entity_type,
    entity_description,
    1 AS mention_count
FROM normalized
