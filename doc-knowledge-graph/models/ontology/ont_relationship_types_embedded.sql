{{
  config(
    materialized = 'dynamic_table',
    target_lag = 'DOWNSTREAM',
    snowflake_warehouse = 'DKG_WH'
  )
}}

SELECT
    rt.relationship_type,
    rt.parent_relationship_type,
    rt.source_entity_type,
    rt.target_entity_type,
    rt.description,
    SNOWFLAKE.CORTEX.EMBED_TEXT_1024(
        'snowflake-arctic-embed-l-v2.0',
        rt.relationship_type || ' (' || rt.source_entity_type || ' -> ' || rt.target_entity_type || '): ' || rt.description
    )::VECTOR(FLOAT, 1024) AS type_embedding
FROM {{ source('ontology', 'relationship_types') }} rt
WHERE rt.is_active = TRUE
