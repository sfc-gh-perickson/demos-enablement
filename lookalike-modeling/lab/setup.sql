-- =============================================================================
-- Lookalike Modeling Lab: Setup Script
-- =============================================================================
-- Run this script once before starting the lab notebook.
-- It creates all prerequisite objects: database, schemas, tables, warehouse,
-- staging infrastructure, and generates synthetic consumer/marketing data.
--
-- Prerequisites:
--   - A role with CREATE DATABASE, CREATE WAREHOUSE privileges
--   - Snowflake ML features enabled on the account
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. DATABASE AND SCHEMAS
-- ─────────────────────────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS LOOKALIKE_DEMO;
USE DATABASE LOOKALIKE_DEMO;

CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS FEATURE_STORE;
CREATE SCHEMA IF NOT EXISTS MODELS;
CREATE SCHEMA IF NOT EXISTS SCORING;
CREATE SCHEMA IF NOT EXISTS MONITORING;

USE SCHEMA RAW;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. WAREHOUSE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE WAREHOUSE IF NOT EXISTS LOOKALIKE_WH
  WAREHOUSE_SIZE = 'MEDIUM'
  AUTO_SUSPEND = 120
  AUTO_RESUME = TRUE;

USE WAREHOUSE LOOKALIKE_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. INTERNAL STAGES
-- ─────────────────────────────────────────────────────────────────────────────

CREATE STAGE IF NOT EXISTS LOOKALIKE_DEMO.MODELS.SKILL_STAGE
  COMMENT = 'Stage for Cortex Agent skill files (SKILL.md and Python scripts)';

CREATE STAGE IF NOT EXISTS LOOKALIKE_DEMO.MODELS.ML_STAGE
  COMMENT = 'Stage for model artifacts';

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. RAW DATA TABLES
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE LOOKALIKE_DEMO.RAW.CONSUMER_UNIVERSE (
    CONSUMER_ID         VARCHAR        COMMENT 'Unique consumer identifier, e.g. CON00001',
    AGE                 NUMBER         COMMENT 'Consumer age in years',
    AGE_GROUP           VARCHAR        COMMENT 'Age bracket: 18-24, 25-34, 35-44, 45-54, 55-64, 65+',
    GENDER              VARCHAR        COMMENT 'Gender: M, F, NB',
    INCOME_BRACKET      VARCHAR        COMMENT 'Household income bracket',
    HOMEOWNER           VARCHAR        COMMENT 'Homeownership: Y, N',
    MARITAL_STATUS      VARCHAR        COMMENT 'Marital status: single, married, divorced, widowed',
    CHILDREN_COUNT      NUMBER         COMMENT 'Number of children in household',
    HOUSEHOLD_SIZE      NUMBER         COMMENT 'Total household members',
    EDUCATION_LEVEL     VARCHAR        COMMENT 'Education: high_school, some_college, bachelors, masters, doctorate',
    OCCUPATION_GROUP    VARCHAR        COMMENT 'Occupation category',
    STATE               VARCHAR        COMMENT 'US state (2-letter)',
    DMA                 VARCHAR        COMMENT 'Designated Market Area',
    URBANICITY          VARCHAR        COMMENT 'urban, suburban, rural',
    ZIP_DENSITY         NUMBER         COMMENT 'Population density percentile of ZIP code (1-100)',
    CREDIT_SCORE_RANGE  VARCHAR        COMMENT 'Credit score range: poor, fair, good, very_good, excellent',
    CHANNEL_PREFERENCE  VARCHAR        COMMENT 'Preferred contact channel: email, mail, digital, social',
    EMAIL_OPT_IN       BOOLEAN        COMMENT 'Whether consumer opted in to email',
    MAIL_OPT_IN        BOOLEAN        COMMENT 'Whether consumer opted in to direct mail',
    TENURE_MONTHS       NUMBER         COMMENT 'Months since consumer entered the database'
);

CREATE OR REPLACE TABLE LOOKALIKE_DEMO.RAW.PURCHASE_HISTORY (
    PURCHASE_ID         VARCHAR        COMMENT 'Unique purchase transaction ID',
    CONSUMER_ID         VARCHAR        COMMENT 'FK to CONSUMER_UNIVERSE',
    CATEGORY            VARCHAR        COMMENT 'Product category: electronics, clothing, home_garden, sports, beauty, food, toys, books',
    PURCHASE_TS         TIMESTAMP_NTZ  COMMENT 'Timestamp of purchase',
    AMOUNT              NUMBER(12,2)   COMMENT 'Purchase amount in USD',
    CHANNEL             VARCHAR        COMMENT 'Purchase channel: online, in_store, mobile_app',
    COUPON_USED         BOOLEAN        COMMENT 'Whether a coupon/promotion was applied'
);

CREATE OR REPLACE TABLE LOOKALIKE_DEMO.RAW.CHANNEL_ENGAGEMENT (
    EVENT_ID            VARCHAR        COMMENT 'Unique engagement event ID',
    CONSUMER_ID         VARCHAR        COMMENT 'FK to CONSUMER_UNIVERSE',
    CHANNEL             VARCHAR        COMMENT 'Channel: email, web, social, direct_mail',
    EVENT_TYPE          VARCHAR        COMMENT 'Event type varies by channel',
    EVENT_TS            TIMESTAMP_NTZ  COMMENT 'Timestamp of engagement event',
    RESPONSE            BOOLEAN        COMMENT 'Whether the engagement resulted in a positive response'
);

CREATE OR REPLACE TABLE LOOKALIKE_DEMO.RAW.CAMPAIGN_SEEDS (
    SEED_NAME           VARCHAR        COMMENT 'Name of the seed audience',
    CONSUMER_ID         VARCHAR        COMMENT 'FK to CONSUMER_UNIVERSE',
    SEED_DESCRIPTION    VARCHAR        COMMENT 'Description of what this seed represents'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. SYNTHETIC DATA GENERATION
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE LOOKALIKE_DEMO.RAW.GENERATE_SYNTHETIC_DATA()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    v_status VARCHAR;
BEGIN
    -- ─────────────────────────────────────────────────────────────────────
    -- CONSUMER UNIVERSE (100,000 consumers)
    -- ─────────────────────────────────────────────────────────────────────
    DELETE FROM LOOKALIKE_DEMO.RAW.CONSUMER_UNIVERSE;

    INSERT INTO LOOKALIKE_DEMO.RAW.CONSUMER_UNIVERSE (
        CONSUMER_ID, AGE, AGE_GROUP, GENDER, INCOME_BRACKET, HOMEOWNER,
        MARITAL_STATUS, CHILDREN_COUNT, HOUSEHOLD_SIZE, EDUCATION_LEVEL,
        OCCUPATION_GROUP, STATE, DMA, URBANICITY, ZIP_DENSITY,
        CREDIT_SCORE_RANGE, CHANNEL_PREFERENCE, EMAIL_OPT_IN, MAIL_OPT_IN, TENURE_MONTHS
    )
    WITH
    states AS (
        SELECT column1 AS state, column2 AS dma
        FROM VALUES
            ('NY', 'New York'), ('CA', 'Los Angeles'), ('CA', 'San Francisco'),
            ('IL', 'Chicago'), ('TX', 'Dallas-Ft. Worth'), ('TX', 'Houston'),
            ('PA', 'Philadelphia'), ('AZ', 'Phoenix'), ('FL', 'Miami-Ft. Lauderdale'),
            ('FL', 'Tampa-St. Pete'), ('WA', 'Seattle-Tacoma'), ('MA', 'Boston'),
            ('CO', 'Denver'), ('GA', 'Atlanta'), ('MI', 'Detroit'),
            ('MN', 'Minneapolis-St. Paul'), ('WI', 'Milwaukee'), ('OH', 'Cleveland'),
            ('NC', 'Charlotte'), ('TN', 'Nashville'), ('OR', 'Portland'),
            ('MO', 'St. Louis'), ('IN', 'Indianapolis'), ('NV', 'Las Vegas'),
            ('VA', 'Norfolk-Portsmouth'), ('MD', 'Baltimore'), ('CT', 'Hartford'),
            ('UT', 'Salt Lake City'), ('KY', 'Louisville'), ('IA', 'Des Moines')
    ),
    numbered_states AS (
        SELECT state, dma, ROW_NUMBER() OVER (ORDER BY state, dma) AS state_idx
        FROM states
    ),
    consumer_rows AS (
        SELECT ROW_NUMBER() OVER (ORDER BY seq4()) AS rn
        FROM TABLE(GENERATOR(ROWCOUNT => 100000))
    )
    SELECT
        'CON' || LPAD(c.rn::VARCHAR, 6, '0') AS consumer_id,
        18 + ABS(MOD(HASH(c.rn::VARCHAR || 'age'), 52)) AS age,
        CASE
            WHEN 18 + ABS(MOD(HASH(c.rn::VARCHAR || 'age'), 52)) < 25 THEN '18-24'
            WHEN 18 + ABS(MOD(HASH(c.rn::VARCHAR || 'age'), 52)) < 35 THEN '25-34'
            WHEN 18 + ABS(MOD(HASH(c.rn::VARCHAR || 'age'), 52)) < 45 THEN '35-44'
            WHEN 18 + ABS(MOD(HASH(c.rn::VARCHAR || 'age'), 52)) < 55 THEN '45-54'
            WHEN 18 + ABS(MOD(HASH(c.rn::VARCHAR || 'age'), 52)) < 65 THEN '55-64'
            ELSE '65+'
        END AS age_group,
        CASE MOD(ABS(HASH(c.rn::VARCHAR || 'gender')), 20)
            WHEN 0 THEN 'NB'
            ELSE CASE WHEN MOD(ABS(HASH(c.rn::VARCHAR || 'gender')), 2) = 0 THEN 'M' ELSE 'F' END
        END AS gender,
        CASE
            WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'income'), 100)) < 15 THEN 'under_25k'
            WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'income'), 100)) < 35 THEN '25k-50k'
            WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'income'), 100)) < 60 THEN '50k-75k'
            WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'income'), 100)) < 80 THEN '75k-100k'
            WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'income'), 100)) < 92 THEN '100k-150k'
            ELSE '150k_plus'
        END AS income_bracket,
        CASE WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'home'), 100)) < 55 THEN 'Y' ELSE 'N' END AS homeowner,
        CASE MOD(ABS(HASH(c.rn::VARCHAR || 'marital')), 4)
            WHEN 0 THEN 'single'
            WHEN 1 THEN 'married'
            WHEN 2 THEN 'divorced'
            ELSE 'widowed'
        END AS marital_status,
        CASE
            WHEN MOD(ABS(HASH(c.rn::VARCHAR || 'marital')), 4) = 0 THEN 0
            ELSE ABS(MOD(HASH(c.rn::VARCHAR || 'children'), 4))
        END AS children_count,
        CASE
            WHEN MOD(ABS(HASH(c.rn::VARCHAR || 'marital')), 4) = 0 THEN 1
            ELSE 2 + ABS(MOD(HASH(c.rn::VARCHAR || 'hh'), 3))
        END AS household_size,
        CASE MOD(ABS(HASH(c.rn::VARCHAR || 'edu')), 5)
            WHEN 0 THEN 'high_school'
            WHEN 1 THEN 'some_college'
            WHEN 2 THEN 'bachelors'
            WHEN 3 THEN 'masters'
            ELSE 'doctorate'
        END AS education_level,
        CASE MOD(ABS(HASH(c.rn::VARCHAR || 'occ')), 6)
            WHEN 0 THEN 'professional'
            WHEN 1 THEN 'management'
            WHEN 2 THEN 'sales_service'
            WHEN 3 THEN 'technical'
            WHEN 4 THEN 'trades'
            ELSE 'retired'
        END AS occupation_group,
        ns.state,
        ns.dma,
        CASE MOD(ABS(HASH(c.rn::VARCHAR || 'urban')), 10)
            WHEN 0 THEN 'rural'
            WHEN 1 THEN 'rural'
            WHEN 2 THEN 'suburban'
            WHEN 3 THEN 'suburban'
            WHEN 4 THEN 'suburban'
            WHEN 5 THEN 'suburban'
            ELSE 'urban'
        END AS urbanicity,
        1 + ABS(MOD(HASH(c.rn::VARCHAR || 'zipd'), 100)) AS zip_density,
        CASE
            WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'credit'), 100)) < 10 THEN 'poor'
            WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'credit'), 100)) < 25 THEN 'fair'
            WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'credit'), 100)) < 55 THEN 'good'
            WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'credit'), 100)) < 80 THEN 'very_good'
            ELSE 'excellent'
        END AS credit_score_range,
        CASE MOD(ABS(HASH(c.rn::VARCHAR || 'chan')), 4)
            WHEN 0 THEN 'email'
            WHEN 1 THEN 'mail'
            WHEN 2 THEN 'digital'
            ELSE 'social'
        END AS channel_preference,
        CASE WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'emailopt'), 100)) < 70 THEN TRUE ELSE FALSE END AS email_opt_in,
        CASE WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'mailopt'), 100)) < 60 THEN TRUE ELSE FALSE END AS mail_opt_in,
        1 + ABS(MOD(HASH(c.rn::VARCHAR || 'tenure'), 60)) AS tenure_months
    FROM consumer_rows c
    JOIN numbered_states ns ON ns.state_idx = MOD(c.rn - 1, 30) + 1;

    -- ─────────────────────────────────────────────────────────────────────
    -- PURCHASE HISTORY (500,000 purchases over past 12 months)
    -- ─────────────────────────────────────────────────────────────────────
    DELETE FROM LOOKALIKE_DEMO.RAW.PURCHASE_HISTORY;

    INSERT INTO LOOKALIKE_DEMO.RAW.PURCHASE_HISTORY (
        PURCHASE_ID, CONSUMER_ID, CATEGORY, PURCHASE_TS, AMOUNT, CHANNEL, COUPON_USED
    )
    WITH
    purchase_rows AS (
        SELECT ROW_NUMBER() OVER (ORDER BY seq4()) AS rn
        FROM TABLE(GENERATOR(ROWCOUNT => 500000))
    ),
    active_consumers AS (
        SELECT CONSUMER_ID,
            ROW_NUMBER() OVER (ORDER BY HASH(CONSUMER_ID || 'purch')) AS cust_rn,
            COUNT(*) OVER () AS total_custs
        FROM LOOKALIKE_DEMO.RAW.CONSUMER_UNIVERSE
    )
    SELECT
        'PUR' || LPAD(p.rn::VARCHAR, 7, '0') AS purchase_id,
        ac.CONSUMER_ID,
        CASE MOD(ABS(HASH(p.rn::VARCHAR || 'cat')), 20)
            WHEN 0 THEN 'electronics'
            WHEN 1 THEN 'electronics'
            WHEN 2 THEN 'clothing'
            WHEN 3 THEN 'clothing'
            WHEN 4 THEN 'clothing'
            WHEN 5 THEN 'home_garden'
            WHEN 6 THEN 'home_garden'
            WHEN 7 THEN 'home_garden'
            WHEN 8 THEN 'sports'
            WHEN 9 THEN 'sports'
            WHEN 10 THEN 'beauty'
            WHEN 11 THEN 'beauty'
            WHEN 12 THEN 'food'
            WHEN 13 THEN 'food'
            WHEN 14 THEN 'food'
            WHEN 15 THEN 'toys'
            WHEN 16 THEN 'toys'
            WHEN 17 THEN 'books'
            WHEN 18 THEN 'books'
            ELSE 'electronics'
        END AS category,
        DATEADD('second',
            -ABS(MOD(HASH(p.rn::VARCHAR || 'ts'), 31536000)),
            CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
        ) AS purchase_ts,
        ROUND(
            CASE MOD(ABS(HASH(p.rn::VARCHAR || 'cat')), 20)
                WHEN 0 THEN 50.0 + ABS(MOD(HASH(p.rn::VARCHAR || 'amt'), 500))
                WHEN 1 THEN 50.0 + ABS(MOD(HASH(p.rn::VARCHAR || 'amt'), 500))
                WHEN 5 THEN 30.0 + ABS(MOD(HASH(p.rn::VARCHAR || 'amt'), 300))
                WHEN 6 THEN 30.0 + ABS(MOD(HASH(p.rn::VARCHAR || 'amt'), 300))
                WHEN 7 THEN 30.0 + ABS(MOD(HASH(p.rn::VARCHAR || 'amt'), 300))
                ELSE 10.0 + ABS(MOD(HASH(p.rn::VARCHAR || 'amt'), 150))
            END, 2) AS amount,
        CASE MOD(ABS(HASH(p.rn::VARCHAR || 'pchan')), 3)
            WHEN 0 THEN 'online'
            WHEN 1 THEN 'in_store'
            ELSE 'mobile_app'
        END AS channel,
        CASE WHEN ABS(MOD(HASH(p.rn::VARCHAR || 'coup'), 100)) < 25 THEN TRUE ELSE FALSE END AS coupon_used
    FROM purchase_rows p
    JOIN active_consumers ac
        ON ac.cust_rn = MOD(ABS(MOD(HASH(p.rn::VARCHAR || 'cust'), ac.total_custs * 2)), ac.total_custs) + 1;

    -- ─────────────────────────────────────────────────────────────────────
    -- CHANNEL ENGAGEMENT (300,000 events over past 6 months)
    -- ─────────────────────────────────────────────────────────────────────
    DELETE FROM LOOKALIKE_DEMO.RAW.CHANNEL_ENGAGEMENT;

    INSERT INTO LOOKALIKE_DEMO.RAW.CHANNEL_ENGAGEMENT (
        EVENT_ID, CONSUMER_ID, CHANNEL, EVENT_TYPE, EVENT_TS, RESPONSE
    )
    WITH
    event_rows AS (
        SELECT ROW_NUMBER() OVER (ORDER BY seq4()) AS rn
        FROM TABLE(GENERATOR(ROWCOUNT => 300000))
    ),
    active_consumers AS (
        SELECT CONSUMER_ID,
            ROW_NUMBER() OVER (ORDER BY HASH(CONSUMER_ID || 'eng')) AS cust_rn,
            COUNT(*) OVER () AS total_custs
        FROM LOOKALIKE_DEMO.RAW.CONSUMER_UNIVERSE
    )
    SELECT
        'ENG' || LPAD(e.rn::VARCHAR, 7, '0') AS event_id,
        ac.CONSUMER_ID,
        CASE MOD(ABS(HASH(e.rn::VARCHAR || 'echan')), 4)
            WHEN 0 THEN 'email'
            WHEN 1 THEN 'web'
            WHEN 2 THEN 'social'
            ELSE 'direct_mail'
        END AS channel,
        CASE MOD(ABS(HASH(e.rn::VARCHAR || 'echan')), 4)
            WHEN 0 THEN CASE MOD(ABS(HASH(e.rn::VARCHAR || 'etype')), 3)
                            WHEN 0 THEN 'open'
                            WHEN 1 THEN 'click'
                            ELSE 'unsubscribe'
                         END
            WHEN 1 THEN CASE MOD(ABS(HASH(e.rn::VARCHAR || 'etype')), 3)
                            WHEN 0 THEN 'page_view'
                            WHEN 1 THEN 'product_view'
                            ELSE 'cart_add'
                         END
            WHEN 2 THEN CASE MOD(ABS(HASH(e.rn::VARCHAR || 'etype')), 3)
                            WHEN 0 THEN 'like'
                            WHEN 1 THEN 'share'
                            ELSE 'comment'
                         END
            ELSE CASE MOD(ABS(HASH(e.rn::VARCHAR || 'etype')), 3)
                    WHEN 0 THEN 'delivered'
                    WHEN 1 THEN 'opened'
                    ELSE 'responded'
                 END
        END AS event_type,
        DATEADD('second',
            -ABS(MOD(HASH(e.rn::VARCHAR || 'ets'), 15768000)),
            CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
        ) AS event_ts,
        CASE WHEN ABS(MOD(HASH(e.rn::VARCHAR || 'resp'), 100)) < 30 THEN TRUE ELSE FALSE END AS response
    FROM event_rows e
    JOIN active_consumers ac
        ON ac.cust_rn = MOD(ABS(MOD(HASH(e.rn::VARCHAR || 'ecust'), ac.total_custs * 2)), ac.total_custs) + 1;

    -- ─────────────────────────────────────────────────────────────────────
    -- CAMPAIGN SEEDS (3 audiences, ~1000 each)
    -- Seed 1: Home & Garden Buyers — homeowners, 35-54, suburban, high H&G spend
    -- Seed 2: Digital-First Millennials — 25-34, urban, high email/web, electronics+beauty
    -- Seed 3: Family Value Seekers — families with 2+ children, 50k-100k income, food+toys
    -- ─────────────────────────────────────────────────────────────────────
    DELETE FROM LOOKALIKE_DEMO.RAW.CAMPAIGN_SEEDS;

    -- Seed 1: Home & Garden Buyers
    INSERT INTO LOOKALIKE_DEMO.RAW.CAMPAIGN_SEEDS (SEED_NAME, CONSUMER_ID, SEED_DESCRIPTION)
    SELECT
        'home_garden_buyers',
        cu.CONSUMER_ID,
        'High-value Home & Garden purchasers: homeowners aged 35-54 in suburban areas with strong mail responsiveness'
    FROM LOOKALIKE_DEMO.RAW.CONSUMER_UNIVERSE cu
    WHERE cu.HOMEOWNER = 'Y'
      AND cu.AGE_GROUP IN ('35-44', '45-54')
      AND cu.URBANICITY = 'suburban'
      AND cu.CONSUMER_ID IN (
          SELECT ph.CONSUMER_ID
          FROM LOOKALIKE_DEMO.RAW.PURCHASE_HISTORY ph
          WHERE ph.CATEGORY = 'home_garden'
          GROUP BY ph.CONSUMER_ID
          HAVING COUNT(*) >= 3 AND SUM(ph.AMOUNT) > 200
      )
    LIMIT 1000;

    -- Seed 2: Digital-First Millennials
    INSERT INTO LOOKALIKE_DEMO.RAW.CAMPAIGN_SEEDS (SEED_NAME, CONSUMER_ID, SEED_DESCRIPTION)
    SELECT
        'digital_first_millennials',
        cu.CONSUMER_ID,
        'Young professionals aged 25-34 in urban areas with high email/web engagement and electronics+beauty purchases'
    FROM LOOKALIKE_DEMO.RAW.CONSUMER_UNIVERSE cu
    WHERE cu.AGE_GROUP = '25-34'
      AND cu.URBANICITY = 'urban'
      AND cu.EMAIL_OPT_IN = TRUE
      AND cu.CHANNEL_PREFERENCE IN ('email', 'digital')
      AND cu.CONSUMER_ID IN (
          SELECT ph.CONSUMER_ID
          FROM LOOKALIKE_DEMO.RAW.PURCHASE_HISTORY ph
          WHERE ph.CATEGORY IN ('electronics', 'beauty')
          GROUP BY ph.CONSUMER_ID
          HAVING COUNT(*) >= 2
      )
    LIMIT 1000;

    -- Seed 3: Family Value Seekers
    INSERT INTO LOOKALIKE_DEMO.RAW.CAMPAIGN_SEEDS (SEED_NAME, CONSUMER_ID, SEED_DESCRIPTION)
    SELECT
        'family_value_seekers',
        cu.CONSUMER_ID,
        'Families with 2+ children, moderate income, frequent food and toys purchases with coupon usage'
    FROM LOOKALIKE_DEMO.RAW.CONSUMER_UNIVERSE cu
    WHERE cu.CHILDREN_COUNT >= 2
      AND cu.INCOME_BRACKET IN ('50k-75k', '75k-100k')
      AND cu.CONSUMER_ID IN (
          SELECT ph.CONSUMER_ID
          FROM LOOKALIKE_DEMO.RAW.PURCHASE_HISTORY ph
          WHERE ph.CATEGORY IN ('food', 'toys')
            AND ph.COUPON_USED = TRUE
          GROUP BY ph.CONSUMER_ID
          HAVING COUNT(*) >= 2
      )
    LIMIT 1000;

    SELECT 'done' INTO :v_status;
    RETURN 'Synthetic data generation complete. Tables populated: CONSUMER_UNIVERSE, PURCHASE_HISTORY, CHANNEL_ENGAGEMENT, CAMPAIGN_SEEDS';
END;
$$;

-- Execute the data generation procedure
CALL LOOKALIKE_DEMO.RAW.GENERATE_SYNTHETIC_DATA();

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. STORED PROCEDURES (Agent Tools)
-- ─────────────────────────────────────────────────────────────────────────────
-- These procedures are the agent's tools. Each is a LANGUAGE PYTHON procedure
-- that runs on the warehouse. The agent invokes them via generic tool calls.

-- Tool 1: List available seed audiences
CREATE OR REPLACE PROCEDURE LOOKALIKE_DEMO.MODELS.LIST_AVAILABLE_SEEDS()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS
$$
def run(session):
    df = session.sql("""
        SELECT SEED_NAME, COUNT(*) AS SIZE, MAX(SEED_DESCRIPTION) AS DESCRIPTION
        FROM LOOKALIKE_DEMO.RAW.CAMPAIGN_SEEDS
        GROUP BY SEED_NAME
        ORDER BY SEED_NAME
    """).to_pandas()
    return df.to_dict('records')
$$;

-- Tool 2: Profile a seed audience vs universe baseline
CREATE OR REPLACE PROCEDURE LOOKALIKE_DEMO.MODELS.PROFILE_SEED_AUDIENCE(seed_name VARCHAR)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'numpy', 'pandas')
HANDLER = 'run'
AS
$$
import numpy as np
import pandas as pd

def run(session, seed_name):
    # Get seed IDs
    seed_df = session.sql(f"""
        SELECT CONSUMER_ID FROM LOOKALIKE_DEMO.RAW.CAMPAIGN_SEEDS
        WHERE SEED_NAME = '{seed_name}'
    """).to_pandas()
    seed_ids = set(seed_df['CONSUMER_ID'].tolist())
    seed_count = len(seed_ids)

    # Get universe demographics
    universe = session.sql("""
        SELECT * FROM LOOKALIKE_DEMO.RAW.CONSUMER_UNIVERSE
    """).to_pandas()

    seed_universe = universe[universe['CONSUMER_ID'].isin(seed_ids)]

    profile = {
        "seed_name": seed_name,
        "seed_size": seed_count,
        "universe_size": len(universe),
        "over_indexes": [],
        "under_indexes": []
    }

    # Numeric columns
    numeric_cols = universe.select_dtypes(include=[np.number]).columns.tolist()
    numeric_cols = [c for c in numeric_cols if c != 'CONSUMER_ID']

    for col in numeric_cols:
        u_mean = universe[col].mean()
        s_mean = seed_universe[col].mean()
        if u_mean > 0:
            ratio = s_mean / u_mean
            if ratio > 1.3:
                profile["over_indexes"].append({"feature": col, "seed_mean": round(float(s_mean), 2), "universe_mean": round(float(u_mean), 2), "ratio": round(float(ratio), 2)})
            elif ratio < 0.7:
                profile["under_indexes"].append({"feature": col, "seed_mean": round(float(s_mean), 2), "universe_mean": round(float(u_mean), 2), "ratio": round(float(ratio), 2)})

    # Categorical columns - find mode differences
    cat_cols = ['AGE_GROUP', 'INCOME_BRACKET', 'HOMEOWNER', 'URBANICITY', 'CHANNEL_PREFERENCE', 'MARITAL_STATUS']
    for col in cat_cols:
        u_mode = universe[col].mode().iloc[0] if not universe[col].mode().empty else None
        s_mode = seed_universe[col].mode().iloc[0] if not seed_universe[col].mode().empty else None
        if s_mode and u_mode:
            s_pct = (seed_universe[col] == s_mode).mean()
            u_pct = (universe[col] == s_mode).mean()
            if s_pct > u_pct * 1.3:
                profile["over_indexes"].append({"feature": col, "seed_dominant": s_mode, "seed_pct": round(float(s_pct * 100), 1), "universe_pct": round(float(u_pct * 100), 1), "type": "categorical"})

    # Purchase category affinity
    purchases = session.sql("""
        SELECT CONSUMER_ID, CATEGORY, SUM(AMOUNT) AS SPEND
        FROM LOOKALIKE_DEMO.RAW.PURCHASE_HISTORY
        GROUP BY CONSUMER_ID, CATEGORY
    """).to_pandas()

    seed_purchases = purchases[purchases['CONSUMER_ID'].isin(seed_ids)]
    if len(seed_purchases) > 0:
        seed_cat_pct = seed_purchases.groupby('CATEGORY')['SPEND'].sum()
        seed_cat_pct = (seed_cat_pct / seed_cat_pct.sum() * 100).round(1)
        all_cat_pct = purchases.groupby('CATEGORY')['SPEND'].sum()
        all_cat_pct = (all_cat_pct / all_cat_pct.sum() * 100).round(1)

        for cat in seed_cat_pct.index:
            if cat in all_cat_pct.index and all_cat_pct[cat] > 0:
                ratio = seed_cat_pct[cat] / all_cat_pct[cat]
                if ratio > 1.3:
                    profile["over_indexes"].append({"feature": f"category_{cat}", "seed_pct": float(seed_cat_pct[cat]), "universe_pct": float(all_cat_pct[cat]), "ratio": round(float(ratio), 2), "type": "purchase_category"})

    return profile
$$;

-- Tool 3: Validate proposed features statistically (balanced sampling)
CREATE OR REPLACE PROCEDURE LOOKALIKE_DEMO.MODELS.VALIDATE_FEATURES(seed_name VARCHAR, feature_list VARCHAR)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'snowflake-ml-python', 'numpy', 'pandas')
HANDLER = 'run'
AS
$$
import numpy as np
import pandas as pd
import json as _json
from snowflake.ml.feature_store import FeatureStore

def run(session, seed_name, feature_list):
    feature_list = _json.loads(feature_list) if isinstance(feature_list, str) else list(feature_list)
    fs = FeatureStore(session=session, database="LOOKALIKE_DEMO", name="FEATURE_STORE",
                      default_warehouse="LOOKALIKE_WH")

    # Get seed IDs
    seed = session.sql(f"""
        SELECT CONSUMER_ID FROM LOOKALIKE_DEMO.RAW.CAMPAIGN_SEEDS
        WHERE SEED_NAME = '{seed_name}'
    """).to_pandas()
    seed_ids = set(seed['CONSUMER_ID'].tolist())
    seed_count = len(seed_ids)

    # Balanced sample: all seed + 3x random non-seed (avoids dilution from full 100K)
    nonseed_limit = seed_count * 3
    nonseed = session.sql(f"""
        SELECT CONSUMER_ID FROM LOOKALIKE_DEMO.RAW.CONSUMER_UNIVERSE
        WHERE CONSUMER_ID NOT IN (
            SELECT CONSUMER_ID FROM LOOKALIKE_DEMO.RAW.CAMPAIGN_SEEDS
            WHERE SEED_NAME = '{seed_name}'
        )
        ORDER BY RANDOM()
        LIMIT {nonseed_limit}
    """).to_pandas()

    sample = pd.concat([
        seed.assign(LABEL=1),
        nonseed.assign(LABEL=0)
    ], ignore_index=True)

    # Retrieve features for the sample
    feature_views = fs.list_feature_views().to_pandas()
    all_features = sample[['CONSUMER_ID', 'LABEL']]

    for _, fv_row in feature_views.iterrows():
        fv = fs.get_feature_view(name=fv_row['NAME'], version=fv_row['VERSION'])
        fv_data = fs.read_feature_view(fv).to_pandas()
        all_features = all_features.merge(fv_data, on='CONSUMER_ID', how='left')

    # Validate each requested feature
    results = []
    for feat in feature_list:
        if feat not in all_features.columns:
            results.append({"feature": feat, "status": "NOT_FOUND", "mutual_information": 0.0, "correlation": 0.0, "recommended": False})
            continue

        col_data = all_features[feat].copy()
        if col_data.dtype == 'object':
            col_data = col_data.astype('category').cat.codes
        col_data = col_data.fillna(0).astype(float)
        label = all_features['LABEL'].astype(float)

        corr = float(np.corrcoef(col_data, label)[0, 1]) if col_data.std() > 0 else 0.0
        if np.isnan(corr):
            corr = 0.0

        bins = min(10, max(2, int(col_data.nunique())))
        try:
            discretized = pd.cut(col_data, bins=bins, labels=False, duplicates='drop').fillna(0).astype(int)
            contingency = pd.crosstab(discretized, label)
            p_joint = contingency / contingency.sum().sum()
            p_x = p_joint.sum(axis=1)
            p_y = p_joint.sum(axis=0)
            mi = 0.0
            for i in p_joint.index:
                for j in p_joint.columns:
                    if p_joint.loc[i, j] > 0:
                        mi += float(p_joint.loc[i, j]) * np.log2(float(p_joint.loc[i, j]) / (float(p_x[i]) * float(p_y[j])))
        except Exception:
            mi = 0.0

        recommended = bool(mi >= 0.005 and abs(corr) >= 0.03)
        results.append({
            "feature": feat,
            "mutual_information": round(float(mi), 4),
            "correlation": round(float(corr), 4),
            "recommended": recommended
        })

    results.sort(key=lambda x: x['mutual_information'], reverse=True)
    kept = [r['feature'] for r in results if r['recommended']]
    dropped = [r['feature'] for r in results if not r['recommended']]

    return {
        "sample_size": len(sample),
        "seed_count": seed_count,
        "results": results,
        "kept_features": kept,
        "dropped_features": dropped,
        "kept_count": len(kept),
        "dropped_count": len(dropped)
    }
$$;

-- Tool 4: Train model, score universe, compute lift (balanced training)
CREATE OR REPLACE PROCEDURE LOOKALIKE_DEMO.MODELS.TRAIN_AND_SCORE(seed_name VARCHAR, feature_list VARCHAR, model_name VARCHAR)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'snowflake-ml-python', 'xgboost', 'numpy', 'pandas', 'scikit-learn')
HANDLER = 'run'
AS
$$
import json as _json
import numpy as np
import pandas as pd
from snowflake.ml.feature_store import FeatureStore

def run(session, seed_name, feature_list, model_name):
    feature_list = _json.loads(feature_list) if isinstance(feature_list, str) else list(feature_list)
    import xgboost as xgb
    from sklearn.metrics import roc_auc_score, precision_score, recall_score, f1_score
    from sklearn.model_selection import train_test_split

    fs = FeatureStore(session=session, database="LOOKALIKE_DEMO", name="FEATURE_STORE",
                      default_warehouse="LOOKALIKE_WH")

    # Get seed IDs
    seed = session.sql(f"""
        SELECT CONSUMER_ID FROM LOOKALIKE_DEMO.RAW.CAMPAIGN_SEEDS
        WHERE SEED_NAME = '{seed_name}'
    """).to_pandas()
    seed_ids = set(seed['CONSUMER_ID'].tolist())
    seed_count = len(seed_ids)

    # Balanced training: all seed + 5x non-seed
    nonseed_limit = min(seed_count * 5, 5000)
    nonseed_sample = session.sql(f"""
        SELECT CONSUMER_ID FROM LOOKALIKE_DEMO.RAW.CONSUMER_UNIVERSE
        WHERE CONSUMER_ID NOT IN (
            SELECT CONSUMER_ID FROM LOOKALIKE_DEMO.RAW.CAMPAIGN_SEEDS
            WHERE SEED_NAME = '{seed_name}'
        )
        ORDER BY RANDOM()
        LIMIT {nonseed_limit}
    """).to_pandas()

    train_sample = pd.concat([
        seed.assign(LABEL=1),
        nonseed_sample.assign(LABEL=0)
    ], ignore_index=True)

    # Full universe for scoring
    full_universe = session.sql("SELECT CONSUMER_ID FROM LOOKALIKE_DEMO.RAW.CONSUMER_UNIVERSE").to_pandas()
    full_universe['LABEL'] = full_universe['CONSUMER_ID'].apply(lambda x: 1 if x in seed_ids else 0)

    # Retrieve features
    feature_views = fs.list_feature_views().to_pandas()
    train_features = train_sample[['CONSUMER_ID', 'LABEL']]
    score_features = full_universe[['CONSUMER_ID', 'LABEL']]
    fvs_used = []

    for _, fv_row in feature_views.iterrows():
        fv = fs.get_feature_view(name=fv_row['NAME'], version=fv_row['VERSION'])
        fv_data = fs.read_feature_view(fv).to_pandas()
        fv_cols = [c for c in fv_data.columns if c != 'CONSUMER_ID']
        if any(f in fv_cols for f in feature_list):
            train_features = train_features.merge(fv_data, on='CONSUMER_ID', how='left')
            score_features = score_features.merge(fv_data, on='CONSUMER_ID', how='left')
            fvs_used.append(fv_row['NAME'])

    # Prepare features
    available = [f for f in feature_list if f in train_features.columns]
    for col in available:
        if train_features[col].dtype == 'object':
            train_features[col] = train_features[col].astype('category').cat.codes
            score_features[col] = score_features[col].astype('category').cat.codes
        train_features[col] = train_features[col].fillna(0).astype(float)
        score_features[col] = score_features[col].fillna(0).astype(float)

    # Stratified train/test split
    train_df, test_df = train_test_split(train_features, test_size=0.2, random_state=42, stratify=train_features['LABEL'])

    X_train = train_df[available].values
    y_train = train_df['LABEL'].values
    X_test = test_df[available].values
    y_test = test_df['LABEL'].values

    # Train on balanced data
    model = xgb.XGBClassifier(
        n_estimators=200, max_depth=5, learning_rate=0.1,
        scale_pos_weight=1.0, eval_metric='logloss', use_label_encoder=False, random_state=42
    )
    model.fit(X_train, y_train)

    # Evaluate
    y_pred_proba = model.predict_proba(X_test)[:, 1]
    y_pred = (y_pred_proba >= 0.5).astype(int)
    auc = float(roc_auc_score(y_test, y_pred_proba))
    prec = float(precision_score(y_test, y_pred, zero_division=0))
    rec = float(recall_score(y_test, y_pred, zero_division=0))
    f1 = float(f1_score(y_test, y_pred, zero_division=0))
    metrics = {"auc": round(auc, 4), "precision": round(prec, 4), "recall": round(rec, 4), "f1": round(f1, 4)}

    # Feature importance
    importance = dict(zip(available, [float(x) for x in model.feature_importances_]))
    sorted_imp = sorted(importance.items(), key=lambda x: x[1], reverse=True)
    top_features = [{"feature": k, "importance": round(v, 4)} for k, v in sorted_imp[:10]]

    # Score full universe
    X_all = score_features[available].values
    score_features['SCORE'] = model.predict_proba(X_all)[:, 1]
    score_features['DECILE'] = pd.qcut(score_features['SCORE'], 10, labels=False, duplicates='drop')
    score_features['DECILE'] = 10 - score_features['DECILE']

    # Save scored universe
    scored_out = score_features[['CONSUMER_ID', 'SCORE', 'DECILE']].copy()
    session.create_dataframe(scored_out).write.save_as_table(
        f"LOOKALIKE_DEMO.SCORING.{model_name.upper()}_SCORED", mode="overwrite"
    )

    # Lift by decile
    lift_data = []
    total_seed = int(score_features['LABEL'].sum())
    for d in range(1, 11):
        decile_df = score_features[score_features['DECILE'] == d]
        seed_in_decile = int(decile_df['LABEL'].sum())
        lift = round(float(seed_in_decile / (total_seed / 10)), 2) if total_seed > 0 else 0.0
        lift_data.append({"DECILE": d, "CONSUMERS": len(decile_df), "SEED_IN_DECILE": seed_in_decile, "LIFT": lift})

    lift_df = pd.DataFrame(lift_data)
    lift_df['CUM_PCT_CAPTURED'] = (lift_df['SEED_IN_DECILE'].cumsum() / total_seed * 100).round(1)
    session.create_dataframe(lift_df).write.save_as_table(
        f"LOOKALIKE_DEMO.MONITORING.{model_name.upper()}_LIFT", mode="overwrite"
    )

    confidence = "High" if auc > 0.75 else ("Medium" if auc > 0.65 else "Low")

    return {
        "model_name": model_name,
        "seed_name": seed_name,
        "metrics": metrics,
        "confidence": confidence,
        "top_features": top_features[:5],
        "lift_decile_1": float(lift_data[0]['LIFT']),
        "features_used": available,
        "feature_views_used": fvs_used,
        "training_set_size": len(train_features),
        "total_scored": len(score_features),
        "top_3_deciles_count": int(score_features[score_features['DECILE'] <= 3].shape[0])
    }
$$;

-- Tool 5: List all feature columns from the Feature Store
CREATE OR REPLACE PROCEDURE LOOKALIKE_DEMO.MODELS.LIST_FEATURE_COLUMNS()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'snowflake-ml-python')
HANDLER = 'run'
AS
$$
from snowflake.ml.feature_store import FeatureStore

def run(session):
    fs = FeatureStore(session=session, database="LOOKALIKE_DEMO", name="FEATURE_STORE",
                      default_warehouse="LOOKALIKE_WH")
    feature_views = fs.list_feature_views().to_pandas()
    result = []
    for _, fv_row in feature_views.iterrows():
        fv = fs.get_feature_view(name=fv_row['NAME'], version=fv_row['VERSION'])
        fv_data = fs.read_feature_view(fv)
        columns = [c for c in fv_data.columns if c != 'CONSUMER_ID']
        result.append({
            "feature_view": fv_row['NAME'],
            "version": fv_row['VERSION'],
            "description": fv_row.get('DESC', ''),
            "columns": columns
        })
    return result
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. VERIFICATION
-- ─────────────────────────────────────────────────────────────────────────────

SELECT 'CONSUMER_UNIVERSE' AS table_name, COUNT(*) AS row_count FROM LOOKALIKE_DEMO.RAW.CONSUMER_UNIVERSE
UNION ALL
SELECT 'PURCHASE_HISTORY', COUNT(*) FROM LOOKALIKE_DEMO.RAW.PURCHASE_HISTORY
UNION ALL
SELECT 'CHANNEL_ENGAGEMENT', COUNT(*) FROM LOOKALIKE_DEMO.RAW.CHANNEL_ENGAGEMENT
UNION ALL
SELECT 'CAMPAIGN_SEEDS', COUNT(*) FROM LOOKALIKE_DEMO.RAW.CAMPAIGN_SEEDS
ORDER BY table_name;

SELECT 'Seed Audience Sizes' AS check_name;
SELECT SEED_NAME, COUNT(*) AS seed_size, MAX(SEED_DESCRIPTION) AS description
FROM LOOKALIKE_DEMO.RAW.CAMPAIGN_SEEDS
GROUP BY SEED_NAME
ORDER BY SEED_NAME;

SELECT 'Universe Demographics' AS check_name;
SELECT AGE_GROUP, COUNT(*) AS consumers, ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct
FROM LOOKALIKE_DEMO.RAW.CONSUMER_UNIVERSE
GROUP BY AGE_GROUP
ORDER BY AGE_GROUP;

SELECT 'Purchase Category Distribution' AS check_name;
SELECT CATEGORY, COUNT(*) AS purchases, ROUND(SUM(AMOUNT), 0) AS total_spend
FROM LOOKALIKE_DEMO.RAW.PURCHASE_HISTORY
GROUP BY CATEGORY
ORDER BY purchases DESC;

SELECT 'Channel Engagement Distribution' AS check_name;
SELECT CHANNEL, EVENT_TYPE, COUNT(*) AS events
FROM LOOKALIKE_DEMO.RAW.CHANNEL_ENGAGEMENT
GROUP BY CHANNEL, EVENT_TYPE
ORDER BY CHANNEL, events DESC;

-- Show all created objects
SHOW SCHEMAS IN DATABASE LOOKALIKE_DEMO;
SHOW TABLES IN SCHEMA LOOKALIKE_DEMO.RAW;
SHOW STAGES IN SCHEMA LOOKALIKE_DEMO.MODELS;
