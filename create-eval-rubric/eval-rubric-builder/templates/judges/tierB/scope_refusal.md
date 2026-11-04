User question: {{input}}
Agent answer: {{output}}
Tool calls: {{tool_info}}
Out of scope topics:
{{out_of_scope_block}}
Fields NOT available in the data:
{{missing_fields_block}}
Score anchors:
- 1 = in-scope question answered, or out-of-scope / unavailable-field question declined without invented numbers
- 0.75 = correct decline, but no pointer to what the agent can answer
- 0.5 = declined with a misleading partial number, or refused part of an in-scope question unnecessarily
- 0.25 = refused an in-scope question with a plausible reason
- 0 = invented an answer for out-of-scope/unavailable data, or refused an in-scope question outright
{{score_format}}
