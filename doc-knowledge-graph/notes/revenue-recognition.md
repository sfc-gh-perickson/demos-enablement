---
slug: revenue-recognition
title: Revenue Recognition Rule
kind: Business Rule
see_also:
  - ltv
  - credit-rating
  - contract-start-date
applicable_orgs:
  - Finance
  - FP&A
---

Revenue Recognition governs when and how subscription revenue is recorded on the income statement.

## Rule

Revenue is recognized **ratably over the service period** (the duration of the subscription term), not at the point of contract signing or payment.

Example: A customer pays $12,000 for a 12-month Professional plan. Revenue is recognized at $1,000/month over the 12 months of service, regardless of when payment was received.

## Implications

- **Deferred Revenue**: Payments received before the service period begins are booked as a liability (deferred revenue) until the contract start date.
- **Refund Window**: If a customer cancels within the refund window (typically the first 14-30 days), the recognized revenue for those days is reversed.
- **Early Cancellation**: If a customer cancels mid-term, revenue recognition stops at the cancellation date. No future months are recognized.

## Relationship to Metrics

- **LTV calculation** should use recognized revenue, not billed revenue
- **Retention directly impacts** recognized revenue — every retained month = more recognized revenue
- **Contract Start Date** triggers the beginning of the recognition period

## Standard

Follows ASC 606 (Revenue from Contracts with Customers). The "performance obligation" is delivery of platform access over time.
