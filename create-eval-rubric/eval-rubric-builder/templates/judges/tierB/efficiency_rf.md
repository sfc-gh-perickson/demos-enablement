User question: {{input}}
Tool calls: {{tool_info}}
Estimate the minimum data calls this question needs. Penalize separate date-resolution calls, retries of
the same query, web search when data tools suffice, and data calls for a question that needs none.
Score anchors:
- 1 = at the minimum with no penalized pattern
- 0.75 = one redundant call that does not change the answer
- 0.5 = one extra data call
- 0.25 = two extra calls, or one penalized pattern
- 0 = three or more extra calls, or a retry loop
{{score_format}}
