-- =============================================================================
-- Server-Side Agent Routing Lab: Setup Script
-- =============================================================================
-- Run this script once before starting the notebook.
-- It creates all prerequisite objects: database, warehouse, specialist agents,
-- wrapper procedures, supervisor agent, and evaluation infrastructure.
--
-- Prerequisites:
--   - A role with CREATE DATABASE, CREATE WAREHOUSE privileges
--   - Cross-region inference enabled (for agent evaluation LLM judges)
--   - SNOWFLAKE.CORTEX_USER database role granted to your role
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. DATABASE AND SCHEMA
-- ─────────────────────────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS ROUTING_DEMO;
USE DATABASE ROUTING_DEMO;
CREATE SCHEMA IF NOT EXISTS ROUTING;
USE SCHEMA ROUTING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. WAREHOUSE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE WAREHOUSE IF NOT EXISTS ROUTING_DEMO_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;

USE WAREHOUSE ROUTING_DEMO_WH;

<<<<<<< local
--  -----------------
-- 3. Tables and Semantic VIEWS
--  -----------------
CREATE OR REPLACE TABLE ROUTING_DEMO.ROUTING.SALES_FACTS (
    deal_id        INT,
    close_date     DATE,
    fiscal_quarter VARCHAR,
    region         VARCHAR,
    channel        VARCHAR,
    product_line   VARCHAR,
    sales_rep      VARCHAR,
    revenue        NUMBER(12,2),
    pipeline_value NUMBER(12,2),
    deals_closed   INT
);
INSERT INTO ROUTING_DEMO.ROUTING.SALES_FACTS
(deal_id, close_date, fiscal_quarter, region, channel, product_line, sales_rep, revenue, pipeline_value, deals_closed)
VALUES
(1001,'2025-01-15','Q1 2025','North America','Direct','Enterprise Suite','A. Rivera',125000.00,200000.00,1),
(1002,'2025-02-03','Q1 2025','North America','Partner','SMB Cloud','B. Chen',48000.00,90000.00,1),
(1003,'2025-02-21','Q1 2025','EMEA','Direct','Enterprise Suite','C. Okafor',98000.00,150000.00,1),
(1004,'2025-03-10','Q1 2025','APAC','Online','SMB Cloud','D. Tanaka',32000.00,60000.00,1),
(1005,'2025-03-28','Q1 2025','North America','Direct','Analytics Add-on','A. Rivera',56000.00,80000.00,1),
(1006,'2025-04-08','Q2 2025','EMEA','Partner','Enterprise Suite','C. Okafor',142000.00,210000.00,1),
(1007,'2025-04-19','Q2 2025','APAC','Direct','Analytics Add-on','D. Tanaka',61000.00,95000.00,1),
(1008,'2025-05-02','Q2 2025','North America','Online','SMB Cloud','B. Chen',27000.00,45000.00,1),
(1009,'2025-05-22','Q2 2025','EMEA','Direct','Enterprise Suite','C. Okafor',115000.00,180000.00,1),
(1010,'2025-06-14','Q2 2025','APAC','Partner','Analytics Add-on','D. Tanaka',73000.00,120000.00,1);

CREATE OR REPLACE TABLE ROUTING_DEMO.ROUTING.PRODUCT_CASES (
    case_id          INT,
    opened_date      DATE,
    product_line     VARCHAR,
    product_model    VARCHAR,
    issue_category   VARCHAR,
    firmware_version VARCHAR,
    warranty_status  VARCHAR,
    resolution       VARCHAR,
    resolved         BOOLEAN,
    days_to_resolve  INT
);
INSERT INTO ROUTING_DEMO.ROUTING.PRODUCT_CASES
(case_id, opened_date, product_line, product_model, issue_category, firmware_version, warranty_status, resolution, resolved, days_to_resolve)
VALUES
(5001,'2025-01-09','Router','RX-200','Connectivity','v3.2.1','In Warranty','Rolled back firmware to v3.1.8',TRUE,2),
(5002,'2025-01-22','Router','RX-200','Connectivity','v3.2.1','In Warranty','Reset network settings, reconnected',TRUE,1),
(5003,'2025-02-11','Sensor','SN-50','Battery','v1.4.0','Out of Warranty','Replaced battery module',TRUE,4),
(5004,'2025-02-27','Camera','CM-110','Firmware','v2.0.3','In Warranty','Applied patch v2.0.4',TRUE,3),
(5005,'2025-03-14','Accessory','AC-Charger','Warranty Inquiry',NULL,'Accessory Warranty','Explained 90-day accessory coverage',TRUE,1),
(5006,'2025-03-30','Router','RX-300','Performance','v4.1.0','In Warranty','Optimized QoS settings',TRUE,2),
(5007,'2025-04-12','Sensor','SN-50','Connectivity','v1.4.1','In Warranty','Pending hardware RMA',FALSE,NULL),
(5008,'2025-04-25','Camera','CM-110','Setup','v2.0.4','In Warranty','Walked through pairing steps',TRUE,1),
(5009,'2025-05-09','Accessory','AC-Mount','Warranty Inquiry',NULL,'Accessory Warranty','Confirmed mount not covered after 90 days',TRUE,1),
(5010,'2025-05-28','Router','RX-300','Connectivity','v4.1.1','In Warranty','Firmware update resolved WiFi drops',TRUE,2);

CREATE OR REPLACE TABLE ROUTING_DEMO.ROUTING.SUPPLY_CHAIN_INVENTORY (
    sku                  VARCHAR,
    product_line         VARCHAR,
    warehouse            VARCHAR,
    region               VARCHAR,
    supplier             VARCHAR,
    supplier_region      VARCHAR,
    units_on_hand        INT,
    reorder_point        INT,
    lead_time_days       INT,
    fulfillment_rate     NUMBER(5,2),
    on_time_delivery_pct NUMBER(5,2)
);
INSERT INTO ROUTING_DEMO.ROUTING.SUPPLY_CHAIN_INVENTORY
(sku, product_line, warehouse, region, supplier, supplier_region, units_on_hand, reorder_point, lead_time_days, fulfillment_rate, on_time_delivery_pct)
VALUES
('RX-200','Router','WH-East','North America','Acme Components','Southeast Asia',1450,500,28,96.50,92.00),
('RX-300','Router','WH-East','North America','Acme Components','Southeast Asia',2200,600,30,97.20,90.50),
('SN-50','Sensor','WH-West','North America','Nimbus Mfg','Southeast Asia',870,300,21,94.80,88.00),
('CM-110','Camera','WH-Central','North America','Orion Optics','EMEA',640,250,18,98.10,95.50),
('AC-Charger','Accessory','WH-West','North America','Volt Supplies','North America',5300,1000,7,99.40,97.80),
('AC-Mount','Accessory','WH-Central','North America','Volt Supplies','North America',4100,800,9,99.00,96.20),
('RX-200','Router','WH-EU','EMEA','Acme Components','Southeast Asia',980,400,32,93.70,85.40),
('SN-50','Sensor','WH-APAC','APAC','Nimbus Mfg','Southeast Asia',1120,350,16,95.60,91.30),
('CM-110','Camera','WH-APAC','APAC','Orion Optics','EMEA',430,200,24,96.90,89.70),
('RX-300','Router','WH-EU','EMEA','Acme Components','Southeast Asia',1560,500,29,94.10,87.60);

CREATE OR REPLACE SEMANTIC VIEW ROUTING_DEMO.ROUTING.SALES_SV
  TABLES (
    sales AS ROUTING_DEMO.ROUTING.SALES_FACTS
      PRIMARY KEY (deal_id)
      WITH SYNONYMS ('deals', 'sales deals')
      COMMENT = 'Closed and in-progress sales deals'
  )
  FACTS (
    sales.revenue AS revenue COMMENT = 'Closed revenue for the deal',
    sales.pipeline_value AS pipeline_value COMMENT = 'Open pipeline value for the deal',
    sales.deals_count AS deals_closed COMMENT = 'Number of deals closed'
  )
  DIMENSIONS (
    sales.deal_id AS deal_id,
    sales.close_date AS close_date COMMENT = 'Date the deal closed',
    sales.fiscal_quarter AS fiscal_quarter WITH SYNONYMS ('quarter') COMMENT = 'Fiscal quarter such as Q1 2025',
    sales.region AS region COMMENT = 'Sales region',
    sales.channel AS channel COMMENT = 'Sales channel: Direct, Partner, Online',
    sales.product_line AS product_line WITH SYNONYMS ('product') COMMENT = 'Product line sold',
    sales.sales_rep AS sales_rep COMMENT = 'Sales representative who owns the deal'
  )
  METRICS (
    sales.total_revenue AS SUM(sales.revenue) COMMENT = 'Total closed revenue',
    sales.total_pipeline AS SUM(sales.pipeline_value) COMMENT = 'Total open pipeline value',
    sales.total_deals AS SUM(sales.deals_count) COMMENT = 'Total number of deals closed',
    sales.avg_deal_size AS AVG(sales.revenue) COMMENT = 'Average closed revenue per deal'
  )
  COMMENT = 'Sales analytics: revenue, pipeline, and deals by quarter, region, channel, and product line';

CREATE OR REPLACE SEMANTIC VIEW ROUTING_DEMO.ROUTING.PRODUCT_SV
  TABLES (
    cases AS ROUTING_DEMO.ROUTING.PRODUCT_CASES
      PRIMARY KEY (case_id)
      WITH SYNONYMS ('support cases', 'tickets')
      COMMENT = 'Product support cases and resolutions'
  )
  FACTS (
    cases.days_to_resolve AS days_to_resolve COMMENT = 'Days taken to resolve the case',
    cases.is_resolved AS IFF(resolved, 1, 0) COMMENT = '1 if the case was resolved'
  )
  DIMENSIONS (
    cases.case_id AS case_id,
    cases.opened_date AS opened_date COMMENT = 'Date the case was opened',
    cases.product_line AS product_line WITH SYNONYMS ('product') COMMENT = 'Product line',
    cases.product_model AS product_model COMMENT = 'Specific product model',
    cases.issue_category AS issue_category WITH SYNONYMS ('issue type') COMMENT = 'Category of the issue such as Connectivity or Warranty Inquiry',
    cases.firmware_version AS firmware_version COMMENT = 'Firmware version on the device',
    cases.warranty_status AS warranty_status COMMENT = 'Warranty coverage status',
    cases.resolution AS resolution COMMENT = 'How the case was resolved'
  )
  METRICS (
    cases.total_cases AS COUNT(cases.case_id) COMMENT = 'Total number of support cases',
    cases.resolved_cases AS SUM(cases.is_resolved) COMMENT = 'Number of resolved cases',
    cases.avg_days_to_resolve AS AVG(cases.days_to_resolve) COMMENT = 'Average days to resolve a case'
  )
  COMMENT = 'Product support analytics: cases, troubleshooting, warranty, and resolution metrics by product and issue';

CREATE OR REPLACE SEMANTIC VIEW ROUTING_DEMO.ROUTING.SUPPLY_CHAIN_SV
  TABLES (
    inventory AS ROUTING_DEMO.ROUTING.SUPPLY_CHAIN_INVENTORY
      PRIMARY KEY (sku, warehouse)
      WITH SYNONYMS ('inventory', 'stock')
      COMMENT = 'Inventory positions and supplier performance by SKU and warehouse'
  )
  FACTS (
    inventory.units_on_hand AS units_on_hand COMMENT = 'Units currently in stock',
    inventory.reorder_point AS reorder_point COMMENT = 'Reorder threshold',
    inventory.lead_time_days AS lead_time_days COMMENT = 'Supplier lead time in days',
    inventory.fulfillment_rate_fact AS fulfillment_rate COMMENT = 'Order fulfillment rate percent',
    inventory.on_time_delivery_fact AS on_time_delivery_pct COMMENT = 'On-time delivery percent'
  )
  DIMENSIONS (
    inventory.sku AS sku WITH SYNONYMS ('item', 'product code') COMMENT = 'Stock keeping unit',
    inventory.product_line AS product_line WITH SYNONYMS ('product') COMMENT = 'Product line',
    inventory.warehouse AS warehouse COMMENT = 'Warehouse holding the stock',
    inventory.region AS region COMMENT = 'Warehouse region',
    inventory.supplier AS supplier COMMENT = 'Supplier name',
    inventory.supplier_region AS supplier_region WITH SYNONYMS ('sourcing region') COMMENT = 'Region the supplier ships from, e.g. Southeast Asia'
  )
  METRICS (
    inventory.total_units_on_hand AS SUM(inventory.units_on_hand) COMMENT = 'Total units in stock',
    inventory.avg_lead_time AS AVG(inventory.lead_time_days) COMMENT = 'Average supplier lead time in days',
    inventory.avg_fulfillment_rate AS AVG(inventory.fulfillment_rate_fact) COMMENT = 'Average fulfillment rate',
    inventory.avg_on_time_delivery AS AVG(inventory.on_time_delivery_fact) COMMENT = 'Average on-time delivery percent'
  )
  COMMENT = 'Supply chain analytics: inventory levels, lead times, supplier performance, and fulfillment by SKU, warehouse, and supplier region';


-- ─────────────────────────────────────────────────────────────────────────────
=======
--  -----------------
-- 3. Tables and Semantic VIEWS
--  -----------------
CREATE OR REPLACE TABLE ROUTING_DEMO.ROUTING.SALES_FACTS (
    deal_id        INT,
    close_date     DATE,
    fiscal_quarter VARCHAR,
    region         VARCHAR,
    channel        VARCHAR,
    product_line   VARCHAR,
    sales_rep      VARCHAR,
    revenue        NUMBER(12,2),
    pipeline_value NUMBER(12,2),
    deals_closed   INT
);
INSERT INTO ROUTING_DEMO.ROUTING.SALES_FACTS
(deal_id, close_date, fiscal_quarter, region, channel, product_line, sales_rep, revenue, pipeline_value, deals_closed)
VALUES
(1001,'2025-01-15','Q1 2025','North America','Direct','Enterprise Suite','A. Rivera',125000.00,200000.00,1),
(1002,'2025-02-03','Q1 2025','North America','Partner','SMB Cloud','B. Chen',48000.00,90000.00,1),
(1003,'2025-02-21','Q1 2025','EMEA','Direct','Enterprise Suite','C. Okafor',98000.00,150000.00,1),
(1004,'2025-03-10','Q1 2025','APAC','Online','SMB Cloud','D. Tanaka',32000.00,60000.00,1),
(1005,'2025-03-28','Q1 2025','North America','Direct','Analytics Add-on','A. Rivera',56000.00,80000.00,1),
(1006,'2025-04-08','Q2 2025','EMEA','Partner','Enterprise Suite','C. Okafor',142000.00,210000.00,1),
(1007,'2025-04-19','Q2 2025','APAC','Direct','Analytics Add-on','D. Tanaka',61000.00,95000.00,1),
(1008,'2025-05-02','Q2 2025','North America','Online','SMB Cloud','B. Chen',27000.00,45000.00,1),
(1009,'2025-05-22','Q2 2025','EMEA','Direct','Enterprise Suite','C. Okafor',115000.00,180000.00,1),
(1010,'2025-06-14','Q2 2025','APAC','Partner','Analytics Add-on','D. Tanaka',73000.00,120000.00,1);

CREATE OR REPLACE TABLE ROUTING_DEMO.ROUTING.PRODUCT_CASES (
    case_id          INT,
    opened_date      DATE,
    product_line     VARCHAR,
    product_model    VARCHAR,
    issue_category   VARCHAR,
    firmware_version VARCHAR,
    warranty_status  VARCHAR,
    resolution       VARCHAR,
    resolved         BOOLEAN,
    days_to_resolve  INT
);
INSERT INTO ROUTING_DEMO.ROUTING.PRODUCT_CASES
(case_id, opened_date, product_line, product_model, issue_category, firmware_version, warranty_status, resolution, resolved, days_to_resolve)
VALUES
(5001,'2025-01-09','Router','RX-200','Connectivity','v3.2.1','In Warranty','Rolled back firmware to v3.1.8',TRUE,2),
(5002,'2025-01-22','Router','RX-200','Connectivity','v3.2.1','In Warranty','Reset network settings, reconnected',TRUE,1),
(5003,'2025-02-11','Sensor','SN-50','Battery','v1.4.0','Out of Warranty','Replaced battery module',TRUE,4),
(5004,'2025-02-27','Camera','CM-110','Firmware','v2.0.3','In Warranty','Applied patch v2.0.4',TRUE,3),
(5005,'2025-03-14','Accessory','AC-Charger','Warranty Inquiry',NULL,'Accessory Warranty','Explained 90-day accessory coverage',TRUE,1),
(5006,'2025-03-30','Router','RX-300','Performance','v4.1.0','In Warranty','Optimized QoS settings',TRUE,2),
(5007,'2025-04-12','Sensor','SN-50','Connectivity','v1.4.1','In Warranty','Pending hardware RMA',FALSE,NULL),
(5008,'2025-04-25','Camera','CM-110','Setup','v2.0.4','In Warranty','Walked through pairing steps',TRUE,1),
(5009,'2025-05-09','Accessory','AC-Mount','Warranty Inquiry',NULL,'Accessory Warranty','Confirmed mount not covered after 90 days',TRUE,1),
(5010,'2025-05-28','Router','RX-300','Connectivity','v4.1.1','In Warranty','Firmware update resolved WiFi drops',TRUE,2);

CREATE OR REPLACE TABLE ROUTING_DEMO.ROUTING.SUPPLY_CHAIN_INVENTORY (
    sku                  VARCHAR,
    product_line         VARCHAR,
    warehouse            VARCHAR,
    region               VARCHAR,
    supplier             VARCHAR,
    supplier_region      VARCHAR,
    units_on_hand        INT,
    reorder_point        INT,
    lead_time_days       INT,
    fulfillment_rate     NUMBER(5,2),
    on_time_delivery_pct NUMBER(5,2)
);
INSERT INTO ROUTING_DEMO.ROUTING.SUPPLY_CHAIN_INVENTORY
(sku, product_line, warehouse, region, supplier, supplier_region, units_on_hand, reorder_point, lead_time_days, fulfillment_rate, on_time_delivery_pct)
VALUES
('RX-200','Router','WH-East','North America','Acme Components','Southeast Asia',1450,500,28,96.50,92.00),
('RX-300','Router','WH-East','North America','Acme Components','Southeast Asia',2200,600,30,97.20,90.50),
('SN-50','Sensor','WH-West','North America','Nimbus Mfg','Southeast Asia',870,300,21,94.80,88.00),
('CM-110','Camera','WH-Central','North America','Orion Optics','EMEA',640,250,18,98.10,95.50),
('AC-Charger','Accessory','WH-West','North America','Volt Supplies','North America',5300,1000,7,99.40,97.80),
('AC-Mount','Accessory','WH-Central','North America','Volt Supplies','North America',4100,800,9,99.00,96.20),
('RX-200','Router','WH-EU','EMEA','Acme Components','Southeast Asia',980,400,32,93.70,85.40),
('SN-50','Sensor','WH-APAC','APAC','Nimbus Mfg','Southeast Asia',1120,350,16,95.60,91.30),
('CM-110','Camera','WH-APAC','APAC','Orion Optics','EMEA',430,200,24,96.90,89.70),
('RX-300','Router','WH-EU','EMEA','Acme Components','Southeast Asia',1560,500,29,94.10,87.60);

CREATE OR REPLACE SEMANTIC VIEW ROUTING_DEMO.ROUTING.SALES_SV
  TABLES (
    sales AS ROUTING_DEMO.ROUTING.SALES_FACTS
      PRIMARY KEY (deal_id)
      WITH SYNONYMS ('deals', 'sales deals')
      COMMENT = 'Closed and in-progress sales deals'
  )
  FACTS (
    sales.revenue AS revenue COMMENT = 'Closed revenue for the deal',
    sales.pipeline_value AS pipeline_value COMMENT = 'Open pipeline value for the deal',
    sales.deals_count AS deals_closed COMMENT = 'Number of deals closed'
  )
  DIMENSIONS (
    sales.deal_id AS deal_id,
    sales.close_date AS close_date COMMENT = 'Date the deal closed',
    sales.fiscal_quarter AS fiscal_quarter WITH SYNONYMS ('quarter') COMMENT = 'Fiscal quarter such as Q1 2025',
    sales.region AS region COMMENT = 'Sales region',
    sales.channel AS channel COMMENT = 'Sales channel: Direct, Partner, Online',
    sales.product_line AS product_line WITH SYNONYMS ('product') COMMENT = 'Product line sold',
    sales.sales_rep AS sales_rep COMMENT = 'Sales representative who owns the deal'
  )
  METRICS (
    sales.total_revenue AS SUM(sales.revenue) COMMENT = 'Total closed revenue',
    sales.total_pipeline AS SUM(sales.pipeline_value) COMMENT = 'Total open pipeline value',
    sales.total_deals AS SUM(sales.deals_count) COMMENT = 'Total number of deals closed',
    sales.avg_deal_size AS AVG(sales.revenue) COMMENT = 'Average closed revenue per deal'
  )
  COMMENT = 'Sales analytics: revenue, pipeline, and deals by quarter, region, channel, and product line';

CREATE OR REPLACE SEMANTIC VIEW ROUTING_DEMO.ROUTING.PRODUCT_SV
  TABLES (
    cases AS ROUTING_DEMO.ROUTING.PRODUCT_CASES
      PRIMARY KEY (case_id)
      WITH SYNONYMS ('support cases', 'tickets')
      COMMENT = 'Product support cases and resolutions'
  )
  FACTS (
    cases.days_to_resolve AS days_to_resolve COMMENT = 'Days taken to resolve the case',
    cases.is_resolved AS IFF(resolved, 1, 0) COMMENT = '1 if the case was resolved'
  )
  DIMENSIONS (
    cases.case_id AS case_id,
    cases.opened_date AS opened_date COMMENT = 'Date the case was opened',
    cases.product_line AS product_line WITH SYNONYMS ('product') COMMENT = 'Product line',
    cases.product_model AS product_model COMMENT = 'Specific product model',
    cases.issue_category AS issue_category WITH SYNONYMS ('issue type') COMMENT = 'Category of the issue such as Connectivity or Warranty Inquiry',
    cases.firmware_version AS firmware_version COMMENT = 'Firmware version on the device',
    cases.warranty_status AS warranty_status COMMENT = 'Warranty coverage status',
    cases.resolution AS resolution COMMENT = 'How the case was resolved'
  )
  METRICS (
    cases.total_cases AS COUNT(cases.case_id) COMMENT = 'Total number of support cases',
    cases.resolved_cases AS SUM(cases.is_resolved) COMMENT = 'Number of resolved cases',
    cases.avg_days_to_resolve AS AVG(cases.days_to_resolve) COMMENT = 'Average days to resolve a case'
  )
  COMMENT = 'Product support analytics: cases, troubleshooting, warranty, and resolution metrics by product and issue';

CREATE OR REPLACE SEMANTIC VIEW ROUTING_DEMO.ROUTING.SUPPLY_CHAIN_SV
  TABLES (
    inventory AS ROUTING_DEMO.ROUTING.SUPPLY_CHAIN_INVENTORY
      PRIMARY KEY (sku, warehouse)
      WITH SYNONYMS ('inventory', 'stock')
      COMMENT = 'Inventory positions and supplier performance by SKU and warehouse'
  )
  FACTS (
    inventory.units_on_hand AS units_on_hand COMMENT = 'Units currently in stock',
    inventory.reorder_point AS reorder_point COMMENT = 'Reorder threshold',
    inventory.lead_time_days AS lead_time_days COMMENT = 'Supplier lead time in days',
    inventory.fulfillment_rate_fact AS fulfillment_rate COMMENT = 'Order fulfillment rate percent',
    inventory.on_time_delivery_fact AS on_time_delivery_pct COMMENT = 'On-time delivery percent'
  )
  DIMENSIONS (
    inventory.sku AS sku WITH SYNONYMS ('item', 'product code') COMMENT = 'Stock keeping unit',
    inventory.product_line AS product_line WITH SYNONYMS ('product') COMMENT = 'Product line',
    inventory.warehouse AS warehouse COMMENT = 'Warehouse holding the stock',
    inventory.region AS region COMMENT = 'Warehouse region',
    inventory.supplier AS supplier COMMENT = 'Supplier name',
    inventory.supplier_region AS supplier_region WITH SYNONYMS ('sourcing region') COMMENT = 'Region the supplier ships from, e.g. Southeast Asia'
  )
  METRICS (
    inventory.total_units_on_hand AS SUM(inventory.units_on_hand) COMMENT = 'Total units in stock',
    inventory.avg_lead_time AS AVG(inventory.lead_time_days) COMMENT = 'Average supplier lead time in days',
    inventory.avg_fulfillment_rate AS AVG(inventory.fulfillment_rate_fact) COMMENT = 'Average fulfillment rate',
    inventory.avg_on_time_delivery AS AVG(inventory.on_time_delivery_fact) COMMENT = 'Average on-time delivery percent'
  )
  COMMENT = 'Supply chain analytics: inventory levels, lead times, supplier performance, and fulfillment by SKU, warehouse, and supplier region';


-- ─────────────────────────────────────────────────────────────────────────────
>>>>>>> remote
-- 3. SPECIALIST AGENTS
-- ─────────────────────────────────────────────────────────────────────────────

-- Specialist Agent 1: Sales Analyst
CREATE OR REPLACE AGENT ROUTING_DEMO.ROUTING.SALES_ANALYST
COMMENT = 'Sales specialist for revenue, pipeline, quotas, and forecasts'
FROM SPECIFICATION $$
models:
  orchestration: auto
instructions:
  response: |
    You are the Sales Analyst. You answer questions about revenue, pipeline,
    quotas, forecasts, channel performance, pricing strategy, deal velocity,
<<<<<<< local
    and growth rates. Use the query_sales tool to get real numbers from the
    SALES_SV semantic view, then provide specific figures in your answer.
  orchestration: "Use query_sales to retrieve sales data before answering."
=======
    and growth rates. Use the query_sales tool to get real numbers from the
    SALES_SV semantic view, then provide specific figures in your answer.
  orchestration: "Use query_sales to retrieve sales data before answering."
>>>>>>> remote
tools:
  - tool_spec:
<<<<<<< local
      type: cortex_analyst_text_to_sql
      name: query_sales
      description: "Query sales data (revenue, pipeline, deals) by quarter, region, channel, product line, and rep"
tool_resources:
  query_sales:
    semantic_view: ROUTING_DEMO.ROUTING.SALES_SV
    execution_environment:
      type: warehouse
      warehouse: ROUTING_DEMO_WH
=======
      type: cortex_analyst_text_to_sql
      name: query_sales
      description: "Query sales data (revenue, pipeline, deals) by quarter, region, channel, product line, and rep"
tool_resources:
  query_sales:
    semantic_view: ROUTING_DEMO.ROUTING.SALES_SV
    execution_environment:
      type: warehouse
      warehouse: ROUTING_DEMO_WH
>>>>>>> remote
$$;

-- Specialist Agent 2: Product Support
CREATE OR REPLACE AGENT ROUTING_DEMO.ROUTING.PRODUCT_SUPPORT
COMMENT = 'Product specialist for troubleshooting, specs, and warranty'
FROM SPECIFICATION $$
models:
  orchestration: auto
instructions:
  response: |
    You are the Product Support specialist. You answer questions about product
    specifications, troubleshooting steps, warranty policies, feature comparisons,
<<<<<<< local
    known issues, and user guides. Use the query_product tool to pull real case
    history and resolutions from the PRODUCT_SV semantic view to ground answers.
  orchestration: "Use query_product to retrieve support case data before answering."
=======
    known issues, and user guides. Use the query_product tool to pull real case
    history and resolutions from the PRODUCT_SV semantic view to ground answers.
  orchestration: "Use query_product to retrieve support case data before answering."
>>>>>>> remote
tools:
  - tool_spec:
<<<<<<< local
      type: cortex_analyst_text_to_sql
      name: query_product
      description: "Query product support cases (issues, firmware, warranty, resolutions) by product line, model, and issue category"
tool_resources:
  query_product:
    semantic_view: ROUTING_DEMO.ROUTING.PRODUCT_SV
    execution_environment:
      type: warehouse
      warehouse: ROUTING_DEMO_WH
=======
      type: cortex_analyst_text_to_sql
      name: query_product
      description: "Query product support cases (issues, firmware, warranty, resolutions) by product line, model, and issue category"
tool_resources:
  query_product:
    semantic_view: ROUTING_DEMO.ROUTING.PRODUCT_SV
    execution_environment:
      type: warehouse
      warehouse: ROUTING_DEMO_WH
>>>>>>> remote
$$;

-- Specialist Agent 3: Supply Chain
CREATE OR REPLACE AGENT ROUTING_DEMO.ROUTING.SUPPLY_CHAIN
COMMENT = 'Supply chain specialist for inventory, logistics, and procurement'
FROM SPECIFICATION $$
models:
  orchestration: auto
instructions:
  response: |
    You are the Supply Chain agent. You answer questions about inventory levels,
    lead times, supplier performance, fulfillment rates, warehouse capacity,
<<<<<<< local
    shipping logistics, and procurement optimization. Use the query_supply_chain
    tool to retrieve real inventory and supplier data from the SUPPLY_CHAIN_SV
    semantic view before answering.
  orchestration: "Use query_supply_chain to retrieve inventory and supplier data before answering."
=======
    shipping logistics, and procurement optimization. Use the query_supply_chain
    tool to retrieve real inventory and supplier data from the SUPPLY_CHAIN_SV
    semantic view before answering.
  orchestration: "Use query_supply_chain to retrieve inventory and supplier data before answering."
>>>>>>> remote
tools:
  - tool_spec:
<<<<<<< local
      type: cortex_analyst_text_to_sql
      name: query_supply_chain
      description: "Query inventory and supplier data (units on hand, lead times, fulfillment, on-time delivery) by SKU, warehouse, and supplier region"
tool_resources:
  query_supply_chain:
    semantic_view: ROUTING_DEMO.ROUTING.SUPPLY_CHAIN_SV
    execution_environment:
      type: warehouse
      warehouse: ROUTING_DEMO_WH
=======
      type: cortex_analyst_text_to_sql
      name: query_supply_chain
      description: "Query inventory and supplier data (units on hand, lead times, fulfillment, on-time delivery) by SKU, warehouse, and supplier region"
tool_resources:
  query_supply_chain:
    semantic_view: ROUTING_DEMO.ROUTING.SUPPLY_CHAIN_SV
    execution_environment:
      type: warehouse
      warehouse: ROUTING_DEMO_WH
>>>>>>> remote
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. STORED PROCEDURE WRAPPERS
-- ─────────────────────────────────────────────────────────────────────────────
-- Each specialist is wrapped in an EXECUTE AS OWNER procedure that calls
-- DATA_AGENT_RUN. The supervisor invokes these as tools — routing happens
-- server-side regardless of which client calls the supervisor.

-- Wrapper for Sales Analyst
<<<<<<< local
CREATE OR REPLACE PROCEDURE ROUTING_DEMO.ROUTING.RUN_SALES_AGENT(message VARCHAR)
=======
CREATE OR REPLACE PROCEDURE ROUTING_DEMO.ROUTING.RUN_SALES_AGENT(message VARCHAR)
>>>>>>> remote
  RETURNS VARCHAR
  LANGUAGE PYTHON
  RUNTIME_VERSION = '3.11'
  PACKAGES = ('snowflake-snowpark-python')
  HANDLER = 'run'
  EXECUTE AS OWNER
AS
$$
import json

<<<<<<< local
def run(session, message):
=======
def run(session, message):
>>>>>>> remote
    body = json.dumps({
<<<<<<< local
        "messages": [{"role": "user", "content": [{"type": "text", "text": message}]}]
=======
        "messages": [{"role": "user", "content": [{"type": "text", "text": message}]}]
>>>>>>> remote
    })
    escaped = body.replace("'", "''")
    result = session.sql(
        f"SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN("
        f"  'ROUTING_DEMO.ROUTING.SALES_ANALYST',"
        f"  '{escaped}'"
        f")"
    ).collect()
    return str(result[0][0]) if result else ''
$$;

-- Wrapper for Product Support
<<<<<<< local
CREATE OR REPLACE PROCEDURE ROUTING_DEMO.ROUTING.RUN_PRODUCT_AGENT(message VARCHAR)
=======
CREATE OR REPLACE PROCEDURE ROUTING_DEMO.ROUTING.RUN_PRODUCT_AGENT(message VARCHAR)
>>>>>>> remote
  RETURNS VARCHAR
  LANGUAGE PYTHON
  RUNTIME_VERSION = '3.11'
  PACKAGES = ('snowflake-snowpark-python')
  HANDLER = 'run'
  EXECUTE AS OWNER
AS
$$
import json

<<<<<<< local
def run(session, message):
=======
def run(session, message):
>>>>>>> remote
    body = json.dumps({
<<<<<<< local
        "messages": [{"role": "user", "content": [{"type": "text", "text": message}]}]
=======
        "messages": [{"role": "user", "content": [{"type": "text", "text": message}]}]
>>>>>>> remote
    })
    escaped = body.replace("'", "''")
    result = session.sql(
        f"SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN("
        f"  'ROUTING_DEMO.ROUTING.PRODUCT_SUPPORT',"
        f"  '{escaped}'"
        f")"
    ).collect()
    return str(result[0][0]) if result else ''
$$;

-- Wrapper for Supply Chain
<<<<<<< local
CREATE OR REPLACE PROCEDURE ROUTING_DEMO.ROUTING.RUN_SUPPLY_CHAIN_AGENT(message VARCHAR)
=======
CREATE OR REPLACE PROCEDURE ROUTING_DEMO.ROUTING.RUN_SUPPLY_CHAIN_AGENT(message VARCHAR)
>>>>>>> remote
  RETURNS VARCHAR
  LANGUAGE PYTHON
  RUNTIME_VERSION = '3.11'
  PACKAGES = ('snowflake-snowpark-python')
  HANDLER = 'run'
  EXECUTE AS OWNER
AS
$$
import json

<<<<<<< local
def run(session, message):
=======
def run(session, message):
>>>>>>> remote
    body = json.dumps({
<<<<<<< local
        "messages": [{"role": "user", "content": [{"type": "text", "text": message}]}]
=======
        "messages": [{"role": "user", "content": [{"type": "text", "text": message}]}]
>>>>>>> remote
    })
    escaped = body.replace("'", "''")
    result = session.sql(
        f"SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN("
        f"  'ROUTING_DEMO.ROUTING.SUPPLY_CHAIN',"
        f"  '{escaped}'"
        f")"
    ).collect()
    return str(result[0][0]) if result else ''
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. SUPERVISOR AGENT (single entry point for all clients)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE AGENT ROUTING_DEMO.ROUTING.SUPERVISOR
COMMENT = 'Server-side routing agent — eliminates cross-surface variance'
FROM SPECIFICATION $$
models:
  orchestration: auto
orchestration:
  budget:
    seconds: 120
    tokens: 12000
instructions:
  response: |
    You are an enterprise routing agent. Your job is to route each user question
    to the correct specialist and return their response directly. Do not add your
    own commentary — relay the specialist's answer faithfully.
  orchestration: |
    You have access to three specialist agents. Route each user question to the
    SINGLE most appropriate specialist:

    - sales_agent: Revenue, pipeline, quotas, forecasts, channel performance,
      pricing, deals, margins, growth rates, sales targets
    - product_agent: Product specifications, troubleshooting, warranty policies,
      feature comparisons, known issues, user guides, product setup
    - supply_chain_agent: Inventory levels, lead times, supplier performance,
      fulfillment rates, logistics, shipping, warehouse capacity, procurement

    ALWAYS call exactly one specialist per question. Pass the user's full
    question as the message parameter. Return the specialist's response to the user.
tools:
  - tool_spec:
      type: generic
      name: sales_agent
      description: "Routes to the Sales Analyst for questions about revenue, pipeline, quotas, forecasts, channel performance, pricing, and deals"
      input_schema:
        type: object
        properties:
          message:
            type: string
            description: "The user's sales-related question"
        required: ["message"]
  - tool_spec:
      type: generic
      name: product_agent
      description: "Routes to Product Support for questions about product specs, troubleshooting, warranty, feature comparisons, and known issues"
      input_schema:
        type: object
        properties:
          message:
            type: string
            description: "The user's product-related question"
        required: ["message"]
  - tool_spec:
      type: generic
      name: supply_chain_agent
      description: "Routes to Supply Chain for questions about inventory, lead times, supplier performance, fulfillment, logistics, and shipping"
      input_schema:
        type: object
        properties:
          message:
            type: string
            description: "The user's supply chain question"
        required: ["message"]
tool_resources:
  sales_agent:
    type: procedure
    identifier: ROUTING_DEMO.ROUTING.RUN_SALES_AGENT
    execution_environment:
      type: warehouse
      warehouse: ROUTING_DEMO_WH
  product_agent:
    type: procedure
    identifier: ROUTING_DEMO.ROUTING.RUN_PRODUCT_AGENT
    execution_environment:
      type: warehouse
      warehouse: ROUTING_DEMO_WH
  supply_chain_agent:
    type: procedure
    identifier: ROUTING_DEMO.ROUTING.RUN_SUPPLY_CHAIN_AGENT
    execution_environment:
      type: warehouse
      warehouse: ROUTING_DEMO_WH
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. EVALUATION INFRASTRUCTURE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FILE FORMAT ROUTING_DEMO.ROUTING.YAML_FORMAT
  TYPE = 'CSV'
  FIELD_DELIMITER = NONE
  RECORD_DELIMITER = '\n'
  SKIP_HEADER = 0
  FIELD_OPTIONALLY_ENCLOSED_BY = NONE
  ESCAPE_UNENCLOSED_FIELD = NONE;

CREATE OR REPLACE STAGE ROUTING_DEMO.ROUTING.EVAL_STAGE
  FILE_FORMAT = ROUTING_DEMO.ROUTING.YAML_FORMAT;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. EVALUATION DATASET (6 rows: 2 per domain)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE ROUTING_DEMO.ROUTING.EVAL_DATA (
    input_query VARCHAR,
    ground_truth VARIANT
);

INSERT INTO ROUTING_DEMO.ROUTING.EVAL_DATA
SELECT column1, PARSE_JSON(column2) FROM VALUES
-- Sales queries → should route to sales_agent
('What was our Q1 2025 revenue by product line?',
 '{"ground_truth_output": "The response should provide revenue figures broken down by product line for Q1 2025, including specific dollar amounts.", "ground_truth_invocations": [{"tool_name": "sales_agent", "tool_input": "Q1 2025 revenue by product line"}]}'),

('How is our pipeline tracking against the Q2 quota?',
 '{"ground_truth_output": "The response should compare current pipeline value against the Q2 sales quota, noting coverage ratio and risk areas.", "ground_truth_invocations": [{"tool_name": "sales_agent", "tool_input": "Pipeline tracking against Q2 quota"}]}'),

-- Product queries → should route to product_agent
('My device keeps disconnecting from WiFi after the latest firmware update. What should I try?',
 '{"ground_truth_output": "The response should provide WiFi troubleshooting steps such as resetting network settings, checking router compatibility, or rolling back firmware.", "ground_truth_invocations": [{"tool_name": "product_agent", "tool_input": "Device WiFi disconnection after firmware update troubleshooting"}]}'),

('What warranty coverage applies to accessories purchased separately?',
 '{"ground_truth_output": "The response should describe warranty terms for separately purchased accessories, including duration and what is covered.", "ground_truth_invocations": [{"tool_name": "product_agent", "tool_input": "Warranty coverage for separately purchased accessories"}]}'),

-- Supply chain queries → should route to supply_chain_agent
('What is our current inventory level for the top-selling SKU?',
 '{"ground_truth_output": "The response should provide current inventory data or stock levels for the top-selling SKU across warehouses or channels.", "ground_truth_invocations": [{"tool_name": "supply_chain_agent", "tool_input": "Current inventory level for top-selling SKU"}]}'),

('What are the average lead times from our Southeast Asia suppliers?',
 '{"ground_truth_output": "The response should provide lead time estimates from Southeast Asia suppliers, ideally broken down by product category or shipping method.", "ground_truth_invocations": [{"tool_name": "supply_chain_agent", "tool_input": "Average lead times from Southeast Asia suppliers"}]}')

AS t(column1, column2);

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. EVALUATION CONFIG YAML (upload to stage via notebook)
-- ─────────────────────────────────────────────────────────────────────────────
-- The eval config YAML is uploaded programmatically in the lab notebook.
-- For reference, the config should contain:
--
--   evaluation:
--     agent_params:
--       agent_name: "ROUTING_DEMO.ROUTING.SUPERVISOR"
--       agent_type: "CORTEX AGENT"
--     run_params:
--       label: "Routing quality baseline"
--       description: "Validates that the supervisor routes to the correct specialist"
--     source_metadata:
--       type: "dataset"
--       dataset_name: "ROUTING_DEMO.ROUTING.ROUTING_EVAL_DATASET"
--
--   metrics:
--     - "answer_correctness"
--     - "tool_selection_accuracy"
--     - "logical_consistency"

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. GRANTS (ensure evaluation permissions)
-- ─────────────────────────────────────────────────────────────────────────────

-- Grant required permissions for agent evaluation
-- (Run as ACCOUNTADMIN or adjust for your role)
GRANT CREATE AGENT ON SCHEMA ROUTING_DEMO.ROUTING TO ROLE SYSADMIN;
GRANT CREATE DATASET ON SCHEMA ROUTING_DEMO.ROUTING TO ROLE SYSADMIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFICATION
-- ─────────────────────────────────────────────────────────────────────────────
-- Verify all objects were created:
SHOW AGENTS IN SCHEMA ROUTING_DEMO.ROUTING;
SHOW PROCEDURES IN SCHEMA ROUTING_DEMO.ROUTING;
SHOW TABLES IN SCHEMA ROUTING_DEMO.ROUTING;
<<<<<<< local
SHOW SEMANTIC VIEWS IN SCHEMA ROUTING_DEMO.ROUTING;
SHOW STAGES IN SCHEMA ROUTING_DEMO.ROUTING;
=======
SHOW SEMANTIC VIEWS IN SCHEMA ROUTING_DEMO.ROUTING;
SHOW STAGES IN SCHEMA ROUTING_DEMO.ROUTING;
>>>>>>> remote

-- ─────────────────────────────────────────────────────────────────────────────
-- SETUP COMPLETE
-- ─────────────────────────────────────────────────────────────────────────────
-- You can now proceed to the lab notebook. All objects are in place:
<<<<<<< local
--   - 3 domain tables (SALES_FACTS, PRODUCT_CASES, SUPPLY_CHAIN_INVENTORY) with data
--   - 3 semantic views (SALES_SV, PRODUCT_SV, SUPPLY_CHAIN_SV)
--   - 3 specialist agents (SALES_ANALYST, PRODUCT_SUPPORT, SUPPLY_CHAIN), each
--     backed by its semantic view via a cortex_analyst_text_to_sql tool
=======
--   - 3 domain tables (SALES_FACTS, PRODUCT_CASES, SUPPLY_CHAIN_INVENTORY) with data
--   - 3 semantic views (SALES_SV, PRODUCT_SV, SUPPLY_CHAIN_SV)
--   - 3 specialist agents (SALES_ANALYST, PRODUCT_SUPPORT, SUPPLY_CHAIN), each
--     backed by its semantic view via a cortex_analyst_text_to_sql tool
>>>>>>> remote
--   - 3 wrapper procedures (RUN_SALES_AGENT, RUN_PRODUCT_AGENT, RUN_SUPPLY_CHAIN_AGENT)
--   - 1 supervisor agent (SUPERVISOR)
--   - 1 evaluation table (EVAL_DATA) with 6 ground truth rows
--   - 1 internal stage (EVAL_STAGE) for YAML configs
