User question: {{input}}
Agent answer: {{output}}
Tool results: {{tool_info}}
List each factual claim in the answer. A claim is grounded if the tool results support it.
Score anchors:
- 1 = all claims grounded
- 0.75 = one hedged qualitative claim not in the results
- 0.5 = one unsupported qualitative claim stated as fact
- 0.25 = several unsupported qualitative claims
- 0 = any unsupported number or entity
Name the first unsupported claim in the reason, if any.
{{score_format}}
