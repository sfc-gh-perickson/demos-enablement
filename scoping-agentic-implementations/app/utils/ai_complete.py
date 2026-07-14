import json
from snowflake.snowpark import Session


def ai_complete(session: Session, prompt: str, model: str = "claude-haiku-4-5") -> str:
    """Call SNOWFLAKE.CORTEX.AI_COMPLETE and return the text response."""
    escaped = prompt.replace("$$", "$ $")
    result = session.sql(f"""
        SELECT AI_COMPLETE('{model}', $${escaped}$$) AS response
    """).collect()
    raw = result[0][0]
    # AI_COMPLETE with a string prompt returns a JSON-encoded string (quoted).
    # AI_COMPLETE with a messages array returns {"choices":[{"messages":"..."}]}.
    # In both cases, unwrap to get the plain text content.
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, str):
            return parsed
        if isinstance(parsed, dict) and "choices" in parsed:
            return parsed["choices"][0]["messages"]
    except (json.JSONDecodeError, KeyError, IndexError, TypeError):
        pass
    return raw


def ai_complete_json(session: Session, prompt: str, model: str = "claude-haiku-4-5", schema: dict = None):
    """Call AI_COMPLETE with structured JSON output. Returns parsed JSON or None on failure.

    schema: A JSON Schema with top-level "type": "object" defining the expected structure.
            Required — Snowflake's structured output needs explicit property definitions.
    """
    if schema is None:
        raise ValueError("schema is required for structured output (must be a top-level object schema)")
    escaped = prompt.replace("$$", "$ $")
    options_str = json.dumps({"response_format": {"type": "json", "schema": schema}})
    options_sql = options_str.replace("'", "''")
    result = session.sql(f"""
        SELECT AI_COMPLETE('{model}', $${escaped}$$, PARSE_JSON('{options_sql}')) AS response
    """).collect()
    raw = result[0][0]
    if raw is None:
        return None
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, str):
            return json.loads(parsed)
        if isinstance(parsed, dict) and "choices" in parsed:
            return json.loads(parsed["choices"][0]["messages"])
        return parsed
    except (json.JSONDecodeError, KeyError, IndexError, TypeError):
        return None
