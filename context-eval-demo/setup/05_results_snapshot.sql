-- Reference results from the original build (2026-11-17, orchestration model 'auto').
-- The app shows these until you run evals in your own account (evals/run_evals.sql).
CREATE OR REPLACE TABLE __DB__.EVALS.RESULTS_SNAPSHOT (
  VERSION_ALIAS STRING, QUESTION_ID STRING, QUESTION_TYPE STRING,
  ANSWER_CORRECTNESS FLOAT, LOGICAL_CONSISTENCY FLOAT, AVG_AGENT_TOKENS NUMBER, N NUMBER);
INSERT INTO __DB__.EVALS.RESULTS_SNAPSHOT VALUES
('V0_STUFFED','Q1','contested_meaning',0.25,1.0,84316,4),
('V1_GOVERNED_SV','Q1','contested_meaning',0.67,1.0,63905,4),
('V2_ONTOLOGY','Q1','contested_meaning',1.0,0.92,69849,4),
('V3_SENSE','Q1','contested_meaning',1.0,0.75,78854,4),
('V4_INSTRUCTIONS','Q1','contested_meaning',1.0,0.84,93259,4),
('V0_STUFFED','Q2','certified_number',0.08,1.0,77136,4),
('V1_GOVERNED_SV','Q2','certified_number',1.0,0.92,55969,4),
('V2_ONTOLOGY','Q2','certified_number',1.0,0.75,79545,4),
('V3_SENSE','Q2','certified_number',1.0,0.59,103950,4),
('V4_INSTRUCTIONS','Q2','certified_number',1.0,0.67,110688,4),
('V0_STUFFED','Q3','long_tail',0.17,0.84,109452,4),
('V1_GOVERNED_SV','Q3','long_tail',0.0,0.92,79230,4),
('V2_ONTOLOGY','Q3','long_tail',0.0,0.59,96274,4),
('V3_SENSE','Q3','long_tail',0.75,0.42,97162,4),
('V4_INSTRUCTIONS','Q3','long_tail',0.83,0.5,95145,4),
('V0_STUFFED','Q4','behavior',0.08,0.92,95125,4),
('V1_GOVERNED_SV','Q4','behavior',0.0,1.0,65532,4),
('V2_ONTOLOGY','Q4','behavior',0.0,0.84,71967,4),
('V3_SENSE','Q4','behavior',0.0,0.84,86374,4),
('V4_INSTRUCTIONS','Q4','behavior',1.0,1.0,19267,4),
('V0_STUFFED','Q5','context_stuffing',0.25,1.0,152518,4),
('V1_GOVERNED_SV','Q5','context_stuffing',0.75,1.0,121463,4),
('V2_ONTOLOGY','Q5','context_stuffing',1.0,0.67,101038,4),
('V3_SENSE','Q5','context_stuffing',0.75,0.75,97148,4),
('V4_INSTRUCTIONS','Q5','context_stuffing',0.75,0.67,97622,4);
