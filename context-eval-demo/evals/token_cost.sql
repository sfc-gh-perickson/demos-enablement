-- Tokens and credits per agent request over the last 7 days, from billing data (lags up to ~45 minutes).
-- All versions share one agent, so this is an account-level cost check; the app's Results tab
-- shows tokens per question for each version, taken from the eval runs.
-- Replace __DB__ with your demo database.
SELECT AGENT_NAME,
       COUNT(*)                            AS requests,
       ROUND(AVG(TOKENS))                  AS avg_tokens_per_request,
       ROUND(SUM(TOKEN_CREDITS), 4)        AS total_token_credits,
       ROUND(AVG(TOKEN_CREDITS) * 1000, 4) AS credits_per_1k_requests
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AGENT_USAGE_HISTORY
WHERE AGENT_DATABASE_NAME = '__DB__'
  AND START_TIME >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY AGENT_NAME;
