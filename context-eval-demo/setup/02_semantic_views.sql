-- Governed semantic view (V1+): 5-table star, business columns only, certified metrics, verified query for ARR.
-- "Bookings" is deliberately left ambiguous here (TCV vs net-new ACV) — the Business Ontology resolves it in V2.
USE SCHEMA __DB__.CRM;
CREATE OR REPLACE SEMANTIC VIEW REVENUE_GOVERNED_SV
  TABLES (
    opportunities AS __DB__.CRM.OPPORTUNITIES PRIMARY KEY (OPPORTUNITY_ID)
      COMMENT = 'One row per sales opportunity (deal).',
    accounts AS __DB__.CRM.ACCOUNTS PRIMARY KEY (ACCOUNT_ID)
      COMMENT = 'Customer accounts.',
    regions AS __DB__.CRM.REGIONS PRIMARY KEY (REGION_ID)
      COMMENT = 'Sales regions: North America, EMEA, APAC, LATAM.',
    reps AS __DB__.CRM.REPS PRIMARY KEY (REP_ID)
      COMMENT = 'Sales reps.',
    subscriptions AS __DB__.CRM.SUBSCRIPTIONS PRIMARY KEY (SUBSCRIPTION_ID)
      COMMENT = 'Recurring revenue lines per account. PRODUCT_TYPE separates Subscription from one-time Services.'
  )
  RELATIONSHIPS (
    opp_account AS opportunities (ACCOUNT_ID) REFERENCES accounts,
    opp_rep AS opportunities (REP_ID) REFERENCES reps,
    account_region AS accounts (REGION_ID) REFERENCES regions,
    sub_account AS subscriptions (ACCOUNT_ID) REFERENCES accounts
  )
  FACTS (
    opportunities.acv AS ACV COMMENT = 'Annual contract value of the deal.',
    opportunities.amount_tcv AS AMOUNT_TCV COMMENT = 'Total contract value across all contract years.',
    opportunities.net_new_acv AS NET_NEW_ACV COMMENT = 'ACV that is new to the company (New and Expansion deals); zero for renewals.',
    subscriptions.mrr AS MRR COMMENT = 'Monthly recurring revenue of the line.'
  )
  DIMENSIONS (
    opportunities.stage AS STAGE COMMENT = 'Proposal, Negotiation, Closed Won, Closed Lost. Open pipeline = Proposal or Negotiation.',
    opportunities.booking_type AS BOOKING_TYPE COMMENT = 'New, Expansion, or Renewal.',
    opportunities.close_date AS CLOSE_DATE COMMENT = 'Date the deal closed or is expected to close. Calendar quarters.',
    opportunities.lead_source AS LEAD_SOURCE COMMENT = 'Lead source captured on the opportunity.',
    accounts.account_name AS ACCOUNT_NAME,
    accounts.segment AS SEGMENT COMMENT = 'Enterprise, Mid-Market, SMB.',
    accounts.is_test_account AS IS_TEST_ACCOUNT COMMENT = 'TRUE for internal sandbox accounts.',
    regions.region_name AS REGION_NAME WITH SYNONYMS = ('region', 'geo'),
    reps.rep_name AS REP_NAME,
    subscriptions.product_type AS PRODUCT_TYPE,
    subscriptions.subscription_status AS STATUS COMMENT = 'Active or Churned as of today.'
  )
  METRICS (
    opportunities.tcv_bookings AS SUM(CASE WHEN opportunities.stage = 'Closed Won' THEN opportunities.amount_tcv END)
      COMMENT = 'Closed Won total contract value (Sales team view of bookings).',
    opportunities.net_new_acv_booked AS SUM(CASE WHEN opportunities.stage = 'Closed Won' AND opportunities.booking_type IN ('New', 'Expansion') THEN opportunities.net_new_acv END)
      COMMENT = 'Closed Won net-new ACV from New and Expansion deals.',
    opportunities.open_pipeline AS SUM(CASE WHEN opportunities.stage IN ('Proposal', 'Negotiation') THEN opportunities.acv END)
      COMMENT = 'ACV of open opportunities.',
    opportunities.deals_won AS COUNT(CASE WHEN opportunities.stage = 'Closed Won' THEN opportunities.opportunity_id END),
    subscriptions.arr AS SUM(CASE WHEN subscriptions.product_type = 'Subscription' AND subscriptions.subscription_status = 'Active' THEN subscriptions.mrr * 12 END)
      WITH SYNONYMS = ('annual recurring revenue')
      COMMENT = 'Certified ARR: 12 x MRR of active Subscription lines. Excludes Services and churned lines.'
  )
  COMMENT = 'Governed revenue model: opportunities, accounts, regions, reps and subscription ARR.'
  AI_VERIFIED_QUERIES (
    current_arr AS (
      QUESTION 'What is our ARR?'
      VERIFIED_AT 1795392000
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = finance_data)'
      SQL 'SELECT SUM(s.mrr * 12) AS arr FROM subscriptions AS s WHERE s.product_type = ''Subscription'' AND s.subscription_status = ''Active'''
    )
  );

-- Anti-pattern (V0): every CRM table and column, auto-generated, no curation.
CREATE OR REPLACE SEMANTIC VIEW __DB__.CRM.ALL_CRM_TABLES_SV
  TABLES (
    accounts AS __DB__.CRM.ACCOUNTS PRIMARY KEY (ACCOUNT_ID),
    accounts_dedup_tmp AS __DB__.CRM.ACCOUNTS_DEDUP_TMP,
    activities AS __DB__.CRM.ACTIVITIES,
    arr_snapshot_draft AS __DB__.CRM.ARR_SNAPSHOT_DRAFT,
    bookings_sales_report AS __DB__.CRM.BOOKINGS_SALES_REPORT,
    campaigns AS __DB__.CRM.CAMPAIGNS,
    campaign_members AS __DB__.CRM.CAMPAIGN_MEMBERS,
    cases AS __DB__.CRM.CASES,
    case_comments AS __DB__.CRM.CASE_COMMENTS,
    contracts AS __DB__.CRM.CONTRACTS,
    contract_amendments AS __DB__.CRM.CONTRACT_AMENDMENTS,
    discount_approvals AS __DB__.CRM.DISCOUNT_APPROVALS,
    email_events AS __DB__.CRM.EMAIL_EVENTS,
    forecast_snapshots AS __DB__.CRM.FORECAST_SNAPSHOTS,
    fx_rates AS __DB__.CRM.FX_RATES,
    invoices AS __DB__.CRM.INVOICES,
    leads AS __DB__.CRM.LEADS,
    lead_scores AS __DB__.CRM.LEAD_SCORES,
    marketing_touches AS __DB__.CRM.MARKETING_TOUCHES,
    nps_responses AS __DB__.CRM.NPS_RESPONSES,
    opportunities AS __DB__.CRM.OPPORTUNITIES PRIMARY KEY (OPPORTUNITY_ID),
    opportunities_stg_2025 AS __DB__.CRM.OPPORTUNITIES_STG_2025,
    partner_directory AS __DB__.CRM.PARTNER_DIRECTORY,
    partner_referrals AS __DB__.CRM.PARTNER_REFERRALS,
    price_books AS __DB__.CRM.PRICE_BOOKS,
    products AS __DB__.CRM.PRODUCTS,
    quota_targets AS __DB__.CRM.QUOTA_TARGETS,
    quotes AS __DB__.CRM.QUOTES,
    quote_lines AS __DB__.CRM.QUOTE_LINES,
    regions AS __DB__.CRM.REGIONS PRIMARY KEY (REGION_ID),
    renewal_forecast AS __DB__.CRM.RENEWAL_FORECAST,
    reps AS __DB__.CRM.REPS PRIMARY KEY (REP_ID),
    subscriptions AS __DB__.CRM.SUBSCRIPTIONS PRIMARY KEY (SUBSCRIPTION_ID),
    tasks AS __DB__.CRM.TASKS,
    territories_legacy AS __DB__.CRM.TERRITORIES_LEGACY,
    usage_events AS __DB__.CRM.USAGE_EVENTS,
    users AS __DB__.CRM.USERS,
    web_sessions AS __DB__.CRM.WEB_SESSIONS
  )
  RELATIONSHIPS (
    r_opp_acct AS opportunities (ACCOUNT_ID) REFERENCES accounts,
    r_opp_rep AS opportunities (REP_ID) REFERENCES reps,
    r_acct_region AS accounts (REGION_ID) REFERENCES regions,
    r_sub_acct AS subscriptions (ACCOUNT_ID) REFERENCES accounts
  )
  FACTS (
    arr_snapshot_draft.arr_snapshot_draft_arr AS ARR,
    bookings_sales_report.bookings_sales_report_bookings AS BOOKINGS,
    campaigns.campaigns_budget AS BUDGET,
    contracts.contracts_contract_value AS CONTRACT_VALUE,
    contract_amendments.contract_amendments_value_change AS VALUE_CHANGE,
    discount_approvals.discount_approvals_discount_pct AS DISCOUNT_PCT,
    forecast_snapshots.forecast_snapshots_commit_amount AS COMMIT_AMOUNT,
    forecast_snapshots.forecast_snapshots_best_case_amount AS BEST_CASE_AMOUNT,
    fx_rates.fx_rates_usd_rate AS USD_RATE,
    invoices.invoices_amount AS AMOUNT,
    leads.leads_lead_score AS LEAD_SCORE,
    lead_scores.lead_scores_fit_score AS FIT_SCORE,
    lead_scores.lead_scores_intent_score AS INTENT_SCORE,
    nps_responses.nps_responses_score AS SCORE,
    opportunities.opportunities_acv AS ACV,
    opportunities.opportunities_amount_tcv AS AMOUNT_TCV,
    opportunities.opportunities_net_new_acv AS NET_NEW_ACV,
    opportunities.opportunities_term_years AS TERM_YEARS,
    opportunities_stg_2025.opportunities_stg_2025_amount AS AMOUNT,
    price_books.price_books_list_price AS LIST_PRICE,
    quota_targets.quota_targets_quota AS QUOTA,
    quotes.quotes_quote_total AS QUOTE_TOTAL,
    quote_lines.quote_lines_quantity AS QUANTITY,
    renewal_forecast.renewal_forecast_renewal_amount AS RENEWAL_AMOUNT,
    renewal_forecast.renewal_forecast_likelihood_pct AS LIKELIHOOD_PCT,
    subscriptions.subscriptions_mrr AS MRR,
    usage_events.usage_events_event_count AS EVENT_COUNT,
    web_sessions.web_sessions_pages_viewed AS PAGES_VIEWED
  )
  DIMENSIONS (
    accounts.accounts_account_id AS ACCOUNT_ID,
    accounts.accounts_account_name AS ACCOUNT_NAME,
    accounts.accounts_region_id AS REGION_ID,
    accounts.accounts_segment AS SEGMENT,
    accounts.accounts_is_test_account AS IS_TEST_ACCOUNT,
    accounts_dedup_tmp.accounts_dedup_tmp_account_id AS ACCOUNT_ID,
    accounts_dedup_tmp.accounts_dedup_tmp_account_name AS ACCOUNT_NAME,
    accounts_dedup_tmp.accounts_dedup_tmp_region_id AS REGION_ID,
    accounts_dedup_tmp.accounts_dedup_tmp_segment AS SEGMENT,
    accounts_dedup_tmp.accounts_dedup_tmp_is_test_account AS IS_TEST_ACCOUNT,
    activities.activities_activity_id AS ACTIVITY_ID,
    activities.activities_opportunity_id AS OPPORTUNITY_ID,
    activities.activities_rep_id AS REP_ID,
    activities.activities_activity_type AS ACTIVITY_TYPE,
    arr_snapshot_draft.arr_snapshot_draft_account_id AS ACCOUNT_ID,
    arr_snapshot_draft.arr_snapshot_draft_snapshot_date AS SNAPSHOT_DATE,
    bookings_sales_report.bookings_sales_report_region_id AS REGION_ID,
    bookings_sales_report.bookings_sales_report_quarter_start AS QUARTER_START,
    campaigns.campaigns_campaign_id AS CAMPAIGN_ID,
    campaigns.campaigns_campaign_name AS CAMPAIGN_NAME,
    campaign_members.campaign_members_campaign_id AS CAMPAIGN_ID,
    campaign_members.campaign_members_lead_id AS LEAD_ID,
    campaign_members.campaign_members_status AS STATUS,
    cases.cases_case_id AS CASE_ID,
    cases.cases_account_id AS ACCOUNT_ID,
    cases.cases_priority AS PRIORITY,
    case_comments.case_comments_comment_id AS COMMENT_ID,
    case_comments.case_comments_case_id AS CASE_ID,
    case_comments.case_comments_body AS BODY,
    contracts.contracts_contract_id AS CONTRACT_ID,
    contracts.contracts_account_id AS ACCOUNT_ID,
    contracts.contracts_signed_date AS SIGNED_DATE,
    contract_amendments.contract_amendments_contract_id AS CONTRACT_ID,
    discount_approvals.discount_approvals_quote_id AS QUOTE_ID,
    email_events.email_events_event_id AS EVENT_ID,
    email_events.email_events_lead_id AS LEAD_ID,
    email_events.email_events_event_type AS EVENT_TYPE,
    forecast_snapshots.forecast_snapshots_snapshot_week AS SNAPSHOT_WEEK,
    forecast_snapshots.forecast_snapshots_region_id AS REGION_ID,
    fx_rates.fx_rates_rate_date AS RATE_DATE,
    fx_rates.fx_rates_currency AS CURRENCY,
    invoices.invoices_invoice_id AS INVOICE_ID,
    invoices.invoices_account_id AS ACCOUNT_ID,
    invoices.invoices_invoice_date AS INVOICE_DATE,
    leads.leads_lead_id AS LEAD_ID,
    leads.leads_created_date AS CREATED_DATE,
    leads.leads_source AS SOURCE,
    lead_scores.lead_scores_lead_id AS LEAD_ID,
    marketing_touches.marketing_touches_touch_id AS TOUCH_ID,
    marketing_touches.marketing_touches_lead_id AS LEAD_ID,
    marketing_touches.marketing_touches_channel AS CHANNEL,
    marketing_touches.marketing_touches_touch_date AS TOUCH_DATE,
    nps_responses.nps_responses_response_id AS RESPONSE_ID,
    nps_responses.nps_responses_account_id AS ACCOUNT_ID,
    opportunities.opportunities_opportunity_id AS OPPORTUNITY_ID,
    opportunities.opportunities_account_id AS ACCOUNT_ID,
    opportunities.opportunities_rep_id AS REP_ID,
    opportunities.opportunities_booking_type AS BOOKING_TYPE,
    opportunities.opportunities_stage AS STAGE,
    opportunities.opportunities_created_date AS CREATED_DATE,
    opportunities.opportunities_close_date AS CLOSE_DATE,
    opportunities.opportunities_lead_source AS LEAD_SOURCE,
    opportunities_stg_2025.opportunities_stg_2025_opportunity_id AS OPPORTUNITY_ID,
    opportunities_stg_2025.opportunities_stg_2025_account_id AS ACCOUNT_ID,
    opportunities_stg_2025.opportunities_stg_2025_stage AS STAGE,
    opportunities_stg_2025.opportunities_stg_2025_close_date AS CLOSE_DATE,
    opportunities_stg_2025.opportunities_stg_2025_lead_source AS LEAD_SOURCE,
    partner_directory.partner_directory_partner_id AS PARTNER_ID,
    partner_directory.partner_directory_partner_name AS PARTNER_NAME,
    partner_directory.partner_directory_tier AS TIER,
    partner_referrals.partner_referrals_referral_id AS REFERRAL_ID,
    partner_referrals.partner_referrals_opportunity_id AS OPPORTUNITY_ID,
    partner_referrals.partner_referrals_partner_name AS PARTNER_NAME,
    partner_referrals.partner_referrals_referral_date AS REFERRAL_DATE,
    partner_referrals.partner_referrals_referral_status AS REFERRAL_STATUS,
    price_books.price_books_product_id AS PRODUCT_ID,
    price_books.price_books_currency AS CURRENCY,
    products.products_product_id AS PRODUCT_ID,
    products.products_product_name AS PRODUCT_NAME,
    products.products_product_type AS PRODUCT_TYPE,
    quota_targets.quota_targets_rep_id AS REP_ID,
    quota_targets.quota_targets_quarter_start AS QUARTER_START,
    quotes.quotes_quote_id AS QUOTE_ID,
    quotes.quotes_opportunity_id AS OPPORTUNITY_ID,
    quote_lines.quote_lines_quote_id AS QUOTE_ID,
    quote_lines.quote_lines_product_id AS PRODUCT_ID,
    regions.regions_region_id AS REGION_ID,
    regions.regions_region_name AS REGION_NAME,
    renewal_forecast.renewal_forecast_account_id AS ACCOUNT_ID,
    reps.reps_rep_id AS REP_ID,
    reps.reps_rep_name AS REP_NAME,
    reps.reps_region_id AS REGION_ID,
    subscriptions.subscriptions_subscription_id AS SUBSCRIPTION_ID,
    subscriptions.subscriptions_account_id AS ACCOUNT_ID,
    subscriptions.subscriptions_product_type AS PRODUCT_TYPE,
    subscriptions.subscriptions_start_date AS START_DATE,
    subscriptions.subscriptions_end_date AS END_DATE,
    subscriptions.subscriptions_status AS STATUS,
    tasks.tasks_task_id AS TASK_ID,
    tasks.tasks_rep_id AS REP_ID,
    tasks.tasks_status AS STATUS,
    territories_legacy.territories_legacy_territory_id AS TERRITORY_ID,
    territories_legacy.territories_legacy_region_id AS REGION_ID,
    territories_legacy.territories_legacy_territory_name AS TERRITORY_NAME,
    usage_events.usage_events_event_id AS EVENT_ID,
    usage_events.usage_events_account_id AS ACCOUNT_ID,
    usage_events.usage_events_event_date AS EVENT_DATE,
    users.users_user_id AS USER_ID,
    users.users_user_name AS USER_NAME,
    users.users_department AS DEPARTMENT,
    web_sessions.web_sessions_session_id AS SESSION_ID,
    web_sessions.web_sessions_lead_id AS LEAD_ID
  )
  METRICS (
    bookings_sales_report.total_bookings AS SUM(bookings_sales_report.bookings_sales_report_bookings),
    arr_snapshot_draft.total_arr AS SUM(arr_snapshot_draft.arr_snapshot_draft_arr),
    opportunities.total_opportunity_amount AS SUM(opportunities.opportunities_amount_tcv),
    opportunities.total_acv AS SUM(opportunities.opportunities_acv),
    subscriptions.total_mrr AS SUM(subscriptions.subscriptions_mrr),
    contracts.total_contract_value AS SUM(contracts.contracts_contract_value),
    forecast_snapshots.total_commit AS SUM(forecast_snapshots.forecast_snapshots_commit_amount)
  )
  COMMENT = 'All CRM tables';
