{{
  config(
    materialized = 'dynamic_table',
    target_lag = '1 hour',
    snowflake_warehouse = 'DKG_WH'
  )
}}

-- =============================================================================
-- Canonical Concept Relationships
-- =============================================================================
-- Combines two sources of edges:
--   1. LLM-extracted relationships from concept note prose
--   2. Explicit see-also edges from note frontmatter
--
-- Both are resolved through the entity node lookup to produce canonical edges.
-- =============================================================================

-- Source 1: LLM-extracted relationships
WITH extracted_relationships AS (
    SELECT
        e.note_id,
        f.value:source::VARCHAR AS source_entity_name,
        f.value:target::VARCHAR AS target_entity_name,
        f.value:type::VARCHAR AS relationship_type,
        f.value:description::VARCHAR AS relationship_description
    FROM {{ ref('stg_entities_extracted') }} e,
        LATERAL FLATTEN(INPUT => e.extraction_result:relationships) f
    WHERE e.extraction_result IS NOT NULL
      AND e.extraction_result:relationships IS NOT NULL
),

-- Source 2: Explicit see-also edges from frontmatter
see_also_edges AS (
    SELECT
        n.note_id,
        n.title AS source_entity_name,
        f.value::VARCHAR AS target_entity_name,
        'SEE_ALSO' AS relationship_type,
        'Explicit cross-reference from concept note frontmatter' AS relationship_description
    FROM {{ ref('stg_notes_parsed') }} n,
        LATERAL FLATTEN(INPUT => n.see_also_edges) f
    WHERE n.see_also_edges IS NOT NULL
),

-- Union both edge sources
all_edges AS (
    SELECT * FROM extracted_relationships
    UNION ALL
    SELECT * FROM see_also_edges
),

-- Resolve names to canonical entity IDs
entity_name_lookup AS (
    SELECT
        raw_entity_name,
        canonical_cluster_id AS entity_id
    FROM {{ ref('stg_entity_resolved') }}
    GROUP BY raw_entity_name, canonical_cluster_id
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY raw_entity_name
        ORDER BY COUNT(*) DESC
    ) = 1
),

resolved AS (
    SELECT
        r.note_id,
        r.relationship_type,
        r.relationship_description,
        src_lookup.entity_id AS source_entity_id,
        src_node.entity_name AS source_entity_name,
        tgt_lookup.entity_id AS target_entity_id,
        tgt_node.entity_name AS target_entity_name
    FROM all_edges r
    JOIN entity_name_lookup src_lookup
        ON r.source_entity_name = src_lookup.raw_entity_name
    JOIN entity_name_lookup tgt_lookup
        ON r.target_entity_name = tgt_lookup.raw_entity_name
    JOIN {{ ref('graph_concept_nodes') }} src_node
        ON src_lookup.entity_id = src_node.entity_id
    JOIN {{ ref('graph_concept_nodes') }} tgt_node
        ON tgt_lookup.entity_id = tgt_node.entity_id
    WHERE r.source_entity_name IS NOT NULL
      AND r.target_entity_name IS NOT NULL
      AND r.relationship_type IS NOT NULL
)

SELECT
    SHA2(
        source_entity_id || '::' || target_entity_id || '::' || relationship_type,
        256
    ) AS relationship_id,
    source_entity_id,
    source_entity_name,
    target_entity_id,
    target_entity_name,
    relationship_type,
    MAX_BY(relationship_description, LENGTH(relationship_description)) AS description,
    COUNT(*) AS mention_count,
    COUNT(DISTINCT note_id) AS note_count,
    ARRAY_AGG(DISTINCT note_id) AS source_notes
FROM resolved
GROUP BY
    source_entity_id,
    source_entity_name,
    target_entity_id,
    target_entity_name,
    relationship_type
