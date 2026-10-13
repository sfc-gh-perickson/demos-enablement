-- =============================================================================
-- Knowledge Vault Cortex Agent
-- =============================================================================

USE DATABASE DOC_KNOWLEDGE_GRAPH_DEMO;
USE SCHEMA SERVING;
USE WAREHOUSE DKG_WH;

CREATE OR REPLACE AGENT SERVING.DOC_KNOWLEDGE_GRAPH_AGENT
FROM SPECIFICATION $$
models:
  orchestration: auto

instructions:
  response: >
    You are a knowledge assistant that helps users understand business concepts,
    metrics, dimensions, and data sources defined in this knowledge vault. Always
    cite which concept notes inform your answer (by slug). Never fabricate
    definitions — if the vault doesn't cover a concept, say so.

    DISAMBIGUATION (abbreviations and shared terms):
    The system prompt provides the user's team or organization.
    When a search returns multiple concept notes matching the same abbreviation or
    term, prefer the note whose applicable_orgs includes the user's team.
    ALWAYS state your interpretation explicitly when disambiguating, e.g.:
    "I'm interpreting 'CR' as 'Conversion Rate' based on your Marketing team context.
    If you meant 'Churn Rate' (used by the Retention team), let me know."
    If the user corrects you, switch to their intended term without pushback.
    If applicable_orgs is empty or null for a result, treat it as universally
    applicable. This is a soft preference, not a hard filter.

  orchestration: >
    TOOL ROUTING:
    For definitional questions (what does X mean, define X, how is X calculated),
    use concept_search. Filter by kind if you know whether it is a Metric,
    Dimension, Business Rule, Persona, Data Source, or Glossary term.
    For relationship questions (how is X related to Y, what depends on X),
    use get_concept_subgraph for a single concept or get_related_concepts for
    multi-hop discovery.
    For full note content, use get_concept_context with the note slug.
    Use entity_search to find entities in the knowledge graph by name or type.

tools:
  - tool_spec:
      type: cortex_search
      name: "concept_search"
      description: >
        Searches the knowledge vault for concept notes by content. Returns
        matching notes with title, kind, related concepts, and applicable_orgs
        (which teams the concept is most relevant to). Filter by kind (Metric,
        Dimension, Business Rule, Persona, Data Source, Glossary) to narrow results.
        Check applicable_orgs in results to disambiguate terms shared across teams.

  - tool_spec:
      type: cortex_search
      name: "entity_search"
      description: >
        Searches the knowledge graph for named entities (metrics, dimensions,
        systems, personas, etc.) by name or description. Filter by entity_type
        to narrow. Use when you need to find an entity before graph traversal.

  - tool_spec:
      type: generic
      name: "get_concept_subgraph"
      description: >
        Returns the complete context for one concept: its type, description,
        top 15 relationships (incoming and outgoing), and which concept notes
        define it. Parameter: concept_name (VARCHAR) - the concept to look up.

  - tool_spec:
      type: generic
      name: "get_related_concepts"
      description: >
        Multi-hop graph traversal from a seed concept. Discovers indirect
        connections (e.g., metrics to business rules to dimensions to data sources).
        Parameters: seed_concept_name (VARCHAR), max_hops (INT, default 2).

  - tool_spec:
      type: generic
      name: "get_concept_context"
      description: >
        Returns the full markdown body of a concept note. Accepts either the
        slug (e.g. "monthly-revenue") or the title (e.g. "Monthly Revenue").
        Use when the user wants the complete definition, not just a search snippet.
        Parameter: concept_identifier (VARCHAR).

tool_resources:
  concept_search:
    search_service: DOC_KNOWLEDGE_GRAPH_DEMO.SERVING.CONCEPT_SEARCH_SERVICE
  entity_search:
    search_service: DOC_KNOWLEDGE_GRAPH_DEMO.SERVING.ENTITY_SEARCH_SERVICE
  get_concept_subgraph:
    type: function
    function: DOC_KNOWLEDGE_GRAPH_DEMO.SERVING.GET_CONCEPT_SUBGRAPH
    execution_environment:
      type: warehouse
      warehouse: DKG_WH
  get_related_concepts:
    type: function
    function: DOC_KNOWLEDGE_GRAPH_DEMO.SERVING.GET_RELATED_CONCEPTS
    execution_environment:
      type: warehouse
      warehouse: DKG_WH
  get_concept_context:
    type: function
    function: DOC_KNOWLEDGE_GRAPH_DEMO.SERVING.GET_CONCEPT_CONTEXT
    execution_environment:
      type: warehouse
      warehouse: DKG_WH
$$;
