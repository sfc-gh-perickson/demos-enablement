-- =============================================================================
-- 06_agent_investigate.sql — Cortex Agent + Investigation Loop
-- =============================================================================

USE WAREHOUSE FRAUD_DEMO_WH;
USE DATABASE FRAUD_DETECTION_DEMO;

-- =============================================================================
-- 1. INVESTIGATION_REPORTS table
-- =============================================================================
CREATE OR REPLACE TABLE APP.INVESTIGATION_REPORTS (
    REPORT_ID VARCHAR DEFAULT UUID_STRING(),
    CUSTOMER_ID VARCHAR,
    PRIORITY_RANK INT,
    FRAUD_PROBABILITY FLOAT,
    TOP_FACTORS VARIANT,
    INVESTIGATION_REPORT VARCHAR(16000),
    RECOMMENDED_ACTION VARCHAR(50),
    THREAD_ID VARCHAR,
    PARENT_MESSAGE_ID VARCHAR,
    INVESTIGATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- =============================================================================
-- 2. Create semantic view for the agent's Cortex Analyst tool
-- Uses correct DDL syntax (alias AS physical_table pattern)
-- =============================================================================
CREATE OR REPLACE SEMANTIC VIEW APP.FRAUD_SEMANTIC_VIEW
  TABLES (
    priorities AS FRAUD_DETECTION_DEMO.APP.PRIORITIES
      PRIMARY KEY (CUSTOMER_ID)
      COMMENT = 'Top fraud risk customers ranked by ML probability',
    reports AS FRAUD_DETECTION_DEMO.APP.INVESTIGATION_REPORTS
      COMMENT = 'Agent investigation reports with thread IDs',
    transactions AS FRAUD_DETECTION_DEMO.RAW.TRANSACTIONS
      PRIMARY KEY (TRANSACTION_ID)
      COMMENT = 'Raw transaction data',
    customers AS FRAUD_DETECTION_DEMO.RAW.CUSTOMERS
      PRIMARY KEY (CUSTOMER_ID)
      COMMENT = 'Customer profiles'
  )
  RELATIONSHIPS (
    priorities_to_customers AS priorities (CUSTOMER_ID) REFERENCES customers,
    reports_to_priorities AS reports (CUSTOMER_ID) REFERENCES priorities,
    transactions_to_customers AS transactions (CUSTOMER_ID) REFERENCES customers
  )
  FACTS (
    priorities.fraud_prob AS FRAUD_PROBABILITY COMMENT = 'ML predicted fraud probability 0 to 1',
    priorities.priority_rnk AS PRIORITY_RANK COMMENT = 'Priority rank 1 is highest',
    transactions.txn_amount AS TRANSACTION_AMOUNT COMMENT = 'Transaction amount in dollars',
    customers.credit_lim AS CREDIT_LIMIT COMMENT = 'Customer credit limit'
  )
  DIMENSIONS (
    priorities.cust_id AS CUSTOMER_ID COMMENT = 'Customer identifier',
    priorities.risk AS RISK_TIER COMMENT = 'Customer risk tier HIGH MEDIUM LOW',
    priorities.inv_status AS INVESTIGATION_STATUS COMMENT = 'PENDING, AGENT_REVIEWED, ESCALATED, MONITORING, or CLEARED',
    reports.action AS RECOMMENDED_ACTION COMMENT = 'ESCALATE MONITOR BLOCK CLEAR',
    reports.tid AS THREAD_ID COMMENT = 'Conversation thread ID for follow-up',
    transactions.chan AS CHANNEL COMMENT = 'POS ONLINE or MOBILE',
    transactions.cust AS CUSTOMER_ID COMMENT = 'Customer who transacted',
    customers.cust_risk AS RISK_TIER COMMENT = 'Risk classification',
    customers.cust_status AS ACCOUNT_STATUS COMMENT = 'ACTIVE or SUSPENDED'
  )
  COMMENT = 'Semantic view for fraud investigation agent';

-- =============================================================================
-- 3. Create the Cortex Agent (uses 'auto' model for region compatibility)
-- =============================================================================
CREATE OR REPLACE AGENT APP.FRAUD_INVESTIGATOR
FROM SPECIFICATION $$
models:
  orchestration: auto
instructions:
  response: |
    You are a senior fraud investigation analyst. When given a customer case:
    1. Analyze SHAP risk factors to identify the likely fraud pattern
    2. Query transaction history for suspicious behaviors
    3. Assess severity based on probability score and pattern type
    4. Provide a clear, actionable recommendation

    Fraud patterns: VELOCITY (rapid transactions), STRUCTURING (amounts just under 10K),
    GEO_ANOMALY (impossible travel), RETURN_ABUSE (excessive returns),
    ACCOUNT_TAKEOVER (dormant account suddenly active with new devices)

    Always conclude with exactly one of: ESCALATE, MONITOR, BLOCK, or CLEAR.
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: fraud_data
      description: Query fraud priorities, investigation reports, transactions, and customer data
tool_resources:
  fraud_data:
    semantic_view: FRAUD_DETECTION_DEMO.APP.FRAUD_SEMANTIC_VIEW
    execution_environment:
      type: warehouse
      warehouse: FRAUD_DEMO_WH
$$;

-- =============================================================================
-- 4. Python stored procedure: RUN_INVESTIGATION_BATCH
-- =============================================================================
CREATE OR REPLACE PROCEDURE APP.RUN_INVESTIGATION_BATCH(BATCH_SIZE INT)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run_batch'
EXECUTE AS CALLER
AS
$$
import json
from snowflake.snowpark import Session

def run_batch(session, batch_size):
    # Get pending priorities (batch_size is an int from SQL, safe to interpolate)
    pending = session.sql(f"""
        SELECT CUSTOMER_ID, PRIORITY_RANK, FRAUD_PROBABILITY, TOP_FACTORS
        FROM FRAUD_DETECTION_DEMO.APP.PRIORITIES
        WHERE INVESTIGATION_STATUS = 'PENDING'
        ORDER BY PRIORITY_RANK
        LIMIT {int(batch_size)}
    """).collect()

    results = []
    for row in pending:
        customer_id = row['CUSTOMER_ID']
        priority_rank = row['PRIORITY_RANK']
        fraud_prob = row['FRAUD_PROBABILITY']
        top_factors = row['TOP_FACTORS']

        # Build investigation prompt
        prompt = f"""Investigate customer {customer_id} for potential fraud.

Fraud Probability: {fraud_prob:.4f}
Priority Rank: {priority_rank}
Top Risk Factors (SHAP analysis):
{top_factors}

Please analyze:
1. What fraud pattern do these risk factors suggest?
2. What is the severity level (CRITICAL/HIGH/MEDIUM/LOW)?
3. What specific transaction behaviors are concerning?
4. What is your recommended action (ESCALATE/MONITOR/BLOCK/CLEAR)?

Provide a concise investigation report."""

        try:
            # Call DATA_AGENT_RUN with thread creation for conversation continuity
            request_body = json.dumps({
                "messages": [{"role": "user", "content": [{"type": "text", "text": prompt}]}]
            })

            agent_result = session.sql("""
                SELECT TRY_PARSE_JSON(
                    SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
                        'FRAUD_DETECTION_DEMO.APP.FRAUD_INVESTIGATOR',
                        ?,
                        TRUE
                    )
                ) AS response
            """, params=[request_body]).collect()

            response_json = agent_result[0]['RESPONSE'] if agent_result else None
            response_text = "Investigation failed"
            thread_id = None
            parent_msg_id = None

            if response_json:
                # Parse agent response
                if isinstance(response_json, str):
                    response_json = json.loads(response_json)
                # Extract text from content array
                content = response_json.get('content', [])
                text_parts = [c['text'] for c in content if c.get('type') == 'text']
                response_text = '\n'.join(text_parts) if text_parts else str(response_json)
                # Extract thread_id and message_id from metadata
                metadata = response_json.get('metadata', {})
                thread_id = str(metadata.get('thread_id', ''))
                parent_msg_id = str(metadata.get('message_id', metadata.get('run_id', '')))

            # Fallback thread_id if agent doesn't return one
            if not thread_id:
                tid_result = session.sql("SELECT UUID_STRING() AS tid").collect()
                thread_id = tid_result[0]['TID']
                parent_msg_id = thread_id + '-msg-1'

            # Extract recommended action from response
            action = 'MONITOR'
            response_upper = response_text.upper()
            if 'ESCALATE' in response_upper:
                action = 'ESCALATE'
            elif 'BLOCK' in response_upper:
                action = 'BLOCK'
            elif 'CLEAR' in response_upper:
                action = 'CLEAR'

            # Insert report using parameterized query
            top_factors_json = json.dumps(
                json.loads(top_factors) if isinstance(top_factors, str) else top_factors
            ) if top_factors else '[]'

            session.sql("""
                INSERT INTO FRAUD_DETECTION_DEMO.APP.INVESTIGATION_REPORTS
                (CUSTOMER_ID, PRIORITY_RANK, FRAUD_PROBABILITY, TOP_FACTORS,
                 INVESTIGATION_REPORT, RECOMMENDED_ACTION, THREAD_ID, PARENT_MESSAGE_ID)
                SELECT ?, ?, ?, PARSE_JSON(?), ?, ?, ?, ?
            """, params=[
                customer_id, priority_rank, fraud_prob, top_factors_json,
                response_text[:15000], action, thread_id, parent_msg_id
            ]).collect()

            # Update priority status — agent has reviewed, awaiting human action
            session.sql("""
                UPDATE FRAUD_DETECTION_DEMO.APP.PRIORITIES
                SET INVESTIGATION_STATUS = 'AGENT_REVIEWED'
                WHERE CUSTOMER_ID = ?
            """, params=[customer_id]).collect()

            results.append({"customer_id": customer_id, "status": "investigated", "action": action})

        except Exception as e:
            results.append({"customer_id": customer_id, "status": "error", "error": str(e)[:200]})

    return {"investigated": len(results), "results": results}
$$;

-- =============================================================================
-- 5. Task: Run investigation batch every 5 minutes
-- =============================================================================
CREATE OR REPLACE TASK APP.INVESTIGATE_TASK
    WAREHOUSE = FRAUD_DEMO_WH
    SCHEDULE = '5 MINUTE'
    COMMENT = 'Investigates pending fraud priorities via Cortex agent'
AS
    CALL APP.RUN_INVESTIGATION_BATCH(10);