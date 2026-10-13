{{
  config(
    materialized = 'dynamic_table',
    target_lag = 'DOWNSTREAM',
    snowflake_warehouse = 'DKG_WH'
  )
}}

-- =============================================================================
-- Embed Concept Notes
-- =============================================================================
-- Generates vector embeddings for each concept note's search text.
-- Uses Arctic Embed L v2.0 (1024-dim) for semantic similarity operations.
-- =============================================================================

SELECT
    note_id,
    slug,
    title,
    kind,
    body_markdown,
    search_text,
    see_also_edges,
    updated_at,
    SNOWFLAKE.CORTEX.EMBED_TEXT_1024(
        'snowflake-arctic-embed-l-v2.0',
        search_text
    ) AS embedding
FROM {{ ref('stg_notes_parsed') }}
