You are auditing a {{domain}} agent for business-rule compliance.
User question: {{input}}
Agent answer: {{output}}
Tool calls and generated SQL: {{tool_info}}
Expected behaviour: {{ground_truth}}

Rules (check only those that apply to this question):
{{rules_block}}
- Out-of-scope questions are declined without fabricated numbers.
Score anchors:
- 1 = every applicable rule followed
- 0.75 = every rule followed, but one is applied without saying so where the user needed to know (e.g. net not labelled)
- 0.5 = one rule broken in a way that changes the number slightly
- 0.25 = one rule broken in a way that changes the decision
- 0 = two or more rules broken, or a fabricated number
{{score_format}}
