---
slug: salesforce
title: Salesforce
kind: Data Source
see_also:
  - lead-source
  - activation-rate
applicable_orgs: []
---

Salesforce is the primary CRM and source of truth for the sales funnel, from lead creation through subscription activation.

## What It Contains

- **Leads**: all prospective customer inquiries (name, contact, product interest, lead source)
- **Opportunities**: qualified leads progressing through the sales funnel
- **Accounts**: company records and customer accounts
- **Subscriptions**: confirmed subscription records linking customer → plan → cohort

## Data Freshness

Salesforce data is replicated to Snowflake via a nightly batch sync (landing by 6:00 AM ET). Near-real-time events (lead creation, stage changes) are also streamed via Salesforce Platform Events with ~5 minute latency.

## Key Objects for Analytics

| Salesforce Object | Snowflake Table | Primary Use |
|---|---|---|
| Lead | `RAW.SALESFORCE.LEAD` | Funnel top, lead source attribution |
| Opportunity | `RAW.SALESFORCE.OPPORTUNITY` | Funnel progression, conversion analysis |
| Account | `RAW.SALESFORCE.ACCOUNT` | Customer identity, firmographics |
| Subscription__c | `RAW.SALESFORCE.SUBSCRIPTION` | Subscription confirmation, cohort assignment |

## Ownership

The Revenue Operations team owns the Salesforce configuration. The Data Engineering team owns the replication pipeline.
