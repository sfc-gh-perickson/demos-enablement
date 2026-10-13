{{
  config(
    materialized = 'dynamic_table',
    target_lag = 'DOWNSTREAM',
    snowflake_warehouse = 'KV_WH'
  )
}}

-- =============================================================================
-- Parse Concept Notes
-- =============================================================================
-- Normalizes raw concept notes from the NOTES_RAW base table. Extracts
-- structured fields from frontmatter and prepares the body for embedding.
-- =============================================================================

SELECT
    n.note_id,
    n.slug,
    n.title,
    n.kind,
    n.body_markdown,
    n.frontmatter_json,
    n.see_also_edges,
    n.applicable_orgs,
    CONCAT(
        'Concept: ', n.title, '\n',
        'Kind: ', n.kind, '\n\n',
        n.body_markdown
    ) AS search_text,
    LENGTH(n.body_markdown) AS body_length,
    n.updated_at
FROM {{ source('raw', 'notes_raw') }} n
WHERE n.body_markdown IS NOT NULL
  AND LENGTH(TRIM(n.body_markdown)) > 0
