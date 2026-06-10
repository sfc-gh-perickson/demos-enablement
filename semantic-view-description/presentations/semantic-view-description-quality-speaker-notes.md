# Speaker Notes: Grading Semantic View Description Quality

## Account Context Summary

This presentation is designed for sales enablement — specifically for SEs and AEs working with customers who are adopting Cortex Analyst and Semantic Views. The core message is that description quality in semantic views is the #1 lever for improving Cortex Analyst accuracy, and Cortex Code provides automated tooling to audit and fix descriptions at scale. Use this deck to (a) educate customers on why their Analyst accuracy may be low, (b) demonstrate the four-criteria grading framework, and (c) show how Cortex Code automates the review process. This is particularly effective for customers who have built semantic views but are seeing inconsistent Analyst results.

---

## Slide: Overview (Hero)

### Talking Points
- Frame the problem: most customers build semantic views with minimal descriptions, then wonder why Cortex Analyst gives wrong answers
- The "2x Analyst Accuracy Lift" stat is directional — customers who go from no/poor descriptions to well-graded descriptions routinely see dramatic accuracy improvements in evaluations
- Position this as a methodology, not just a tool pitch — the four criteria are useful even without Cortex Code

### Candid Internal Context
- There is no published benchmark for "2x accuracy lift" — this is based on field observations from early adopters. Use "significant improvement" if the customer pushes for specifics
- The grading framework itself is not a product feature — it's a best-practice methodology. Cortex Code's semantic-view skill implements this methodology but the skill is part of Cortex Code (the CLI dev tool), not Snowsight
- Competitive angle: dbt Semantic Layer and Looker's LookML both have description fields but no automated quality grading. This is a differentiator for Snowflake's developer tooling story

### References
- https://docs.snowflake.com/en/user-guide/views-semantic/overview
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst-evaluations

---

## Slide: Why Descriptions Matter

### Talking Points
- Lead with the AI angle: "Descriptions are instructions to the AI, not documentation for humans"
- Cortex Analyst reads the `comment` property on every dimension, fact, and metric when generating SQL. Poor descriptions = ambiguous instructions = wrong SQL
- Business user trust is the real cost — once users get wrong answers, they stop using the tool entirely. This is the adoption killer
- Discoverability matters at scale — customers with 50+ metrics need descriptions to disambiguate. "Revenue" appearing 5 times with different meanings is common

### Candid Internal Context
- Cortex Analyst does NOT currently expose a "confidence score" or tell users when it's unsure due to bad descriptions. It just generates potentially wrong SQL silently. This is a known gap
- The "maintenance at scale" point is forward-looking — most customers today have <50 elements. But enterprise customers building shared semantic views across teams hit this fast
- If the customer asks "can't we just add more verified queries instead?" — VQs help but don't scale. You need hundreds of VQs to cover all variations. Good descriptions reduce the VQ burden by giving the LLM better context for novel questions

### References
- https://docs.snowflake.com/en/user-guide/views-semantic/overview
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst/custom-instructions

---

## Slide: The Four Grading Criteria

### Talking Points
- Present these as independent axes — an element can be precise but verbose, or concise but circular
- Each criterion catches a different failure mode in AI interpretation
- Walk through quickly here, then deep-dive on each in the next four slides

### Candid Internal Context
- These four criteria are not documented in Snowflake's official docs — they're a framework we've developed from field experience. Don't claim they're "Snowflake's official rubric"
- The criteria map roughly to how the LLM processes descriptions: preciseness helps with disambiguation, conciseness reduces noise, non-circularity ensures new information is provided, correctness prevents hallucinated logic

### References
- https://docs.snowflake.com/en/user-guide/views-semantic/semantic-view-yaml-spec

---

## Slide: 1. Preciseness

### Talking Points
- The key question: "Could someone confuse this with another element in the same view?"
- For metrics especially: specify the aggregation function, what's included/excluded, and any filters
- For dimensions: specify the source column, any transformations, and the grain
- Good precision doesn't mean long — it means specific

### Candid Internal Context
- Common customer pushback: "But the name is already precise!" — counter with: the AI doesn't have your tribal knowledge. TOTAL_REVENUE could mean 10 different things across departments
- If a customer has a data dictionary or glossary, descriptions should reference those canonical definitions rather than inventing new ones
- The "before" example ("The total revenue") is extremely common in real customer semantic views — probably 60-70% of descriptions we see in the field look like this

### References
- https://docs.snowflake.com/en/user-guide/views-semantic/semantic-view-yaml-spec

---

## Slide: 2. Conciseness

### Talking Points
- Conciseness is about signal-to-noise ratio, not character count
- The LLM has a context window — verbose descriptions across 100+ elements waste context and dilute signal
- Common filler: "This field represents...", "This column contains...", "This is the..."
- Rule of thumb: if you can remove a word and the meaning doesn't change, remove it

### Candid Internal Context
- Some customers generate descriptions with ChatGPT or Copilot and get extremely verbose output. Cortex Code's skill is tuned to produce concise descriptions specifically optimized for Cortex Analyst's consumption
- There's no hard character limit on descriptions, but based on internal testing, descriptions over ~50 words for simple elements start to hurt more than help because the LLM has to parse more noise
- If customer asks about character limits: there's a 1024 character limit on comments in Snowflake metadata. This is plenty for well-written descriptions

### References
- https://docs.snowflake.com/en/sql-reference/sql/create-semantic-view

---

## Slide: 3. Non-Circular

### Talking Points
- The "delete the name" test is powerful and memorable — use it in the demo
- Circular descriptions are the #1 most common anti-pattern we see in the field
- They happen because people feel obligated to add a description but don't know what to write beyond restating the name
- A non-circular description answers: "How is this computed?" or "What business concept does this represent that isn't obvious from the name?"

### Candid Internal Context
- Circular descriptions are arguably worse than no description at all — they give the LLM false confidence that it understands the element, when actually no new information was provided
- The Snowsight semantic view editor does NOT flag circular descriptions. This is a gap that Cortex Code fills
- If customer says "but the name IS the definition" — that's fine for truly self-evident things like ORDER_DATE. But even then, adding "from the o_orderdate column" tells the AI which physical column to reference

### References
- https://docs.snowflake.com/en/user-guide/views-semantic/overview
- https://docs.snowflake.com/en/sql-reference/sql/desc-semantic-view

---

## Slide: 4. Correctness

### Talking Points
- This is the most dangerous failure — a description that contradicts the SQL expression actively misleads the AI
- Most common: saying "total" when the expression uses AVG, or saying "average" when it uses SUM
- Also watch for: claiming something "excludes returns" when the expression has no filter for returns
- Correctness requires comparing the description against the actual SQL expression — this is where automation shines

### Candid Internal Context
- Correctness errors often happen when someone changes the expression but forgets to update the description. This is especially common after the semantic view has been live for a while
- Cortex Analyst has no built-in validation that descriptions match expressions. It trusts the description. If the description says "total" and the expression is AVG, Analyst may SUM() the result when a user asks for "total X"
- This is where the Cortex Code skill adds the most unique value — it can programmatically compare the description semantics against the SQL expression semantics, which is very hard for humans to do consistently across 100+ elements

### References
- https://docs.snowflake.com/en/sql-reference/sql/desc-semantic-view
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst-evaluations

---

## Slide: Grading Rubric

### Talking Points
- Walk through one column (e.g., Correctness) top to bottom to show the progression from A to F
- Emphasize that most real-world semantic views start at C/D level — this is normal and fixable
- The goal isn't perfection on day one — it's establishing a baseline and iterating
- Grade F (missing) is actually common — many customers have elements with no description at all

### Candid Internal Context
- Don't get bogged down on whether something is a B vs B-. The grades are directional, not precise measurements
- For the demo, cherry-pick elements that clearly demonstrate each grade level. Don't try to grade ambiguous cases live — it can lead to disagreements that derail the conversation
- If customer asks "what grade do I need for good Analyst accuracy?" — aim for B+ or above on all four criteria for metrics (which Analyst uses most heavily). Dimensions can tolerate slightly lower grades since they're often used as grouping/filter columns

### References
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst-evaluations

---

## Slide: Automating Review with Cortex Code

### Talking Points
- Position Cortex Code as the developer's companion for semantic view development
- The semantic-view skill is one of many skills — it auto-loads when the context is relevant
- Key differentiator: it's expression-aware. It doesn't just check text quality — it validates the description against the SQL
- Batch analysis means you don't have to review one element at a time — load the whole view and get a comprehensive scorecard

### Candid Internal Context
- Cortex Code is a CLI tool (not Snowsight). The customer needs to be using Cortex Code already or be willing to adopt it. It's free and included with Snowflake
- The semantic-view skill is loaded automatically when working with semantic view content — no manual invocation needed
- Fix-in-place works on both YAML files (for `cortex reflect` workflow) and can generate ALTER SEMANTIC VIEW DDL
- Pricing: Cortex Code uses Cortex AI credits for the LLM calls. Reviewing a 50-element semantic view typically costs a few cents in credits
- Competitive: No other cloud data platform has an AI-powered description quality grader built into their developer tooling. Databricks Unity Catalog has descriptions but no quality analysis. BigQuery has no equivalent

### References
- https://docs.snowflake.com/en/user-guide/views-semantic/best-practices-dev

---

## Slide: Demo Workflow

### Talking Points
- This is the slide to use as a script for the live demo
- Step 1: Show pulling down an existing semantic view with `cortex semantic-views describe`
- Step 2: The prompt is simple — just ask Cortex Code to grade the descriptions
- Step 3: Show the scorecard output — highlight a few elements with low grades and explain why
- Step 4: Accept a rewrite suggestion live and show the diff
- Step 5: Run `cortex reflect` to validate — this gives the customer confidence nothing broke

### Candid Internal Context
- For the demo, use a semantic view with intentionally mediocre descriptions so the grading has something to find. The TPCH sample semantic view is good for this — its descriptions are short and often circular
- If `cortex reflect` is not available in the customer's environment, skip step 5 and just show the YAML diff
- Common demo failure: if the semantic view is very small (2-3 elements), the grading output is underwhelming. Use a view with at least 8-10 elements for a compelling demo
- If doing this demo for an SE audience: focus on the speed. The whole audit takes 30 seconds vs. hours of manual review

### References
- https://docs.snowflake.com/en/user-guide/views-semantic/best-practices-dev

---

## Slide: Before & After: Real Examples

### Talking Points
- These examples use the TPCH sample data semantic view from Snowflake docs
- Walk through one row in detail: read the before, explain what's wrong, read the after, explain what's better
- DISCOUNTED_PRICE is the best example — the formula makes it precise, the scope makes it non-circular, and it's still concise
- Point out that CUSTOMER_NAME going from "Name of the customer" to referencing the source column is a pattern that applies everywhere

### Candid Internal Context
- The "before" descriptions are the actual descriptions from the Snowflake sample semantic view in the documentation. This is intentional — it shows that even Snowflake's own examples have room for improvement
- Don't spend too long on this slide — it's supporting evidence, not the main pitch. Move to Next Steps quickly
- If customer says "these improvements seem minor" — remind them that at scale (50+ elements), consistent quality across ALL descriptions is what drives accuracy. One bad description can cause Analyst to misroute queries

### References
- https://docs.snowflake.com/en/sql-reference/sql/desc-semantic-view

---

## Slide: Next Steps (Closing)

### Talking Points
- "Audit your existing views" is the immediate call to action — offer to do this together as a follow-up engagement
- The standard/rubric adoption is a longer-term play for mature data teams
- Measuring Analyst accuracy before/after is powerful — use the Cortex Analyst Evaluations feature (now GA) to establish a baseline
- End with the key takeaway: "Descriptions are instructions to the AI, not documentation"

### Candid Internal Context
- The real next step is getting the customer to install Cortex Code and try the skill on their own semantic view. Offer to pair on this in a follow-up session
- If the customer doesn't have Cortex Analyst deployed yet, pivot: "Even without Analyst today, good descriptions future-proof your semantic view and improve discoverability for BI tool integrations"
- For customers already using the Cortex Analyst Evaluations feature: propose running an evaluation before and after description improvements. This gives hard data on the accuracy lift
- Pricing discussion: Cortex Code itself is free. The credits used for the LLM review are minimal (< $1 for most semantic views). The real cost is the time investment to review and approve suggestions — but that's 10x faster than doing it manually

### References
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst-evaluations
- https://docs.snowflake.com/en/user-guide/views-semantic/best-practices-dev
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst/analyst-optimization
