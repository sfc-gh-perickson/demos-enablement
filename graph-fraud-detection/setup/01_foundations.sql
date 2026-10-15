/*=============================================================
  01_foundations.sql — Graph Fraud Detection Demo
  Database, schemas, warehouse, and synthetic application data
  (~3M returns, ~3M applicants, ~500K addresses, ~100 fraud rings)

  Data design: overlapping distributions, partial attribute
  sharing, and gray-zone applicants prevent any single feature
  from perfectly separating fraud from legitimate returns.
=============================================================*/

USE ROLE ACCOUNTADMIN;

-- Database & schemas
CREATE DATABASE IF NOT EXISTS GRAPH_FRAUD_DEMO;
USE DATABASE GRAPH_FRAUD_DEMO;

CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS EDGES;
CREATE SCHEMA IF NOT EXISTS GRAPH;
CREATE SCHEMA IF NOT EXISTS FEATURES;
CREATE SCHEMA IF NOT EXISTS MODELS;

-- Warehouse for data generation
CREATE WAREHOUSE IF NOT EXISTS GRAPH_FRAUD_WH
    WAREHOUSE_SIZE = 'XLARGE'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;

USE WAREHOUSE GRAPH_FRAUD_WH;

/*-------------------------------------------------------------
  1. ADDRESSES (~500K)
  ~5% are "apartment buildings" with many tenants (25K buildings).
  The rest are single-household addresses.
-------------------------------------------------------------*/
USE SCHEMA RAW;

CREATE OR REPLACE TABLE ADDRESSES (
    ADDRESS_ID     INT,
    STREET         VARCHAR,
    APT            VARCHAR,
    CITY           VARCHAR,
    STATE          VARCHAR,
    ZIP            VARCHAR,
    IS_MULTI_UNIT  BOOLEAN
);

INSERT INTO ADDRESSES
SELECT
    SEQ4()                                                  AS ADDRESS_ID,
    'Street_' || SEQ4()                                     AS STREET,
    CASE WHEN UNIFORM(1,10,RANDOM()) <= 3
         THEN 'Apt ' || UNIFORM(1,20,RANDOM())::VARCHAR
         ELSE NULL END                                      AS APT,
    'City_' || UNIFORM(1, 500, RANDOM())                    AS CITY,
    ARRAY_CONSTRUCT(
        'CA','TX','FL','NY','IL','PA','OH','GA','NC','MI',
        'NJ','VA','WA','AZ','MA','TN','IN','MO','MD','WI'
    )[UNIFORM(0,19,RANDOM())]::VARCHAR                      AS STATE,
    LPAD(UNIFORM(10000, 99999, RANDOM())::VARCHAR, 5, '0')  AS ZIP,
    -- First 25K addresses are apartment buildings / multi-unit
    CASE WHEN SEQ4() < 25000 THEN TRUE ELSE FALSE END       AS IS_MULTI_UNIT
FROM TABLE(GENERATOR(ROWCOUNT => 500000));

/*-------------------------------------------------------------
  2. SHARED IPs (~2000)
  Represent offices, libraries, public wifi, VPN exit nodes.
  Each will be used by 10-100 legitimate applicants.
-------------------------------------------------------------*/
CREATE OR REPLACE TABLE SHARED_IPS (
    SHARED_IP_ID   INT,
    IP_ADDRESS     VARCHAR,
    IP_TYPE        VARCHAR
);

INSERT INTO SHARED_IPS
SELECT
    SEQ4()                                                        AS SHARED_IP_ID,
    UNIFORM(10,250,RANDOM()) || '.' ||
        UNIFORM(0,255,RANDOM()) || '.' ||
        UNIFORM(0,255,RANDOM()) || '.' ||
        UNIFORM(0,255,RANDOM())                                   AS IP_ADDRESS,
    ARRAY_CONSTRUCT('office','library','public_wifi','vpn','university')
        [UNIFORM(0,4,RANDOM())]::VARCHAR                          AS IP_TYPE
FROM TABLE(GENERATOR(ROWCOUNT => 2000));

/*-------------------------------------------------------------
  3. APPLICANTS (~3M)
  Multi-unit addresses get 5-50 tenants each (realistic sharing).
  Remaining applicants get random single-household addresses.
-------------------------------------------------------------*/
CREATE OR REPLACE TABLE APPLICANTS (
    APPLICANT_ID        INT,
    SSN_HASH           VARCHAR,
    PRIMARY_ADDRESS_ID INT,
    CREATED_TS         TIMESTAMP_NTZ
);

-- Generate all 3M applicants with placeholder address IDs
INSERT INTO APPLICANTS
SELECT
    SEQ4()                                                           AS APPLICANT_ID,
    SHA2(SEQ4()::VARCHAR || RANDOM()::VARCHAR, 256)                  AS SSN_HASH,
    0                                                                AS PRIMARY_ADDRESS_ID,
    DATEADD('second',
            -UNIFORM(0, 94608000, RANDOM()),
            '2026-04-15'::TIMESTAMP_NTZ)                             AS CREATED_TS
FROM TABLE(GENERATOR(ROWCOUNT => 3000000));

-- Assign ~150K applicants to apartment buildings (5-50 tenants per building)
-- This creates realistic address sharing among legitimate applicants
CREATE OR REPLACE TEMPORARY TABLE APARTMENT_ASSIGNMENTS AS
WITH building_slots AS (
    SELECT
        a.ADDRESS_ID,
        UNIFORM(5, 50, RANDOM()) AS NUM_TENANTS
    FROM ADDRESSES a
    WHERE a.IS_MULTI_UNIT = TRUE
),
expanded AS (
    SELECT
        bs.ADDRESS_ID,
        ROW_NUMBER() OVER (ORDER BY RANDOM()) AS GLOBAL_SEQ
    FROM building_slots bs,
         TABLE(GENERATOR(ROWCOUNT => 50)) g
    QUALIFY ROW_NUMBER() OVER (PARTITION BY bs.ADDRESS_ID ORDER BY RANDOM()) <= bs.NUM_TENANTS
)
SELECT
    ADDRESS_ID,
    GLOBAL_SEQ
FROM expanded;

-- Assign apartment dwellers (first ~N applicants get apartment addresses)
UPDATE APPLICANTS t
SET PRIMARY_ADDRESS_ID = aa.ADDRESS_ID
FROM (
    SELECT
        ADDRESS_ID,
        ROW_NUMBER() OVER (ORDER BY GLOBAL_SEQ) - 1 AS APPLICANT_ID
    FROM APARTMENT_ASSIGNMENTS
) aa
WHERE t.APPLICANT_ID = aa.APPLICANT_ID;

-- Remaining applicants get random single-household addresses
UPDATE APPLICANTS
SET PRIMARY_ADDRESS_ID = UNIFORM(25000, 499999, RANDOM())
WHERE PRIMARY_ADDRESS_ID = 0;

/*-------------------------------------------------------------
  4. Planted fraud rings (~100 rings, 5-50 members each)
  Members RANDOMLY sampled from the 3M applicant pool.
  Partial attribute sharing — not all members share every signal.
-------------------------------------------------------------*/
CREATE OR REPLACE TABLE FRAUD_RINGS (
    RING_ID        INT,
    RING_SIZE      INT,
    RING_ADDRESS_ID     INT,
    RING_IP        VARCHAR,
    RING_DEVICE    VARCHAR,
    RING_BANK_HASH VARCHAR
);

INSERT INTO FRAUD_RINGS
SELECT
    SEQ4()                                                        AS RING_ID,
    UNIFORM(5, 50, RANDOM())                                      AS RING_SIZE,
    -- Rings use apartment buildings so they mix with legit tenants
    UNIFORM(0, 24999, RANDOM())                                   AS RING_ADDRESS_ID,
    UNIFORM(10,250,RANDOM()) || '.' ||
        UNIFORM(0,255,RANDOM()) || '.' ||
        UNIFORM(0,255,RANDOM()) || '.' ||
        UNIFORM(0,255,RANDOM())                                   AS RING_IP,
    'DEV_' || SHA2(SEQ4()::VARCHAR || RANDOM()::VARCHAR, 256)     AS RING_DEVICE,
    SHA2(SEQ4()::VARCHAR || 'ring_bank' || RANDOM()::VARCHAR, 256) AS RING_BANK_HASH
FROM TABLE(GENERATOR(ROWCOUNT => 100));

-- Expand rings and randomly sample members from the full applicant pool
CREATE OR REPLACE TABLE FRAUD_RING_MEMBERS AS
WITH ring_expansion AS (
    SELECT
        fr.RING_ID,
        fr.RING_SIZE,
        fr.RING_ADDRESS_ID,
        fr.RING_IP,
        fr.RING_DEVICE,
        fr.RING_BANK_HASH,
        ROW_NUMBER() OVER (PARTITION BY fr.RING_ID ORDER BY RANDOM()) AS MEMBER_SEQ
    FROM FRAUD_RINGS fr,
         TABLE(GENERATOR(ROWCOUNT => 50)) g
    QUALIFY MEMBER_SEQ <= fr.RING_SIZE
)
SELECT
    re.RING_ID,
    -- Randomly sample from the full 3M applicant pool
    UNIFORM(0, 2999999, RANDOM())                                AS APPLICANT_ID,
    re.RING_ADDRESS_ID,
    re.RING_IP,
    re.RING_DEVICE,
    re.RING_BANK_HASH,
    -- Partial sharing probabilities: each member independently decides
    UNIFORM(1, 100, RANDOM()) <= 80                              AS SHARES_ADDRESS,
    UNIFORM(1, 100, RANDOM()) <= 60                              AS SHARES_IP,
    UNIFORM(1, 100, RANDOM()) <= 40                              AS SHARES_DEVICE,
    UNIFORM(1, 100, RANDOM()) <= 70                              AS SHARES_BANK
FROM ring_expansion re;

-- Deduplicate: if a applicant was sampled into the same ring twice, keep one
CREATE OR REPLACE TABLE FRAUD_RING_MEMBERS AS
SELECT * FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY RING_ID, APPLICANT_ID ORDER BY RANDOM()) AS DUP_RN
    FROM FRAUD_RING_MEMBERS
)
WHERE DUP_RN = 1;

ALTER TABLE FRAUD_RING_MEMBERS DROP COLUMN DUP_RN;

-- Note: a applicant CAN be in multiple rings (cross-ring overlap)

-- Update addresses for ring members who share the ring address
UPDATE APPLICANTS t
SET PRIMARY_ADDRESS_ID = frm.RING_ADDRESS_ID
FROM FRAUD_RING_MEMBERS frm
WHERE t.APPLICANT_ID = frm.APPLICANT_ID
  AND frm.SHARES_ADDRESS = TRUE;

/*-------------------------------------------------------------
  5. APPLICATIONS (~3M, one submission period)
  Overlapping claim distributions — lognormal for both classes.
  Legit: centered ~$3K, fraud: centered ~$8K, heavy overlap.
  Fraud members use shared attributes per their sharing flags.
-------------------------------------------------------------*/
CREATE OR REPLACE TABLE APPLICATIONS (
    RETURN_ID         INT,
    APPLICANT_ID       INT,
    ADDRESS_ID INT,
    CLAIM_AMOUNT     NUMBER(12,2),
    BANK_ACCOUNT_HASH VARCHAR,
    IP_ADDRESS        VARCHAR,
    DEVICE_ID         VARCHAR,
    SUBMITTED_AT         TIMESTAMP_NTZ
) CHANGE_TRACKING = TRUE;

-- Legitimate returns (non-ring applicants)
-- Lognormal claim: EXP(NORMAL) centered ~$3K, clipped to $100-$50K
-- ~10% of legit applicants reuse a shared IP (office, library, household)
INSERT INTO APPLICATIONS
SELECT
    SEQ4()                                                        AS RETURN_ID,
    t.APPLICANT_ID,
    t.PRIMARY_ADDRESS_ID                                          AS ADDRESS_ID,
    LEAST(50000.00, GREATEST(100.00,
        ROUND(EXP(LN(3000) + (UNIFORM(-200,200,RANDOM())/100.0) * 1.2), 2)
    ))                                                            AS CLAIM_AMOUNT,
    SHA2(t.APPLICANT_ID::VARCHAR || 'bank' || RANDOM()::VARCHAR, 256) AS BANK_ACCOUNT_HASH,
    -- 10% of legit applicants use a shared IP
    CASE WHEN UNIFORM(1,100,RANDOM()) <= 10
         THEN (SELECT IP_ADDRESS FROM SHARED_IPS
               WHERE SHARED_IP_ID = UNIFORM(0, 1999, RANDOM()))
         ELSE UNIFORM(1,255,RANDOM()) || '.' ||
              UNIFORM(0,255,RANDOM()) || '.' ||
              UNIFORM(0,255,RANDOM()) || '.' ||
              UNIFORM(0,255,RANDOM())
    END                                                           AS IP_ADDRESS,
    'DEV_' || SHA2(t.APPLICANT_ID::VARCHAR || RANDOM()::VARCHAR, 256) AS DEVICE_ID,
    DATEADD('second',
            -UNIFORM(0, 7776000, RANDOM()),
            '2026-04-15'::TIMESTAMP_NTZ)                          AS SUBMITTED_AT
FROM APPLICANTS t
WHERE t.APPLICANT_ID NOT IN (SELECT APPLICANT_ID FROM FRAUD_RING_MEMBERS);

-- Fraud ring returns: partial attribute sharing per member flags
-- Lognormal claim centered ~$8K, clipped to $500-$50K (overlaps with legit)
INSERT INTO APPLICATIONS
SELECT
    (SELECT MAX(RETURN_ID) FROM APPLICATIONS) + ROW_NUMBER() OVER (ORDER BY frm.APPLICANT_ID) AS RETURN_ID,
    frm.APPLICANT_ID,
    -- Shared address (p=0.8) or their own address
    CASE WHEN frm.SHARES_ADDRESS
         THEN frm.RING_ADDRESS_ID
         ELSE t.PRIMARY_ADDRESS_ID
    END                                                           AS ADDRESS_ID,
    -- Lognormal centered ~$8K, overlaps with legit in $2K-$15K range
    LEAST(50000.00, GREATEST(500.00,
        ROUND(EXP(LN(8000) + (UNIFORM(-200,200,RANDOM())/100.0) * 1.0), 2)
    ))                                                            AS CLAIM_AMOUNT,
    -- Shared bank (p=0.7) or unique bank
    CASE WHEN frm.SHARES_BANK
         THEN frm.RING_BANK_HASH
         ELSE SHA2(frm.APPLICANT_ID::VARCHAR || 'bank' || RANDOM()::VARCHAR, 256)
    END                                                           AS BANK_ACCOUNT_HASH,
    -- Shared IP (p=0.6) or random IP
    CASE WHEN frm.SHARES_IP
         THEN frm.RING_IP
         ELSE UNIFORM(1,255,RANDOM()) || '.' ||
              UNIFORM(0,255,RANDOM()) || '.' ||
              UNIFORM(0,255,RANDOM()) || '.' ||
              UNIFORM(0,255,RANDOM())
    END                                                           AS IP_ADDRESS,
    -- Shared device (p=0.4) or unique device
    CASE WHEN frm.SHARES_DEVICE
         THEN frm.RING_DEVICE
         ELSE 'DEV_' || SHA2(frm.APPLICANT_ID::VARCHAR || RANDOM()::VARCHAR, 256)
    END                                                           AS DEVICE_ID,
    -- Fraud submissions cluster in last 48h (burst pattern)
    DATEADD('second',
            -UNIFORM(0, 172800, RANDOM()),
            '2026-04-15'::TIMESTAMP_NTZ)                          AS SUBMITTED_AT
FROM FRAUD_RING_MEMBERS frm
JOIN APPLICANTS t ON frm.APPLICANT_ID = t.APPLICANT_ID;

/*-------------------------------------------------------------
  6. GRAY ZONE FILERS (~5000)
  Legitimate applicants who look suspicious: shared addresses with
  fraud ring members, high claims, shared IPs. These create
  false positive pressure for the model.
-------------------------------------------------------------*/

-- 6a. Legit roommates at fraud ring addresses (~2000)
-- Move some legit applicants to addresses used by fraud rings
UPDATE APPLICANTS
SET PRIMARY_ADDRESS_ID = (
    SELECT RING_ADDRESS_ID FROM FRAUD_RINGS
    WHERE RING_ID = UNIFORM(0, 99, RANDOM())
)
WHERE APPLICANT_ID IN (
    SELECT APPLICANT_ID FROM APPLICANTS
    WHERE APPLICANT_ID NOT IN (SELECT APPLICANT_ID FROM FRAUD_RING_MEMBERS)
    ORDER BY RANDOM()
    LIMIT 2000
);

-- Update their applications to use the new address
UPDATE APPLICATIONS tr
SET ADDRESS_ID = t.PRIMARY_ADDRESS_ID
FROM APPLICANTS t
WHERE tr.APPLICANT_ID = t.APPLICANT_ID
  AND tr.ADDRESS_ID != t.PRIMARY_ADDRESS_ID
  AND tr.APPLICANT_ID NOT IN (SELECT APPLICANT_ID FROM FRAUD_RING_MEMBERS);

-- 6b. Legit applicants using fraud ring IPs (~1500)
-- Office workers or VPN users who happen to share an IP with a ring
UPDATE APPLICATIONS
SET IP_ADDRESS = (
    SELECT RING_IP FROM FRAUD_RINGS
    WHERE RING_ID = UNIFORM(0, 99, RANDOM())
)
WHERE RETURN_ID IN (
    SELECT RETURN_ID FROM APPLICATIONS
    WHERE APPLICANT_ID NOT IN (SELECT APPLICANT_ID FROM FRAUD_RING_MEMBERS)
    ORDER BY RANDOM()
    LIMIT 1500
);

-- 6c. Legit high-claim applicants (~1500)
-- Wealthy legitimate applicants with claims in the fraud range
UPDATE APPLICATIONS
SET CLAIM_AMOUNT = ROUND(UNIFORM(8000, 45000, RANDOM()) +
                          UNIFORM(0, 99, RANDOM()) / 100.0, 2)
WHERE RETURN_ID IN (
    SELECT RETURN_ID FROM APPLICATIONS
    WHERE APPLICANT_ID NOT IN (SELECT APPLICANT_ID FROM FRAUD_RING_MEMBERS)
    ORDER BY RANDOM()
    LIMIT 1500
);

/*-------------------------------------------------------------
  7. Cleanup temp objects
-------------------------------------------------------------*/
DROP TABLE IF EXISTS APARTMENT_ASSIGNMENTS;

/*-------------------------------------------------------------
  8. Validation
-------------------------------------------------------------*/
SELECT 'ADDRESSES'   AS TBL, COUNT(*) AS ROW_CNT FROM RAW.ADDRESSES
UNION ALL
SELECT 'APPLICANTS',          COUNT(*)            FROM RAW.APPLICANTS
UNION ALL
SELECT 'APPLICATIONS',        COUNT(*)            FROM RAW.APPLICATIONS
UNION ALL
SELECT 'FRAUD_RINGS',        COUNT(*)            FROM RAW.FRAUD_RINGS
UNION ALL
SELECT 'FRAUD_RING_MEMBERS', COUNT(*)            FROM RAW.FRAUD_RING_MEMBERS
UNION ALL
SELECT 'SHARED_IPS',         COUNT(*)            FROM RAW.SHARED_IPS;

-- Verify partial sharing: rings should NOT have uniform sharing
SELECT
    frm.RING_ID,
    COUNT(*)                                                AS RING_SIZE,
    COUNT(DISTINCT tr.IP_ADDRESS)                           AS DISTINCT_IPS,
    COUNT(DISTINCT tr.DEVICE_ID)                            AS DISTINCT_DEVICES,
    COUNT(DISTINCT tr.ADDRESS_ID)                    AS DISTINCT_ADDRESSES,
    COUNT(DISTINCT tr.BANK_ACCOUNT_HASH)                    AS DISTINCT_BANKS,
    ROUND(SUM(CASE WHEN frm.SHARES_ADDRESS THEN 1 ELSE 0 END)
          / COUNT(*)::FLOAT, 2)                             AS PCT_SHARING_ADDR,
    ROUND(SUM(CASE WHEN frm.SHARES_IP THEN 1 ELSE 0 END)
          / COUNT(*)::FLOAT, 2)                             AS PCT_SHARING_IP
FROM RAW.FRAUD_RING_MEMBERS frm
JOIN RAW.APPLICATIONS tr ON frm.APPLICANT_ID = tr.APPLICANT_ID
GROUP BY frm.RING_ID
ORDER BY RING_SIZE DESC
LIMIT 10;

-- Verify claim overlap: both classes should have returns in $2K-$15K
SELECT
    CASE WHEN frm.APPLICANT_ID IS NOT NULL THEN 'FRAUD' ELSE 'LEGIT' END AS CLASS,
    COUNT(*)                                                AS NUM_RETURNS,
    ROUND(MIN(tr.CLAIM_AMOUNT), 2)                         AS MIN_REFUND,
    ROUND(AVG(tr.CLAIM_AMOUNT), 2)                         AS AVG_REFUND,
    ROUND(MEDIAN(tr.CLAIM_AMOUNT), 2)                      AS MEDIAN_REFUND,
    ROUND(MAX(tr.CLAIM_AMOUNT), 2)                         AS MAX_REFUND,
    SUM(CASE WHEN tr.CLAIM_AMOUNT BETWEEN 2000 AND 15000
             THEN 1 ELSE 0 END)                             AS IN_OVERLAP_ZONE
FROM RAW.APPLICATIONS tr
LEFT JOIN RAW.FRAUD_RING_MEMBERS frm ON tr.APPLICANT_ID = frm.APPLICANT_ID
GROUP BY CLASS;

-- Verify gray zone: legit applicants sharing addresses with fraud rings
SELECT COUNT(DISTINCT tr.APPLICANT_ID) AS LEGIT_AT_FRAUD_ADDRESSES
FROM RAW.APPLICATIONS tr
JOIN RAW.FRAUD_RINGS fr ON tr.ADDRESS_ID = fr.RING_ADDRESS_ID
WHERE tr.APPLICANT_ID NOT IN (SELECT APPLICANT_ID FROM RAW.FRAUD_RING_MEMBERS);
