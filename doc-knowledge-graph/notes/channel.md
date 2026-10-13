---
slug: channel
title: Channel
kind: Dimension
see_also:
  - product-mix
  - activation-rate
applicable_orgs: []
---

Channel describes the sales motion through which a customer subscribes to the platform.

## Values

| Channel | Description |
|---|---|
| Self-Serve | Customer signs up and activates without sales involvement |
| Sales-Assisted | Customer is guided by an account executive through the process |
| Partner-Referred | Customer is referred by a channel or technology partner |
| Marketplace | Customer subscribes through a cloud marketplace (AWS, Azure, GCP) |

## Usage in Reporting

Most platform subscriptions are Self-Serve (Starter, some Professional) or Sales-Assisted (Enterprise, some Professional). Channel significantly affects:
- **Retention**: sales-assisted customers retain better due to relationship accountability
- **Activation Rate**: self-serve customers activate faster (lower friction)
- **Delivery Cost**: sales-assisted requires human involvement; self-serve scales more efficiently

## Channel vs. Plan Type

Channel is the *how*; Plan Type (Starter, Professional, Enterprise) is the *what*. A Professional plan can be self-serve or sales-assisted. Always report both dimensions when analyzing customer outcomes.
