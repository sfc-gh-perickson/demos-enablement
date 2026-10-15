/*==========================================================================
  04_community_assignments.sql
  Static table for Leiden community assignment results.

  The ADDRESS and IP_NETWORK entities in the Feature Store provide inherited
  community context at query time through the real-time Feature View.
  No separate heuristic Dynamic Table is needed.

  leiden_job.py MERGEs results into COMMUNITY_ASSIGNMENTS after each run.
==========================================================================*/

USE DATABASE GRAPH_FRAUD_DEMO;

CREATE TABLE IF NOT EXISTS GRAPH.COMMUNITY_ASSIGNMENTS (
    APPLICANT_ID       VARCHAR(40)   NOT NULL,
    COMMUNITY_ID      INT           NOT NULL,
    ASSIGNMENT_SOURCE VARCHAR(20)   NOT NULL DEFAULT 'LEIDEN',
    CONFIDENCE        FLOAT         DEFAULT 1.0,
    ASSIGNED_AT       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (APPLICANT_ID)
);
