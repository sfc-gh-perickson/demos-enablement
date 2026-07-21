# Cortex Agent Document Context - Speaker Notes

## Account Context

This presentation covers the architecture pattern for enabling file/document uploads in custom frontends that call the Cortex Agent REST API. The customer has a multi-agent strategy deployed via a custom React app hitting the agents API directly. Their primary agent is live across leadership. The request is to allow users to attach files (competitive analysis PDFs, market research, data exports) during conversations for contextual Q&A -- similar to the "+" button in Snowflake Intelligence, but in their custom UI.

---

## Slide: The Problem

**Talking points:**
- The agent:run API accepts `messages` with `content` blocks, but the only input types are `text` (and limited `image` for newer Claude models).
- There is no `type: "file"` -- raw binary upload is not a supported primitive.
- Snowflake Intelligence's file attachment uses a proprietary internal pipeline (backend upload + processing service) that is not publicly documented or reusable.
- This is a common ask from customers building custom frontends. The pattern we're presenting is the recommended approach.

**Internal context:**
- Native file support in agent:run is not on a near-term public roadmap as of July 2026.
- The SI/CoWork "+" feature uses internal stage paths and a separate processing service -- it's deeply coupled to the SI frontend and not extractable as an API.
- If the customer asks "when will file upload be natively supported?" -- answer honestly that it's not on a committed timeline, and that the UDF tool pattern is the recommended approach for custom frontends.

---

## Slide: Architecture

**Talking points:**
- The key architectural decision: give the agent a tool to read files, rather than injecting content client-side.
- The middleware becomes stateless: upload + hint. No parsing logic, no file-type routing, no content injection.
- The agent decides autonomously whether to read the file based on the question context.
- This means: if a user asks something unrelated after uploading a file, the tool is never invoked (saves cost).

**Why this is better than client-side injection:**
- Agent autonomy -- it reads the file only when relevant
- No context window waste on irrelevant turns
- Simpler middleware -- fewer failure modes
- Works naturally with threads (agent retains file knowledge across turns)

---

## Slide: The UDF Tool

**Talking points:**
- A SQL UDF is the simplest approach. It calls AI_PARSE_DOCUMENT internally.
- Registered as a `generic` tool in the agent spec with an `input_schema` that takes a filename string.
- The agent sees it as: "I have a tool called read_document that takes a filename and returns text content."
- LAYOUT mode preserves tables, headers, and structure -- important for PDFs with complex formatting.

**Technical details to know:**
- SQL UDF (not a stored procedure) -- the agent's generic tool framework calls UDFs, not procedures.
- The UDF must use fully-qualified stage paths (`@DB.SCHEMA.STAGE`) since it runs in the warehouse context.
- AI_PARSE_DOCUMENT supports: PDF, DOCX, PPTX, TXT, HTML, JPEG, PNG, TIF.
- It does NOT support .csv or .json -- hence the rename pattern in the middleware.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_parse_document
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-run

---

## Slide: Middleware Pattern

**Talking points:**
- Walk through the three steps: upload, hint, forward.
- The "hint" is just a text content block prepended to the user message. It's not a special API field.
- The wording matters: tell the agent the filename and that it should use `read_document` to access it.
- Thread ID and parent_message_id are passed through for multi-turn support.

**Implementation notes:**
- In a React/Node backend: the upload endpoint does `PUT` to stage via the SQL API, then constructs the agent:run request.
- The hint is a single short string (~100 chars) -- negligible token cost.
- Multiple files can be listed in one hint: "User uploaded 'a.txt', 'b.pdf'."

---

## Slide: File Type Handling

**Talking points:**
- AI_PARSE_DOCUMENT doesn't support .csv/.json extensions, but it handles .txt perfectly.
- The "conversion" is literally just renaming the file extension before PUT. Zero content transformation.
- This is a middleware responsibility -- the UDF doesn't need to know about it.
- For images: AI_PARSE_DOCUMENT extracts visible text via OCR. For richer image understanding (charts, diagrams), consider a separate UDF using AI_COMPLETE with multimodal models.

**If asked about PDFs specifically:**
- AI_PARSE_DOCUMENT in LAYOUT mode handles multi-page PDFs with tables, headers, and structure.
- Use `page_split: true` for large documents so the UDF can return page-by-page.
- Max file size: 100 MB. Max pages: 2,000.

---

## Slide: Multi-Turn Conversations

**Talking points:**
- Threads are created via `POST /api/v2/cortex/threads`.
- First message: `parent_message_id: 0` (start of thread). Include the file hint.
- Subsequent messages: `parent_message_id: <assistant_message_id from previous response>`. No file hint needed.
- The agent retains context of the document across the thread -- it saw the tool result in turn 1 and can reference it.

**Important caveats:**
- Thread compaction: after many turns, the thread summary may lose fine-grained document details. For long conversations, the agent may need to re-read the file.
- The middleware should track `thread_id` and `parent_message_id` in its session store (Redis, DynamoDB, etc.).

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-threads

---

## Slide: Production Considerations

**Talking points:**
- Context window: most models have 128K-200K token windows. A 50-page PDF might be 30-40K tokens. Very large docs need chunking.
- Cost: AI_PARSE_DOCUMENT bills per page. But since the agent only calls the tool when needed, you don't pay for irrelevant turns.
- Caching: store parsed content in a table keyed by file hash + stage path. Modify the UDF to check cache first.
- Security: the UDF hardcodes the stage path, preventing path traversal. Per-user subdirectories add isolation.

**If asked about Cortex Search as an alternative:**
- Cortex Search is better for: large document corpuses, repeated Q&A over the same docs, semantic retrieval over hundreds of files.
- The UDF tool pattern is better for: one-off file attachments during a conversation, real-time uploads, documents that change frequently.
- They can use both: Cortex Search for the permanent knowledge base, UDF tool for ad-hoc uploads.

---

## Slide: Next Steps

**Talking points:**
- The lab is fully runnable -- setup.sql creates everything, notebook walks through the pattern end-to-end.
- For their React backend integration: the key endpoint is the file upload handler that does PUT + agent:run call.
- Caching is optional but recommended for production scale.
- Cortex Search is the natural evolution if they build a large document library for their agent.
