-- Seeds realistic analyst query history: partner sourcing is always derived from PARTNER_REFERRALS (Accepted),
-- never from OPPORTUNITIES.LEAD_SOURCE. Cortex Sense learns this usage pattern from query history.
USE SCHEMA __DB__.CRM;
-- partner-sourced closed-won deals by month
SELECT DATE_TRUNC('month', o.CLOSE_DATE) AS close_month, COUNT(DISTINCT o.OPPORTUNITY_ID) AS partner_sourced_deals, SUM(o.ACV) AS partner_sourced_acv
FROM OPPORTUNITIES o JOIN PARTNER_REFERRALS p ON p.OPPORTUNITY_ID = o.OPPORTUNITY_ID
WHERE p.REFERRAL_STATUS = 'Accepted' AND o.STAGE = 'Closed Won' GROUP BY 1 ORDER BY 1;
-- partner-sourced pipeline by partner
SELECT p.PARTNER_NAME, COUNT(*) AS open_partner_deals, SUM(o.ACV) AS partner_pipeline
FROM OPPORTUNITIES o JOIN PARTNER_REFERRALS p ON p.OPPORTUNITY_ID = o.OPPORTUNITY_ID
WHERE p.REFERRAL_STATUS = 'Accepted' AND o.STAGE IN ('Proposal','Negotiation') GROUP BY 1 ORDER BY 3 DESC;
-- partner-sourced win rate by quarter
SELECT DATE_TRUNC('quarter', o.CLOSE_DATE) AS q, COUNT_IF(o.STAGE = 'Closed Won') / NULLIF(COUNT_IF(o.STAGE IN ('Closed Won','Closed Lost')), 0) AS partner_win_rate
FROM OPPORTUNITIES o JOIN PARTNER_REFERRALS p ON p.OPPORTUNITY_ID = o.OPPORTUNITY_ID
WHERE p.REFERRAL_STATUS = 'Accepted' GROUP BY 1 ORDER BY 1;
-- partner-sourced deals closed last month with account and region
SELECT o.OPPORTUNITY_ID, a.ACCOUNT_NAME, r.REGION_NAME, p.PARTNER_NAME, o.ACV, o.CLOSE_DATE
FROM OPPORTUNITIES o JOIN PARTNER_REFERRALS p ON p.OPPORTUNITY_ID = o.OPPORTUNITY_ID
JOIN ACCOUNTS a ON a.ACCOUNT_ID = o.ACCOUNT_ID JOIN REGIONS r ON r.REGION_ID = a.REGION_ID
WHERE p.REFERRAL_STATUS = 'Accepted' AND o.STAGE = 'Closed Won'
  AND o.CLOSE_DATE >= DATE_TRUNC('month', DATEADD(month, -1, '2026-11-17'::DATE)) AND o.CLOSE_DATE < DATE_TRUNC('month', '2026-11-17'::DATE)
ORDER BY o.ACV DESC;
-- partner contribution share of closed-won ACV by region
SELECT r.REGION_NAME, SUM(IFF(p.OPPORTUNITY_ID IS NOT NULL, o.ACV, 0)) / SUM(o.ACV) AS partner_share
FROM OPPORTUNITIES o JOIN ACCOUNTS a ON a.ACCOUNT_ID = o.ACCOUNT_ID JOIN REGIONS r ON r.REGION_ID = a.REGION_ID
LEFT JOIN PARTNER_REFERRALS p ON p.OPPORTUNITY_ID = o.OPPORTUNITY_ID AND p.REFERRAL_STATUS = 'Accepted'
WHERE o.STAGE = 'Closed Won' AND NOT a.IS_TEST_ACCOUNT GROUP BY 1;
-- bookings by quarter, Finance definition
SELECT DATE_TRUNC('quarter', CLOSE_DATE) AS q, SUM(NET_NEW_ACV) AS bookings
FROM OPPORTUNITIES WHERE STAGE = 'Closed Won' AND BOOKING_TYPE IN ('New','Expansion') GROUP BY 1 ORDER BY 1;
-- open pipeline by region, test accounts excluded
SELECT r.REGION_NAME, SUM(o.ACV) AS open_pipeline FROM OPPORTUNITIES o JOIN ACCOUNTS a ON a.ACCOUNT_ID = o.ACCOUNT_ID JOIN REGIONS r ON r.REGION_ID = a.REGION_ID
WHERE o.STAGE IN ('Proposal','Negotiation') AND NOT a.IS_TEST_ACCOUNT GROUP BY 1 ORDER BY 2 DESC;
