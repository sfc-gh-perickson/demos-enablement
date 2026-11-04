You are grading the efficiency of a {{domain}} agent.
User question: {{input}}
Tool calls: {{tool_info}}
Expected behaviour (contains min_data_calls): {{ground_truth}}

Count data tool calls (analyst/SQL/search). Penalize: separate calls just to resolve dates, retries of
the same query, web search when the data tools could answer, any data call when min_data_calls is 0.
Score anchors:
- 1 = calls <= min_data_calls and no penalized pattern
- 0.75 = one redundant call that does not change the answer
- 0.5 = one extra data call or one penalized pattern
- 0.25 = two extra calls, or one extra call plus a penalized pattern
- 0 = three or more extra calls, or a retry loop
{{score_format}}
