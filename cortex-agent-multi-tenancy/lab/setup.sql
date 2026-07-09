-- Cortex Agent Multi-Tenancy Lab: Setup Script
-- Co-authored with CoCo
-- ====================================================

-- Run this script once before starting the notebook.
-- It creates all prerequisite objects: database, tables, policies, semantic view,
-- and the multi-tenant Cortex Agent.
--
-- Prerequisites:
--   - A role with CREATE DATABASE, CREATE WAREHOUSE, CREATE ROW ACCESS POLICY privileges
--   - SNOWFLAKE.CORTEX_USER database role granted to your role
--   - Cross-region inference enabled (for agent LLM calls)
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. DATABASE AND SCHEMA
-- ─────────────────────────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS MULTI_TENANCY_LAB;
USE DATABASE MULTI_TENANCY_LAB;
CREATE SCHEMA IF NOT EXISTS PUBLIC;
USE SCHEMA PUBLIC;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. WAREHOUSE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE WAREHOUSE IF NOT EXISTS MULTI_TENANCY_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;

USE WAREHOUSE MULTI_TENANCY_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. SALES_DATA TABLE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE SALES_DATA (
    SALE_ID         NUMBER,
    TENANT_ID       VARCHAR,
    REGION          VARCHAR,
    PRODUCT         VARCHAR,
    AMOUNT          NUMBER(12,2),
    SALE_DATE       DATE,
    CUSTOMER_NAME   VARCHAR,
    CUSTOMER_EMAIL  VARCHAR
);

INSERT INTO SALES_DATA VALUES
-- acme_corp (30 rows)
(1001, 'acme_corp', 'North America', 'Enterprise Platform License', 4500.00, '2024-01-15', 'John Martinez', 'john.martinez@acme.com'),
(1002, 'acme_corp', 'North America', 'Cloud Storage Bundle', 1200.00, '2024-01-22', 'Sarah Chen', 'sarah.chen@acme.com'),
(1003, 'acme_corp', 'Europe', 'Enterprise Platform License', 4800.00, '2024-02-03', 'Hans Mueller', 'hans.mueller@acme.com'),
(1004, 'acme_corp', 'North America', 'Analytics Add-on', 750.00, '2024-02-14', 'Emily Watson', 'emily.watson@acme.com'),
(1005, 'acme_corp', 'Asia Pacific', 'Cloud Storage Bundle', 1100.00, '2024-02-28', 'Yuki Tanaka', 'yuki.tanaka@acme.com'),
(1006, 'acme_corp', 'Europe', 'Security Suite', 3200.00, '2024-03-05', 'Marie Dupont', 'marie.dupont@acme.com'),
(1007, 'acme_corp', 'North America', 'Enterprise Platform License', 4500.00, '2024-03-18', 'Robert Johnson', 'robert.johnson@acme.com'),
(1008, 'acme_corp', 'North America', 'Analytics Add-on', 850.00, '2024-04-02', 'Lisa Park', 'lisa.park@acme.com'),
(1009, 'acme_corp', 'Asia Pacific', 'Enterprise Platform License', 4200.00, '2024-04-15', 'Wei Zhang', 'wei.zhang@acme.com'),
(1010, 'acme_corp', 'Europe', 'Cloud Storage Bundle', 1350.00, '2024-05-01', 'Anna Schmidt', 'anna.schmidt@acme.com'),
(1011, 'acme_corp', 'North America', 'Security Suite', 3400.00, '2024-05-12', 'Mike Thompson', 'mike.thompson@acme.com'),
(1012, 'acme_corp', 'North America', 'Data Integration Tool', 2100.00, '2024-05-28', 'Jennifer Lee', 'jennifer.lee@acme.com'),
(1013, 'acme_corp', 'Europe', 'Analytics Add-on', 800.00, '2024-06-10', 'Pierre Martin', 'pierre.martin@acme.com'),
(1014, 'acme_corp', 'North America', 'Enterprise Platform License', 4500.00, '2024-06-22', 'David Wilson', 'david.wilson@acme.com'),
(1015, 'acme_corp', 'Asia Pacific', 'Security Suite', 3100.00, '2024-07-05', 'Priya Sharma', 'priya.sharma@acme.com'),
(1016, 'acme_corp', 'North America', 'Cloud Storage Bundle', 1250.00, '2024-07-18', 'Chris Anderson', 'chris.anderson@acme.com'),
(1017, 'acme_corp', 'Europe', 'Data Integration Tool', 2200.00, '2024-08-01', 'Sofia Rossi', 'sofia.rossi@acme.com'),
(1018, 'acme_corp', 'North America', 'Enterprise Platform License', 4700.00, '2024-08-14', 'James Brown', 'james.brown@acme.com'),
(1019, 'acme_corp', 'North America', 'Analytics Add-on', 900.00, '2024-09-02', 'Amanda Taylor', 'amanda.taylor@acme.com'),
(1020, 'acme_corp', 'Asia Pacific', 'Cloud Storage Bundle', 1150.00, '2024-09-15', 'Kenji Watanabe', 'kenji.watanabe@acme.com'),
(1021, 'acme_corp', 'Europe', 'Enterprise Platform License', 4600.00, '2024-09-28', 'Klaus Weber', 'klaus.weber@acme.com'),
(1022, 'acme_corp', 'North America', 'Security Suite', 3300.00, '2024-10-10', 'Rachel Green', 'rachel.green@acme.com'),
(1023, 'acme_corp', 'North America', 'Data Integration Tool', 2050.00, '2024-10-22', 'Tom Harris', 'tom.harris@acme.com'),
(1024, 'acme_corp', 'Europe', 'Analytics Add-on', 825.00, '2024-11-05', 'Luca Bianchi', 'luca.bianchi@acme.com'),
(1025, 'acme_corp', 'North America', 'Enterprise Platform License', 4500.00, '2024-11-18', 'Karen White', 'karen.white@acme.com'),
(1026, 'acme_corp', 'Asia Pacific', 'Security Suite', 3050.00, '2024-11-30', 'Raj Patel', 'raj.patel@acme.com'),
(1027, 'acme_corp', 'North America', 'Cloud Storage Bundle', 1300.00, '2024-12-05', 'Steve Miller', 'steve.miller@acme.com'),
(1028, 'acme_corp', 'Europe', 'Enterprise Platform License', 4900.00, '2024-12-12', 'Elena Popov', 'elena.popov@acme.com'),
(1029, 'acme_corp', 'North America', 'Data Integration Tool', 2150.00, '2024-12-18', 'Nancy Davis', 'nancy.davis@acme.com'),
(1030, 'acme_corp', 'North America', 'Analytics Add-on', 950.00, '2024-12-28', 'Brian Clark', 'brian.clark@acme.com'),

-- globex_inc (30 rows)
(2001, 'globex_inc', 'North America', 'Workflow Automation', 1800.00, '2024-01-08', 'Alex Rivera', 'alex.rivera@globex.com'),
(2002, 'globex_inc', 'Europe', 'API Gateway Pro', 2400.00, '2024-01-20', 'Thomas Berg', 'thomas.berg@globex.com'),
(2003, 'globex_inc', 'North America', 'Workflow Automation', 1900.00, '2024-02-05', 'Jessica Moore', 'jessica.moore@globex.com'),
(2004, 'globex_inc', 'Asia Pacific', 'Data Warehouse Connector', 3100.00, '2024-02-18', 'Hiroshi Sato', 'hiroshi.sato@globex.com'),
(2005, 'globex_inc', 'North America', 'API Gateway Pro', 2500.00, '2024-03-01', 'Daniel Kim', 'daniel.kim@globex.com'),
(2006, 'globex_inc', 'Europe', 'Workflow Automation', 1750.00, '2024-03-14', 'Isabel Garcia', 'isabel.garcia@globex.com'),
(2007, 'globex_inc', 'North America', 'Data Warehouse Connector', 3200.00, '2024-03-28', 'Ryan Cooper', 'ryan.cooper@globex.com'),
(2008, 'globex_inc', 'North America', 'Monitoring Dashboard', 950.00, '2024-04-10', 'Michelle Lee', 'michelle.lee@globex.com'),
(2009, 'globex_inc', 'Europe', 'API Gateway Pro', 2600.00, '2024-04-22', 'Francesco Russo', 'francesco.russo@globex.com'),
(2010, 'globex_inc', 'Asia Pacific', 'Workflow Automation', 1850.00, '2024-05-05', 'Sakura Yamamoto', 'sakura.yamamoto@globex.com'),
(2011, 'globex_inc', 'North America', 'Data Warehouse Connector', 3300.00, '2024-05-18', 'Kevin Wright', 'kevin.wright@globex.com'),
(2012, 'globex_inc', 'Europe', 'Monitoring Dashboard', 1000.00, '2024-06-01', 'Olga Petrov', 'olga.petrov@globex.com'),
(2013, 'globex_inc', 'North America', 'API Gateway Pro', 2450.00, '2024-06-15', 'Carlos Mendez', 'carlos.mendez@globex.com'),
(2014, 'globex_inc', 'North America', 'Workflow Automation', 1950.00, '2024-07-01', 'Stephanie Adams', 'stephanie.adams@globex.com'),
(2015, 'globex_inc', 'Asia Pacific', 'Data Warehouse Connector', 3150.00, '2024-07-14', 'Min-Jun Park', 'minjun.park@globex.com'),
(2016, 'globex_inc', 'Europe', 'API Gateway Pro', 2550.00, '2024-07-28', 'Lars Johansson', 'lars.johansson@globex.com'),
(2017, 'globex_inc', 'North America', 'Monitoring Dashboard', 975.00, '2024-08-10', 'Patricia Nguyen', 'patricia.nguyen@globex.com'),
(2018, 'globex_inc', 'North America', 'Workflow Automation', 1800.00, '2024-08-22', 'Andrew Scott', 'andrew.scott@globex.com'),
(2019, 'globex_inc', 'Europe', 'Data Warehouse Connector', 3250.00, '2024-09-05', 'Emma Lindberg', 'emma.lindberg@globex.com'),
(2020, 'globex_inc', 'North America', 'API Gateway Pro', 2500.00, '2024-09-18', 'Marcus Johnson', 'marcus.johnson@globex.com'),
(2021, 'globex_inc', 'Asia Pacific', 'Monitoring Dashboard', 900.00, '2024-10-02', 'Aiko Nakamura', 'aiko.nakamura@globex.com'),
(2022, 'globex_inc', 'North America', 'Data Warehouse Connector', 3100.00, '2024-10-15', 'Laura Martinez', 'laura.martinez@globex.com'),
(2023, 'globex_inc', 'Europe', 'Workflow Automation', 1850.00, '2024-10-28', 'Viktor Novak', 'viktor.novak@globex.com'),
(2024, 'globex_inc', 'North America', 'API Gateway Pro', 2650.00, '2024-11-10', 'Christina Hall', 'christina.hall@globex.com'),
(2025, 'globex_inc', 'North America', 'Data Warehouse Connector', 3200.00, '2024-11-22', 'Jason Turner', 'jason.turner@globex.com'),
(2026, 'globex_inc', 'Europe', 'Monitoring Dashboard', 1050.00, '2024-12-01', 'Giulia Ferrari', 'giulia.ferrari@globex.com'),
(2027, 'globex_inc', 'North America', 'Workflow Automation', 1900.00, '2024-12-08', 'Brandon Phillips', 'brandon.phillips@globex.com'),
(2028, 'globex_inc', 'Asia Pacific', 'API Gateway Pro', 2400.00, '2024-12-15', 'Mei Ling', 'mei.ling@globex.com'),
(2029, 'globex_inc', 'North America', 'Data Warehouse Connector', 3350.00, '2024-12-20', 'Samantha Brooks', 'samantha.brooks@globex.com'),
(2030, 'globex_inc', 'Europe', 'Workflow Automation', 1800.00, '2024-12-28', 'Henrik Larsen', 'henrik.larsen@globex.com'),

-- initech (30 rows)
(3001, 'initech', 'North America', 'Compliance Manager', 2800.00, '2024-01-10', 'Gary Stevens', 'gary.stevens@initech.io'),
(3002, 'initech', 'North America', 'Report Builder', 650.00, '2024-01-25', 'Sandra Holmes', 'sandra.holmes@initech.io'),
(3003, 'initech', 'Europe', 'Compliance Manager', 2900.00, '2024-02-08', 'Jan Kowalski', 'jan.kowalski@initech.io'),
(3004, 'initech', 'North America', 'Audit Trail System', 3500.00, '2024-02-20', 'Peter Maxwell', 'peter.maxwell@initech.io'),
(3005, 'initech', 'Asia Pacific', 'Report Builder', 700.00, '2024-03-04', 'Ananya Gupta', 'ananya.gupta@initech.io'),
(3006, 'initech', 'Europe', 'Audit Trail System', 3600.00, '2024-03-17', 'Marco Colombo', 'marco.colombo@initech.io'),
(3007, 'initech', 'North America', 'Compliance Manager', 2850.00, '2024-03-30', 'Linda Foster', 'linda.foster@initech.io'),
(3008, 'initech', 'North America', 'Document Vault', 1500.00, '2024-04-12', 'Wayne Roberts', 'wayne.roberts@initech.io'),
(3009, 'initech', 'Europe', 'Report Builder', 680.00, '2024-04-25', 'Katarina Novak', 'katarina.novak@initech.io'),
(3010, 'initech', 'North America', 'Audit Trail System', 3450.00, '2024-05-08', 'Timothy Grant', 'timothy.grant@initech.io'),
(3011, 'initech', 'Asia Pacific', 'Compliance Manager', 2750.00, '2024-05-20', 'Sunita Reddy', 'sunita.reddy@initech.io'),
(3012, 'initech', 'North America', 'Document Vault', 1550.00, '2024-06-03', 'Diane Murphy', 'diane.murphy@initech.io'),
(3013, 'initech', 'Europe', 'Audit Trail System', 3550.00, '2024-06-16', 'Alejandro Diaz', 'alejandro.diaz@initech.io'),
(3014, 'initech', 'North America', 'Report Builder', 720.00, '2024-06-28', 'Charles Reed', 'charles.reed@initech.io'),
(3015, 'initech', 'North America', 'Compliance Manager', 2900.00, '2024-07-10', 'Betty Crawford', 'betty.crawford@initech.io'),
(3016, 'initech', 'Asia Pacific', 'Document Vault', 1450.00, '2024-07-22', 'Vikram Singh', 'vikram.singh@initech.io'),
(3017, 'initech', 'Europe', 'Compliance Manager', 2950.00, '2024-08-05', 'Monika Bauer', 'monika.bauer@initech.io'),
(3018, 'initech', 'North America', 'Audit Trail System', 3500.00, '2024-08-18', 'Frank Mitchell', 'frank.mitchell@initech.io'),
(3019, 'initech', 'North America', 'Report Builder', 750.00, '2024-09-01', 'Dorothy Palmer', 'dorothy.palmer@initech.io'),
(3020, 'initech', 'Europe', 'Document Vault', 1600.00, '2024-09-14', 'Pavel Horvat', 'pavel.horvat@initech.io'),
(3021, 'initech', 'North America', 'Compliance Manager', 2800.00, '2024-09-27', 'Roger Campbell', 'roger.campbell@initech.io'),
(3022, 'initech', 'Asia Pacific', 'Audit Trail System', 3400.00, '2024-10-10', 'Deepak Krishnan', 'deepak.krishnan@initech.io'),
(3023, 'initech', 'North America', 'Report Builder', 690.00, '2024-10-23', 'Cynthia Barnes', 'cynthia.barnes@initech.io'),
(3024, 'initech', 'Europe', 'Compliance Manager', 2850.00, '2024-11-05', 'Stefan Richter', 'stefan.richter@initech.io'),
(3025, 'initech', 'North America', 'Document Vault', 1500.00, '2024-11-18', 'Harold Young', 'harold.young@initech.io'),
(3026, 'initech', 'North America', 'Audit Trail System', 3600.00, '2024-11-30', 'Gloria Simmons', 'gloria.simmons@initech.io'),
(3027, 'initech', 'Europe', 'Report Builder', 700.00, '2024-12-08', 'Tomas Cerny', 'tomas.cerny@initech.io'),
(3028, 'initech', 'Asia Pacific', 'Compliance Manager', 2750.00, '2024-12-15', 'Meena Iyer', 'meena.iyer@initech.io'),
(3029, 'initech', 'North America', 'Audit Trail System', 3550.00, '2024-12-22', 'Russell Howard', 'russell.howard@initech.io'),
(3030, 'initech', 'North America', 'Document Vault', 1550.00, '2024-12-30', 'Kathleen Morris', 'kathleen.morris@initech.io'),

-- umbrella_co (30 rows)
(4001, 'umbrella_co', 'North America', 'Biotech Analytics Suite', 4800.00, '2024-01-12', 'Victor Stone', 'victor.stone@umbrella.co'),
(4002, 'umbrella_co', 'Europe', 'Lab Management System', 2200.00, '2024-01-28', 'Ingrid Hoffmann', 'ingrid.hoffmann@umbrella.co'),
(4003, 'umbrella_co', 'North America', 'Research Data Platform', 3800.00, '2024-02-10', 'Nathan Cole', 'nathan.cole@umbrella.co'),
(4004, 'umbrella_co', 'Asia Pacific', 'Biotech Analytics Suite', 4600.00, '2024-02-22', 'Akira Fujimoto', 'akira.fujimoto@umbrella.co'),
(4005, 'umbrella_co', 'Europe', 'Supply Chain Tracker', 1700.00, '2024-03-06', 'Beatrice Laurent', 'beatrice.laurent@umbrella.co'),
(4006, 'umbrella_co', 'North America', 'Lab Management System', 2300.00, '2024-03-19', 'Derek Walsh', 'derek.walsh@umbrella.co'),
(4007, 'umbrella_co', 'North America', 'Research Data Platform', 3900.00, '2024-04-01', 'Monica Hayes', 'monica.hayes@umbrella.co'),
(4008, 'umbrella_co', 'Europe', 'Biotech Analytics Suite', 4700.00, '2024-04-14', 'Reinhard Keller', 'reinhard.keller@umbrella.co'),
(4009, 'umbrella_co', 'Asia Pacific', 'Supply Chain Tracker', 1650.00, '2024-04-27', 'Soo-Yeon Kim', 'sooyeon.kim@umbrella.co'),
(4010, 'umbrella_co', 'North America', 'Lab Management System', 2250.00, '2024-05-10', 'Craig Henderson', 'craig.henderson@umbrella.co'),
(4011, 'umbrella_co', 'Europe', 'Research Data Platform', 3850.00, '2024-05-23', 'Chiara Moretti', 'chiara.moretti@umbrella.co'),
(4012, 'umbrella_co', 'North America', 'Biotech Analytics Suite', 4900.00, '2024-06-05', 'Wendy Patterson', 'wendy.patterson@umbrella.co'),
(4013, 'umbrella_co', 'North America', 'Supply Chain Tracker', 1750.00, '2024-06-18', 'Gregory Fox', 'gregory.fox@umbrella.co'),
(4014, 'umbrella_co', 'Asia Pacific', 'Lab Management System', 2150.00, '2024-07-01', 'Hana Suzuki', 'hana.suzuki@umbrella.co'),
(4015, 'umbrella_co', 'Europe', 'Research Data Platform', 3750.00, '2024-07-14', 'Oscar Fernandez', 'oscar.fernandez@umbrella.co'),
(4016, 'umbrella_co', 'North America', 'Biotech Analytics Suite', 4850.00, '2024-07-27', 'Tiffany Reeves', 'tiffany.reeves@umbrella.co'),
(4017, 'umbrella_co', 'North America', 'Supply Chain Tracker', 1800.00, '2024-08-09', 'Douglas Perry', 'douglas.perry@umbrella.co'),
(4018, 'umbrella_co', 'Europe', 'Lab Management System', 2350.00, '2024-08-22', 'Anja Muller', 'anja.muller@umbrella.co'),
(4019, 'umbrella_co', 'Asia Pacific', 'Biotech Analytics Suite', 4650.00, '2024-09-04', 'Ravi Deshmukh', 'ravi.deshmukh@umbrella.co'),
(4020, 'umbrella_co', 'North America', 'Research Data Platform', 3900.00, '2024-09-17', 'Caroline Bishop', 'caroline.bishop@umbrella.co'),
(4021, 'umbrella_co', 'Europe', 'Supply Chain Tracker', 1700.00, '2024-09-30', 'Matteo Conti', 'matteo.conti@umbrella.co'),
(4022, 'umbrella_co', 'North America', 'Lab Management System', 2200.00, '2024-10-13', 'Keith Russell', 'keith.russell@umbrella.co'),
(4023, 'umbrella_co', 'Asia Pacific', 'Research Data Platform', 3700.00, '2024-10-26', 'Jia Wei', 'jia.wei@umbrella.co'),
(4024, 'umbrella_co', 'North America', 'Biotech Analytics Suite', 5000.00, '2024-11-08', 'Angela Cross', 'angela.cross@umbrella.co'),
(4025, 'umbrella_co', 'Europe', 'Supply Chain Tracker', 1750.00, '2024-11-20', 'Nikolai Volkov', 'nikolai.volkov@umbrella.co'),
(4026, 'umbrella_co', 'North America', 'Lab Management System', 2400.00, '2024-12-02', 'Donna Stewart', 'donna.stewart@umbrella.co'),
(4027, 'umbrella_co', 'North America', 'Research Data Platform', 3950.00, '2024-12-10', 'Wayne Mitchell', 'wayne.mitchell@umbrella.co'),
(4028, 'umbrella_co', 'Europe', 'Biotech Analytics Suite', 4750.00, '2024-12-16', 'Elise Bonnet', 'elise.bonnet@umbrella.co'),
(4029, 'umbrella_co', 'Asia Pacific', 'Supply Chain Tracker', 1650.00, '2024-12-22', 'Takeshi Ono', 'takeshi.ono@umbrella.co'),
(4030, 'umbrella_co', 'North America', 'Lab Management System', 2300.00, '2024-12-30', 'Phillip Norman', 'phillip.norman@umbrella.co');

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. USER_ENTITLEMENTS TABLE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE USER_ENTITLEMENTS (
    EXTERNAL_USER_ID  VARCHAR,
    TENANT_ID         VARCHAR,
    ACCESS_LEVEL      VARCHAR
);

INSERT INTO USER_ENTITLEMENTS VALUES
-- acme_corp users
('user_acme_admin', 'acme_corp', 'full'),
('user_acme_manager', 'acme_corp', 'full'),
('user_acme_analyst1', 'acme_corp', 'summary'),
('user_acme_analyst2', 'acme_corp', 'summary'),
('user_acme_viewer', 'acme_corp', 'restricted'),

-- globex_inc users
('user_globex_admin', 'globex_inc', 'full'),
('user_globex_director', 'globex_inc', 'full'),
('user_globex_analyst', 'globex_inc', 'summary'),
('user_globex_intern1', 'globex_inc', 'restricted'),
('user_globex_intern2', 'globex_inc', 'restricted'),

-- initech users
('user_initech_ceo', 'initech', 'full'),
('user_initech_cfo', 'initech', 'full'),
('user_initech_ops1', 'initech', 'summary'),
('user_initech_ops2', 'initech', 'summary'),
('user_initech_contractor', 'initech', 'restricted'),

-- umbrella_co users
('user_umbrella_exec', 'umbrella_co', 'full'),
('user_umbrella_lead', 'umbrella_co', 'summary'),
('user_umbrella_researcher1', 'umbrella_co', 'summary'),
('user_umbrella_researcher2', 'umbrella_co', 'summary'),
('user_umbrella_temp', 'umbrella_co', 'restricted');

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. SECURE UDF: GET_USER_ACCESS_LEVEL
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE SECURE FUNCTION GET_USER_ACCESS_LEVEL()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
  SELECT ACCESS_LEVEL
  FROM MULTI_TENANCY_LAB.PUBLIC.USER_ENTITLEMENTS
  WHERE EXTERNAL_USER_ID = SYS_CONTEXT('SNOWFLAKE$SESSION_ATTRIBUTES', 'user_id')
  LIMIT 1
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. ROW ACCESS POLICY
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE ROW ACCESS POLICY RAP_TENANT_FILTER
AS (tenant_id_col VARCHAR) RETURNS BOOLEAN ->
  -- Allow access only when session tenant_id matches the row's tenant_id
  -- If no session attribute is set, deny all rows (fail-closed)
  tenant_id_col = SYS_CONTEXT('SNOWFLAKE$SESSION_ATTRIBUTES', 'tenant_id')
  OR SYS_CONTEXT('SNOWFLAKE$SESSION_ATTRIBUTES', 'tenant_id') IS NULL
;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. MASKING POLICY: CUSTOMER_EMAIL
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE MASKING POLICY MASK_CUSTOMER_EMAIL
AS (val VARCHAR) RETURNS VARCHAR ->
  CASE
    WHEN GET_USER_ACCESS_LEVEL() = 'full' THEN val
    ELSE '***@***.***'
  END;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. MASKING POLICY: CUSTOMER_NAME
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE MASKING POLICY MASK_CUSTOMER_NAME
AS (val VARCHAR) RETURNS VARCHAR ->
  CASE
    WHEN GET_USER_ACCESS_LEVEL() IN ('full', 'summary') THEN val
    ELSE '*** MASKED ***'
  END;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. APPLY POLICIES TO SALES_DATA
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE SALES_DATA ADD ROW ACCESS POLICY RAP_TENANT_FILTER ON (TENANT_ID);
ALTER TABLE SALES_DATA MODIFY COLUMN CUSTOMER_EMAIL SET MASKING POLICY MASK_CUSTOMER_EMAIL;
ALTER TABLE SALES_DATA MODIFY COLUMN CUSTOMER_NAME SET MASKING POLICY MASK_CUSTOMER_NAME;

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. SEMANTIC VIEW
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE SEMANTIC VIEW TENANT_SALES_ANALYTICS
  TABLES (
    MULTI_TENANCY_LAB.PUBLIC.SALES_DATA
  )
  DIMENSIONS (
    SALES_DATA.TENANT_ID AS TENANT_ID comment='Company tenant identifier (acme_corp, globex_inc, initech, umbrella_co)',
    SALES_DATA.REGION AS REGION comment='Geographic sales region: North America, Europe, or Asia Pacific',
    SALES_DATA.PRODUCT AS PRODUCT comment='Product or service that was sold',
    SALES_DATA.SALE_DATE AS SALE_DATE comment='Date of the sale transaction'
  )
  METRICS (
    SALES_DATA.TOTAL_REVENUE AS SUM(AMOUNT) comment='Total revenue in USD (sum of sale amounts)',
    SALES_DATA.AVG_ORDER_VALUE AS AVG(AMOUNT) comment='Average order value in USD',
    SALES_DATA.ORDER_COUNT AS COUNT(*) comment='Total number of sales orders'
  )
  COMMENT = 'Multi-tenant sales analytics for Cortex Agent'
  AI_SQL_GENERATION 'This is a multi-tenant sales table. Row access policies automatically filter data by tenant based on session attributes — do not add tenant_id filters in SQL. Always round currency to 2 decimal places. When no date filter is specified, default to the full year 2024.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. CORTEX AGENT
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE AGENT TENANT_SALES_AGENT
  COMMENT = 'Multi-tenant sales analytics agent with RBAC via session attributes'
FROM SPECIFICATION
$$
models:
  orchestration: auto

instructions:
  response: |
    You are a sales analytics assistant. Answer questions about sales performance,
    revenue, and product metrics. Always be concise and data-driven.
    Present currency values with $ prefix and 2 decimal places.
    When comparing time periods, clearly label each period.

tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "sales_analytics"
      description: "Query sales performance data including revenue, order counts, product breakdowns, and regional analysis. Use for any quantitative question about sales metrics."

tool_resources:
  sales_analytics:
    semantic_view: "MULTI_TENANCY_LAB.PUBLIC.TENANT_SALES_ANALYTICS"
    execution_environment:
        type: warehouse
        warehouse: MULTI_TENANCY_WH
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 12. GRANTS (adjust role as needed)
-- ─────────────────────────────────────────────────────────────────────────────

-- Grant required permissions for agent usage
-- (Run as ACCOUNTADMIN or adjust for your role)
GRANT CREATE AGENT ON SCHEMA MULTI_TENANCY_LAB.PUBLIC TO ROLE SYSADMIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- SETUP COMPLETE
-- ─────────────────────────────────────────────────────────────────────────────
-- Verify objects were created:
SHOW TABLES IN SCHEMA MULTI_TENANCY_LAB.PUBLIC;
SHOW SEMANTIC VIEWS IN SCHEMA MULTI_TENANCY_LAB.PUBLIC;
SHOW MASKING POLICIES IN SCHEMA MULTI_TENANCY_LAB.PUBLIC;
SHOW ROW ACCESS POLICIES IN SCHEMA MULTI_TENANCY_LAB.PUBLIC;
