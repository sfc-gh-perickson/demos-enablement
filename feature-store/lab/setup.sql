-- =============================================================================
-- Feature Store Lab: Setup Script
-- =============================================================================
-- Run this script once before starting the lab notebooks.
-- It creates all prerequisite objects: database, schemas, tables, warehouse,
-- staging infrastructure, and generates synthetic e-commerce data for a
-- real-time product recommendation use case.
--
-- Prerequisites:
--   - A role with CREATE DATABASE, CREATE WAREHOUSE privileges
--   - Snowflake ML Functions enabled on the account
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. DATABASE AND SCHEMAS
-- ─────────────────────────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS FEATURE_STORE_DEMO;
USE DATABASE FEATURE_STORE_DEMO;

CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS FEATURE_STORE;
CREATE SCHEMA IF NOT EXISTS MODELS;
CREATE SCHEMA IF NOT EXISTS SCORING;

USE SCHEMA RAW;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. WAREHOUSE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE WAREHOUSE IF NOT EXISTS FS_DEMO_WH
  WAREHOUSE_SIZE = 'MEDIUM'
  AUTO_SUSPEND = 120
  AUTO_RESUME = TRUE;

USE WAREHOUSE FS_DEMO_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. INTERNAL STAGE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE STAGE IF NOT EXISTS FEATURE_STORE_DEMO.MODELS.ML_STAGE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. RAW DATA TABLES
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE FEATURE_STORE_DEMO.RAW.CUSTOMER_PROFILE (
    CUSTOMER_ID         VARCHAR        COMMENT 'Unique customer identifier, e.g. C00001',
    SIGNUP_DATE         DATE           COMMENT 'Date the customer created their account',
    AGE_GROUP           VARCHAR        COMMENT 'Age bracket: 18-24, 25-34, 35-44, 45-54, 55+',
    GENDER              VARCHAR        COMMENT 'Gender: M, F, NB',
    LOYALTY_TIER        VARCHAR        COMMENT 'Loyalty tier: bronze, silver, gold, platinum',
    PREFERRED_CATEGORY  VARCHAR        COMMENT 'Most-purchased product category',
    CITY                VARCHAR        COMMENT 'Customer city',
    STATE               VARCHAR        COMMENT 'Customer state (US 2-letter)',
    ACCOUNT_STATUS      VARCHAR        COMMENT 'Account status: active, inactive',
    LIFETIME_ORDERS     NUMBER         COMMENT 'Total number of orders placed',
    LIFETIME_SPEND      NUMBER(12,2)   COMMENT 'Total spend in USD',
    AVG_ORDER_VALUE     NUMBER(10,2)   COMMENT 'Average order value in USD',
    DAYS_SINCE_LAST_ORDER NUMBER       COMMENT 'Days since the most recent order'
);

CREATE OR REPLACE TABLE FEATURE_STORE_DEMO.RAW.PRODUCT_CATALOG (
    PRODUCT_ID       VARCHAR        COMMENT 'Unique product identifier, e.g. P0001',
    PRODUCT_NAME     VARCHAR        COMMENT 'Product display name',
    CATEGORY         VARCHAR        COMMENT 'Top-level category',
    SUBCATEGORY      VARCHAR        COMMENT 'Subcategory within category',
    BRAND            VARCHAR        COMMENT 'Brand name',
    PRICE            NUMBER(10,2)   COMMENT 'Current retail price in USD',
    AVG_RATING       NUMBER(3,2)    COMMENT 'Average customer rating 1.0-5.0',
    REVIEW_COUNT     NUMBER         COMMENT 'Total number of reviews',
    DAYS_SINCE_LAUNCH NUMBER        COMMENT 'Days since the product was first listed',
    IN_STOCK         BOOLEAN        COMMENT 'Whether the product is currently in stock',
    MARGIN_PCT       NUMBER(5,2)    COMMENT 'Gross margin percentage'
);

CREATE OR REPLACE TABLE FEATURE_STORE_DEMO.RAW.PURCHASE_HISTORY (
    PURCHASE_ID      VARCHAR        COMMENT 'Unique purchase transaction ID',
    CUSTOMER_ID      VARCHAR        COMMENT 'FK to CUSTOMER_PROFILE',
    PRODUCT_ID       VARCHAR        COMMENT 'FK to PRODUCT_CATALOG',
    PURCHASE_TS      TIMESTAMP_NTZ  COMMENT 'Timestamp of the purchase',
    QUANTITY         NUMBER         COMMENT 'Number of units purchased',
    UNIT_PRICE       NUMBER(10,2)   COMMENT 'Price per unit at time of purchase',
    DISCOUNT_PCT     NUMBER(5,2)    COMMENT 'Discount percentage applied',
    TOTAL_AMOUNT     NUMBER(12,2)   COMMENT 'Final amount charged (qty * price * (1 - discount))'
);

CREATE OR REPLACE TABLE FEATURE_STORE_DEMO.RAW.BROWSE_EVENTS (
    EVENT_ID         VARCHAR        COMMENT 'Unique browse event ID',
    CUSTOMER_ID      VARCHAR        COMMENT 'FK to CUSTOMER_PROFILE',
    PRODUCT_ID       VARCHAR        COMMENT 'FK to PRODUCT_CATALOG',
    EVENT_TS         TIMESTAMP_NTZ  COMMENT 'Timestamp of the browse event',
    EVENT_TYPE       VARCHAR        COMMENT 'Event type: page_view, add_to_cart, wishlist, search_click',
    SESSION_ID       VARCHAR        COMMENT 'Browser session identifier',
    DEVICE_TYPE      VARCHAR        COMMENT 'Device: mobile, desktop, tablet',
    REFERRER         VARCHAR        COMMENT 'Traffic source: search, email, social, direct, recommendation'
);

CREATE OR REPLACE TABLE FEATURE_STORE_DEMO.RAW.PRODUCT_DAILY_METRICS (
    PRODUCT_ID       VARCHAR        COMMENT 'FK to PRODUCT_CATALOG',
    METRIC_DATE      DATE           COMMENT 'Date of the metrics',
    DAILY_VIEWS      NUMBER         COMMENT 'Number of page views for this product',
    DAILY_PURCHASES  NUMBER         COMMENT 'Number of purchases for this product',
    DAILY_CART_ADDS  NUMBER         COMMENT 'Number of add-to-cart events',
    CONVERSION_RATE  NUMBER(5,4)    COMMENT 'Purchases / views ratio',
    TRENDING_SCORE   NUMBER(6,2)    COMMENT 'Composite trending score (higher = more trending)'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. SYNTHETIC DATA GENERATION
-- ─────────────────────────────────────────────────────────────────────────────
-- Generates:
--   CUSTOMER_PROFILE:     ~10,000 rows
--   PRODUCT_CATALOG:      ~1,000 rows
--   PURCHASE_HISTORY:     ~200,000 rows
--   BROWSE_EVENTS:        ~500,000 rows
--   PRODUCT_DAILY_METRICS: ~30,000 rows (1000 products × 30 days)

CREATE OR REPLACE PROCEDURE FEATURE_STORE_DEMO.RAW.GENERATE_SYNTHETIC_DATA()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    v_status VARCHAR;
BEGIN
    -- ─────────────────────────────────────────────────────────────────────
    -- PRODUCT CATALOG (1,000 products)
    -- ─────────────────────────────────────────────────────────────────────
    DELETE FROM FEATURE_STORE_DEMO.RAW.PRODUCT_CATALOG;

    INSERT INTO FEATURE_STORE_DEMO.RAW.PRODUCT_CATALOG (
        PRODUCT_ID, PRODUCT_NAME, CATEGORY, SUBCATEGORY, BRAND,
        PRICE, AVG_RATING, REVIEW_COUNT, DAYS_SINCE_LAUNCH, IN_STOCK, MARGIN_PCT
    )
    WITH
    categories AS (
        SELECT column1 AS cat, column2 AS subcat, column3 AS brand_prefix, column4 AS price_low, column5 AS price_high
        FROM VALUES
            ('Electronics',      'Smartphones',      'Tech',    299.99, 1299.99),
            ('Electronics',      'Laptops',          'Comp',    499.99, 2499.99),
            ('Electronics',      'Headphones',       'Audio',    29.99,  399.99),
            ('Electronics',      'Tablets',          'Tech',    199.99,  999.99),
            ('Electronics',      'Smartwatches',     'Wear',     99.99,  599.99),
            ('Clothing',         'Mens Tops',        'Style',    19.99,  149.99),
            ('Clothing',         'Womens Tops',      'Vogue',    19.99,  179.99),
            ('Clothing',         'Shoes',            'Step',     39.99,  299.99),
            ('Clothing',         'Outerwear',        'Layer',    49.99,  399.99),
            ('Clothing',         'Activewear',       'Fit',      24.99,  129.99),
            ('Home & Garden',    'Furniture',        'Home',     79.99,  999.99),
            ('Home & Garden',    'Kitchen',          'Chef',      9.99,  299.99),
            ('Home & Garden',    'Decor',            'Casa',     14.99,  199.99),
            ('Home & Garden',    'Garden Tools',     'Green',    12.99,  149.99),
            ('Sports',           'Fitness Equipment','Power',    19.99,  499.99),
            ('Sports',           'Outdoor Gear',     'Trail',    29.99,  399.99),
            ('Sports',           'Team Sports',      'Play',      9.99,  199.99),
            ('Books',            'Fiction',          'Read',      7.99,   29.99),
            ('Books',            'Non-Fiction',      'Know',      9.99,   39.99),
            ('Books',            'Technical',        'Code',     19.99,   79.99),
            ('Beauty',           'Skincare',         'Glow',      9.99,   99.99),
            ('Beauty',           'Makeup',           'Color',     7.99,   69.99),
            ('Beauty',           'Haircare',         'Silk',      8.99,   59.99),
            ('Food & Beverage',  'Snacks',           'Munch',     2.99,   24.99),
            ('Food & Beverage',  'Beverages',        'Sip',       1.99,   39.99),
            ('Food & Beverage',  'Gourmet',          'Fine',      9.99,   99.99),
            ('Toys',             'Educational',      'Brain',     9.99,   79.99),
            ('Toys',             'Action Figures',   'Hero',      7.99,   49.99),
            ('Toys',             'Board Games',      'Fun',      14.99,   69.99),
            ('Toys',             'Building Sets',    'Block',    19.99,  149.99)
    ),
    numbered_cats AS (
        SELECT cat, subcat, brand_prefix, price_low, price_high,
               ROW_NUMBER() OVER (ORDER BY cat, subcat) AS cat_idx
        FROM categories
    ),
    product_rows AS (
        SELECT
            ROW_NUMBER() OVER (ORDER BY seq4()) AS rn
        FROM TABLE(GENERATOR(ROWCOUNT => 1000))
    )
    SELECT
        'P' || LPAD(p.rn::VARCHAR, 4, '0') AS product_id,
        nc.brand_prefix || ' ' || nc.subcat || ' ' || 
            CASE MOD(p.rn, 5) 
                WHEN 0 THEN 'Pro'
                WHEN 1 THEN 'Elite'
                WHEN 2 THEN 'Classic'
                WHEN 3 THEN 'Essential'
                ELSE 'Premium'
            END || ' ' || CEIL(p.rn / 30.0)::VARCHAR AS product_name,
        nc.cat AS category,
        nc.subcat AS subcategory,
        nc.brand_prefix || 
            CASE MOD(ABS(HASH(p.rn::VARCHAR || 'brand')), 4)
                WHEN 0 THEN 'Corp'
                WHEN 1 THEN 'Labs'
                WHEN 2 THEN 'Co'
                ELSE 'Inc'
            END AS brand,
        ROUND(nc.price_low + (nc.price_high - nc.price_low) * 
            (ABS(MOD(HASH(p.rn::VARCHAR || 'price'), 10000)) / 10000.0), 2) AS price,
        ROUND(2.5 + 2.5 * (ABS(MOD(HASH(p.rn::VARCHAR || 'rating'), 10000)) / 10000.0), 2) AS avg_rating,
        GREATEST(1, ROUND(
            CASE 
                WHEN ABS(MOD(HASH(p.rn::VARCHAR || 'popular'), 100)) < 10 THEN 500 + ABS(MOD(HASH(p.rn::VARCHAR || 'rev'), 2000))
                WHEN ABS(MOD(HASH(p.rn::VARCHAR || 'popular'), 100)) < 40 THEN 50 + ABS(MOD(HASH(p.rn::VARCHAR || 'rev'), 500))
                ELSE 1 + ABS(MOD(HASH(p.rn::VARCHAR || 'rev'), 100))
            END
        )) AS review_count,
        ABS(MOD(HASH(p.rn::VARCHAR || 'launch'), 730)) + 1 AS days_since_launch,
        CASE WHEN ABS(MOD(HASH(p.rn::VARCHAR || 'stock'), 100)) < 90 THEN TRUE ELSE FALSE END AS in_stock,
        ROUND(10.0 + 50.0 * (ABS(MOD(HASH(p.rn::VARCHAR || 'margin'), 10000)) / 10000.0), 2) AS margin_pct
    FROM product_rows p
    JOIN numbered_cats nc ON nc.cat_idx = MOD(p.rn - 1, 30) + 1;

    -- ─────────────────────────────────────────────────────────────────────
    -- CUSTOMER PROFILE (10,000 customers)
    -- ─────────────────────────────────────────────────────────────────────
    DELETE FROM FEATURE_STORE_DEMO.RAW.CUSTOMER_PROFILE;

    INSERT INTO FEATURE_STORE_DEMO.RAW.CUSTOMER_PROFILE (
        CUSTOMER_ID, SIGNUP_DATE, AGE_GROUP, GENDER, LOYALTY_TIER,
        PREFERRED_CATEGORY, CITY, STATE, ACCOUNT_STATUS,
        LIFETIME_ORDERS, LIFETIME_SPEND, AVG_ORDER_VALUE, DAYS_SINCE_LAST_ORDER
    )
    WITH
    cities AS (
        SELECT column1 AS city, column2 AS state
        FROM VALUES
            ('New York',      'NY'), ('Los Angeles',   'CA'), ('Chicago',       'IL'),
            ('Houston',       'TX'), ('Phoenix',       'AZ'), ('Philadelphia',  'PA'),
            ('San Antonio',   'TX'), ('San Diego',     'CA'), ('Dallas',        'TX'),
            ('San Jose',      'CA'), ('Austin',        'TX'), ('Jacksonville',  'FL'),
            ('Fort Worth',    'TX'), ('Columbus',      'OH'), ('Charlotte',     'NC'),
            ('Indianapolis',  'IN'), ('San Francisco', 'CA'), ('Seattle',       'WA'),
            ('Denver',        'CO'), ('Nashville',     'TN'), ('Portland',      'OR'),
            ('Oklahoma City', 'OK'), ('Las Vegas',     'NV'), ('Memphis',       'TN'),
            ('Louisville',    'KY'), ('Baltimore',     'MD'), ('Milwaukee',     'WI'),
            ('Albuquerque',   'NM'), ('Tucson',        'AZ'), ('Fresno',        'CA')
    ),
    numbered_cities AS (
        SELECT city, state, ROW_NUMBER() OVER (ORDER BY city) AS city_idx
        FROM cities
    ),
    customer_rows AS (
        SELECT ROW_NUMBER() OVER (ORDER BY seq4()) AS rn
        FROM TABLE(GENERATOR(ROWCOUNT => 10000))
    )
    SELECT
        'C' || LPAD(c.rn::VARCHAR, 5, '0') AS customer_id,
        DATEADD('day', -ABS(MOD(HASH(c.rn::VARCHAR || 'signup'), 1095)), CURRENT_DATE()) AS signup_date,
        CASE MOD(ABS(HASH(c.rn::VARCHAR || 'age')), 5)
            WHEN 0 THEN '18-24'
            WHEN 1 THEN '25-34'
            WHEN 2 THEN '35-44'
            WHEN 3 THEN '45-54'
            ELSE '55+'
        END AS age_group,
        CASE MOD(ABS(HASH(c.rn::VARCHAR || 'gender')), 10)
            WHEN 0 THEN 'NB'
            ELSE CASE WHEN MOD(ABS(HASH(c.rn::VARCHAR || 'gender')), 2) = 0 THEN 'M' ELSE 'F' END
        END AS gender,
        CASE
            WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'tier'), 100)) < 45 THEN 'bronze'
            WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'tier'), 100)) < 75 THEN 'silver'
            WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'tier'), 100)) < 92 THEN 'gold'
            ELSE 'platinum'
        END AS loyalty_tier,
        CASE MOD(ABS(HASH(c.rn::VARCHAR || 'pref')), 8)
            WHEN 0 THEN 'Electronics'
            WHEN 1 THEN 'Clothing'
            WHEN 2 THEN 'Home & Garden'
            WHEN 3 THEN 'Sports'
            WHEN 4 THEN 'Books'
            WHEN 5 THEN 'Beauty'
            WHEN 6 THEN 'Food & Beverage'
            ELSE 'Toys'
        END AS preferred_category,
        nc.city,
        nc.state,
        CASE WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'status'), 100)) < 85 THEN 'active' ELSE 'inactive' END AS account_status,
        CASE
            WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'tier'), 100)) >= 92 THEN 30 + ABS(MOD(HASH(c.rn::VARCHAR || 'orders'), 70))
            WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'tier'), 100)) >= 75 THEN 15 + ABS(MOD(HASH(c.rn::VARCHAR || 'orders'), 40))
            WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'tier'), 100)) >= 45 THEN 5 + ABS(MOD(HASH(c.rn::VARCHAR || 'orders'), 20))
            ELSE 1 + ABS(MOD(HASH(c.rn::VARCHAR || 'orders'), 10))
        END AS lifetime_orders,
        ROUND(
            CASE
                WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'tier'), 100)) >= 92 THEN 3000.0 + ABS(MOD(HASH(c.rn::VARCHAR || 'spend'), 12000))
                WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'tier'), 100)) >= 75 THEN 1000.0 + ABS(MOD(HASH(c.rn::VARCHAR || 'spend'), 5000))
                WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'tier'), 100)) >= 45 THEN 200.0 + ABS(MOD(HASH(c.rn::VARCHAR || 'spend'), 2000))
                ELSE 20.0 + ABS(MOD(HASH(c.rn::VARCHAR || 'spend'), 500))
            END, 2) AS lifetime_spend,
        ROUND(
            CASE
                WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'tier'), 100)) >= 92 THEN 80.0 + ABS(MOD(HASH(c.rn::VARCHAR || 'aov'), 120))
                WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'tier'), 100)) >= 75 THEN 50.0 + ABS(MOD(HASH(c.rn::VARCHAR || 'aov'), 80))
                WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'tier'), 100)) >= 45 THEN 30.0 + ABS(MOD(HASH(c.rn::VARCHAR || 'aov'), 50))
                ELSE 15.0 + ABS(MOD(HASH(c.rn::VARCHAR || 'aov'), 35))
            END, 2) AS avg_order_value,
        CASE
            WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'tier'), 100)) >= 92 THEN ABS(MOD(HASH(c.rn::VARCHAR || 'lastord'), 14))
            WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'tier'), 100)) >= 75 THEN ABS(MOD(HASH(c.rn::VARCHAR || 'lastord'), 30))
            WHEN ABS(MOD(HASH(c.rn::VARCHAR || 'tier'), 100)) >= 45 THEN ABS(MOD(HASH(c.rn::VARCHAR || 'lastord'), 60))
            ELSE ABS(MOD(HASH(c.rn::VARCHAR || 'lastord'), 180))
        END AS days_since_last_order
    FROM customer_rows c
    JOIN numbered_cities nc ON nc.city_idx = MOD(c.rn - 1, 30) + 1;

    -- ─────────────────────────────────────────────────────────────────────
    -- PURCHASE HISTORY (200,000 purchases over past 12 months)
    -- ─────────────────────────────────────────────────────────────────────
    DELETE FROM FEATURE_STORE_DEMO.RAW.PURCHASE_HISTORY;

    INSERT INTO FEATURE_STORE_DEMO.RAW.PURCHASE_HISTORY (
        PURCHASE_ID, CUSTOMER_ID, PRODUCT_ID, PURCHASE_TS,
        QUANTITY, UNIT_PRICE, DISCOUNT_PCT, TOTAL_AMOUNT
    )
    WITH
    purchase_rows AS (
        SELECT ROW_NUMBER() OVER (ORDER BY seq4()) AS rn
        FROM TABLE(GENERATOR(ROWCOUNT => 200000))
    ),
    customer_weights AS (
        SELECT CUSTOMER_ID, LOYALTY_TIER,
            CASE LOYALTY_TIER
                WHEN 'platinum' THEN 8
                WHEN 'gold' THEN 4
                WHEN 'silver' THEN 2
                ELSE 1
            END AS weight
        FROM FEATURE_STORE_DEMO.RAW.CUSTOMER_PROFILE
        WHERE ACCOUNT_STATUS = 'active'
    ),
    weighted_customers AS (
        SELECT CUSTOMER_ID, LOYALTY_TIER,
            ROW_NUMBER() OVER (ORDER BY HASH(CUSTOMER_ID || 'weight')) AS cust_rn,
            COUNT(*) OVER () AS total_custs
        FROM customer_weights
    ),
    product_weights AS (
        SELECT PRODUCT_ID, PRICE, CATEGORY,
            CASE
                WHEN REVIEW_COUNT > 300 THEN 5
                WHEN REVIEW_COUNT > 100 THEN 3
                WHEN REVIEW_COUNT > 30 THEN 2
                ELSE 1
            END AS popularity_weight,
            ROW_NUMBER() OVER (ORDER BY HASH(PRODUCT_ID || 'pweight')) AS prod_rn,
            COUNT(*) OVER () AS total_prods
        FROM FEATURE_STORE_DEMO.RAW.PRODUCT_CATALOG
        WHERE IN_STOCK = TRUE
    )
    SELECT
        'PUR' || LPAD(p.rn::VARCHAR, 7, '0') AS purchase_id,
        wc.CUSTOMER_ID,
        pw.PRODUCT_ID,
        DATEADD('second',
            -ABS(MOD(HASH(p.rn::VARCHAR || 'ts'), 31536000)),
            CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
        ) AS purchase_ts,
        1 + ABS(MOD(HASH(p.rn::VARCHAR || 'qty'), 4)) AS quantity,
        pw.PRICE AS unit_price,
        ROUND(
            CASE
                WHEN ABS(MOD(HASH(p.rn::VARCHAR || 'disc'), 100)) < 60 THEN 0.00
                WHEN ABS(MOD(HASH(p.rn::VARCHAR || 'disc'), 100)) < 80 THEN 5.00 + ABS(MOD(HASH(p.rn::VARCHAR || 'dval'), 10))
                WHEN ABS(MOD(HASH(p.rn::VARCHAR || 'disc'), 100)) < 95 THEN 15.00 + ABS(MOD(HASH(p.rn::VARCHAR || 'dval'), 10))
                ELSE 25.00 + ABS(MOD(HASH(p.rn::VARCHAR || 'dval'), 15))
            END, 2) AS discount_pct,
        ROUND(
            (1 + ABS(MOD(HASH(p.rn::VARCHAR || 'qty'), 4))) * pw.PRICE *
            (1.0 - (
                CASE
                    WHEN ABS(MOD(HASH(p.rn::VARCHAR || 'disc'), 100)) < 60 THEN 0.00
                    WHEN ABS(MOD(HASH(p.rn::VARCHAR || 'disc'), 100)) < 80 THEN 5.00 + ABS(MOD(HASH(p.rn::VARCHAR || 'dval'), 10))
                    WHEN ABS(MOD(HASH(p.rn::VARCHAR || 'disc'), 100)) < 95 THEN 15.00 + ABS(MOD(HASH(p.rn::VARCHAR || 'dval'), 10))
                    ELSE 25.00 + ABS(MOD(HASH(p.rn::VARCHAR || 'dval'), 15))
                END / 100.0)
            )
        , 2) AS total_amount
    FROM purchase_rows p
    JOIN weighted_customers wc
        ON wc.cust_rn = MOD(
            ABS(MOD(HASH(p.rn::VARCHAR || 'cust'), wc.total_custs * 3)),
            wc.total_custs
        ) + 1
    JOIN product_weights pw
        ON pw.prod_rn = MOD(
            ABS(MOD(HASH(p.rn::VARCHAR || 'prod'), pw.total_prods * pw.popularity_weight)),
            pw.total_prods
        ) + 1;

    -- ─────────────────────────────────────────────────────────────────────
    -- BROWSE EVENTS (500,000 events over past 30 days)
    -- ─────────────────────────────────────────────────────────────────────
    DELETE FROM FEATURE_STORE_DEMO.RAW.BROWSE_EVENTS;

    INSERT INTO FEATURE_STORE_DEMO.RAW.BROWSE_EVENTS (
        EVENT_ID, CUSTOMER_ID, PRODUCT_ID, EVENT_TS,
        EVENT_TYPE, SESSION_ID, DEVICE_TYPE, REFERRER
    )
    WITH
    event_rows AS (
        SELECT ROW_NUMBER() OVER (ORDER BY seq4()) AS rn
        FROM TABLE(GENERATOR(ROWCOUNT => 500000))
    ),
    active_customers AS (
        SELECT CUSTOMER_ID,
            ROW_NUMBER() OVER (ORDER BY HASH(CUSTOMER_ID || 'browse')) AS cust_rn,
            COUNT(*) OVER () AS total_custs
        FROM FEATURE_STORE_DEMO.RAW.CUSTOMER_PROFILE
        WHERE ACCOUNT_STATUS = 'active'
    ),
    all_products AS (
        SELECT PRODUCT_ID,
            ROW_NUMBER() OVER (ORDER BY HASH(PRODUCT_ID || 'browse')) AS prod_rn,
            COUNT(*) OVER () AS total_prods
        FROM FEATURE_STORE_DEMO.RAW.PRODUCT_CATALOG
    )
    SELECT
        'EVT' || LPAD(e.rn::VARCHAR, 7, '0') AS event_id,
        ac.CUSTOMER_ID,
        ap.PRODUCT_ID,
        DATEADD('second',
            -ABS(MOD(HASH(e.rn::VARCHAR || 'ets'), 2592000)),
            CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
        ) AS event_ts,
        CASE MOD(ABS(HASH(e.rn::VARCHAR || 'etype')), 10)
            WHEN 0 THEN 'add_to_cart'
            WHEN 1 THEN 'wishlist'
            WHEN 2 THEN 'search_click'
            WHEN 3 THEN 'search_click'
            ELSE 'page_view'
        END AS event_type,
        'SESS' || LPAD(
            (MOD(ABS(HASH(e.rn::VARCHAR || 'sess')), 100000) + 1)::VARCHAR, 6, '0'
        ) AS session_id,
        CASE MOD(ABS(HASH(e.rn::VARCHAR || 'device')), 10)
            WHEN 0 THEN 'tablet'
            WHEN 1 THEN 'tablet'
            WHEN 2 THEN 'desktop'
            WHEN 3 THEN 'desktop'
            WHEN 4 THEN 'desktop'
            ELSE 'mobile'
        END AS device_type,
        CASE MOD(ABS(HASH(e.rn::VARCHAR || 'ref')), 10)
            WHEN 0 THEN 'email'
            WHEN 1 THEN 'social'
            WHEN 2 THEN 'social'
            WHEN 3 THEN 'recommendation'
            WHEN 4 THEN 'recommendation'
            ELSE 'search'
        END AS referrer
    FROM event_rows e
    JOIN active_customers ac
        ON ac.cust_rn = MOD(ABS(MOD(HASH(e.rn::VARCHAR || 'ecust'), ac.total_custs * 2)), ac.total_custs) + 1
    JOIN all_products ap
        ON ap.prod_rn = MOD(ABS(MOD(HASH(e.rn::VARCHAR || 'eprod'), ap.total_prods * 2)), ap.total_prods) + 1;

    -- ─────────────────────────────────────────────────────────────────────
    -- PRODUCT DAILY METRICS (30,000 rows = 1000 products × 30 days)
    -- Trending products get increasing scores over time
    -- ─────────────────────────────────────────────────────────────────────
    DELETE FROM FEATURE_STORE_DEMO.RAW.PRODUCT_DAILY_METRICS;

    INSERT INTO FEATURE_STORE_DEMO.RAW.PRODUCT_DAILY_METRICS (
        PRODUCT_ID, METRIC_DATE, DAILY_VIEWS, DAILY_PURCHASES,
        DAILY_CART_ADDS, CONVERSION_RATE, TRENDING_SCORE
    )
    WITH
    products AS (
        SELECT PRODUCT_ID, REVIEW_COUNT, AVG_RATING,
            CASE
                WHEN DAYS_SINCE_LAUNCH < 60 THEN TRUE
                ELSE FALSE
            END AS is_new_product,
            CASE
                WHEN REVIEW_COUNT > 300 THEN 'hot'
                WHEN REVIEW_COUNT > 100 THEN 'warm'
                ELSE 'normal'
            END AS popularity_tier
        FROM FEATURE_STORE_DEMO.RAW.PRODUCT_CATALOG
    ),
    days AS (
        SELECT DATEADD('day', -seq4(), CURRENT_DATE()) AS metric_date,
               seq4() AS days_ago
        FROM TABLE(GENERATOR(ROWCOUNT => 30))
    )
    SELECT
        p.PRODUCT_ID,
        d.metric_date,
        GREATEST(0, ROUND(
            CASE p.popularity_tier
                WHEN 'hot' THEN 200 + ABS(MOD(HASH(p.PRODUCT_ID || d.metric_date::VARCHAR || 'views'), 300))
                WHEN 'warm' THEN 50 + ABS(MOD(HASH(p.PRODUCT_ID || d.metric_date::VARCHAR || 'views'), 150))
                ELSE 5 + ABS(MOD(HASH(p.PRODUCT_ID || d.metric_date::VARCHAR || 'views'), 50))
            END
            * CASE WHEN p.is_new_product THEN 1.0 + (30 - d.days_ago) * 0.03 ELSE 1.0 END
            * (0.8 + 0.4 * ABS(MOD(HASH(p.PRODUCT_ID || d.metric_date::VARCHAR || 'noise'), 1000)) / 1000.0)
        )) AS daily_views,
        GREATEST(0, ROUND(
            CASE p.popularity_tier
                WHEN 'hot' THEN 15 + ABS(MOD(HASH(p.PRODUCT_ID || d.metric_date::VARCHAR || 'purch'), 25))
                WHEN 'warm' THEN 3 + ABS(MOD(HASH(p.PRODUCT_ID || d.metric_date::VARCHAR || 'purch'), 12))
                ELSE ABS(MOD(HASH(p.PRODUCT_ID || d.metric_date::VARCHAR || 'purch'), 5))
            END
            * CASE WHEN p.is_new_product THEN 1.0 + (30 - d.days_ago) * 0.04 ELSE 1.0 END
        )) AS daily_purchases,
        GREATEST(0, ROUND(
            CASE p.popularity_tier
                WHEN 'hot' THEN 30 + ABS(MOD(HASH(p.PRODUCT_ID || d.metric_date::VARCHAR || 'cart'), 40))
                WHEN 'warm' THEN 8 + ABS(MOD(HASH(p.PRODUCT_ID || d.metric_date::VARCHAR || 'cart'), 20))
                ELSE 1 + ABS(MOD(HASH(p.PRODUCT_ID || d.metric_date::VARCHAR || 'cart'), 8))
            END
            * CASE WHEN p.is_new_product THEN 1.0 + (30 - d.days_ago) * 0.03 ELSE 1.0 END
        )) AS daily_cart_adds,
        ROUND(
            CASE p.popularity_tier
                WHEN 'hot' THEN 0.04 + 0.06 * ABS(MOD(HASH(p.PRODUCT_ID || d.metric_date::VARCHAR || 'cvr'), 1000)) / 1000.0
                WHEN 'warm' THEN 0.03 + 0.04 * ABS(MOD(HASH(p.PRODUCT_ID || d.metric_date::VARCHAR || 'cvr'), 1000)) / 1000.0
                ELSE 0.01 + 0.03 * ABS(MOD(HASH(p.PRODUCT_ID || d.metric_date::VARCHAR || 'cvr'), 1000)) / 1000.0
            END
            * CASE WHEN p.AVG_RATING > 4.0 THEN 1.2 ELSE 1.0 END
        , 4) AS conversion_rate,
        ROUND(
            CASE p.popularity_tier
                WHEN 'hot' THEN 70.0 + ABS(MOD(HASH(p.PRODUCT_ID || d.metric_date::VARCHAR || 'trend'), 30))
                WHEN 'warm' THEN 30.0 + ABS(MOD(HASH(p.PRODUCT_ID || d.metric_date::VARCHAR || 'trend'), 30))
                ELSE 1.0 + ABS(MOD(HASH(p.PRODUCT_ID || d.metric_date::VARCHAR || 'trend'), 25))
            END
            * CASE WHEN p.is_new_product THEN 1.0 + (30 - d.days_ago) * 0.05 ELSE 1.0 END
        , 2) AS trending_score
    FROM products p
    CROSS JOIN days d;

    SELECT 'done' INTO :v_status;
    RETURN 'Synthetic data generation complete. Tables populated: CUSTOMER_PROFILE, PRODUCT_CATALOG, PURCHASE_HISTORY, BROWSE_EVENTS, PRODUCT_DAILY_METRICS';
END;
$$;

-- Execute the data generation procedure
CALL FEATURE_STORE_DEMO.RAW.GENERATE_SYNTHETIC_DATA();

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. VERIFICATION
-- ─────────────────────────────────────────────────────────────────────────────

SELECT 'CUSTOMER_PROFILE' AS table_name, COUNT(*) AS row_count FROM FEATURE_STORE_DEMO.RAW.CUSTOMER_PROFILE
UNION ALL
SELECT 'PRODUCT_CATALOG', COUNT(*) FROM FEATURE_STORE_DEMO.RAW.PRODUCT_CATALOG
UNION ALL
SELECT 'PURCHASE_HISTORY', COUNT(*) FROM FEATURE_STORE_DEMO.RAW.PURCHASE_HISTORY
UNION ALL
SELECT 'BROWSE_EVENTS', COUNT(*) FROM FEATURE_STORE_DEMO.RAW.BROWSE_EVENTS
UNION ALL
SELECT 'PRODUCT_DAILY_METRICS', COUNT(*) FROM FEATURE_STORE_DEMO.RAW.PRODUCT_DAILY_METRICS
ORDER BY table_name;

SELECT 'Loyalty Tier Distribution' AS check_name;
SELECT LOYALTY_TIER, COUNT(*) AS customers, ROUND(AVG(LIFETIME_SPEND), 2) AS avg_spend
FROM FEATURE_STORE_DEMO.RAW.CUSTOMER_PROFILE
GROUP BY LOYALTY_TIER
ORDER BY avg_spend DESC;

SELECT 'Product Category Distribution' AS check_name;
SELECT CATEGORY, COUNT(*) AS products, ROUND(AVG(PRICE), 2) AS avg_price
FROM FEATURE_STORE_DEMO.RAW.PRODUCT_CATALOG
GROUP BY CATEGORY
ORDER BY products DESC;

SELECT 'Purchase History Time Range' AS check_name;
SELECT MIN(PURCHASE_TS) AS earliest_purchase,
       MAX(PURCHASE_TS) AS latest_purchase,
       COUNT(DISTINCT CUSTOMER_ID) AS unique_customers,
       COUNT(DISTINCT PRODUCT_ID) AS unique_products
FROM FEATURE_STORE_DEMO.RAW.PURCHASE_HISTORY;

SELECT 'Browse Events Summary' AS check_name;
SELECT EVENT_TYPE, COUNT(*) AS event_count
FROM FEATURE_STORE_DEMO.RAW.BROWSE_EVENTS
GROUP BY EVENT_TYPE
ORDER BY event_count DESC;

-- Show all created objects
SHOW SCHEMAS IN DATABASE FEATURE_STORE_DEMO;
SHOW TABLES IN SCHEMA FEATURE_STORE_DEMO.RAW;
SHOW STAGES IN SCHEMA FEATURE_STORE_DEMO.MODELS;

-- ─────────────────────────────────────────────────────────────────────────────
-- SETUP COMPLETE
-- ─────────────────────────────────────────────────────────────────────────────
-- Expected output:
--   - CUSTOMER_PROFILE:      10,000 rows
--   - PRODUCT_CATALOG:        1,000 rows
--   - PURCHASE_HISTORY:     200,000 rows
--   - BROWSE_EVENTS:        500,000 rows
--   - PRODUCT_DAILY_METRICS: 30,000 rows
--   - 4 schemas: RAW, FEATURE_STORE, MODELS, SCORING
--   - 1 stage: ML_STAGE in MODELS schema
--   - 1 warehouse: FS_DEMO_WH (MEDIUM, auto-suspend 120s)
