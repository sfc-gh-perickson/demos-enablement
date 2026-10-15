/*=============================================================
  02_edge_construction.sql — Dynamic Table: APPLICANT_EDGES
  Builds (applicant_a, applicant_b, edge_type, weight) from
  shared submission attributes: address, IP, device, bank account.

  IMPORTANT: Self-joins are capped to avoid combinatorial explosion
  on high-fan-out attributes (large apartments, shared office IPs).
  Only groups with <= MAX_GROUP_SIZE members produce edges.
=============================================================*/

USE ROLE ACCOUNTADMIN;
USE DATABASE GRAPH_FRAUD_DEMO;
USE WAREHOUSE GRAPH_FRAUD_WH;
USE SCHEMA EDGES;

CREATE OR REPLACE DYNAMIC TABLE APPLICANT_EDGES
    TARGET_LAG = '5 minutes'
    WAREHOUSE = GRAPH_FRAUD_WH
AS
WITH
-- Pre-filter: only join within groups small enough to be suspicious
-- Large apartment complexes (50+ applicants) and office IPs (100+ applicants) are noise
addr_groups AS (
    SELECT ADDRESS_ID, COUNT(DISTINCT APPLICANT_ID) AS cnt
    FROM RAW.APPLICATIONS
    GROUP BY ADDRESS_ID
    HAVING cnt BETWEEN 2 AND 100
),
ip_groups AS (
    SELECT IP_ADDRESS, COUNT(DISTINCT APPLICANT_ID) AS cnt
    FROM RAW.APPLICATIONS
    GROUP BY IP_ADDRESS
    HAVING cnt BETWEEN 2 AND 50
),
device_groups AS (
    SELECT DEVICE_ID, COUNT(DISTINCT APPLICANT_ID) AS cnt
    FROM RAW.APPLICATIONS
    GROUP BY DEVICE_ID
    HAVING cnt BETWEEN 2 AND 20
),
bank_groups AS (
    SELECT BANK_ACCOUNT_HASH, COUNT(DISTINCT APPLICANT_ID) AS cnt
    FROM RAW.APPLICATIONS
    GROUP BY BANK_ACCOUNT_HASH
    HAVING cnt BETWEEN 2 AND 20
),
shared_address AS (
    SELECT
        LEAST(a.APPLICANT_ID, b.APPLICANT_ID)    AS APPLICANT_A,
        GREATEST(a.APPLICANT_ID, b.APPLICANT_ID) AS APPLICANT_B,
        'SHARED_ADDRESS'                        AS EDGE_TYPE
    FROM RAW.APPLICATIONS a
    JOIN RAW.APPLICATIONS b
        ON a.ADDRESS_ID = b.ADDRESS_ID
        AND a.APPLICANT_ID < b.APPLICANT_ID
    JOIN addr_groups ag ON ag.ADDRESS_ID = a.ADDRESS_ID
    GROUP BY 1, 2, 3
),
shared_ip AS (
    SELECT
        LEAST(a.APPLICANT_ID, b.APPLICANT_ID)    AS APPLICANT_A,
        GREATEST(a.APPLICANT_ID, b.APPLICANT_ID) AS APPLICANT_B,
        'SHARED_IP'                             AS EDGE_TYPE
    FROM RAW.APPLICATIONS a
    JOIN RAW.APPLICATIONS b
        ON a.IP_ADDRESS = b.IP_ADDRESS
        AND a.APPLICANT_ID < b.APPLICANT_ID
    JOIN ip_groups ig ON ig.IP_ADDRESS = a.IP_ADDRESS
    GROUP BY 1, 2, 3
),
shared_device AS (
    SELECT
        LEAST(a.APPLICANT_ID, b.APPLICANT_ID)    AS APPLICANT_A,
        GREATEST(a.APPLICANT_ID, b.APPLICANT_ID) AS APPLICANT_B,
        'SHARED_DEVICE'                         AS EDGE_TYPE
    FROM RAW.APPLICATIONS a
    JOIN RAW.APPLICATIONS b
        ON a.DEVICE_ID = b.DEVICE_ID
        AND a.APPLICANT_ID < b.APPLICANT_ID
    JOIN device_groups dg ON dg.DEVICE_ID = a.DEVICE_ID
    GROUP BY 1, 2, 3
),
shared_bank AS (
    SELECT
        LEAST(a.APPLICANT_ID, b.APPLICANT_ID)    AS APPLICANT_A,
        GREATEST(a.APPLICANT_ID, b.APPLICANT_ID) AS APPLICANT_B,
        'SHARED_BANK'                           AS EDGE_TYPE
    FROM RAW.APPLICATIONS a
    JOIN RAW.APPLICATIONS b
        ON a.BANK_ACCOUNT_HASH = b.BANK_ACCOUNT_HASH
        AND a.APPLICANT_ID < b.APPLICANT_ID
    JOIN bank_groups bg ON bg.BANK_ACCOUNT_HASH = a.BANK_ACCOUNT_HASH
    GROUP BY 1, 2, 3
),
all_edges AS (
    SELECT * FROM shared_address
    UNION ALL
    SELECT * FROM shared_ip
    UNION ALL
    SELECT * FROM shared_device
    UNION ALL
    SELECT * FROM shared_bank
)
SELECT
    APPLICANT_A,
    APPLICANT_B,
    EDGE_TYPE,
    COUNT(*) AS WEIGHT
FROM all_edges
GROUP BY APPLICANT_A, APPLICANT_B, EDGE_TYPE;

/*-------------------------------------------------------------
  Validation: check edge distribution
-------------------------------------------------------------*/
SELECT
    EDGE_TYPE,
    COUNT(*)                   AS EDGE_COUNT,
    COUNT(DISTINCT APPLICANT_A) AS DISTINCT_NODE_A,
    COUNT(DISTINCT APPLICANT_B) AS DISTINCT_NODE_B
FROM EDGES.APPLICANT_EDGES
GROUP BY EDGE_TYPE
ORDER BY EDGE_COUNT DESC;
