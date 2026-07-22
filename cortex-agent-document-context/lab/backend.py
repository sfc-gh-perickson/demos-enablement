"""
BiteIQ Backend — Middleware for file upload to Snowflake stage + agent:run proxy.
Run: python backend.py
Requires: pip install flask flask-cors snowflake-snowpark-python
"""
import os, json, tempfile
from pathlib import Path
from flask import Flask, request, jsonify
from flask_cors import CORS
from snowflake.snowpark import Session

app = Flask(__name__)
CORS(app)  # Allow React frontend to call this

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

# Extensions to rename to .txt before staging
CONVERT_TO_TXT = {'.csv', '.json', '.md', '.tsv', '.log', '.xml', '.yaml', '.yml'}


@app.route("/upload", methods=["POST"])
def upload_file():
    """Upload a file to @DOC_UPLOADS stage. Returns the staged path."""
    if "file" not in request.files:
        return jsonify({"error": "No file provided"}), 400

    f = request.files["file"]
    original_name = f.filename
    ext = Path(original_name).suffix.lower()

    # Convert unsupported extensions to .txt
    if ext in CONVERT_TO_TXT:
        stage_name = Path(original_name).with_suffix('.txt').name
    else:
        stage_name = original_name

    # Save to temp and PUT to stage
    with tempfile.NamedTemporaryFile(delete=False, suffix=f"_{stage_name}") as tmp:
        f.save(tmp.name)
        tmp_path = tmp.name

    try:
        session.file.put(
            tmp_path,
            "@DOC_UPLOADS/uploads",
            auto_compress=False,
            overwrite=True
        )
        staged_path = f"uploads/{Path(tmp_path).name}"
        return jsonify({"staged_path": staged_path, "original_name": original_name})
    finally:
        os.unlink(tmp_path)


@app.route("/ask", methods=["POST"])
def ask_agent():
    """
    Call the agent with optional file context.
    Body: { "question": "...", "staged_files": ["uploads/foo.txt"] }
    """
    data = request.json
    question = data.get("question", "")
    staged_files = data.get("staged_files", [])

    # Build content blocks
    content_blocks = []
    if staged_files:
        file_list = ", ".join(f"'{f}'" for f in staged_files)
        content_blocks.append({
            "type": "text",
            "text": f"[The user has uploaded the following files to the document stage: {file_list}. "
                    f"Use the read_document tool to access them if relevant to the question.]"
        })
    content_blocks.append({"type": "text", "text": question})

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
        return jsonify(resp.json())


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "user": session.sql("SELECT CURRENT_USER()").collect()[0][0]})


if __name__ == "__main__":
    print("BiteIQ backend running on http://localhost:5001")
    print("Endpoints:")
    print("  POST /upload  — upload file to stage (multipart form)")
    print("  POST /ask     — call agent with question + staged files")
    print("  GET  /health  — check connection")
    app.run(port=5001, debug=True)
