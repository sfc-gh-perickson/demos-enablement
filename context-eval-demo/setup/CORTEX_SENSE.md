# Step 3 (optional): build the Cortex Sense context

V3 needs a Cortex Sense context named `<DB>.SENSE.REVENUE_DEMO`. V4 uses it too when it exists.
Without the context, `deploy.py` still installs V0, V1, V2 and V4; V4 is installed without the Sense tool.

The context is built offline by Snowflake (minutes to a few hours), so it can't be created by a single
SQL script. The fastest path is Cortex Code.

## Before you start

- Your account has Cortex Sense enabled. Check with:
  `SELECT SYSTEM$CORTEX_AGENT_CORTEX_CONTEXT_BUILDER('{"action":"list-contexts"}');`
  An error saying the feature is unsupported means the account doesn't have it yet. Skip this step.
- `deploy.py` has finished, so the data, semantic view and ontology node exist.
- Wait about 45 minutes after `deploy.py`. The seeded partner-attribution queries need to appear in
  `ACCOUNT_USAGE.QUERY_HISTORY`. This is how Sense learns that analysts join `PARTNER_REFERRALS`, the thing that fixes Q3.

## Build it with Cortex Code

1. In Cortex Code, run `$cortex-sense`. Ask it to set up a context for this demo, and give it
   `setup/cortex_sense_scope.yaml`. Replace `__DB__` with your database and `__WH__` with your warehouse.
   - Context location: `<DB>.SENSE`, name `REVENUE_DEMO`.
   - Description: *Revenue analytics for sales and finance: deals and opportunities, bookings, ARR and
     subscriptions, open pipeline by region and rep, and partner-sourced deals attributed through
     partner referrals.*
2. Confirm the scope box with `build`, and confirm the description.
3. When the skill reports the context as processed, add V3 and refresh V4:

   ```bash
   python3 scripts/deploy.py -c <connection> --database <DB> --steps agent
   ```

   This recreates `REVENUE_ASSISTANT` with all five versions. Version numbers restart, but the aliases stay the same.

## What the scope contains, and why

| Source | What | Why |
|---|---|---|
| catalog_objects | The 7 core CRM tables, not the 31 noise tables | Sense learns the real schema without the lookalikes |
| semantic_views | `REVENUE_GOVERNED_SV` | So Sense knows what the SV already covers |
| query_history | Analyst queries on these tables | Where the "accepted partner referral" join comes from |
| business_ontology | Domain `Revenue Demo` | Keeps Sense consistent with the governed Bookings definition |
