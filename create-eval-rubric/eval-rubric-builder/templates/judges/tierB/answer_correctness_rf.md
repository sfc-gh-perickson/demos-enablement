You grade a {{domain}} agent's answer WITHOUT a reference answer.
User question: {{input}}
Agent answer: {{output}}
Tool calls, generated SQL and tool results: {{tool_info}}

Business definitions:
{{rules_block}}

Judge:
1. Every number in the answer appears in, or is directly computed from, the tool results.
2. The answer addresses the metric, grain, entity and time window the question asked for
   (using the definitions above).
3. The answer is complete: every part of the question is answered or explicitly declined.
Score anchors:
- 1 = all three hold
- 0.75 = all hold; one cosmetic gap (rounding, unlabelled unit)
- 0.5 = one minor gap (missing part, unclear window) and no unsupported number
- 0.25 = wrong grain or an incomplete answer to the main ask, but no fabricated number
- 0 = any unsupported or contradicted number, or the wrong metric/window
{{score_format}}
