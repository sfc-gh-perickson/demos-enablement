You are scoring how efficiently an analytics agent reached its answer.
User question: {{input}}
Tool calls: {{tool_info}}
Duration (ms): {{duration}}
Expected behaviour (min_data_calls = minimum data tool calls needed): {{ground_truth}}

Count the agent's data tool calls (text-to-SQL and SQL execution). Penalise: separate "what is today" or date-resolution
queries, asking the user to confirm dates, web searches, repeated or retried queries, and any tool call for a question
whose min_data_calls is 0.
Score: 1.0 = no more calls than needed (min_data_calls, or min_data_calls + 1 for skill/multi-step questions) and no
penalised behaviour; 0.7 = one extra call; 0.4 = two extra calls or one penalised behaviour; 0.0 = three or more extra
calls or several penalised behaviours.
Reply with the score first, then the call count and the reason.
