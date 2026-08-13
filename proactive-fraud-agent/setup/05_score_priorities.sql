-- =============================================================================
-- 05_score_priorities.sql — Model inference → APP.PRIORITIES table
-- =============================================================================

USE WAREHOUSE FRAUD_DEMO_WH;
USE DATABASE FRAUD_DETECTION_DEMO;

-- =============================================================================
-- APP.PRIORITIES: Top fraud-risk customers for investigation
-- Uses pre-computed fraud probabilities from SHAP_SUMMARY (produced by training)
-- =============================================================================
CREATE OR REPLACE TABLE APP.PRIORITIES AS
SELECT
    ss.CUSTOMER_ID,
    ss.FRAUD_PROBABILITY,
    RANK() OVER (ORDER BY ss.FRAUD_PROBABILITY DESC) AS PRIORITY_RANK,
    ss.TOP_FACTORS,
    c.RISK_TIER,
    c.ACCOUNT_STATUS,
    'PENDING'::VARCHAR(20) AS INVESTIGATION_STATUS,
    CURRENT_TIMESTAMP() AS SCORED_AT
FROM FEATURES.SHAP_SUMMARY ss
JOIN RAW.CUSTOMERS c ON ss.CUSTOMER_ID = c.CUSTOMER_ID
WHERE ss.FRAUD_PROBABILITY > 0.6
ORDER BY ss.FRAUD_PROBABILITY DESC
LIMIT 100;

-- =============================================================================
-- Stored Procedure: REFRESH_PRIORITIES
-- Re-scores all customers using the registered model and refreshes priorities
-- =============================================================================
CREATE OR REPLACE PROCEDURE APP.REFRESH_PRIORITIES()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    -- Re-create priorities from latest SHAP_SUMMARY scores
    CREATE OR REPLACE TABLE APP.PRIORITIES AS
    SELECT
        ss.CUSTOMER_ID,
        ss.FRAUD_PROBABILITY,
        RANK() OVER (ORDER BY ss.FRAUD_PROBABILITY DESC) AS PRIORITY_RANK,
        ss.TOP_FACTORS,
        c.RISK_TIER,
        c.ACCOUNT_STATUS,
        'PENDING'::VARCHAR(20) AS INVESTIGATION_STATUS,
        CURRENT_TIMESTAMP() AS SCORED_AT
    FROM FEATURES.SHAP_SUMMARY ss
    JOIN RAW.CUSTOMERS c ON ss.CUSTOMER_ID = c.CUSTOMER_ID
    WHERE ss.FRAUD_PROBABILITY > 0.6
    ORDER BY ss.FRAUD_PROBABILITY DESC
    LIMIT 100;

    RETURN 'Priorities refreshed: ' || (SELECT COUNT(*) FROM APP.PRIORITIES)::VARCHAR || ' customers';
END;
$$;
