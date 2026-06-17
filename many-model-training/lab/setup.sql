-- =============================================================================
-- Many-Model Training Lab: Setup Script
-- =============================================================================
-- Run this script once before starting the lab notebooks.
-- It creates all prerequisite objects: database, schemas, tables, warehouse,
-- staging infrastructure, and generates synthetic retail demand data.
--
-- Prerequisites:
--   - A role with CREATE DATABASE, CREATE WAREHOUSE privileges
--   - Snowflake ML Functions enabled on the account
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. DATABASE AND SCHEMA
-- ─────────────────────────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS MMT_DEMO;
USE DATABASE MMT_DEMO;
CREATE SCHEMA IF NOT EXISTS FORECASTING;
USE SCHEMA FORECASTING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. WAREHOUSE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE WAREHOUSE IF NOT EXISTS MMT_DEMO_WH
  WAREHOUSE_SIZE = 'MEDIUM'
  AUTO_SUSPEND = 120
  AUTO_RESUME = TRUE;

USE WAREHOUSE MMT_DEMO_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. INTERNAL STAGE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE STAGE IF NOT EXISTS ML_STAGE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. FEATURE STORE SCHEMA AND TABLE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE SCHEMA IF NOT EXISTS MMT_DEMO.FEATURE_STORE;

CREATE OR REPLACE TABLE MMT_DEMO.FEATURE_STORE.FEATURE_TABLE (
    STORE_ITEM_ID         VARCHAR       COMMENT 'Partition key, e.g. S001_SANDWICH_A',
    TS                    TIMESTAMP_NTZ COMMENT 'Hourly timestamp',
    DEMAND                NUMBER        COMMENT 'Target: units demanded per hour',
    HOUR_OF_DAY           NUMBER        COMMENT 'Hour extracted from TS (0-23)',
    DAY_OF_WEEK           NUMBER        COMMENT 'Day of week (0=Mon, 6=Sun)',
    IS_WEEKEND            BOOLEAN       COMMENT 'True if Saturday or Sunday',
    IS_HOLIDAY            BOOLEAN       COMMENT 'True if timestamp falls on a holiday',
    WEATHER_TEMP          FLOAT         COMMENT 'Temperature in Fahrenheit',
    EVENT_FLAG            BOOLEAN       COMMENT 'True if a local event is occurring',
    ROLLING_7D_AVG        FLOAT         COMMENT 'Rolling 7-day average demand for this partition',
    ROLLING_4W_SAME_HOUR  FLOAT         COMMENT 'Average demand for same hour over prior 4 weeks'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. SYNTHETIC DATA GENERATION
-- ─────────────────────────────────────────────────────────────────────────────
-- Generates 432,000 rows: 200 partitions × 2,160 hourly timesteps (90 days).
-- Store archetypes: urban, suburban, rural, college, highway
-- Items: breakfast/lunch/dinner/snack profiles with realistic hourly patterns.

CREATE OR REPLACE PROCEDURE MMT_DEMO.FORECASTING.GENERATE_SYNTHETIC_DATA()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    v_status VARCHAR;
BEGIN
    -- Clear existing data
    DELETE FROM MMT_DEMO.FEATURE_STORE.FEATURE_TABLE;

    -- Generate all combinations of stores, items, and timestamps
    -- then apply demand patterns based on store archetype and item type
    INSERT INTO MMT_DEMO.FEATURE_STORE.FEATURE_TABLE (
        STORE_ITEM_ID, TS, DEMAND, HOUR_OF_DAY, DAY_OF_WEEK,
        IS_WEEKEND, IS_HOLIDAY, WEATHER_TEMP, EVENT_FLAG,
        ROLLING_7D_AVG, ROLLING_4W_SAME_HOUR
    )
    WITH
    -- Store definitions with archetypes
    stores AS (
        SELECT column1 AS store_id, column2 AS archetype, column3 AS base_volume
        FROM VALUES
            ('S001', 'urban',    50), ('S002', 'urban',    55), ('S003', 'urban',    48), ('S004', 'urban',    52),
            ('S005', 'suburban', 35), ('S006', 'suburban', 38), ('S007', 'suburban', 33), ('S008', 'suburban', 36),
            ('S009', 'rural',    20), ('S010', 'rural',    22), ('S011', 'rural',    18), ('S012', 'rural',    21),
            ('S013', 'college',  40), ('S014', 'college',  42), ('S015', 'college',  38), ('S016', 'college',  41),
            ('S017', 'highway',  30), ('S018', 'highway',  32), ('S019', 'highway',  28), ('S020', 'highway',  31)
    ),
    -- Item definitions with meal-period affinity
    items AS (
        SELECT column1 AS item_id, column2 AS item_type, column3 AS item_multiplier
        FROM VALUES
            ('SANDWICH_A', 'lunch',     1.0),
            ('SANDWICH_B', 'lunch',     0.8),
            ('PIZZA',      'dinner',    1.2),
            ('HOT_DOG',    'lunch',     0.7),
            ('SNACK_A',    'snack',     0.5),
            ('SNACK_B',    'snack',     0.4),
            ('BEVERAGE_A', 'beverage',  1.3),
            ('BEVERAGE_B', 'beverage',  0.9),
            ('SOUP',       'breakfast', 0.6),
            ('PASTRY',     'breakfast', 0.8)
    ),
    -- Generate 2160 hourly timestamps starting 2026-01-01
    hours AS (
        SELECT DATEADD('hour', seq4(), '2026-01-01'::TIMESTAMP_NTZ) AS ts
        FROM TABLE(GENERATOR(ROWCOUNT => 2160))
    ),
    -- US holidays in the 90-day window (Jan-Mar 2026)
    holidays AS (
        SELECT column1::DATE AS holiday_date
        FROM VALUES
            ('2026-01-01'),  -- New Year's Day
            ('2026-01-19'),  -- MLK Day
            ('2026-02-16'),  -- Presidents' Day
            ('2026-03-17')   -- St. Patrick's Day (observed)
    ),
    -- Base weather: sinusoidal daily pattern with random variation per day
    -- Temperature range: 15-55°F for Jan-Mar (winter/early spring)
    weather_base AS (
        SELECT
            ts,
            -- Seasonal trend: starts cold in Jan, warms toward March
            25.0 + (DATEDIFF('day', '2026-01-01', ts) * 0.15)
            -- Daily cycle: cooler at night, warmer midday
            + 8.0 * SIN(((HOUR(ts) - 6.0) / 24.0) * 2 * 3.14159)
            -- Random daily variation (seeded by day)
            + (ABS(MOD(HASH(DATE_TRUNC('day', ts)::VARCHAR), 1000)) / 1000.0 - 0.5) * 20.0
            AS temp_f
        FROM hours
    ),
    -- Event flags: ~5% of hours have an event, clustered on weekends/evenings
    events AS (
        SELECT
            ts,
            CASE
                WHEN DAYOFWEEK(ts) IN (0, 6) AND HOUR(ts) BETWEEN 10 AND 22
                    AND ABS(MOD(HASH(ts::VARCHAR || 'event'), 100)) < 15
                THEN TRUE
                WHEN HOUR(ts) BETWEEN 17 AND 22
                    AND ABS(MOD(HASH(ts::VARCHAR || 'event2'), 100)) < 5
                THEN TRUE
                ELSE FALSE
            END AS event_flag
        FROM hours
    ),
    -- Cross join all dimensions
    base_data AS (
        SELECT
            s.store_id,
            s.archetype,
            s.base_volume,
            i.item_id,
            i.item_type,
            i.item_multiplier,
            h.ts,
            HOUR(h.ts) AS hour_of_day,
            DAYOFWEEK(h.ts) AS day_of_week,  -- 0=Mon in Snowflake
            CASE WHEN DAYOFWEEK(h.ts) IN (5, 6) THEN TRUE ELSE FALSE END AS is_weekend,
            CASE WHEN h.ts::DATE IN (SELECT holiday_date FROM holidays) THEN TRUE ELSE FALSE END AS is_holiday,
            GREATEST(w.temp_f, 5.0) AS weather_temp,
            e.event_flag,
            s.store_id || '_' || i.item_id AS store_item_id
        FROM stores s
        CROSS JOIN items i
        CROSS JOIN hours h
        LEFT JOIN weather_base w ON w.ts = h.ts
        LEFT JOIN events e ON e.ts = h.ts
    ),
    -- Apply demand patterns
    demand_calc AS (
        SELECT
            store_item_id,
            ts,
            hour_of_day,
            day_of_week,
            is_weekend,
            is_holiday,
            weather_temp,
            event_flag,
            -- Calculate raw demand based on archetype + item + hour interaction
            GREATEST(0, ROUND(
                base_volume * item_multiplier
                -- Hour-of-day multiplier based on item type
                * CASE item_type
                    WHEN 'breakfast' THEN
                        CASE WHEN hour_of_day BETWEEN 6 AND 9 THEN 2.5
                             WHEN hour_of_day BETWEEN 10 AND 11 THEN 1.2
                             ELSE 0.3 END
                    WHEN 'lunch' THEN
                        CASE WHEN hour_of_day BETWEEN 11 AND 14 THEN 2.5
                             WHEN hour_of_day BETWEEN 15 AND 17 THEN 1.0
                             ELSE 0.4 END
                    WHEN 'dinner' THEN
                        CASE WHEN hour_of_day BETWEEN 17 AND 20 THEN 2.5
                             WHEN hour_of_day BETWEEN 21 AND 22 THEN 1.5
                             ELSE 0.3 END
                    WHEN 'snack' THEN
                        CASE WHEN hour_of_day BETWEEN 10 AND 22 THEN 1.2
                             WHEN hour_of_day BETWEEN 23 AND 23 OR hour_of_day BETWEEN 0 AND 2 THEN 0.8
                             ELSE 0.3 END
                    WHEN 'beverage' THEN
                        CASE WHEN hour_of_day BETWEEN 7 AND 9 THEN 2.0
                             WHEN hour_of_day BETWEEN 11 AND 14 THEN 1.8
                             WHEN hour_of_day BETWEEN 15 AND 20 THEN 1.3
                             ELSE 0.4 END
                  END
                -- Archetype modifiers
                * CASE archetype
                    WHEN 'urban' THEN
                        CASE WHEN hour_of_day BETWEEN 7 AND 9 THEN 1.5
                             WHEN hour_of_day BETWEEN 12 AND 13 THEN 1.8
                             ELSE 1.0 END
                    WHEN 'suburban' THEN
                        CASE WHEN is_weekend THEN 1.4 ELSE 1.0 END
                    WHEN 'rural' THEN
                        CASE WHEN hour_of_day BETWEEN 11 AND 13 THEN 2.0
                             ELSE 0.7 END
                    WHEN 'college' THEN
                        CASE WHEN hour_of_day BETWEEN 21 AND 23 OR hour_of_day BETWEEN 0 AND 2 THEN 2.5
                             WHEN hour_of_day BETWEEN 10 AND 14 THEN 1.3
                             ELSE 0.6 END
                    WHEN 'highway' THEN 1.0  -- Steady 24hr
                  END
                -- Day-of-week effect
                * CASE
                    WHEN day_of_week IN (5, 6) THEN 1.15  -- Weekend boost
                    WHEN day_of_week = 4 THEN 1.05        -- Friday boost
                    ELSE 1.0
                  END
                -- Holiday boost
                * CASE WHEN is_holiday THEN 1.3 ELSE 1.0 END
                -- Event boost
                * CASE WHEN event_flag THEN 1.4 ELSE 1.0 END
                -- Weather effect: cold weather boosts soup/hot items, warm boosts beverages
                * CASE
                    WHEN item_type = 'breakfast' AND weather_temp < 30 THEN 1.2
                    WHEN item_type = 'beverage' AND weather_temp > 45 THEN 1.2
                    WHEN weather_temp < 20 THEN 0.85  -- Extreme cold reduces traffic
                    ELSE 1.0
                  END
                -- Random noise (±20% using hash-based pseudo-random)
                * (0.8 + 0.4 * (ABS(MOD(HASH(store_item_id || ts::VARCHAR), 10000)) / 10000.0))
            ))::NUMBER AS demand
        FROM base_data
    ),
    -- Compute rolling averages
    with_rolling AS (
        SELECT
            store_item_id,
            ts,
            demand,
            hour_of_day,
            day_of_week,
            is_weekend,
            is_holiday,
            weather_temp,
            event_flag,
            -- Rolling 7-day average (168 hours)
            AVG(demand) OVER (
                PARTITION BY store_item_id
                ORDER BY ts
                ROWS BETWEEN 168 PRECEDING AND 1 PRECEDING
            ) AS rolling_7d_avg,
            -- Rolling 4-week same-hour average
            AVG(demand) OVER (
                PARTITION BY store_item_id, hour_of_day
                ORDER BY ts
                ROWS BETWEEN 28 PRECEDING AND 1 PRECEDING
            ) AS rolling_4w_same_hour
        FROM demand_calc
    )
    SELECT
        store_item_id,
        ts,
        demand,
        hour_of_day,
        day_of_week,
        is_weekend,
        is_holiday,
        weather_temp,
        event_flag,
        ROUND(COALESCE(rolling_7d_avg, demand), 2) AS rolling_7d_avg,
        ROUND(COALESCE(rolling_4w_same_hour, demand), 2) AS rolling_4w_same_hour
    FROM with_rolling;

    SELECT COUNT(*) INTO :v_status FROM MMT_DEMO.FEATURE_STORE.FEATURE_TABLE;
    RETURN 'Synthetic data generation complete. Rows inserted: ' || v_status;
END;
$$;

-- Execute the data generation procedure
CALL MMT_DEMO.FORECASTING.GENERATE_SYNTHETIC_DATA();

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. DOWNSTREAM TABLES
-- ─────────────────────────────────────────────────────────────────────────────

-- Model catalog: tracks trained models per partition
CREATE OR REPLACE TABLE MMT_DEMO.FORECASTING.MODEL_CATALOG (
    PARTITION_ID    VARCHAR       COMMENT 'Store-item partition key',
    TRAINED_AT      TIMESTAMP_NTZ COMMENT 'When the model was last trained',
    METRICS         VARIANT       COMMENT 'Training metrics (MAPE, RMSE, etc.)',
    MODEL_VERSION   VARCHAR       COMMENT 'Semantic version of the model',
    IS_ACTIVE       BOOLEAN       COMMENT 'Whether this is the active production model',
    STAGE_PATH      VARCHAR       COMMENT 'Path to serialized model in ML_STAGE'
);

-- Forecast telemetry: stores predictions vs actuals for monitoring
CREATE OR REPLACE TABLE MMT_DEMO.FORECASTING.FORECAST_TELEMETRY (
    STORE_ITEM_ID   VARCHAR       COMMENT 'Partition key',
    TS              TIMESTAMP_NTZ COMMENT 'Prediction timestamp',
    ACTUAL          NUMBER        COMMENT 'Actual observed demand',
    PREDICTED       NUMBER        COMMENT 'Model-predicted demand',
    ERROR           FLOAT         COMMENT 'Absolute prediction error',
    ROLLING_7D_MAPE FLOAT         COMMENT 'Rolling 7-day MAPE for this partition',
    DRIFT_FLAG      BOOLEAN       COMMENT 'True if model drift detected'
);

-- Experiment log: tracks champion/challenger experiments
CREATE OR REPLACE TABLE MMT_DEMO.FORECASTING.EXPERIMENT_LOG (
    EXPERIMENT_ID       VARCHAR       COMMENT 'Unique experiment identifier',
    CREATED_AT          TIMESTAMP_NTZ COMMENT 'When the experiment was created',
    CHAMPION_VERSION    VARCHAR       COMMENT 'Current champion model version',
    CHALLENGER_VERSION  VARCHAR       COMMENT 'Challenger model version being tested',
    STATUS              VARCHAR       COMMENT 'Status: running, completed, promoted, rejected',
    SUMMARY             VARIANT       COMMENT 'Experiment summary metrics and decision'
);

-- Experiment results: per-partition experiment outcomes
CREATE OR REPLACE TABLE MMT_DEMO.FORECASTING.EXPERIMENT_RESULTS (
    EXPERIMENT_ID    VARCHAR COMMENT 'References EXPERIMENT_LOG.EXPERIMENT_ID',
    PARTITION_ID     VARCHAR COMMENT 'Store-item partition key',
    CHAMPION_MAPE    FLOAT  COMMENT 'Champion model MAPE on this partition',
    CHALLENGER_MAPE  FLOAT  COMMENT 'Challenger model MAPE on this partition',
    WINNER           VARCHAR COMMENT 'Which model won: champion or challenger'
);

-- Agent insights: AI-generated operational recommendations
CREATE OR REPLACE TABLE MMT_DEMO.FORECASTING.AGENT_INSIGHTS (
    INSIGHT_ID      VARCHAR       COMMENT 'Unique insight identifier',
    CREATED_AT      TIMESTAMP_NTZ COMMENT 'When the insight was generated',
    CATEGORY        VARCHAR       COMMENT 'Category: drift, anomaly, recommendation, alert',
    STORE_ITEM_ID   VARCHAR       COMMENT 'Relevant partition (nullable for global insights)',
    SUMMARY         VARCHAR       COMMENT 'One-line summary of the insight',
    DETAIL          VARCHAR       COMMENT 'Full explanation',
    RECOMMENDATION  VARCHAR       COMMENT 'Suggested action',
    STATUS          VARCHAR       COMMENT 'Status: new, acknowledged, resolved, dismissed',
    METADATA        VARIANT       COMMENT 'Additional structured metadata'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. VERIFICATION
-- ─────────────────────────────────────────────────────────────────────────────

-- Verify row count in feature table
SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT STORE_ITEM_ID) AS partitions,
       MIN(TS) AS first_ts,
       MAX(TS) AS last_ts
FROM MMT_DEMO.FEATURE_STORE.FEATURE_TABLE;

-- Show all created objects
SHOW TABLES IN SCHEMA MMT_DEMO.FORECASTING;
SHOW TABLES IN SCHEMA MMT_DEMO.FEATURE_STORE;
SHOW STAGES IN SCHEMA MMT_DEMO.FORECASTING;

-- ─────────────────────────────────────────────────────────────────────────────
-- SETUP COMPLETE
-- ─────────────────────────────────────────────────────────────────────────────
-- Expected output:
--   - FEATURE_TABLE: 432,000 rows across 200 partitions
--   - Time range: 2026-01-01 00:00:00 to 2026-03-31 23:00:00
--   - 5 downstream tables created (empty, ready for lab use)
