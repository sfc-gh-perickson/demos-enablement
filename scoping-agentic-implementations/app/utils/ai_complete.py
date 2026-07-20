import json
from snowflake.snowpark import Session

DEFAULT_MODEL = "claude-sonnet-4-5"
DEFAULT_TIMEOUT = 600


def ai_complete(session: Session, prompt: str, model: str = DEFAULT_MODEL) -> str:
    """Call SNOWFLAKE.CORTEX.AI_COMPLETE and return the text response."""
    escaped = prompt.replace("$$", "$ $")
    result = session.sql(f"""
        SELECT AI_COMPLETE('{model}', $${escaped}$$) AS response
    """).collect(statement_params={"STATEMENT_TIMEOUT_IN_SECONDS": str(DEFAULT_TIMEOUT)})
    raw = result[0][0]
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, str):
            return parsed
        if isinstance(parsed, dict) and "choices" in parsed:
            return parsed["choices"][0]["messages"]
    except (json.JSONDecodeError, KeyError, IndexError, TypeError):
        pass
    return raw


def ai_complete_json(session: Session, prompt: str, model: str = DEFAULT_MODEL, schema: dict = None):
    """Call AI_COMPLETE with structured JSON output. Returns parsed JSON or None on failure."""
    if schema is None:
        raise ValueError("schema is required for structured output (must be a top-level object schema)")
    escaped = prompt.replace("$$", "$ $")
    options_str = json.dumps({"response_format": {"type": "json", "schema": schema}})
    options_sql = options_str.replace("'", "''")
    result = session.sql(f"""
        SELECT AI_COMPLETE('{model}', $${escaped}$$, PARSE_JSON('{options_sql}')) AS response
    """).collect(statement_params={"STATEMENT_TIMEOUT_IN_SECONDS": str(DEFAULT_TIMEOUT)})
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
