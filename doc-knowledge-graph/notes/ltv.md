---
slug: ltv
title: Lifetime Value (LTV)
kind: Metric
see_also:
  - retention-rate
  - product-mix
  - revenue-recognition
applicable_orgs:
  - Finance
  - Analytics
  - Growth
---

Lifetime Value (LTV) estimates the total net revenue a customer will generate over their entire relationship with the platform.

## Calculation

```
LTV = Average Revenue Per Period × Expected Number of Periods × Gross Margin %
```

Where:
- **Revenue Per Period** = subscription fee per month/quarter depending on billing model
- **Expected Number of Periods** = derived from historical retention curves for that plan type
- **Gross Margin** = revenue minus direct delivery costs (infrastructure, support, onboarding)

## LTV by Plan Type (approximate ranges)

| Plan Type | Typical LTV |
|---|---|
| Enterprise | $50,000 - $200,000 |
| Professional | $8,000 - $25,000 |
| Starter | $1,500 - $5,000 |

## LTV:CAC Ratio

The key health metric is LTV:CAC (Customer Acquisition Cost). Target ratios:
- Enterprise: > 3:1
- Professional: > 2:1
- Starter: > 1.5:1

A ratio below threshold signals either unsustainable acquisition spending or a retention problem eroding LTV.
