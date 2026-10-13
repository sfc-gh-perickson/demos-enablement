-- =============================================================================
-- CI Deploy Script: Push concept notes from git into NOTES_RAW
-- =============================================================================
-- Called by CI on merge to main. Loads notes directly into the base table;
-- the dynamic table DAG handles the rest.
--
-- Usage from CI:
--   snow sql -f scripts/04_deploy_notes.sql \
--     --variable "stage_path=@DOC_KNOWLEDGE_GRAPH_DEMO.RAW.NOTES_STAGE/notes/"
--
-- The CI step should first PUT note files to the stage, then run this script.
-- =============================================================================

USE DATABASE DOC_KNOWLEDGE_GRAPH_DEMO;
USE SCHEMA RAW;
USE WAREHOUSE DKG_WH;

-- MERGE pattern: upsert notes from staged JSON manifest
MERGE INTO RAW.NOTES_RAW tgt
USING (
    SELECT
        f.value:slug::VARCHAR AS slug,
        f.value:title::VARCHAR AS title,
        f.value:kind::VARCHAR AS kind,
        f.value:body_markdown::VARCHAR AS body_markdown,
        f.value:frontmatter::VARIANT AS frontmatter_json,
        f.value:see_also::ARRAY AS see_also_edges,
        f.value:applicable_orgs::ARRAY AS applicable_orgs,
        CURRENT_TIMESTAMP() AS updated_at
    FROM @RAW.NOTES_STAGE/notes_manifest.json (FILE_FORMAT => 'RAW.JSON_FORMAT') AS t,
        LATERAL FLATTEN(INPUT => PARSE_JSON(t.$1)) f
) src
ON tgt.slug = src.slug
WHEN MATCHED AND (
    tgt.body_markdown != src.body_markdown
    OR tgt.title != src.title
    OR tgt.kind != src.kind
) THEN UPDATE SET
    title = src.title,
    kind = src.kind,
    body_markdown = src.body_markdown,
    frontmatter_json = src.frontmatter_json,
    see_also_edges = src.see_also_edges,
    applicable_orgs = src.applicable_orgs,
    updated_at = src.updated_at
WHEN NOT MATCHED THEN INSERT (slug, title, kind, body_markdown, frontmatter_json, see_also_edges, applicable_orgs, updated_at)
    VALUES (src.slug, src.title, src.kind, src.body_markdown, src.frontmatter_json, src.see_also_edges, src.applicable_orgs, src.updated_at);
