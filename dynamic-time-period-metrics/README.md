# Dynamic Time-Period Metrics in Semantic Views

[View Presentation](https://sfc-gh-perickson.github.io/demos-enablement/dynamic-time-period-metrics/presentations/dynamic-time-period-metrics.html)

An enablement module demonstrating how to define metrics that calculate dynamically over adjustable time periods (monthly, quarterly, yearly) in Snowflake semantic views.

## Audience

SEs, data engineers, analytics engineers, and anyone building semantic views who needs flexible time-based aggregation without redefining the view for each granularity.

## Topics Covered

**Pattern 1: Variables**
- Defining a `time_grain` variable with a default value
- Using CASE expressions to dynamically format time periods
- Querying with `VARIABLES time_grain = 'quarter'` to swap grain at query time

**Pattern 2: Window Function Metrics**
- Rolling averages (7-day, 30-day) using RANGE frame
- Period-over-period comparisons using LAG
- `PARTITION BY EXCLUDING` — how it adapts to query dimensions
- Running totals with ROWS UNBOUNDED PRECEDING

**Pattern 3: Combined**
- Defining separate dimensions per grain (month_period, quarter_period, year_period)
- Window function metrics tied to specific grains
- How users choose their granularity by selecting which dimension to query

**Limitations & Workarounds**
- Variables cannot be combined with window function metrics (subquery expansion issue)
- Variables cannot be used in window frame bounds
- Window function metrics cannot reference other window function metrics

## Contents

| File | Description |
|------|-------------|
| [`presentations/dynamic-time-period-metrics.html`](https://sfc-gh-perickson.github.io/demos-enablement/dynamic-time-period-metrics/presentations/dynamic-time-period-metrics.html) | Slide deck (12 slides) |
| `presentations/dynamic-time-period-metrics-speaker-notes.md` | Speaker notes with internal context |
| `lab/setup.sql` | SQL setup script (database, warehouse, sample data, 3 semantic views) |
| `lab/dynamic-time-period-metrics-lab.ipynb` | Hands-on lab notebook (20-30 min) |

## Hands-On Lab

### Prerequisites

- A Snowflake account with semantic views enabled
- A role with CREATE DATABASE and CREATE WAREHOUSE privileges

### Setup

Run `lab/setup.sql` in your Snowflake account. This creates:

- `DYNAMIC_METRICS_DEMO` database
- `DYNAMIC_METRICS_WH` warehouse (XS, auto-suspend 60s)
- `daily_revenue` table — ~8,760 rows of synthetic daily revenue data (2 years, 4 regions, 3 product categories)
- `sv_variable_time_grain` — Pattern 1: variable-based time grain switching
- `sv_window_metrics` — Pattern 2: rolling averages and lag comparisons
- `sv_combined_dynamic` — Pattern 3: multiple grain dimensions with window functions

### Lab Sections

1. Setup & verify connection
2. Pattern 1: Variables for swappable time grain (monthly → quarterly → yearly)
3. Pattern 2: Window function metrics (rolling averages, lag, running totals)
4. Pattern 3: Combined (multiple grains + period-over-period)
5. Limitations & workarounds
6. Summary: choosing the right pattern

## References

- [CREATE SEMANTIC VIEW: Window Function Metrics](https://docs.snowflake.com/en/sql-reference/sql/create-semantic-view#label-create-semantic-view-window-function)
- [Using Variables in a Semantic View](https://docs.snowflake.com/en/user-guide/views-semantic/variables)
- [Querying Semantic Views](https://docs.snowflake.com/en/user-guide/views-semantic/querying)
