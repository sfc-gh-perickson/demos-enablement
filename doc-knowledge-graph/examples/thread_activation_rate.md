# Example Agent Thread

This is a representative conversation with the Knowledge Vault Agent showing concept lookup, full note retrieval, and relationship traversal.

---

## Turn 1: Basic Concept Lookup

**User:** What is activation rate?

**Agent:**

Activation Rate is a Metric that measures the percentage of trial users who complete onboarding and become paying subscribers.

**Calculation**

```
Activation Rate = Activated Subscribers / Qualified Trials × 100
```

Key things to keep in mind:

- The denominator uses qualified trials, not total sign-ups. A trial qualifies once the user completes at least one core workflow (e.g., connects a data source or creates a dashboard).
- Activation is confirmed when the first subscription payment is processed — not at the point of plan selection.
- Rates vary significantly by plan tier (Starter vs. Professional), so always report with that dimension. Self-serve plans also have different activation windows and shouldn't be compared directly to sales-assisted plans without normalization.
- Don't confuse it with Conversion Rate. Activation Rate starts at qualified trials, while Conversion Rate is a broader funnel metric (Paying Subscribers / Total Sign-Ups × 100) that includes all inbound sign-ups, even those who never log in. A helpful diagnostic: low conversion with high activation rate signals a lead-quality problem, while high conversion with low activation rate signals a product or onboarding problem.

Sources: the Activation Rate and Conversion Rate concept notes.

Want me to pull the full note content for either of these, or map out how Activation Rate relates to the underlying data sources and business rules?

> *2 sources: activation-rate, conversion-rate*

---

## Turn 2: Full Note Retrieval

**User:** Can you pull the full concept note for Activation Rate?

**Agent:**

**Concept: Activation Rate**
**Kind: Metric**

Activation Rate measures the percentage of trial users who complete onboarding and become paying subscribers.

## Calculation

```
Activation Rate = Activated Subscribers / Qualified Trials × 100
```

## Key Considerations

- The denominator uses qualified trials, not total sign-ups. A trial qualifies once the user completes at least one core workflow (e.g., connects a data source or creates a dashboard).
- Activation is confirmed when the first subscription payment is processed, not at the point of plan selection.
- Rates vary significantly by plan tier (Starter vs. Professional) and should always be reported with that dimension.

## Common Pitfalls

- Do not confuse with Conversion Rate, which measures a broader funnel (all sign-ups → paying subscribers).
- Self-serve plans have different activation windows and should not be compared directly to sales-assisted plans without normalization.

> *1 source: activation-rate*

---

## Turn 3: Relationship Traversal

**User:** How is Activation Rate related to its underlying data sources and business rules?

**Agent:**

### The metric's inputs

`Activation Rate = Activated Subscribers / Qualified Trials × 100`. Its two direct inputs each have specific definitions and system origins:

- **Qualified Trials** (denominator): a trial qualifies once the user completes at least one core workflow (connects a data source, creates a dashboard).
- **Activated Subscribers** (numerator): activation is confirmed when the first subscription payment is processed.

### Underlying data source — Salesforce

Salesforce is the primary CRM and source of truth for the entire sales funnel, from lead creation through subscription activation, which makes it the system that supplies both the numerator and denominator. The relevant objects/tables:

| Input | Salesforce Object | Snowflake Table |
|-------|-------------------|-----------------|
| Qualified Trials (funnel progression) | Opportunity | `RAW.SALESFORCE.OPPORTUNITY` |
| Leads (funnel top) | Lead | `RAW.SALESFORCE.LEAD` |
| Activated Subscribers (confirmation, cohort) | Subscription__c | `RAW.SALESFORCE.SUBSCRIPTION` |
| Customer identity | Account | `RAW.SALESFORCE.ACCOUNT` |

Freshness matters for reporting: Salesforce replicates to Snowflake via a nightly batch sync (landing by 6:00 AM ET), with near-real-time lead/stage events streamed at ~5-minute latency. Revenue Operations owns the Salesforce config; Data Engineering owns the replication pipeline.

### Governing business rules and related concepts

- **Revenue Recognition Rule** (Business Rule): Activation (and its associated payment) is not the same as recognized revenue — revenue is recognized ratably over the service period, not at the point of activation or payment.
- **Contract Start Date** (Glossary): Governs the sales funnel close date — leads must convert before quarter-end or slip to the next period.
- **Lead Source** (Dimension): Captured in Salesforce at lead creation (first-touch, immutable) and a standard breakdown for the metric's denominator.
- **Product Mix / Channel** (Dimension): Activation Rate varies significantly by plan type and channel and should always be reported broken out.

### How it fits together

```
Salesforce (Lead / Opportunity / Subscription__c)
        │  nightly sync → Snowflake RAW tables
        ▼
Qualified Trials ──┐
                   ├──► Activation Rate ──(segmented by)──► Lead Source, Product Mix/Channel
Activated Subs ────┘         │
   (payment)                 └── bounded by Contract Start Date (funnel close)
        │
        └── payment ≠ recognized revenue → governed by Revenue Recognition Rule (ASC 606)
```

Notes referenced: activation-rate, salesforce, revenue-recognition, contract-start-date, lead-source, product-mix.

> *6 sources*
