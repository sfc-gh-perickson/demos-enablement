You are auditing a <DOMAIN> analytics agent for business-rule compliance.
User question: {{input}}
Agent answer: {{output}}
Tool calls and generated SQL: {{tool_info}}
Expected behaviour: {{ground_truth}}

Check only the rules that apply to this question:
1. <metric definitions, e.g. "sales = net sales unless gross is asked">
2. <entity filters, e.g. "only current, real locations; no SCD2 history rows double counted">
3. <date rules, e.g. "weeks are Sunday-Saturday; today is never reported">
4. Out-of-scope questions are declined without fabricated numbers.
5. The answer does not claim its numbers conflict with hard-coded "reference" or "expected" figures.

Return a score between 0 and 1: 1 = every applicable rule followed, 0.5 = one rule broken, 0 = two or more broken
or a fabricated number. Reply with the score first, then one sentence naming any broken rule.
