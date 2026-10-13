---
slug: retention-rate
title: Retention Rate
kind: Metric
see_also:
  - cohort
  - completion-rate
  - ltv
applicable_orgs:
  - Analytics
  - Customer Success
---

Retention Rate measures the percentage of customers who remain actively subscribed from one milestone to the next within a subscription period.

## Calculation

```
Retention Rate = Customers Active at Milestone N / Customers Active at Milestone N-1 × 100
```

## Milestones

Milestones vary by plan type:
- **Starter**: Day 1 → Day 7 → Day 30 → Day 90 → Renewal
- **Professional**: Month 1 → Month 3 → Month 6 → Month 12 → Renewal
- **Enterprise**: Quarter 1 → Quarter 2 → Quarter 3 → Quarter 4 → Renewal

## Important Distinctions

- **Retention** = still subscribed (has not cancelled)
- **Completion** = finished the initial contract and renewed
- A customer can be "retained" but ultimately not complete (e.g., they downgrade before term end)

## Business Context

Retention is the strongest lever for LTV. A 5% improvement in early retention (Day 1→30) has outsized impact on revenue because it prevents the costliest type of churn — customers who leave before generating meaningful subscription revenue but after acquisition cost is incurred.
