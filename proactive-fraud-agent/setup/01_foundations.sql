-- =============================================================================
-- 01_foundations.sql — Database, schemas, warehouse, and synthetic data
-- REDESIGNED: Realistic overlapping distributions for meaningful ML/investigation
-- =============================================================================

-- Database
CREATE OR REPLACE DATABASE FRAUD_DETECTION_DEMO;

CREATE SCHEMA FRAUD_DETECTION_DEMO.RAW;
CREATE SCHEMA FRAUD_DETECTION_DEMO.CURATED;
CREATE SCHEMA FRAUD_DETECTION_DEMO.FEATURES;
CREATE SCHEMA FRAUD_DETECTION_DEMO.MODELS;
CREATE SCHEMA FRAUD_DETECTION_DEMO.APP;

CREATE WAREHOUSE IF NOT EXISTS FRAUD_DEMO_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;

USE WAREHOUSE FRAUD_DEMO_WH;
USE DATABASE FRAUD_DETECTION_DEMO;
USE SCHEMA RAW;

-- =============================================================================
-- CUSTOMERS (10K)
-- 500 known fraud, 300 "gray zone" (suspicious-looking but legitimate), 9200 normal
-- =============================================================================
CREATE OR REPLACE TABLE RAW.CUSTOMERS (
    CUSTOMER_ID VARCHAR(20),
    FIRST_NAME VARCHAR(50),
    LAST_NAME VARCHAR(50),
    EMAIL VARCHAR(100),
    PHONE VARCHAR(20),
    ADDRESS_CITY VARCHAR(50),
    ADDRESS_STATE VARCHAR(2),
    ADDRESS_COUNTRY VARCHAR(3),
    HOME_LAT FLOAT,
    HOME_LON FLOAT,
    ACCOUNT_OPEN_DATE DATE,
    ACCOUNT_STATUS VARCHAR(10),
    RISK_TIER VARCHAR(10),
    CREDIT_LIMIT FLOAT,
    CUSTOMER_SEGMENT VARCHAR(20),  -- NORMAL, FRAUD, GRAY_ZONE
    FRAUD_PATTERN_TYPE VARCHAR(30)
);

INSERT INTO RAW.CUSTOMERS
WITH customer_gen AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS rn,
        'CUST-' || LPAD(ROW_NUMBER() OVER (ORDER BY SEQ4())::VARCHAR, 6, '0') AS customer_id
    FROM TABLE(GENERATOR(ROWCOUNT => 10000))
)
SELECT
    customer_id,
    'First_' || rn AS first_name,
    'Last_' || rn AS last_name,
    'customer' || rn || '@email.com' AS email,
    '+1-555-' || LPAD((rn % 10000)::VARCHAR, 4, '0') AS phone,
    CASE MOD(rn, 10)
        WHEN 0 THEN 'New York' WHEN 1 THEN 'Los Angeles' WHEN 2 THEN 'Chicago'
        WHEN 3 THEN 'Houston' WHEN 4 THEN 'Phoenix' WHEN 5 THEN 'Philadelphia'
        WHEN 6 THEN 'San Antonio' WHEN 7 THEN 'San Diego' WHEN 8 THEN 'Dallas'
        ELSE 'Austin'
    END AS address_city,
    CASE MOD(rn, 10)
        WHEN 0 THEN 'NY' WHEN 1 THEN 'CA' WHEN 2 THEN 'IL'
        WHEN 3 THEN 'TX' WHEN 4 THEN 'AZ' WHEN 5 THEN 'PA'
        WHEN 6 THEN 'TX' WHEN 7 THEN 'CA' WHEN 8 THEN 'TX'
        ELSE 'TX'
    END AS address_state,
    'USA' AS address_country,
    ROUND(30.0 + UNIFORM(0::FLOAT, 15::FLOAT, RANDOM()), 4) AS home_lat,
    ROUND(-120.0 + UNIFORM(0::FLOAT, 50::FLOAT, RANDOM()), 4) AS home_lon,
    DATEADD('day', -UNIFORM(30, 3650, RANDOM()), CURRENT_DATE()) AS account_open_date,
    CASE WHEN rn <= 500 AND UNIFORM(0, 100, RANDOM()) < 20 THEN 'SUSPENDED'
         WHEN UNIFORM(0, 100, RANDOM()) < 5 THEN 'REVIEW'
         ELSE 'ACTIVE' END AS account_status,
    -- Risk tier: fraud customers aren't all HIGH (some slip through as LOW)
    CASE WHEN rn <= 500 THEN
            CASE WHEN UNIFORM(0, 100, RANDOM()) < 40 THEN 'HIGH'
                 WHEN UNIFORM(0, 100, RANDOM()) < 60 THEN 'MEDIUM'
                 ELSE 'LOW' END
         WHEN rn <= 800 THEN  -- gray zone: often flagged MEDIUM
            CASE WHEN UNIFORM(0, 100, RANDOM()) < 30 THEN 'HIGH'
                 WHEN UNIFORM(0, 100, RANDOM()) < 70 THEN 'MEDIUM'
                 ELSE 'LOW' END
         ELSE
            CASE WHEN UNIFORM(0, 100, RANDOM()) < 5 THEN 'HIGH'
                 WHEN UNIFORM(0, 100, RANDOM()) < 20 THEN 'MEDIUM'
                 ELSE 'LOW' END
    END AS risk_tier,
    -- Credit limits vary: fraud customers can have high limits (account takeover)
    ROUND(UNIFORM(2000, 75000, RANDOM()), 2) AS credit_limit,
    -- Segment
    CASE WHEN rn <= 500 THEN 'FRAUD'
         WHEN rn <= 800 THEN 'GRAY_ZONE'
         ELSE 'NORMAL' END AS customer_segment,
    -- Fraud patterns (only for fraud customers, not all get the same one)
    CASE
        WHEN rn <= 100 THEN 'VELOCITY'
        WHEN rn <= 200 THEN 'STRUCTURING'
        WHEN rn <= 300 THEN 'GEO_ANOMALY'
        WHEN rn <= 400 THEN 'RETURN_ABUSE'
        WHEN rn <= 500 THEN 'ACCOUNT_TAKEOVER'
        ELSE NULL
    END AS fraud_pattern_type
FROM customer_gen;

-- =============================================================================
-- MERCHANTS (1K)
-- =============================================================================
CREATE OR REPLACE TABLE RAW.MERCHANTS (
    MERCHANT_ID VARCHAR(20),
    MERCHANT_NAME VARCHAR(100),
    CATEGORY VARCHAR(30),
    RISK_SCORE FLOAT,
    COUNTRY VARCHAR(3),
    CITY VARCHAR(50),
    MERCHANT_LAT FLOAT,
    MERCHANT_LON FLOAT,
    IS_HIGH_RISK BOOLEAN,
    DAYS_ACTIVE INT
);

INSERT INTO RAW.MERCHANTS
WITH merchant_gen AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS rn,
        'MERCH-' || LPAD(ROW_NUMBER() OVER (ORDER BY SEQ4())::VARCHAR, 4, '0') AS merchant_id
    FROM TABLE(GENERATOR(ROWCOUNT => 1000))
)
SELECT
    merchant_id,
    'Merchant_' || rn AS merchant_name,
    CASE MOD(rn, 10)
        WHEN 0 THEN 'GROCERY' WHEN 1 THEN 'ELECTRONICS' WHEN 2 THEN 'RESTAURANT'
        WHEN 3 THEN 'GAS_STATION' WHEN 4 THEN 'ONLINE_RETAIL' WHEN 5 THEN 'TRAVEL'
        WHEN 6 THEN 'ENTERTAINMENT' WHEN 7 THEN 'SERVICES' WHEN 8 THEN 'CRYPTO_EXCHANGE'
        ELSE 'WIRE_TRANSFER'
    END AS category,
    ROUND(UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()), 3) AS risk_score,
    CASE WHEN rn <= 700 THEN 'USA'
         WHEN rn <= 800 THEN 'GBR'
         WHEN rn <= 900 THEN 'NGA'
         ELSE 'RUS' END AS country,
    CASE MOD(rn, 6)
        WHEN 0 THEN 'New York' WHEN 1 THEN 'London' WHEN 2 THEN 'Lagos'
        WHEN 3 THEN 'Moscow' WHEN 4 THEN 'Los Angeles' ELSE 'Miami'
    END AS city,
    ROUND(30.0 + UNIFORM(0::FLOAT, 30::FLOAT, RANDOM()), 4) AS merchant_lat,
    ROUND(-120.0 + UNIFORM(0::FLOAT, 120::FLOAT, RANDOM()), 4) AS merchant_lon,
    CASE WHEN rn > 850 THEN TRUE
         WHEN UNIFORM(0, 100, RANDOM()) < 8 THEN TRUE
         ELSE FALSE END AS is_high_risk,
    UNIFORM(1, 3000, RANDOM()) AS days_active
FROM merchant_gen;

-- =============================================================================
-- TRANSACTIONS (500K) — Realistic overlapping distributions
-- Key change: fraud customers also have NORMAL transactions mixed in,
-- and normal customers occasionally have suspicious-looking activity
-- =============================================================================
CREATE OR REPLACE TABLE RAW.TRANSACTIONS (
    TRANSACTION_ID VARCHAR(30),
    CUSTOMER_ID VARCHAR(20),
    MERCHANT_ID VARCHAR(20),
    TRANSACTION_AMOUNT FLOAT,
    TRANSACTION_TIMESTAMP TIMESTAMP_NTZ,
    CHANNEL VARCHAR(10),
    TRANSACTION_TYPE VARCHAR(15),
    CURRENCY VARCHAR(3),
    IS_INTERNATIONAL BOOLEAN,
    TRANSACTION_LAT FLOAT,
    TRANSACTION_LON FLOAT,
    DEVICE_TYPE VARCHAR(15),
    IS_FRAUD BOOLEAN DEFAULT FALSE,
    FRAUD_PATTERN VARCHAR(30)
);

-- =============================================================================
-- NORMAL transactions for ALL customers (400K)
-- Even fraud customers have legitimate baseline activity
-- =============================================================================
INSERT INTO RAW.TRANSACTIONS
WITH txn_gen AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS rn,
        'TXN-N-' || LPAD(ROW_NUMBER() OVER (ORDER BY SEQ4())::VARCHAR, 8, '0') AS transaction_id
    FROM TABLE(GENERATOR(ROWCOUNT => 400000))
)
SELECT
    transaction_id,
    -- ALL customers get normal transactions (including fraud customers)
    'CUST-' || LPAD(UNIFORM(1, 10000, RANDOM())::VARCHAR, 6, '0') AS customer_id,
    'MERCH-' || LPAD(UNIFORM(1, 700, RANDOM())::VARCHAR, 4, '0') AS merchant_id,
    -- Normal amount distribution: median ~$50, long tail to $500
    ROUND(ABS(NORMAL(60, 40, RANDOM())) + 5, 2) AS transaction_amount,
    DATEADD('second', -UNIFORM(0, 2592000, RANDOM()), CURRENT_TIMESTAMP()) AS transaction_timestamp,
    CASE UNIFORM(1, 10, RANDOM())
        WHEN 1 THEN 'ATM' WHEN 2 THEN 'ATM'
        WHEN 3 THEN 'ONLINE' WHEN 4 THEN 'ONLINE' WHEN 5 THEN 'ONLINE'
        WHEN 6 THEN 'MOBILE' WHEN 7 THEN 'MOBILE'
        ELSE 'POS'
    END AS channel,
    CASE UNIFORM(1, 5, RANDOM())
        WHEN 1 THEN 'PURCHASE' WHEN 2 THEN 'PURCHASE' WHEN 3 THEN 'PURCHASE'
        WHEN 4 THEN 'WITHDRAWAL' ELSE 'TRANSFER'
    END AS transaction_type,
    'USD' AS currency,
    CASE WHEN UNIFORM(0, 100, RANDOM()) < 3 THEN TRUE ELSE FALSE END AS is_international,
    ROUND(30.0 + UNIFORM(0::FLOAT, 15::FLOAT, RANDOM()), 4) AS transaction_lat,
    ROUND(-120.0 + UNIFORM(0::FLOAT, 50::FLOAT, RANDOM()), 4) AS transaction_lon,
    CASE UNIFORM(1, 4, RANDOM()) WHEN 1 THEN 'MOBILE' WHEN 2 THEN 'DESKTOP' WHEN 3 THEN 'TERMINAL' ELSE 'TABLET' END AS device_type,
    FALSE AS is_fraud,
    NULL AS fraud_pattern
FROM txn_gen;

-- =============================================================================
-- VELOCITY fraud (8K txns from customers 1-100)
-- BUT: not all at once — clusters spread over several days, mixed with gaps
-- =============================================================================
INSERT INTO RAW.TRANSACTIONS
WITH velocity_gen AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS rn,
        'TXN-V-' || LPAD(ROW_NUMBER() OVER (ORDER BY SEQ4())::VARCHAR, 7, '0') AS transaction_id
    FROM TABLE(GENERATOR(ROWCOUNT => 8000))
)
SELECT
    transaction_id,
    'CUST-' || LPAD((MOD(rn - 1, 100) + 1)::VARCHAR, 6, '0') AS customer_id,
    'MERCH-' || LPAD(UNIFORM(1, 1000, RANDOM())::VARCHAR, 4, '0') AS merchant_id,
    -- Amounts overlap with normal: $20-$300 (normal customers also spend this much)
    ROUND(UNIFORM(20::FLOAT, 300::FLOAT, RANDOM()), 2) AS transaction_amount,
    -- Clustered in bursts: 3-8 txns within 2 hours, then gaps of hours
    DATEADD('minute',
        -(MOD(rn, 8) * UNIFORM(5, 20, RANDOM())) - (FLOOR(rn/8) * UNIFORM(180, 720, RANDOM())),
        DATEADD('day', -UNIFORM(0, 14, RANDOM()), CURRENT_TIMESTAMP())
    ) AS transaction_timestamp,
    CASE UNIFORM(1, 3, RANDOM()) WHEN 1 THEN 'ONLINE' WHEN 2 THEN 'MOBILE' ELSE 'POS' END AS channel,
    'PURCHASE' AS transaction_type,
    'USD' AS currency,
    CASE WHEN UNIFORM(0, 100, RANDOM()) < 10 THEN TRUE ELSE FALSE END AS is_international,
    ROUND(30.0 + UNIFORM(0::FLOAT, 15::FLOAT, RANDOM()), 4) AS transaction_lat,
    ROUND(-120.0 + UNIFORM(0::FLOAT, 50::FLOAT, RANDOM()), 4) AS transaction_lon,
    CASE UNIFORM(1, 3, RANDOM()) WHEN 1 THEN 'MOBILE' WHEN 2 THEN 'DESKTOP' ELSE 'TABLET' END AS device_type,
    -- Only 60-80% are actually fraud (some bursts are legitimate shopping sprees)
    CASE WHEN UNIFORM(0, 100, RANDOM()) < 70 THEN TRUE ELSE FALSE END AS is_fraud,
    'VELOCITY' AS fraud_pattern
FROM velocity_gen;

-- =============================================================================
-- STRUCTURING fraud (8K txns from customers 101-200)
-- Amounts cluster $5K-$12K (overlaps with legitimate large purchases)
-- =============================================================================
INSERT INTO RAW.TRANSACTIONS
WITH struct_gen AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS rn,
        'TXN-S-' || LPAD(ROW_NUMBER() OVER (ORDER BY SEQ4())::VARCHAR, 7, '0') AS transaction_id
    FROM TABLE(GENERATOR(ROWCOUNT => 8000))
)
SELECT
    transaction_id,
    'CUST-' || LPAD((MOD(rn - 1, 100) + 101)::VARCHAR, 6, '0') AS customer_id,
    'MERCH-' || LPAD(UNIFORM(1, 1000, RANDOM())::VARCHAR, 4, '0') AS merchant_id,
    -- Wide range overlapping with legitimate big purchases: $4K-$12K
    ROUND(UNIFORM(4000::FLOAT, 12000::FLOAT, RANDOM()), 2) AS transaction_amount,
    DATEADD('hour', -UNIFORM(1, 720, RANDOM()), CURRENT_TIMESTAMP()) AS transaction_timestamp,
    CASE UNIFORM(1, 3, RANDOM()) WHEN 1 THEN 'ATM' WHEN 2 THEN 'POS' ELSE 'ONLINE' END AS channel,
    CASE UNIFORM(1, 3, RANDOM()) WHEN 1 THEN 'WITHDRAWAL' WHEN 2 THEN 'TRANSFER' ELSE 'PURCHASE' END AS transaction_type,
    'USD' AS currency,
    FALSE AS is_international,
    ROUND(30.0 + UNIFORM(0::FLOAT, 5::FLOAT, RANDOM()), 4) AS transaction_lat,
    ROUND(-120.0 + UNIFORM(0::FLOAT, 10::FLOAT, RANDOM()), 4) AS transaction_lon,
    CASE UNIFORM(1, 3, RANDOM()) WHEN 1 THEN 'TERMINAL' WHEN 2 THEN 'MOBILE' ELSE 'DESKTOP' END AS device_type,
    CASE WHEN UNIFORM(0, 100, RANDOM()) < 65 THEN TRUE ELSE FALSE END AS is_fraud,
    'STRUCTURING' AS fraud_pattern
FROM struct_gen;

-- =============================================================================
-- GEO_ANOMALY fraud (8K txns from customers 201-300)
-- International transactions — but legitimate travelers also have these
-- =============================================================================
INSERT INTO RAW.TRANSACTIONS
WITH geo_gen AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS rn,
        'TXN-G-' || LPAD(ROW_NUMBER() OVER (ORDER BY SEQ4())::VARCHAR, 7, '0') AS transaction_id
    FROM TABLE(GENERATOR(ROWCOUNT => 8000))
)
SELECT
    transaction_id,
    'CUST-' || LPAD((MOD(rn - 1, 100) + 201)::VARCHAR, 6, '0') AS customer_id,
    'MERCH-' || LPAD(UNIFORM(700, 1000, RANDOM())::VARCHAR, 4, '0') AS merchant_id,
    ROUND(UNIFORM(50::FLOAT, 3000::FLOAT, RANDOM()), 2) AS transaction_amount,
    DATEADD('hour', -UNIFORM(0, 720, RANDOM()), CURRENT_TIMESTAMP()) AS transaction_timestamp,
    CASE UNIFORM(1, 3, RANDOM()) WHEN 1 THEN 'ONLINE' WHEN 2 THEN 'POS' ELSE 'MOBILE' END AS channel,
    'PURCHASE' AS transaction_type,
    CASE UNIFORM(1, 4, RANDOM()) WHEN 1 THEN 'EUR' WHEN 2 THEN 'GBP' WHEN 3 THEN 'NGN' ELSE 'USD' END AS currency,
    TRUE AS is_international,
    -- Far from US home locations
    ROUND(45.0 + UNIFORM(0::FLOAT, 20::FLOAT, RANDOM()), 4) AS transaction_lat,
    ROUND(-5.0 + UNIFORM(0::FLOAT, 45::FLOAT, RANDOM()), 4) AS transaction_lon,
    CASE UNIFORM(1, 2, RANDOM()) WHEN 1 THEN 'DESKTOP' ELSE 'MOBILE' END AS device_type,
    CASE WHEN UNIFORM(0, 100, RANDOM()) < 60 THEN TRUE ELSE FALSE END AS is_fraud,
    'GEO_ANOMALY' AS fraud_pattern
FROM geo_gen;

-- =============================================================================
-- RETURN_ABUSE (8K txns from customers 301-400)
-- Buy then return — but legitimate returns happen too
-- =============================================================================
INSERT INTO RAW.TRANSACTIONS
WITH return_gen AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS rn,
        'TXN-R-' || LPAD(ROW_NUMBER() OVER (ORDER BY SEQ4())::VARCHAR, 7, '0') AS transaction_id
    FROM TABLE(GENERATOR(ROWCOUNT => 8000))
)
SELECT
    transaction_id,
    'CUST-' || LPAD((MOD(rn - 1, 100) + 301)::VARCHAR, 6, '0') AS customer_id,
    'MERCH-' || LPAD(UNIFORM(1, 200, RANDOM())::VARCHAR, 4, '0') AS merchant_id,
    CASE WHEN MOD(rn, 3) = 0
         THEN -ROUND(UNIFORM(100::FLOAT, 1500::FLOAT, RANDOM()), 2)  -- refund
         ELSE ROUND(UNIFORM(100::FLOAT, 1500::FLOAT, RANDOM()), 2)   -- purchase
    END AS transaction_amount,
    DATEADD('hour', -UNIFORM(0, 720, RANDOM()), CURRENT_TIMESTAMP()) AS transaction_timestamp,
    'POS' AS channel,
    CASE WHEN MOD(rn, 3) = 0 THEN 'REFUND' ELSE 'PURCHASE' END AS transaction_type,
    'USD' AS currency,
    FALSE AS is_international,
    ROUND(30.0 + UNIFORM(0::FLOAT, 5::FLOAT, RANDOM()), 4) AS transaction_lat,
    ROUND(-120.0 + UNIFORM(0::FLOAT, 10::FLOAT, RANDOM()), 4) AS transaction_lon,
    'TERMINAL' AS device_type,
    CASE WHEN UNIFORM(0, 100, RANDOM()) < 55 THEN TRUE ELSE FALSE END AS is_fraud,
    'RETURN_ABUSE' AS fraud_pattern
FROM return_gen;

-- =============================================================================
-- ACCOUNT_TAKEOVER (8K txns from customers 401-500)
-- Dormant accounts suddenly active, new device types, changed behavior
-- =============================================================================
INSERT INTO RAW.TRANSACTIONS
WITH takeover_gen AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS rn,
        'TXN-T-' || LPAD(ROW_NUMBER() OVER (ORDER BY SEQ4())::VARCHAR, 7, '0') AS transaction_id
    FROM TABLE(GENERATOR(ROWCOUNT => 8000))
)
SELECT
    transaction_id,
    'CUST-' || LPAD((MOD(rn - 1, 100) + 401)::VARCHAR, 6, '0') AS customer_id,
    'MERCH-' || LPAD(UNIFORM(800, 1000, RANDOM())::VARCHAR, 4, '0') AS merchant_id,
    -- Higher amounts: draining the account
    ROUND(UNIFORM(500::FLOAT, 8000::FLOAT, RANDOM()), 2) AS transaction_amount,
    -- All recent (last 3 days) — sudden burst after dormancy
    DATEADD('hour', -UNIFORM(0, 72, RANDOM()), CURRENT_TIMESTAMP()) AS transaction_timestamp,
    'ONLINE' AS channel,
    CASE UNIFORM(1, 3, RANDOM()) WHEN 1 THEN 'PURCHASE' WHEN 2 THEN 'TRANSFER' ELSE 'WITHDRAWAL' END AS transaction_type,
    'USD' AS currency,
    CASE WHEN UNIFORM(0, 100, RANDOM()) < 30 THEN TRUE ELSE FALSE END AS is_international,
    -- Different location from home
    ROUND(40.0 + UNIFORM(0::FLOAT, 10::FLOAT, RANDOM()), 4) AS transaction_lat,
    ROUND(-80.0 + UNIFORM(0::FLOAT, 20::FLOAT, RANDOM()), 4) AS transaction_lon,
    -- New device types they haven't used before
    CASE UNIFORM(1, 2, RANDOM()) WHEN 1 THEN 'DESKTOP' ELSE 'TABLET' END AS device_type,
    CASE WHEN UNIFORM(0, 100, RANDOM()) < 75 THEN TRUE ELSE FALSE END AS is_fraud,
    'ACCOUNT_TAKEOVER' AS fraud_pattern
FROM takeover_gen;

-- =============================================================================
-- GRAY ZONE: Suspicious-looking but LEGITIMATE activity (20K txns, customers 501-800)
-- Business travelers, resellers, day traders — create false positive pressure
-- =============================================================================
INSERT INTO RAW.TRANSACTIONS
WITH gray_gen AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS rn,
        'TXN-GZ-' || LPAD(ROW_NUMBER() OVER (ORDER BY SEQ4())::VARCHAR, 7, '0') AS transaction_id
    FROM TABLE(GENERATOR(ROWCOUNT => 20000))
)
SELECT
    transaction_id,
    'CUST-' || LPAD((MOD(rn - 1, 300) + 501)::VARCHAR, 6, '0') AS customer_id,
    'MERCH-' || LPAD(UNIFORM(1, 1000, RANDOM())::VARCHAR, 4, '0') AS merchant_id,
    -- Gray zone: some have high amounts (resellers), some have high velocity (day traders)
    CASE
        WHEN MOD(rn, 3) = 0 THEN ROUND(UNIFORM(2000::FLOAT, 9000::FLOAT, RANDOM()), 2)  -- reseller
        WHEN MOD(rn, 3) = 1 THEN ROUND(UNIFORM(20::FLOAT, 150::FLOAT, RANDOM()), 2)    -- day trader (many small)
        ELSE ROUND(UNIFORM(200::FLOAT, 3000::FLOAT, RANDOM()), 2)                       -- business traveler
    END AS transaction_amount,
    DATEADD('hour', -UNIFORM(0, 720, RANDOM()), CURRENT_TIMESTAMP()) AS transaction_timestamp,
    CASE UNIFORM(1, 4, RANDOM()) WHEN 1 THEN 'ONLINE' WHEN 2 THEN 'MOBILE' WHEN 3 THEN 'POS' ELSE 'ATM' END AS channel,
    CASE UNIFORM(1, 3, RANDOM()) WHEN 1 THEN 'PURCHASE' WHEN 2 THEN 'TRANSFER' ELSE 'WITHDRAWAL' END AS transaction_type,
    CASE WHEN MOD(rn, 3) = 2 THEN
        CASE UNIFORM(1, 3, RANDOM()) WHEN 1 THEN 'EUR' WHEN 2 THEN 'GBP' ELSE 'USD' END
    ELSE 'USD' END AS currency,
    CASE WHEN MOD(rn, 3) = 2 THEN TRUE ELSE FALSE END AS is_international,  -- travelers are international
    ROUND(30.0 + UNIFORM(0::FLOAT, 25::FLOAT, RANDOM()), 4) AS transaction_lat,
    ROUND(-120.0 + UNIFORM(0::FLOAT, 80::FLOAT, RANDOM()), 4) AS transaction_lon,
    CASE UNIFORM(1, 4, RANDOM()) WHEN 1 THEN 'MOBILE' WHEN 2 THEN 'DESKTOP' WHEN 3 THEN 'TABLET' ELSE 'TERMINAL' END AS device_type,
    FALSE AS is_fraud,  -- These are ALL legitimate
    NULL AS fraud_pattern
FROM gray_gen;

-- =============================================================================
-- Enable change tracking
-- =============================================================================
ALTER TABLE RAW.TRANSACTIONS SET CHANGE_TRACKING = TRUE;
ALTER TABLE RAW.CUSTOMERS SET CHANGE_TRACKING = TRUE;
ALTER TABLE RAW.MERCHANTS SET CHANGE_TRACKING = TRUE;

-- Verification
SELECT 'TRANSACTIONS' AS tbl, COUNT(*) AS cnt, SUM(IS_FRAUD::INT) AS fraud_cnt FROM RAW.TRANSACTIONS
UNION ALL
SELECT 'CUSTOMERS', COUNT(*), SUM(CASE WHEN CUSTOMER_SEGMENT = 'FRAUD' THEN 1 ELSE 0 END) FROM RAW.CUSTOMERS
UNION ALL
SELECT 'MERCHANTS', COUNT(*), SUM(IS_HIGH_RISK::INT) FROM RAW.MERCHANTS;
