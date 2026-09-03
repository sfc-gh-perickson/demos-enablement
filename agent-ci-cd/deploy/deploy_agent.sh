#!/bin/bash
set -euo pipefail

# Deploy the Cortex Agent to the specified environment
# Usage: ./deploy/deploy_agent.sh <dev|prod>

ENV="${1:-dev}"

if [ "$ENV" = "prod" ]; then
    DATABASE="AGENT_CICD_PROD"
else
    DATABASE="AGENT_CICD_DEV"
fi

echo "Deploying Cortex Agent to $DATABASE..."

snow sql -q "
SET agent_database = '$DATABASE';

CREATE OR REPLACE AGENT $DATABASE.SEMANTIC.RETAIL_ASSISTANT
    MODEL = 'claude-3-5-sonnet'
    COMMENT = 'Retail analytics Q&A agent powered by semantic view'
    INSTRUCTIONS = '
You are a retail analytics assistant. You help users answer questions about
customers, orders, products, and revenue using structured data.

Guidelines:
- Always provide specific numbers when answering quantitative questions
- If a question is ambiguous, ask for clarification
- Format currency values with dollar sign and two decimal places
- When discussing trends, reference specific date ranges
- If you cannot answer a question from the available data, say so clearly
'
    TOOLS = (
        ANALYST_TOOL(
            SEMANTIC_VIEW => '$DATABASE.SEMANTIC.RETAIL_ANALYTICS',
            DESCRIPTION => 'Query retail data including customers, orders, products, revenue, and order metrics.'
        )
    );
" --connection default

echo "Agent deployed successfully to $DATABASE.SEMANTIC.RETAIL_ASSISTANT"
