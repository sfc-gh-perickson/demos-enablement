-- =============================================================================
-- Dynamic Time-Period Metrics in Semantic Views: Setup Script
-- =============================================================================
-- Run this script once before starting the notebook.
-- It creates all prerequisite objects: database, warehouse, sample data table,
-- and three semantic views demonstrating different patterns.
--
-- Prerequisites:
--   - A role with CREATE DATABASE, CREATE WAREHOUSE privileges
--   - Semantic views feature enabled on your account
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. DATABASE AND SCHEMA
-- ─────────────────────────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS DYNAMIC_METRICS_DEMO;
USE DATABASE DYNAMIC_METRICS_DEMO;
CREATE SCHEMA IF NOT EXISTS PUBLIC;
USE SCHEMA PUBLIC;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. WAREHOUSE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE WAREHOUSE IF NOT EXISTS DYNAMIC_METRICS_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;

USE WAREHOUSE DYNAMIC_METRICS_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. SAMPLE DATA: daily_revenue
-- ─────────────────────────────────────────────────────────────────────────────
-- 2 years of daily revenue data (2023-01-01 to 2024-12-30)
-- 4 regions x 3 product categories = 12 rows per day = ~8,760 total rows
-- Includes seasonality, growth trend, and random noise for realism.

CREATE OR REPLACE TABLE daily_revenue AS
WITH date_spine AS (
  SELECT DATEADD(day, seq4(), '2023-01-01')::DATE AS sale_date
  FROM TABLE(GENERATOR(ROWCOUNT => 730))
),
regions AS (
  SELECT column1 AS region FROM VALUES ('East'), ('West'), ('North'), ('South')
),
categories AS (
  SELECT column1 AS product_category FROM VALUES ('Electronics'), ('Clothing'), ('Food')
),
base AS (
  SELECT
    d.sale_date,
    r.region,
    c.product_category
  FROM date_spine d
  CROSS JOIN regions r
  CROSS JOIN categories c
)
SELECT
  sale_date,
  region,
  product_category,
  ROUND(
    CASE product_category
      WHEN 'Electronics' THEN 5000
      WHEN 'Clothing' THEN 2000
      WHEN 'Food' THEN 1000
    END
    * (1 + 0.3 * SIN(2 * PI() * DAYOFYEAR(sale_date) / 365))
    * (1 + 0.1 * (DATEDIFF(day, '2023-01-01', sale_date) / 365.0))
    * (0.8 + 0.4 * RANDOM() / 9223372036854775807)
  , 2) AS revenue,
  ROUND(
    CASE product_category
      WHEN 'Electronics' THEN 20
      WHEN 'Clothing' THEN 50
      WHEN 'Food' THEN 200
    END
    * (1 + 0.2 * SIN(2 * PI() * DAYOFYEAR(sale_date) / 365))
    * (0.8 + 0.4 * RANDOM() / 9223372036854775807)
  , 0) AS units_sold
FROM base;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. SEMANTIC VIEW #1: Variable-Based Dynamic Time Grain
-- ─────────────────────────────────────────────────────────────────────────────
-- Uses a `time_grain` variable that accepts 'month', 'quarter', or 'year'.
-- The dimension expression dynamically formats the time period label.

CREATE OR REPLACE SEMANTIC VIEW sv_variable_time_grain
  TABLES (
    revenue AS DYNAMIC_METRICS_DEMO.PUBLIC.daily_revenue
  )
  VARIABLES (
    time_grain VARCHAR DEFAULT 'month'
  )
  DIMENSIONS (
    revenue.time_period AS
      CASE time_grain
        WHEN 'month'   THEN TO_CHAR(sale_date, 'YYYY-MM')
        WHEN 'quarter' THEN TO_CHAR(sale_date, 'YYYY') || '-Q' || TO_CHAR(QUARTER(sale_date))
        WHEN 'year'    THEN TO_CHAR(sale_date, 'YYYY')
        ELSE TO_CHAR(sale_date, 'YYYY-MM')
      END,
    revenue.region AS region,
    revenue.product_category AS product_category
  )
  METRICS (
    revenue.total_revenue AS SUM(revenue),
    revenue.total_units AS SUM(units_sold),
    revenue.avg_daily_revenue AS AVG(revenue),
    revenue.transaction_days AS COUNT(sale_date)
  )
  COMMENT = 'Pattern 1: Use time_grain variable (month/quarter/year) to dynamically switch aggregation period';

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. SEMANTIC VIEW #2: Window Function Metrics
-- ─────────────────────────────────────────────────────────────────────────────
-- Defines rolling averages, running totals, and lag-based comparisons
-- on daily-grain data using window function metrics.

CREATE OR REPLACE SEMANTIC VIEW sv_window_metrics
  TABLES (
    revenue AS DYNAMIC_METRICS_DEMO.PUBLIC.daily_revenue
  )
  DIMENSIONS (
    revenue.sale_date AS sale_date,
    revenue.region AS region,
    revenue.product_category AS product_category
  )
  METRICS (
    revenue.daily_revenue AS SUM(revenue),

    revenue.rolling_7day_avg AS AVG(daily_revenue)
      OVER (PARTITION BY EXCLUDING revenue.sale_date
            ORDER BY revenue.sale_date
            RANGE BETWEEN INTERVAL '6 days' PRECEDING AND CURRENT ROW),

    revenue.rolling_30day_total AS SUM(daily_revenue)
      OVER (PARTITION BY EXCLUDING revenue.sale_date
            ORDER BY revenue.sale_date
            RANGE BETWEEN INTERVAL '29 days' PRECEDING AND CURRENT ROW),

    revenue.revenue_7_days_ago AS LAG(daily_revenue, 7)
      OVER (PARTITION BY EXCLUDING revenue.sale_date
            ORDER BY revenue.sale_date),

    revenue.revenue_30_days_ago AS LAG(daily_revenue, 30)
      OVER (PARTITION BY EXCLUDING revenue.sale_date
            ORDER BY revenue.sale_date)
  )
  COMMENT = 'Pattern 2: Window function metrics for rolling averages, running totals, and period-over-period lag comparisons';

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. SEMANTIC VIEW #3: Combined (Multiple Grain Dimensions + Window Functions)
-- ─────────────────────────────────────────────────────────────────────────────
-- Defines separate dimensions for each grain (month, quarter, year).
-- Users choose which grain to query with, and window functions compute
-- prior-period, cumulative, and moving average metrics that adapt accordingly.

CREATE OR REPLACE SEMANTIC VIEW sv_combined_dynamic
  TABLES (
    revenue AS DYNAMIC_METRICS_DEMO.PUBLIC.daily_revenue
  )
  DIMENSIONS (
    revenue.month_period AS TO_CHAR(sale_date, 'YYYY-MM'),
    revenue.quarter_period AS TO_CHAR(sale_date, 'YYYY') || '-Q' || TO_CHAR(QUARTER(sale_date)),
    revenue.year_period AS TO_CHAR(sale_date, 'YYYY'),
    revenue.region AS region,
    revenue.product_category AS product_category
  )
  METRICS (
    revenue.period_revenue AS SUM(revenue),

    revenue.prior_month_revenue AS LAG(period_revenue, 1)
      OVER (PARTITION BY EXCLUDING revenue.month_period
            ORDER BY revenue.month_period),

    revenue.prior_quarter_revenue AS LAG(period_revenue, 1)
      OVER (PARTITION BY EXCLUDING revenue.quarter_period
            ORDER BY revenue.quarter_period),

    revenue.moving_avg_3_months AS AVG(period_revenue)
      OVER (PARTITION BY EXCLUDING revenue.month_period
            ORDER BY revenue.month_period
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW),

    revenue.cumulative_monthly AS SUM(period_revenue)
      OVER (PARTITION BY EXCLUDING revenue.month_period
            ORDER BY revenue.month_period
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
  )
  COMMENT = 'Pattern 3: Multiple grain dimensions + window functions. Query with month_period OR quarter_period to get different granularities with their respective window calculations.';

-- ─────────────────────────────────────────────────────────────────────────────
-- SETUP COMPLETE
-- ─────────────────────────────────────────────────────────────────────────────
-- Verify objects were created:
SELECT COUNT(*) AS row_count FROM daily_revenue;
SHOW SEMANTIC VIEWS IN SCHEMA DYNAMIC_METRICS_DEMO.PUBLIC;
