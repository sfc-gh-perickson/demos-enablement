You grade whether a {{domain}} agent chose the right tools, WITHOUT a reference.
User question: {{input}}
Available tools and when to use them:
{{tools_block}}
Out of scope:
{{out_of_scope_block}}
Tool calls made: {{tool_info}}
Agent answer: {{output}}
Score anchors:
- 1 = the tools the descriptions call for, with no unnecessary tool, OR a correct decline with no tool
- 0.75 = right tools plus one harmless extra call
- 0.5 = right tools but a needed tool is missing for one part of the question
- 0.25 = a wrong tool used where a right one existed, answer partly salvageable
- 0 = wrong tools for the main ask, or tools used for a question that should be declined
{{score_format}}
