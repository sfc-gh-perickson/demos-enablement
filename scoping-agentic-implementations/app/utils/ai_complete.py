import json
from snowflake.snowpark import Session


def ai_complete(session: Session, prompt: str, model: str = "claude-sonnet") -> str:
    """Call SNOWFLAKE.CORTEX.AI_COMPLETE and return the text response."""
    escaped = prompt.replace("$$", "$ $")
    result = session.sql(f"""
        SELECT SNOWFLAKE.CORTEX.AI_COMPLETE('{model}', $${escaped}$$) AS response
    """).collect()
    return result[0][0]


def ai_complete_json(session: Session, prompt: str, model: str = "claude-sonnet"):
    """Call AI_COMPLETE and parse the response as JSON. Returns None on parse failure."""
    raw = ai_complete(session, prompt, model)
    # Strip markdown fences if present
    cleaned = raw.strip()
    if cleaned.startswith("```"):
        lines = cleaned.split("\n")
        lines = [l for l in lines if not l.strip().startswith("```")]
        cleaned = "\n".join(lines)
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        # Try to find JSON array or object within the response
        for start_char, end_char in [("[", "]"), ("{", "}")]:
            start = cleaned.find(start_char)
            end = cleaned.rfind(end_char)
            if start != -1 and end != -1 and end > start:
                try:
                    return json.loads(cleaned[start:end + 1])
                except json.JSONDecodeError:
                    continue
        return None
