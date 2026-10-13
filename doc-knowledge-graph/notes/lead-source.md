---
slug: lead-source
title: Lead Source
kind: Dimension
see_also:
  - conversion-rate
  - activation-rate
applicable_orgs:
  - Marketing
  - Growth
---

Lead Source identifies the channel or method through which a prospective customer first interacted with the platform.

## Standard Lead Source Values

| Lead Source | Description |
|---|---|
| Organic Search | Found via Google/Bing without paid ads |
| Paid Search | Clicked a paid search ad (Google Ads, Bing Ads) |
| Paid Social | Clicked a paid social media ad (Meta, LinkedIn, TikTok) |
| Organic Social | Engaged via non-paid social content |
| Referral | Referred by an existing customer |
| Partner Direct | Came through a channel partner's own channels |
| Email | Responded to an email campaign |
| Event | Attended a webinar, conference, or demo session |

## Attribution Rules

- Lead Source uses **first-touch attribution** — the first known interaction gets credit.
- If a lead arrives via multiple channels before qualifying, only the first is recorded as Lead Source.
- For multi-touch analysis, use the Marketing Attribution Model (separate from Lead Source).

## Data Source

Lead Source is captured in Salesforce at lead creation time and is immutable after creation.
