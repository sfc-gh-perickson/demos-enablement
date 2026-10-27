-- =====================================================================
-- AI Functions Lifecycle Demo: Setup
-- Creates database, schemas, and synthetic support tickets with
-- ground-truth labels (labels assigned first, text generated to match).
-- =====================================================================
USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;

CREATE DATABASE IF NOT EXISTS AI_FUNCTIONS_EVAL_DEMO;
CREATE SCHEMA IF NOT EXISTS AI_FUNCTIONS_EVAL_DEMO.RAW;
CREATE SCHEMA IF NOT EXISTS AI_FUNCTIONS_EVAL_DEMO.EVAL;
CREATE SCHEMA IF NOT EXISTS AI_FUNCTIONS_EVAL_DEMO.PROD;
USE SCHEMA AI_FUNCTIONS_EVAL_DEMO.RAW;

-- 1. Ground-truth attributes for 300 tickets
CREATE OR REPLACE TABLE TICKET_LABELS AS
WITH g AS (
  SELECT SEQ4() AS id,
         UNIFORM(0, 5, RANDOM(11)) AS p, UNIFORM(0, 5, RANDOM(12)) AS i,
         UNIFORM(0, 2, RANDOM(13)) AS s, UNIFORM(0, 4, RANDOM(14)) AS a,
         UNIFORM(0, 9, RANDOM(15)) AS legal_roll, UNIFORM(0, 3, RANDOM(16)) AS repeat_roll,
         UNIFORM(0, 3, RANDOM(17)) AS has_order_roll
  FROM TABLE(GENERATOR(ROWCOUNT => 300))
)
SELECT
  id + 1 AS ticket_id,
  ARRAY_CONSTRUCT('SmartThermo X2','AeroBlend Pro Blender','PulseFit Watch','NovaBook 14 Laptop','QuietWave Headphones','HomeCam 360')[p]::STRING AS product,
  ARRAY_CONSTRUCT('billing','shipping','defect','safety','account','how_to')[i]::STRING AS issue_type,
  ARRAY_CONSTRUCT('negative','neutral','positive')[s]::STRING AS sentiment,
  ARRAY_CONSTRUCT('refund','replacement','repair','information','cancel_order')[a]::STRING AS requested_action,
  IFF(has_order_roll > 0, 'ORD-' || LPAD(UNIFORM(10000, 99999, RANDOM(18))::STRING, 5, '0'), NULL) AS order_id,
  legal_roll = 0 AS mentions_legal,
  repeat_roll = 0 AS repeat_contact
FROM g;

-- Business rule for escalation (this is the "domain logic" the prompt must capture)
CREATE OR REPLACE VIEW TICKET_LABELS_V AS
SELECT *,
  (issue_type = 'safety' OR mentions_legal OR (sentiment = 'negative' AND repeat_contact)) AS escalation_flag
FROM TICKET_LABELS;

-- 2. Generate realistic ticket text that matches the labels
CREATE OR REPLACE TABLE TICKETS AS
SELECT
  ticket_id,
  DATEADD('minute', -ticket_id * 37, CURRENT_TIMESTAMP())::TIMESTAMP_NTZ AS created_at,
  AI_COMPLETE(
    model => 'claude-sonnet-4-6',
    prompt => 'Write one realistic customer support email (60-140 words, no subject line, no placeholders) with these properties. '
      || 'Product: ' || product || '. Issue category: ' || issue_type || '. Overall tone: ' || sentiment || '. '
      || 'Customer wants: ' || requested_action || '. '
      || IFF(order_id IS NOT NULL, 'Mention order number ' || order_id || ' naturally. ', 'Do not mention any order number. ')
      || IFF(mentions_legal, 'Customer hints at legal action, a lawyer, or a regulator complaint. ', '')
      || IFF(repeat_contact, 'Customer says this is not their first time contacting support about it. ', '')
      || 'Vary writing style; it may include typos. Return only the email body.'
  )::STRING AS ticket_text
FROM TICKET_LABELS_V;

-- 3. Ground truth as a single VARIANT label (matches function output shape)
CREATE OR REPLACE TABLE TICKETS_LABELED AS
SELECT t.ticket_id, t.created_at, t.ticket_text,
  OBJECT_CONSTRUCT_KEEP_NULL(
    'product', l.product, 'issue_type', l.issue_type, 'sentiment', l.sentiment,
    'requested_action', l.requested_action, 'order_id', l.order_id,
    'escalation_flag', l.escalation_flag) AS expected
FROM TICKETS t JOIN TICKET_LABELS_V l USING (ticket_id);

-- 4. Splits: 50 train (optimize), 50 holdout (eval), 200 "production" stream
CREATE OR REPLACE TABLE AI_FUNCTIONS_EVAL_DEMO.EVAL.TRAIN   AS SELECT ticket_text, expected FROM TICKETS_LABELED WHERE ticket_id <= 50;
CREATE OR REPLACE TABLE AI_FUNCTIONS_EVAL_DEMO.EVAL.HOLDOUT AS SELECT ticket_text, expected FROM TICKETS_LABELED WHERE ticket_id BETWEEN 51 AND 100;
CREATE OR REPLACE TABLE AI_FUNCTIONS_EVAL_DEMO.PROD.INCOMING_TICKETS AS
  SELECT ticket_id, created_at, ticket_text FROM TICKETS_LABELED WHERE ticket_id > 100;

SELECT 'train' s, COUNT(*) FROM AI_FUNCTIONS_EVAL_DEMO.EVAL.TRAIN
UNION ALL SELECT 'holdout', COUNT(*) FROM AI_FUNCTIONS_EVAL_DEMO.EVAL.HOLDOUT
UNION ALL SELECT 'prod', COUNT(*) FROM AI_FUNCTIONS_EVAL_DEMO.PROD.INCOMING_TICKETS;
