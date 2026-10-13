---
slug: activation-rate
title: Activation Rate
kind: Metric
see_also:
  - cohort
  - conversion-rate
  - product-mix
applicable_orgs:
  - Analytics
  - Marketing
---

Activation Rate measures the percentage of trial users who complete onboarding and become paying subscribers.

## Calculation

```
Activation Rate = Activated Subscribers / Qualified Trials × 100
```

## Key Considerations

- The denominator uses **qualified trials**, not total sign-ups. A trial qualifies once the user completes at least one core workflow (e.g., connects a data source or creates a dashboard).
- Activation is confirmed when the first subscription payment is processed, not at the point of plan selection.
- Rates vary significantly by plan tier (Starter vs. Professional) and should always be reported with that dimension.

## Common Pitfalls

- Do not confuse with **Conversion Rate**, which measures a broader funnel (all sign-ups → paying subscribers).
- Self-serve plans have different activation windows and should not be compared directly to sales-assisted plans without normalization.
