"""Block until every agent request in this lab's runs is billed in CORTEX_AGENT_USAGE_HISTORY (lags hours).

Usage: python wait_billing.py lab.yaml [--timeout-min 240] [--once]
Exit 0 when fully billed; exit 2 on timeout (scorecard is then partial: say so in the report).
"""
import sys
import time

from common import connect, load_lab

SQL = """
WITH req AS (
  SELECT RECORD_ATTRIBUTES:"ai.observability.record_id"::VARCHAR AS RECORD_ID,
         MAX(RECORD_ATTRIBUTES:"snow.ai.observability.run.name"::VARCHAR) AS RUN_NAME,
         MAX(IFF(RECORD:name::VARCHAR = 'AgentV2RequestResponseInfo',
                 RECORD_ATTRIBUTES:"snow.ai.observability.agent.request_id"::VARCHAR, NULL)) AS REQUEST_ID
  FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(%(db)s, %(schema)s, %(name)s, 'CORTEX AGENT'))
  WHERE RECORD_ATTRIBUTES:"ai.observability.record_id" IS NOT NULL
  GROUP BY 1
  HAVING STARTSWITH(RUN_NAME, %(prefix)s) AND REQUEST_ID IS NOT NULL
)
SELECT req.RUN_NAME, COUNT(*) AS REQUESTS, COUNT(u.REQUEST_ID) AS BILLED
FROM req
LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AGENT_USAGE_HISTORY u
  ON u.REQUEST_ID = req.REQUEST_ID AND UPPER(u.AGENT_NAME) = %(name)s AND u.START_TIME >= %(since)s::TIMESTAMP_LTZ
GROUP BY 1 ORDER BY 1
"""


def main():
    lab = load_lab(sys.argv[1])
    timeout = float(sys.argv[sys.argv.index("--timeout-min") + 1]) if "--timeout-min" in sys.argv else 240
    params = {"db": lab["_db"], "schema": lab["_schema"], "name": lab["_name"].upper(),
              "prefix": lab["run_prefix"] + "_", "since": str(lab["since"])}
    cur = connect(lab).cursor()
    t0 = time.time()
    while True:
        cur.execute(SQL, params)
        rows = cur.fetchall()
        missing = sum(r[1] - r[2] for r in rows)
        print(time.strftime("%H:%M:%S"), f"missing={missing}", [(r[0], f"{r[2]}/{r[1]}") for r in rows], flush=True)
        if rows and missing == 0:
            return
        if "--once" in sys.argv or time.time() - t0 > timeout * 60:
            sys.exit(2)
        time.sleep(600)


if __name__ == "__main__":
    main()
