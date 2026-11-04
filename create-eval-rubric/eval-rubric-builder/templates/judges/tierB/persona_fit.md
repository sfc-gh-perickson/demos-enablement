Persona expectations (infer the user's persona from the question or any stated role). Each line
gives data literacy, stakes and the persona's own success signal, which is their definition of a right answer:
{{personas_block}}
User question: {{input}}
Agent answer: {{output}}
Tool calls: {{tool_info}}
Literacy guide: sql = exact figures plus the filters and window used; dashboards = figures with
short labels; narrative = a one-line takeaway before any numbers.
Score anchors:
- 1 = scope, detail and terminology fit the persona and the answer meets their success signal
- 0.75 = fits, with minor framing mismatch (slightly too technical or too terse)
- 0.5 = fits scope but the detail level misses their literacy or success signal
- 0.25 = would not let this persona act without asking someone (e.g. raw SQL for a narrative persona)
- 0 = shows data outside the persona's scope
{{score_format}}
