/*=============================================================
  03_spcs_infrastructure.sql
  GPU compute pool, image repository, and Leiden job service
  for the Graph Fraud Detection demo.
=============================================================*/

USE DATABASE GRAPH_FRAUD_DEMO;

--------------------------------------------------------------
-- 1. Image Repository
--------------------------------------------------------------
CREATE IMAGE REPOSITORY IF NOT EXISTS GRAPH.IMAGE_REPO;

-- After running this script, push the Docker image:
--   snow spcs image-registry login
--   docker build -t <org>-<acct>.registry.snowflakecomputing.com/graph_fraud_demo/graph/image_repo/leiden_job:latest ./spcs
--   docker push <org>-<acct>.registry.snowflakecomputing.com/graph_fraud_demo/graph/image_repo/leiden_job:latest

--------------------------------------------------------------
-- 2. GPU Compute Pool
--------------------------------------------------------------
CREATE COMPUTE POOL IF NOT EXISTS GRAPH_FRAUD_GPU_POOL
    MIN_NODES = 1
    MAX_NODES = 1
    INSTANCE_FAMILY = GPU_NV_S
    AUTO_SUSPEND_SECS = 300
    COMMENT = 'Single-node GPU pool for cuGraph Leiden community detection';

--------------------------------------------------------------
-- 3. Community results & assignments tables
--------------------------------------------------------------
USE SCHEMA GRAPH;

CREATE TABLE IF NOT EXISTS COMMUNITY_RESULTS (
    APPLICANT_ID        VARCHAR NOT NULL,
    COMMUNITY_ID       INTEGER NOT NULL,
    DEGREE_CENTRALITY  FLOAT,
    COMMUNITY_SIZE     INTEGER,
    MODULARITY         FLOAT,
    CONSTRAINT pk_community_results PRIMARY KEY (APPLICANT_ID)
);

CREATE TABLE IF NOT EXISTS COMMUNITY_ASSIGNMENTS (
    APPLICANT_ID        VARCHAR(40) NOT NULL,
    COMMUNITY_ID       INTEGER NOT NULL,
    ASSIGNMENT_SOURCE  VARCHAR(20) NOT NULL DEFAULT 'LEIDEN',  -- 'LEIDEN', 'HEURISTIC', or 'PENDING'
    CONFIDENCE         FLOAT DEFAULT 1.0,
    ASSIGNED_AT        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (APPLICANT_ID)
);

--------------------------------------------------------------
-- 4. Execute Job Service (ad-hoc / called by Task)
--------------------------------------------------------------
-- Run Leiden as an SPCS job service.  Container starts, runs
-- leiden_job.py, writes results, exits.  GPU released on exit.
DROP SERVICE IF EXISTS GRAPH_FRAUD_DEMO.GRAPH.LEIDEN_JOB;
EXECUTE JOB SERVICE
    IN COMPUTE POOL GRAPH_FRAUD_GPU_POOL
    NAME = GRAPH.LEIDEN_JOB
    QUERY_WAREHOUSE = GRAPH_FRAUD_WH
    FROM SPECIFICATION $$
    spec:
      containers:
        - name: leiden
          image: /graph_fraud_demo/graph/image_repo/leiden_job:latest
          env:
            SNOWFLAKE_WAREHOUSE: GRAPH_FRAUD_WH
            LEIDEN_RESOLUTION: "1.0"
          resources:
            requests:
              nvidia.com/gpu: 1
            limits:
              nvidia.com/gpu: 1
    $$;

--------------------------------------------------------------
-- 5. Scheduled Task — re-run Leiden every 15 minutes
--------------------------------------------------------------
CREATE OR REPLACE TASK GRAPH.LEIDEN_REFRESH_TASK
    WAREHOUSE = GRAPH_FRAUD_WH
    SCHEDULE  = '15 MINUTE'
    COMMENT   = 'Periodically re-run full Leiden community detection on GPU'
AS
    EXECUTE JOB SERVICE
        IN COMPUTE POOL GRAPH_FRAUD_GPU_POOL
        NAME = GRAPH.LEIDEN_JOB
        QUERY_WAREHOUSE = GRAPH_FRAUD_WH
        FROM SPECIFICATION $$
        spec:
          containers:
            - name: leiden
              image: /graph_fraud_demo/graph/image_repo/leiden_job:latest
              env:
                SNOWFLAKE_WAREHOUSE: GRAPH_FRAUD_WH
                LEIDEN_RESOLUTION: "1.0"
              resources:
                requests:
                  nvidia.com/gpu: 1
                limits:
                  nvidia.com/gpu: 1
        $$;

-- Task is created suspended; resume when ready to start the refresh cycle
-- ALTER TASK GRAPH.LEIDEN_REFRESH_TASK RESUME;
