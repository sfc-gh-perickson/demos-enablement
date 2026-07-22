"""
BiteIQ Backend — Middleware for file upload to Snowflake stage + agent:run proxy.
Run: uvicorn backend:app --port 5001 --reload
Requires: pip install fastapi uvicorn python-multipart snowflake-snowpark-python
"""
import os, json, tempfile
from pathlib import Path
from contextlib import asynccontextmanager

from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from snowflake.snowpark import Session

# --- Snowflake connection (uses ~/.snowflake/config.toml) ---
import tomllib

config_path = Path.home() / ".snowflake" / "config.toml"
with open(config_path, "rb") as f:
    config = tomllib.load(f)

conn_name = os.environ.get(
    "SNOWFLAKE_DEFAULT_CONNECTION_NAME",
    config.get("default_connection_name", "default")
)
conn_params = config["connections"][conn_name]
session = Session.builder.configs(conn_params).create()
session.sql("USE DATABASE DOCUMENT_CONTEXT_LAB").collect()
session.sql("USE SCHEMA PUBLIC").collect()
session.sql("USE WAREHOUSE DOCUMENT_CONTEXT_LAB_WH").collect()

print(f"Connected as: {session.sql('SELECT CURRENT_USER()').collect()[0][0]}")

# --- App ---
app = FastAPI(title="BiteIQ Backend", version="1.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

# Extensions to rename to .txt before staging (no longer needed — UDF reads raw)
# Keeping .csv/.json as-is since READ_DOCUMENT_BY_PATH handles them directly.
CONVERT_TO_TXT = set()  # empty — no conversion needed


@app.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    """Upload a file to @DOC_UPLOADS stage. Returns the staged path."""
    original_name = file.filename
    ext = Path(original_name).suffix.lower()

    # Convert unsupported extensions to .txt
    if ext in CONVERT_TO_TXT:
        stage_name = Path(original_name).with_suffix('.txt').name
    else:
        stage_name = original_name

    # Save to temp and PUT to stage
    content = await file.read()
    tmp_dir = tempfile.mkdtemp()
    tmp_path = os.path.join(tmp_dir, stage_name)
    Path(tmp_path).write_bytes(content)

    try:
        session.file.put(
            tmp_path,
            "@DOC_UPLOADS/uploads",
            auto_compress=False,
            overwrite=True
        )
        staged_path = f"uploads/{stage_name}"
        return {"staged_path": staged_path, "original_name": original_name}
    finally:
        os.unlink(tmp_path)
        os.rmdir(tmp_dir)


class AskRequest(BaseModel):
    question: str
    staged_files: list[str] = []


@app.post("/ask")
async def ask_agent(req: AskRequest):
    """Call the agent with optional file context."""
    content_blocks = []
    if req.staged_files:
        file_list = ", ".join(f"'{f}'" for f in req.staged_files)
        content_blocks.append({
            "type": "text",
            "text": f"[The user has uploaded the following files to the document stage: {file_list}. "
                    f"Use the read_document tool to access them if relevant to the question.]"
        })
    content_blocks.append({"type": "text", "text": req.question})

    # Call agent:run via the session's REST client
    rest = session.connection.rest
    url = f"{rest.server_url}/api/v2/databases/DOCUMENT_CONTEXT_LAB/schemas/PUBLIC/agents/BITEIQ_AGENT:run"
    headers = {
        "Authorization": f'Snowflake Token="{rest.token}"',
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    body = {
        "stream": False,
        "messages": [{"role": "user", "content": content_blocks}]
    }

    with rest.use_requests_session(url) as s:
        resp = s.post(url, json=body, headers=headers)
        resp.raise_for_status()
        return resp.json()


@app.get("/health")
async def health():
    return {"status": "ok", "user": session.sql("SELECT CURRENT_USER()").collect()[0][0]}


if __name__ == "__main__":
    import uvicorn
    print("BiteIQ backend running on http://localhost:5001")
    print("Endpoints:")
    print("  POST /upload  — upload file to stage (multipart form)")
    print("  POST /ask     — call agent with question + staged files")
    print("  GET  /health  — check connection")
    print("  GET  /docs    — OpenAPI docs (Swagger UI)")
    uvicorn.run(app, host="0.0.0.0", port=5001)
