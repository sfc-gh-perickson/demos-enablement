# Semantic View Description Quality

[View Presentation](https://sfc-gh-perickson.github.io/demos-enablement/semantic-view-description/presentations/semantic-view-description-quality.html)

A sales enablement module teaching a four-criteria grading framework for semantic view descriptions — the single biggest lever for improving Cortex Analyst accuracy.

## Audience

SEs and AEs working with customers who are adopting Cortex Analyst and Semantic Views, particularly customers seeing inconsistent Analyst results.

## Topics Covered

- Why descriptions matter (they're instructions to the AI, not docs for humans)
- The four grading criteria: Preciseness, Conciseness, Non-Circularity, Correctness
- Grading rubric (A through F) with before/after examples
- How Cortex Code automates description review at scale
- Demo workflow for live customer engagements

## The Four Criteria

| Criterion | What It Catches |
|-----------|----------------|
| **Preciseness** | Ambiguous descriptions that don't disambiguate between similar elements |
| **Conciseness** | Verbose descriptions that add noise for the LLM |
| **Non-Circularity** | Descriptions that just restate the element name without adding information |
| **Correctness** | Descriptions with factual errors that lead to wrong SQL generation |

## Contents

| File | Description |
|------|-------------|
| `presentations/semantic-view-description-quality.html` | Slide deck |
| `presentations/semantic-view-description-quality-speaker-notes.md` | Speaker notes with demo scripts, competitive context, and objection handling |

## Competitive Context

- dbt Semantic Layer and Looker's LookML both have description fields but no automated quality grading
- This positions Snowflake's developer tooling (Cortex Code) as a differentiator

## References

- [Semantic Views Overview](https://docs.snowflake.com/en/user-guide/views-semantic/overview)
- [Semantic View YAML Spec](https://docs.snowflake.com/en/user-guide/views-semantic/semantic-view-yaml-spec)
- [Cortex Analyst Custom Instructions](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst/custom-instructions)
