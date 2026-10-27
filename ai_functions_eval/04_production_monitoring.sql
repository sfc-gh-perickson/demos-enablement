-- =====================================================================
-- AI Functions Lifecycle Demo: Production pipeline + monitoring
-- Prereq: PROD.TRIAGE_TICKET deployed (see 03_optimized_function_v2.sql,
--         or CREATE AI FUNCTION ... FROM EXPERIMENT <exp> RUN <run>)
-- =====================================================================
USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA AI_FUNCTIONS_EVAL_DEMO.PROD;

-- ---------------------------------------------------------------------
-- 1. Incremental production pipeline (stream + task), every output logged
--    with the function version so quality can be traced to a prompt/model.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE TRIAGE_RESULTS (
  ticket_id        NUMBER,
  created_at       TIMESTAMP_NTZ,
  processed_at     TIMESTAMP_NTZ,
  function_version STRING,
  ticket_text      STRING,
  result           VARIANT
);

CREATE OR REPLACE STREAM INCOMING_TICKETS_STREAM ON TABLE INCOMING_TICKETS SHOW_INITIAL_ROWS = TRUE;

CREATE OR REPLACE TASK TRIAGE_TICKETS_TASK
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = '5 MINUTE'
  QUERY_TAG = '{"app":"ticket_triage","env":"prod"}'   -- cost attribution in usage history
  WHEN SYSTEM$STREAM_HAS_DATA('INCOMING_TICKETS_STREAM')
AS
  INSERT INTO TRIAGE_RESULTS
  SELECT ticket_id, created_at, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
         'opt_v2', ticket_text, TRIAGE_TICKET(ticket_text)
  FROM INCOMING_TICKETS_STREAM
  WHERE METADATA$ACTION = 'INSERT';

ALTER TASK TRIAGE_TICKETS_TASK RESUME;
EXECUTE TASK TRIAGE_TICKETS_TASK;   -- kick off the first batch now

-- ---------------------------------------------------------------------
-- 2. COST: credits + tokens for this workload (via QUERY_TAG)
--    ACCOUNT_USAGE latency: up to ~5 minutes
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW MON_COST_DAILY AS
WITH u AS (
  SELECT h.START_TIME, h.MODEL_NAME, h.QUERY_ID, h.CREDITS,
         SUM(IFF(f.value:key:metric::STRING = 'input',  f.value:value::NUMBER, 0)) AS input_tokens,
         SUM(IFF(f.value:key:metric::STRING = 'output', f.value:value::NUMBER, 0)) AS output_tokens
  FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY h,
       LATERAL FLATTEN(input => h.METRICS) f
  WHERE TRY_PARSE_JSON(h.QUERY_TAG):app::STRING = 'ticket_triage'
  GROUP BY 1, 2, 3, 4
)
SELECT DATE_TRUNC('day', START_TIME) AS usage_day, MODEL_NAME,
       COUNT(DISTINCT QUERY_ID) AS queries,
       SUM(CREDITS)             AS credits,
       SUM(input_tokens)        AS input_tokens,
       SUM(output_tokens)       AS output_tokens
FROM u GROUP BY 1, 2;

-- Cost per 1,000 tickets (joins credits to rows processed that day)
CREATE OR REPLACE VIEW MON_COST_PER_1K AS
SELECT c.usage_day, c.credits,
       r.tickets, ROUND(c.credits / NULLIF(r.tickets, 0) * 1000, 4) AS credits_per_1k_tickets
FROM (SELECT usage_day, SUM(credits) credits FROM MON_COST_DAILY GROUP BY 1) c
JOIN (SELECT DATE_TRUNC('day', processed_at) usage_day, COUNT(*) tickets
        FROM TRIAGE_RESULTS GROUP BY 1) r USING (usage_day);

-- ---------------------------------------------------------------------
-- 3. OUTPUT HEALTH: schema / taxonomy conformance (no labels needed)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW MON_OUTPUT_HEALTH AS
SELECT DATE_TRUNC('hour', processed_at) AS hour, function_version,
  COUNT(*) AS tickets,
  AVG(IFF(result IS NULL, 1, 0))                                                         AS null_result_rate,
  AVG(IFF(result:issue_type::STRING IN ('billing','shipping','defect','safety','account','how_to'), 0, 1)) AS bad_issue_type_rate,
  AVG(IFF(result:sentiment::STRING IN ('negative','neutral','positive'), 0, 1))           AS bad_sentiment_rate,
  AVG(IFF(result:requested_action::STRING IN ('refund','replacement','repair','information','cancel_order'), 0, 1)) AS bad_action_rate,
  AVG(IFF(result:order_id IS NULL OR IS_NULL_VALUE(result:order_id)
          OR REGEXP_LIKE(result:order_id::STRING, 'ORD-[0-9]{5}'), 0, 1))                 AS bad_order_id_rate
FROM TRIAGE_RESULTS GROUP BY 1, 2;

-- ---------------------------------------------------------------------
-- 4. DRIFT: production output distribution vs. the labeled eval baseline
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW MON_DRIFT AS
WITH base AS (
  SELECT AVG(IFF(expected:escalation_flag::BOOLEAN, 1, 0))       AS esc_rate,
         AVG(IFF(expected:sentiment::STRING = 'negative', 1, 0)) AS neg_rate
  FROM AI_FUNCTIONS_EVAL_DEMO.EVAL.HOLDOUT_V2   -- reviewed golden set (DATASET TICKETS_HOLDOUT v2)
), prod AS (
  SELECT DATE_TRUNC('day', processed_at) AS day,
         AVG(IFF(result:escalation_flag::BOOLEAN, 1, 0))       AS esc_rate,
         AVG(IFF(result:sentiment::STRING = 'negative', 1, 0)) AS neg_rate,
         COUNT(*) AS tickets
  FROM TRIAGE_RESULTS GROUP BY 1
)
SELECT p.day, p.tickets,
       p.esc_rate, b.esc_rate AS baseline_esc_rate, p.esc_rate - b.esc_rate AS esc_rate_delta,
       p.neg_rate, b.neg_rate AS baseline_neg_rate, p.neg_rate - b.neg_rate AS neg_rate_delta
FROM prod p CROSS JOIN base b;

-- ---------------------------------------------------------------------
-- 5. QUALITY: reference-free LLM-judge on a daily sample of production rows
--    (no ground truth in prod, so the judge reads ticket + prediction)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE QUALITY_SAMPLES (
  judged_at TIMESTAMP_NTZ, ticket_id NUMBER, function_version STRING, verdict VARIANT
);

CREATE OR REPLACE TASK JUDGE_SAMPLE_TASK
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = 'USING CRON 0 6 * * * America/Los_Angeles'
  QUERY_TAG = '{"app":"ticket_triage","env":"prod_judge"}'
AS
  INSERT INTO QUALITY_SAMPLES
  SELECT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, ticket_id, function_version,
    AI_COMPLETE(
      model => 'claude-sonnet-4-6',
      prompt => 'You audit support-ticket triage. Given the ticket and the extracted JSON, judge each field. '
        || 'Taxonomies: issue_type in [billing,shipping,defect,safety,account,how_to], sentiment in [negative,neutral,positive], '
        || 'requested_action in [refund,replacement,repair,information,cancel_order], order_id like ORD-12345 or null. '
        || 'Escalate when: safety issue, legal threat/regulator, or negative customer on a repeat contact.\n\nTICKET:\n'
        || ticket_text || '\n\nEXTRACTION:\n' || TO_VARCHAR(result),
      response_format => {'type':'json','schema':{'type':'object','properties':{
          'all_correct':{'type':'boolean'},
          'incorrect_fields':{'type':'array','items':{'type':'string'}},
          'reason':{'type':'string'}},
        'required':['all_correct','incorrect_fields','reason']}}
    )
  FROM (SELECT * FROM TRIAGE_RESULTS
        WHERE processed_at >= DATEADD('day', -1, CURRENT_TIMESTAMP())) SAMPLE (20 ROWS);

ALTER TASK JUDGE_SAMPLE_TASK RESUME;

CREATE OR REPLACE VIEW MON_QUALITY_DAILY AS
SELECT DATE_TRUNC('day', judged_at) AS day, function_version,
       COUNT(*) AS judged,
       AVG(IFF(verdict:all_correct::BOOLEAN, 1, 0)) AS judge_accuracy
FROM QUALITY_SAMPLES GROUP BY 1, 2;

-- ---------------------------------------------------------------------
-- 6. ALERTING: health/drift/quality guardrails -> alert log
--    (swap the INSERT for SYSTEM$SEND_EMAIL with a notification integration)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE ALERT_LOG (fired_at TIMESTAMP_NTZ, alert STRING, detail VARIANT);

CREATE OR REPLACE ALERT TRIAGE_QUALITY_ALERT
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = '60 MINUTE'
  IF (EXISTS (
    SELECT 1 FROM MON_OUTPUT_HEALTH
     WHERE hour >= DATEADD('hour', -2, CURRENT_TIMESTAMP())
       AND (bad_issue_type_rate > 0.02 OR bad_sentiment_rate > 0.02 OR null_result_rate > 0.01)
    UNION ALL
    SELECT 1 FROM MON_DRIFT WHERE day = CURRENT_DATE() AND ABS(esc_rate_delta) > 0.15
    UNION ALL
    SELECT 1 FROM MON_QUALITY_DAILY WHERE day = CURRENT_DATE() AND judge_accuracy < 0.85
  ))
  THEN
    INSERT INTO ALERT_LOG
    SELECT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, 'triage_quality',
           OBJECT_CONSTRUCT('health', (SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*)) FROM MON_OUTPUT_HEALTH
                                        WHERE hour >= DATEADD('hour', -2, CURRENT_TIMESTAMP())),
                            'drift',  (SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*)) FROM MON_DRIFT WHERE day = CURRENT_DATE()));

ALTER ALERT TRIAGE_QUALITY_ALERT RESUME;
