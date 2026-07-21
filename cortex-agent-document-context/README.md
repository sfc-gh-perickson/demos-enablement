# Cortex Agent Document Context Lab

Hands-on lab demonstrating how to build middleware that enables file/document uploads in a custom frontend calling the Cortex Agent REST API.

## Scenario

FreshBite (fictional QSR chain) has deployed **BiteIQ**, an executive insights agent accessed via a custom React frontend. Leadership wants users to attach documents (competitive analysis PDFs, market research, lease data) during conversations for contextual Q&A.

The Cortex Agent API does not natively accept file attachments (`type: "file"` is not supported). This lab teaches the middleware pattern:

1. Accept the file in your frontend
2. Upload it to a Snowflake internal stage
3. Extract content with `AI_PARSE_DOCUMENT`
4. Inject the extracted text into the `agent:run` request as a `type: "text"` content block

## Prerequisites

- Snowflake account with `ACCOUNTADMIN` (or equivalent) for setup
- `SNOWFLAKE.CORTEX_USER` database role granted
- Cross-region inference enabled (for agent LLM calls)
- Python environment with `snowflake-snowpark-python` and `requests`

## Quick Start

1. Run `lab/setup.sql` as ACCOUNTADMIN
2. Open `lab/cortex-agent-document-context-lab.ipynb`
3. Execute cells sequentially

## What's Covered

| Section | Topic |
|---------|-------|
| 1 | API landscape — what's supported, what's not |
| 2 | Uploading files to internal stage |
| 3 | Parsing documents with AI_PARSE_DOCUMENT |
| 4 | Injecting content into agent:run requests |
| 5 | Handling different file types (PDF, CSV, images) |
| 6 | Reusable production middleware pattern |
| 7 | Production considerations (caching, security, context limits) |

## Documentation

- [Cortex Agent Run API](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-run)
- [AI_PARSE_DOCUMENT](https://docs.snowflake.com/en/sql-reference/functions/ai_parse_document)
- [Cortex AI Multimodal](https://docs.snowflake.com/en/user-guide/snowflake-cortex/ai-multimodal)
