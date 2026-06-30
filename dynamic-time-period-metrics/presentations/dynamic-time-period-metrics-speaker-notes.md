# Dynamic Time-Period Metrics in Semantic Views — Speaker Notes

## Slide 1: Hero / Overview

**Key message:** Semantic views now support two features that eliminate the need for multiple views or complex SQL to handle different time granularities.

**Talking points:**
- Common customer request: "I want the same dashboard to show monthly, quarterly, or yearly — without rebuilding anything"
- Two features make this possible: **variables** (query-time parameters) and **window function metrics** (rolling/comparative calcs)
- This deck covers three patterns — simple to advanced — so the audience can pick what fits their use case

**Audience note:** This applies to anyone building semantic views for Cortex Analyst or direct SQL queries.

---

## Slide 2: The Problem

**Key message:** Without these features, supporting multiple time grains means duplicated logic and brittle maintenance.

**Talking points:**
- Traditional approach: create `v_revenue_monthly`, `v_revenue_quarterly`, `v_revenue_yearly` — same metrics defined three times
- Rolling averages require CTEs or self-joins in every query
- Period-over-period (MoM, QoQ) needs LAG in an outer query wrapping the semantic view
- Semantic view variables and window functions bring this logic INTO the view definition

**Common question:** "Can't I just use DATE_TRUNC in my query?" — Yes, but the semantic view approach lets non-SQL users (via Cortex Analyst) get the same flexibility through natural language.

---

## Slide 3: Three Approaches

**Key message:** There's a spectrum of complexity — start with Pattern 1, add patterns as needed.

**Talking points:**
- Pattern 1 (Variables) is the simplest and handles 70% of use cases
- Pattern 2 (Window Functions) adds time-relative calculations
- Pattern 3 (Combined) is for when you need both — with a known limitation to discuss

**Transition:** "Let's look at each in detail, starting with variables."

---

## Slide 4: Pattern 1 — Variables

**Key message:** A single CASE expression with a variable gives you month/quarter/year switching in one dimension.

**Talking points:**
- Variables are defined in the `VARIABLES` clause with a data type and optional default
- Any fact, dimension, or metric expression can reference the variable
- The default value (`'month'`) means existing queries don't break when you add the variable
- Variables expand internally as subqueries — this is important context for limitations later

**Demo tip:** If live-demoing, show the DESCRIBE SEMANTIC VIEW output to highlight the variable shows up in metadata.

---

## Slide 5: Pattern 1 Demo

**Key message:** Same query, different `VARIABLES` clause — instant grain switch.

**Talking points:**
- The query structure is identical — only the VARIABLES line changes
- Works with additional dimensions (region, product category) — the variable only affects the time_period dimension
- Cortex Analyst understands variables — users can say "show me quarterly revenue" and it will set the variable

**Common question:** "What if the user doesn't specify a variable?" — The default kicks in (monthly in this case).

---

## Slide 6: Pattern 2 — Window Functions

**Key message:** Window function metrics are a new metric type where the window function operates on ANOTHER metric (not a raw column).

**Talking points:**
- The inner argument (`daily_revenue`) is itself a metric — this is what makes it a "window function metric"
- `PARTITION BY EXCLUDING` is the key innovation — it removes the specified dimension from partitioning, keeping everything else
- This means if a user queries by `sale_date` and `region`, the rolling average is computed per-region automatically
- Supported window functions: AVG, SUM, MIN, MAX, LAG, LEAD, FIRST_VALUE, LAST_VALUE, etc.

**Internal context:** Window function metrics were added in 2025 — some customers may not have seen them yet.

---

## Slide 7: Pattern 2 Demo

**Key message:** The results show daily revenue alongside its 7-day rolling average and week-ago comparison — all from the semantic view definition.

**Talking points:**
- Note that NULL appears for `revenue_7_days_ago` in the first 7 rows — LAG returns NULL when there's no prior data
- The rolling average smooths out daily noise — useful for dashboards
- Adding `revenue.region` to DIMENSIONS partitions the window by region automatically
- Important: you MUST include the ORDER BY dimension (`sale_date`) in your query or you'll get a compilation error

**Demo tip:** Show the error message when you omit the required dimension — it's clear and actionable.

---

## Slide 8: Pattern 3 — Combined

**Key message:** Since variables can't be used with window functions (slide 10), the workaround is separate dimensions per grain.

**Talking points:**
- Three dimensions: `month_period`, `quarter_period`, `year_period` — user picks which to query
- Window function metrics are tied to specific grains (`prior_month_revenue` uses `month_period`)
- This is more verbose to define but gives full flexibility at query time
- The trade-off: more metrics to define, but each one is clear and self-documenting

---

## Slide 9: Pattern 3 Demo

**Key message:** Monthly shows MoM + moving average; quarterly shows QoQ — same semantic view, different dimension selection.

**Talking points:**
- Left panel: monthly with prior month and 3-month moving average
- Right panel: quarterly with prior quarter comparison
- Adding `revenue.region` works here too — prior month is computed per-region
- This is the most powerful pattern for executive dashboards that need both grain switching AND comparative metrics

---

## Slide 10: Limitations

**Key message:** These are real constraints today — plan your view structure with them in mind.

**Talking points:**
- **Variables + Window Functions:** This is the most surprising limitation. Snowflake expands variables into subqueries, and those subqueries aren't valid GROUP BY expressions when window functions are involved. Error message: "not a valid group by expression"
- **Variable Frame Bounds:** You can't do `RANGE BETWEEN INTERVAL my_var PRECEDING` — the frame must be a literal. Define separate metrics for each frame size you need.
- **Window Metric Chaining:** Can't do `LAG(rolling_7day_avg, 7)` — each window metric must reference a base (non-window) metric.

**Common question:** "Will the variable + window limitation be fixed?" — It's a known area of development; recommend Pattern 3 for now.

---

## Slide 11: Decision Guide

**Key message:** Start with the simplest pattern that meets your needs.

**Talking points:**
- If they just need SUM/AVG/COUNT at different grains → Pattern 1 (Variables)
- If they need rolling/lag at one grain → Pattern 2 (Window Functions)
- If they need both → Pattern 3 (Combined)
- Variables aren't just for time — they work for any parameterized calculation (thresholds, filters, multipliers)

**Transition to lab:** "The hands-on lab has all three patterns with runnable queries if you want to try them yourself."

---

## Slide 12: Key Takeaways

**Key message:** Semantic views now handle dynamic time-period metrics natively — no duplicate views, no complex SQL from end users.

**Talking points:**
- Variables = query-time parameterization for any dimension/metric/fact expression
- Window function metrics = rolling/cumulative/comparative calculations defined once
- PARTITION BY EXCLUDING = makes window metrics adaptive to any query structure
- Know the boundaries: variables and window functions don't mix in the same expression

**Call to action:** Point them to the lab, and the three documentation links at the bottom.

---

## General Presentation Tips

- **Duration:** 15-20 minutes for the deck, 20-30 minutes with the hands-on lab
- **Live demo option:** If you have Snowflake access, run the setup.sql and demo Pattern 1 live — the variable swap is the most visually impactful moment
- **For technical audiences:** Spend more time on Pattern 3 and the limitations
- **For business audiences:** Focus on Pattern 1 and the Cortex Analyst implications (natural language → automatic variable setting)
