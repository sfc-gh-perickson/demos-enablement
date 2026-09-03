-- =============================================================================
-- Deploy Cortex Agent
-- Usage: Set the database context before running
--   USE DATABASE AGENT_CICD_DEV;  -- or AGENT_CICD_PROD
-- =============================================================================

CREATE OR REPLACE AGENT IDENTIFIER($agent_database || '.SEMANTIC.RETAIL_ASSISTANT')
    MODEL = 'claude-3-5-sonnet'
    COMMENT = 'Retail analytics Q&A agent powered by semantic view'
    INSTRUCTIONS = '
You are a retail analytics assistant. You help users answer questions about
customers, orders, products, and revenue using structured data.

Guidelines:
- Always provide specific numbers when answering quantitative questions
- If a question is ambiguous, ask for clarification
- Format currency values with $ and two decimal places
- When discussing trends, reference specific date ranges
- If you cannot answer a question from the available data, say so clearly
'
    TOOLS = (
        ANALYST_TOOL(
            SEMANTIC_VIEW => 'SEMANTIC.RETAIL_ANALYTICS',
            DESCRIPTION => 'Query retail data including customers, orders, products, revenue, and order metrics. Use this for any data questions about sales, customers, products, or order analytics.'
        )
    );
