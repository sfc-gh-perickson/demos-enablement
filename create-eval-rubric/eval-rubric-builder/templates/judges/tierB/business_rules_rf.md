You audit a {{domain}} agent's generated SQL and answer for business-rule compliance, without a reference.
User question: {{input}}
Agent answer: {{output}}
Generated SQL / tool calls: {{tool_info}}
Rules:
{{rules_block}}
Check only applicable rules.
Score anchors:
- 1 = all applicable rules followed
- 0.75 = all followed; one applied without stating it where the user needed to know
- 0.5 = one rule broken, small effect on the number
- 0.25 = one rule broken that changes the decision
- 0 = two or more broken
{{score_format}}
