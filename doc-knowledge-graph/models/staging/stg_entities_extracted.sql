{{
  config(
    materialized = 'dynamic_table',
    target_lag = 'DOWNSTREAM',
    snowflake_warehouse = 'KV_WH'
  )
}}

-- =============================================================================
-- Entity & Relationship Extraction from Concept Notes
-- =============================================================================
-- Extracts structured entities and relationships from each concept note using
-- an LLM, guided by a per-note subset of the ontology selected via semantic
-- retrieval.
-- =============================================================================

-- Retrieve top-5 entity types per note by cosine similarity
WITH top_entity_types AS (
    SELECT
        n.note_id,
        ote.entity_type,
        VECTOR_COSINE_SIMILARITY(n.embedding, ote.type_embedding) AS sim
    FROM {{ ref('stg_notes_embedded') }} n
    CROSS JOIN {{ ref('ont_entity_types_embedded') }} ote
    WHERE ote.parent_entity_type IS NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY n.note_id ORDER BY sim DESC) <= 5
),

-- Expand parents to include children
relevant_entity_types AS (
    SELECT DISTINCT
        tp.note_id,
        ote.entity_type,
        ote.description,
        ote.examples
    FROM top_entity_types tp
    JOIN {{ ref('ont_entity_types_embedded') }} ote
        ON ote.entity_type = tp.entity_type

    UNION

    SELECT
        tp.note_id,
        child.entity_type,
        child.description,
        child.examples
    FROM top_entity_types tp
    JOIN {{ ref('ont_entity_types_embedded') }} child
        ON child.parent_entity_type = tp.entity_type
    JOIN {{ ref('stg_notes_embedded') }} n
        ON n.note_id = tp.note_id
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY tp.note_id, tp.entity_type
        ORDER BY VECTOR_COSINE_SIMILARITY(n.embedding, child.type_embedding) DESC
    ) <= 10
),

-- Aggregate entity types into a prompt string per note
note_entity_prompt AS (
    SELECT
        note_id,
        LISTAGG(
            '- ' || entity_type || ': ' || description || ' (e.g., ' || examples || ')',
            '\n'
        ) WITHIN GROUP (ORDER BY entity_type) AS entity_types_prompt
    FROM relevant_entity_types
    GROUP BY note_id
),

-- Retrieve top-5 relationship types per note
top_rel_types AS (
    SELECT
        n.note_id,
        orte.relationship_type,
        VECTOR_COSINE_SIMILARITY(n.embedding, orte.type_embedding) AS sim
    FROM {{ ref('stg_notes_embedded') }} n
    CROSS JOIN {{ ref('ont_relationship_types_embedded') }} orte
    WHERE orte.parent_relationship_type IS NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY n.note_id ORDER BY sim DESC) <= 5
),

relevant_rel_types AS (
    SELECT DISTINCT
        tp.note_id,
        orte.relationship_type,
        orte.source_entity_type,
        orte.target_entity_type,
        orte.description
    FROM top_rel_types tp
    JOIN {{ ref('ont_relationship_types_embedded') }} orte
        ON orte.relationship_type = tp.relationship_type
),

note_rel_prompt AS (
    SELECT
        note_id,
        LISTAGG(
            '- ' || relationship_type
                || ' (from: ' || source_entity_type || ', to: ' || target_entity_type || '): '
                || description,
            '\n'
        ) WITHIN GROUP (ORDER BY relationship_type) AS relationship_types_prompt
    FROM relevant_rel_types
    GROUP BY note_id
)

-- LLM extraction with per-note ontology guidance
SELECT
    n.note_id,
    n.slug,
    n.title,
    n.kind,
    TRY_PARSE_JSON(
        REGEXP_REPLACE(
            SNOWFLAKE.CORTEX.COMPLETE(
                'llama3.1-70b',
                CONCAT(
                    'You are a knowledge graph extraction engine for a business intelligence knowledge vault.\n',
                    'Extract entities and relationships from the following concept note.\n\n',
                    '## NOTE METADATA\n',
                    'Title: ', n.title, '\n',
                    'Kind: ', n.kind, '\n\n',
                    '## ENTITY TYPES (use these)\n',
                    nep.entity_types_prompt, '\n\n',
                    '## RELATIONSHIP TYPES (use these)\n',
                    nrp.relationship_types_prompt, '\n\n',
                    '## NOTE CONTENT\n',
                    n.body_markdown, '\n\n',
                    '## INSTRUCTIONS\n',
                    'Return a JSON object with two arrays:\n',
                    '- "entities": [{"name": "...", "type": "...", "description": "..."}]\n',
                    '- "relationships": [{"source": "...", "target": "...", "type": "...", "description": "..."}]\n\n',
                    '## RULES\n',
                    '- Extract named concepts, metrics, dimensions, systems, and personas mentioned in the note\n',
                    '- Use the entity type that describes what the thing IS (identity), not its role\n',
                    '- The relationship type encodes the role or connection\n',
                    '- Do NOT extract generic words — only specific named entities\n',
                    '- If an entity does not fit any listed type, assign a descriptive type label\n',
                    '- Do NOT wrap your response in markdown code fences\n',
                    '- Return ONLY the raw JSON object, no other text.'
                )
            ),
            '```[a-z]*\\n?|```', ''
        )
    ) AS extraction_result,
    CURRENT_TIMESTAMP() AS extracted_at
FROM {{ ref('stg_notes_embedded') }} n
JOIN note_entity_prompt nep ON nep.note_id = n.note_id
JOIN note_rel_prompt nrp ON nrp.note_id = n.note_id
