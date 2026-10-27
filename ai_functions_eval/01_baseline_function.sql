CREATE AI FUNCTION AI_FUNCTIONS_EVAL_DEMO.EVAL.TRIAGE_TICKET(TICKET_TEXT VARCHAR)
RETURNS VARIANT
COMMENT = 'Extract structured fields, sentiment, and an escalation flag from a support ticket'
AS
$$
    SELECT AI_COMPLETE(
    model=>'claude-sonnet-4-6',
    messages=>ARRAY_CONSTRUCT(
        OBJECT_CONSTRUCT(
            'role', 'system',
            'content', 'You are a customer support assistant. Read the ticket and fill in the requested fields.'
        ),
        OBJECT_CONSTRUCT(
            'role', 'user',
            'content', 'Ticket: ' || TICKET_TEXT
        )
    ),
    response_format=>PARSE_JSON('{
    "type": "json",
    "schema": {
        "type": "object",
        "properties": {
            "product": {
                "type": "string",
                "description": "product name"
            },
            "issue_type": {
                "type": "string",
                "description": "type of issue"
            },
            "sentiment": {
                "type": "string",
                "description": "customer sentiment"
            },
            "requested_action": {
                "type": "string",
                "description": "what the customer wants"
            },
            "order_id": {
                "type": "string",
                "description": "order number if present"
            },
            "escalation_flag": {
                "type": "boolean",
                "description": "should this be escalated"
            }
        },
        "required": [
            "product",
            "issue_type",
            "sentiment",
            "requested_action",
            "order_id",
            "escalation_flag"
        ],
        "additionalProperties": false
    }
}')
)
$$;
