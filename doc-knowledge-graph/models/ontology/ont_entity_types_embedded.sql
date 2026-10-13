{{
  config(
    materialized = 'dynamic_table',
    target_lag = 'DOWNSTREAM',
    snowflake_warehouse = 'DKG_WH'
  )
}}

SELECT
    et.entity_type,
    et.parent_entity_type,
    et.description,
    et.examples,
    SNOWFLAKE.CORTEX.EMBED_TEXT_1024(
        'snowflake-arctic-embed-l-v2.0',
        et.entity_type || ': ' || et.description
    )::VECTOR(FLOAT, 1024) AS type_embedding
FROM {{ source('ontology', 'entity_types') }} et
WHERE et.is_active = TRUE
