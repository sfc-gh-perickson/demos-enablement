"""
Cortex Agent client for Streamlit-in-Snowflake.

Calls a named Cortex Agent object via REST API.
In SiS, uses _snowflake.send_snow_api_request() for auth.
Locally, uses PAT from ~/.snowflake/config.toml.
"""

import json

# Agent object location
AGENT_DATABASE = "CORTEX_AGENT_DEMO"
AGENT_SCHEMA = "ANALYTICS"
AGENT_NAME = "ANALYTICS_AGENT"
AGENT_PATH = f"/api/v2/databases/{AGENT_DATABASE}/schemas/{AGENT_SCHEMA}/agents/{AGENT_NAME}:run"


def _call_agent_sis(payload: dict) -> dict:
    """Call agent using SiS built-in REST helper (no external auth needed)."""
    import _snowflake

    resp = _snowflake.send_snow_api_request(
        "POST",
        AGENT_PATH,
        {},  # headers
        json.dumps(payload),
    )
    if isinstance(resp, dict):
        return resp
    if isinstance(resp, str):
        return json.loads(resp)
    # Object with .text or similar
    raw = getattr(resp, 'text', None) or getattr(resp, 'content', None) or str(resp)
    return json.loads(raw)


def _call_agent_local(payload: dict) -> dict:
    """Call agent using PAT auth for local development."""
    import tomllib
    from pathlib import Path
    import requests

    config_path = Path.home() / ".snowflake" / "config.toml"
    with open(config_path, "rb") as f:
        config = tomllib.load(f)

    # Use default connection
    default_name = config.get("default_connection_name", "default")
    connection = config["connections"][default_name]
    account = connection["account"]
    pat = connection["password"]

    host = account.lower().replace("_", "-") + ".snowflakecomputing.com"
    url = f"https://{host}{AGENT_PATH}"

    headers = {
        "Authorization": f"Bearer {pat}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }

    resp = requests.post(url, headers=headers, json=payload, timeout=180)
    resp.raise_for_status()
    return resp.json()


def _is_sis() -> bool:
    """Detect if running inside Streamlit-in-Snowflake."""
    try:
        import _snowflake  # noqa: F401
        return True
    except ImportError:
        return False


def call_agent(user_question: str, page_context: dict) -> dict:
    """
    Call the named Cortex Agent with context injected into the messages.

    The agent object already has tools, model, and base instructions configured.
    Dynamic page context is passed as the first message in the conversation.
    """
    context_text = "\n".join(f"- {k}: {v}" for k, v in page_context.items())

    system_msg = (
        f"Here is the user's current application context:\n{context_text}\n\n"
        "IMPORTANT: Only discuss data that is visible on the user's current page. "
        "Do NOT reference or include data from other segments, pages, or time periods "
        "unless the user explicitly asks to compare. When querying data, filter to "
        "only the segment and time period shown above. Focus exclusively on the "
        "metrics shown in the current context."
    )

    payload = {
        "messages": [
            {
                "role": "system",
                "content": [{"type": "text", "text": system_msg}],
            },
            {
                "role": "user",
                "content": [{"type": "text", "text": user_question}],
            },
        ],
        "stream": False,
    }

    if _is_sis():
        return _call_agent_sis(payload)
    else:
        return _call_agent_local(payload)


def extract_text_response(api_response: dict) -> str:
    """Extract the text content from an agent API response."""
    content = api_response.get("content", [])
    text_parts = [item["text"] for item in content if item.get("type") == "text"]
    return "\n".join(text_parts) if text_parts else "(No text response)"
