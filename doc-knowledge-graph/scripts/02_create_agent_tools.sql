-- =============================================================================
-- Agent Tool Functions for the Knowledge Vault Cortex Agent
-- =============================================================================

USE DATABASE DOC_KNOWLEDGE_GRAPH_DEMO;
USE SCHEMA SERVING;
USE WAREHOUSE DKG_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. GET_CONCEPT_SUBGRAPH: Complete context for a named concept
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE SERVING.GET_CONCEPT_SUBGRAPH(
    concept_name VARCHAR
)
RETURNS TABLE (
    entity_name VARCHAR,
    entity_type VARCHAR,
    description VARCHAR,
    mention_count INT,
    note_count INT,
    top_relationships VARCHAR,
    source_notes VARCHAR
)
LANGUAGE SQL
AS
$$
DECLARE
    res RESULTSET;
BEGIN
    res := (
        WITH target AS (
            SELECT entity_id, entity_name, entity_type, description,
                   mention_count, note_count, source_slugs
            FROM DOC_KNOWLEDGE_GRAPH_DEMO.SERVING.GRAPH_CONCEPT_NODES
            WHERE UPPER(entity_name) = UPPER(:concept_name)
            LIMIT 1
        ),
        all_rels AS (
            SELECT
                r.relationship_type || ': ' || r.target_entity_name || ' (' || tn.entity_type || ')' AS rel_text,
                r.mention_count
            FROM DOC_KNOWLEDGE_GRAPH_DEMO.SERVING.GRAPH_CONCEPT_RELATIONSHIPS r
            JOIN target t ON r.source_entity_id = t.entity_id
            JOIN DOC_KNOWLEDGE_GRAPH_DEMO.SERVING.GRAPH_CONCEPT_NODES tn ON tn.entity_id = r.target_entity_id

            UNION ALL

            SELECT
                r.relationship_type || ' (from ' || r.source_entity_name || ', ' || sn.entity_type || ')' AS rel_text,
                r.mention_count
            FROM DOC_KNOWLEDGE_GRAPH_DEMO.SERVING.GRAPH_CONCEPT_RELATIONSHIPS r
            JOIN target t ON r.target_entity_id = t.entity_id
            JOIN DOC_KNOWLEDGE_GRAPH_DEMO.SERVING.GRAPH_CONCEPT_NODES sn ON sn.entity_id = r.source_entity_id
        ),
        top_rels AS (
            SELECT rel_text FROM all_rels ORDER BY mention_count DESC LIMIT 15
        ),
        rel_agg AS (
            SELECT LISTAGG(rel_text, '; ') WITHIN GROUP (ORDER BY rel_text) AS relationships
            FROM top_rels
        )
        SELECT
            t.entity_name,
            t.entity_type,
            LEFT(t.description, 500) AS description,
            t.mention_count,
            t.note_count,
            ra.relationships AS top_relationships,
            ARRAY_TO_STRING(t.source_slugs, ', ') AS source_notes
        FROM target t
        CROSS JOIN rel_agg ra
    );
    RETURN TABLE(res);
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. GET_RELATED_CONCEPTS: Multi-hop traversal through the knowledge graph
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE SERVING.GET_RELATED_CONCEPTS(
    seed_concept_name VARCHAR,
    max_hops INT DEFAULT 2
)
RETURNS TABLE (
    entity_name VARCHAR,
    entity_type VARCHAR,
    relationship_type VARCHAR,
    related_entity_name VARCHAR,
    related_entity_type VARCHAR,
    hop_distance INT,
    direction VARCHAR
)
LANGUAGE SQL
AS
$$
DECLARE
    res RESULTSET;
BEGIN
    res := (
        WITH RECURSIVE
        seed AS (
            SELECT entity_id, entity_name, entity_type
            FROM DOC_KNOWLEDGE_GRAPH_DEMO.SERVING.GRAPH_CONCEPT_NODES
            WHERE UPPER(entity_name) = UPPER(:seed_concept_name)
            LIMIT 1
        ),
        edges AS (
            SELECT source_entity_id AS from_id, target_entity_id AS to_id,
                   relationship_type, 'outgoing' AS direction
            FROM DOC_KNOWLEDGE_GRAPH_DEMO.SERVING.GRAPH_CONCEPT_RELATIONSHIPS
            UNION ALL
            SELECT target_entity_id AS from_id, source_entity_id AS to_id,
                   relationship_type, 'incoming' AS direction
            FROM DOC_KNOWLEDGE_GRAPH_DEMO.SERVING.GRAPH_CONCEPT_RELATIONSHIPS
        ),
        graph_walk AS (
            SELECT
                s.entity_name, s.entity_type,
                NULL::VARCHAR AS relationship_type,
                NULL::VARCHAR AS related_entity_name,
                NULL::VARCHAR AS related_entity_type,
                0 AS hop_distance,
                NULL::VARCHAR AS direction,
                s.entity_id AS current_entity_id,
                ARRAY_CONSTRUCT(s.entity_id) AS visited
            FROM seed s

            UNION ALL

            SELECT
                gw.entity_name, gw.entity_type,
                e.relationship_type,
                t.entity_name AS related_entity_name,
                t.entity_type AS related_entity_type,
                gw.hop_distance + 1 AS hop_distance,
                e.direction,
                t.entity_id AS current_entity_id,
                ARRAY_APPEND(gw.visited, t.entity_id) AS visited
            FROM graph_walk gw
            JOIN edges e ON e.from_id = gw.current_entity_id
            JOIN DOC_KNOWLEDGE_GRAPH_DEMO.SERVING.GRAPH_CONCEPT_NODES t ON t.entity_id = e.to_id
            WHERE gw.hop_distance < :max_hops
              AND NOT ARRAY_CONTAINS(t.entity_id::VARIANT, gw.visited)
        )
        SELECT
            entity_name, entity_type, relationship_type,
            related_entity_name, related_entity_type,
            hop_distance, direction
        FROM graph_walk
        WHERE hop_distance > 0
        QUALIFY ROW_NUMBER() OVER (
            PARTITION BY entity_name, related_entity_name
            ORDER BY hop_distance
        ) = 1
        ORDER BY hop_distance, related_entity_name
        LIMIT 50
    );
    RETURN TABLE(res);
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. GET_CONCEPT_CONTEXT: Returns the full note content for a concept by slug
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE SERVING.GET_CONCEPT_CONTEXT(
    concept_identifier VARCHAR
)
RETURNS TABLE (
    slug VARCHAR,
    title VARCHAR,
    kind VARCHAR,
    body_markdown VARCHAR,
    related_concepts VARCHAR
)
LANGUAGE SQL
AS
$$
DECLARE
    res RESULTSET;
BEGIN
    res := (
        WITH note AS (
            SELECT note_id, slug, title, kind, body_markdown
            FROM DOC_KNOWLEDGE_GRAPH_DEMO.PIPELINE.STG_NOTES_PARSED
            WHERE slug = :concept_identifier
               OR UPPER(title) = UPPER(:concept_identifier)
            LIMIT 1
        ),
        related AS (
            SELECT LISTAGG(DISTINCT r.target_entity_name, ', ') AS concepts
            FROM DOC_KNOWLEDGE_GRAPH_DEMO.SERVING.GRAPH_CONCEPT_RELATIONSHIPS r
            JOIN DOC_KNOWLEDGE_GRAPH_DEMO.SERVING.GRAPH_CONCEPT_NODES n
                ON r.source_entity_id = n.entity_id
            WHERE UPPER(n.entity_name) = UPPER((SELECT title FROM note))
        )
        SELECT
            n.slug,
            n.title,
            n.kind,
            n.body_markdown,
            r.concepts AS related_concepts
        FROM note n
        CROSS JOIN related r
    );
    RETURN TABLE(res);
END;
$$;
