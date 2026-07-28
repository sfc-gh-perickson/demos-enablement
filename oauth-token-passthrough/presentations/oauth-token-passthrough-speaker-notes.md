# Speaker Notes: OAuth Token Passthrough — Entra ID to Cortex Agent via AgentCore

## Presentation Context

This is an SE enablement presentation covering how to pass OAuth tokens from Microsoft Entra ID (Azure AD) through AWS AgentCore to a Snowflake Cortex Agent, achieving per-user RBAC without a Snowflake user per person. It targets Snowflake SEs who need to help customers integrate their existing Entra ID infrastructure with Cortex Agents.

The presentation is structured in three sections: Concepts (slides 1-3) covers the auth flow and architecture; Implementation (slides 4-7) covers the External OAuth security integration, token validation, and AgentCore relay; Operations (slides 8-10) covers testing, failure modes, audit, and combining with multi-tenancy.

---

## Slide 1: Hero / Title

**Talking Points:**
- Frame the session: "We're going to cover how to pass a user's existing Entra ID OAuth token all the way through to a Cortex Agent, so Snowflake sees the real user identity — no service account impersonation required."
- Emphasize this is about authentication plumbing, not authorization logic. The multi-tenancy module covers the RBAC side; this module covers how the user's identity gets into Snowflake in the first place.
- The key value prop: customers who already use Entra ID for their workforce identity get per-user audit and RBAC in Snowflake without building a separate user-management layer.

**Key Insight:**
Token passthrough eliminates the "service account bottleneck" where all agent calls appear to come from one identity. Instead, Snowflake creates a session as the actual end user, inheriting their roles and privileges. This is critical for audit, compliance, and least-privilege access.

**Common Questions:**
- *Q: Is External OAuth GA?*
  A: Yes. External OAuth security integrations are GA. The combination with Cortex Agents is also GA.
- *Q: Does this require Snowflake users to exist?*
  A: Yes — each Entra ID user who calls the agent must have a corresponding Snowflake user with a matching login_name (their UPN). This differs from the multi-tenancy approach which uses a single service account.
- *Q: When would I use token passthrough vs. multi-tenancy session attributes?*
  A: Token passthrough is for internal/workforce users who already have Snowflake accounts (e.g., 50-500 employees). Multi-tenancy session attributes are for external users at scale (e.g., 10K+ customers) where creating per-user Snowflake accounts isn't feasible.

---

## Slide 2: The Problem / Why Token Passthrough

**Talking Points:**
- Start with the common pattern today: a Teams bot or internal app calls a Cortex Agent using a service account. Everyone appears as the same user in audit logs.
- Walk through the three problems this creates: (1) no per-user audit trail, (2) no per-user RBAC enforcement, (3) no way to revoke a single user's access without rotating the service account.
- The highlight: "If the token never reaches Snowflake, Snowflake can't enforce per-user security."

**Key Insight:**
The fundamental issue is identity loss. In a typical service-account pattern, the user authenticates to Teams/the app, but by the time the request reaches Snowflake, the original user's identity is gone — replaced by the service account. Token passthrough preserves identity end-to-end.

**Common Questions:**
- *Q: Can't we just log the user's identity in the application layer?*
  A: You can, but Snowflake won't enforce RBAC based on your app logs. If a table has a row access policy that filters by user, the policy evaluates CURRENT_USER() — which is the service account unless you pass the real user's token.
- *Q: What about using session attributes instead?*
  A: Session attributes set via the API are mutable by design (the caller chooses what to send). Token passthrough is cryptographically verified by Snowflake — the identity is attested by Entra ID and cannot be spoofed by the application layer.

---

## Slide 3: Architecture / Auth Flow

**Talking Points:**
- Walk through the end-to-end flow: User → Teams → AgentCore → Cortex Agent API → Snowflake session
- Step 1: User authenticates to Microsoft Teams (or your app) via Entra ID. They get an access token.
- Step 2: Teams/app sends the request to AWS AgentCore (or your orchestration layer). The access token is attached.
- Step 3: AgentCore relays the request to Snowflake's agent:run API, passing the token as a Bearer token in the Authorization header.
- Step 4: Snowflake validates the token against the External OAuth security integration (checks issuer, audience, signature via JWKS).
- Step 5: Snowflake maps the token's UPN claim to a Snowflake user (via login_name match).
- Step 6: The agent executes with that user's session — all their roles, policies, and grants apply.
- Emphasize: no shared secret exchange between AgentCore and Snowflake. The trust chain goes Entra ID → token signature → Snowflake JWKS validation.

**Key Insight:**
The security integration is a "trust declaration" — Snowflake says "I trust tokens from this Entra ID tenant, for this audience, mapped via this claim." Once configured, no application code needs to handle Snowflake credentials. The OAuth token IS the credential.

**Common Questions:**
- *Q: What if AgentCore modifies the token?*
  A: It can't. JWTs are signed by Entra ID's private key. Any modification invalidates the signature. Snowflake verifies the signature using Entra ID's public keys (from the JWKS URL). AgentCore is a passthrough — it relays the token verbatim.
- *Q: Does this work with any IdP or only Entra ID?*
  A: External OAuth supports Azure AD (Entra ID), Okta, Ping Identity, and any custom OAuth 2.0 provider. The EXTERNAL_OAUTH_TYPE parameter determines the validation behavior. This lab uses Azure, but the pattern is the same for other providers.
- *Q: What about token expiration?*
  A: Standard OAuth behavior applies. Entra ID tokens typically expire in 60-90 minutes. Your application/AgentCore needs to handle token refresh. Snowflake rejects expired tokens — the session is per-request, not long-lived.

**References:**
- https://docs.snowflake.com/en/user-guide/oauth-ext-overview
- https://docs.snowflake.com/en/sql-reference/sql/create-security-integration-oauth-external

---

## Slide 4: External OAuth Security Integration — Deep Dive

**Talking Points:**
- This is the most important slide for SEs to internalize. Walk through each parameter of the CREATE SECURITY INTEGRATION statement.
- `EXTERNAL_OAUTH_TYPE = AZURE`: Tells Snowflake the token format is Azure AD / Entra ID.
- `EXTERNAL_OAUTH_ISSUER`: The expected `iss` claim in the token. Must match exactly (including trailing slash for Azure).
- `EXTERNAL_OAUTH_JWS_KEYS_URL`: Where Snowflake fetches the public keys to verify token signatures. Snowflake caches these and refreshes periodically.
- `EXTERNAL_OAUTH_AUDIENCE_LIST`: The expected `aud` claim. This is your app registration's Application ID URI in Entra ID.
- `EXTERNAL_OAUTH_TOKEN_USER_MAPPING_CLAIM = 'upn'`: Which token claim contains the user identity.
- `EXTERNAL_OAUTH_SNOWFLAKE_USER_MAPPING_ATTRIBUTE = 'login_name'`: Which Snowflake user attribute to match against.
- `EXTERNAL_OAUTH_ANY_ROLE_MODE = 'ENABLE'`: Allows the token to use any role granted to the mapped user (vs. requiring the role to be in the token's scope).

**Key Insight:**
The user mapping is where most configuration errors happen. The UPN in the token (e.g., `jsmith@contoso.onmicrosoft.com`) must exactly match the `login_name` of a Snowflake user. Case sensitivity matters. Trailing whitespace matters. Help customers verify this mapping before anything else.

**Common Questions:**
- *Q: What if users have different UPNs than their email?*
  A: You can use a different claim (e.g., `email`, `oid`, or a custom claim). Change TOKEN_USER_MAPPING_CLAIM accordingly. Just ensure the chosen claim has a 1:1 match with Snowflake login_names.
- *Q: Can I use multiple security integrations for different tenants?*
  A: Yes. You can have multiple External OAuth integrations. Snowflake tries each one when validating a token and uses the first one that matches the issuer/audience.
- *Q: What does ANY_ROLE_MODE = 'ENABLE' mean for security?*
  A: It means the user can assume any role they've been granted in Snowflake, without that role needing to be listed in the token's scope. This is the common pattern for workforce identity. If you need tighter control, use 'DISABLE' and manage role scopes in Entra ID.
- *Q: Does Snowflake cache the JWKS keys?*
  A: Yes. Snowflake fetches and caches the public keys. Key rotation in Entra ID is handled automatically — Snowflake will re-fetch when it encounters a token signed with an unknown key ID (kid).

**References:**
- https://docs.snowflake.com/en/sql-reference/sql/create-security-integration-oauth-external

---

## Slide 5: Entra ID App Registration Setup

**Talking Points:**
- Walk through what customers need to configure on the Entra ID side.
- Step 1: Register an application in Entra ID (Azure Portal → App Registrations → New).
- Step 2: Set an Application ID URI (this becomes the audience). Convention: `api://<application-id>`.
- Step 3: Configure token claims — ensure UPN is included (it is by default for v1 tokens).
- Step 4: Optionally add app roles or scopes if using role-restricted mode.
- Emphasize: the app registration does NOT need a client secret for token passthrough. The secret is only needed if the app itself acquires tokens (e.g., for the device code flow in the lab).

**Key Insight:**
Customers often already have an app registration for their Teams bot or internal application. They can reuse it — just add Snowflake as an authorized audience or ensure the existing audience matches what's configured in the security integration.

**Common Questions:**
- *Q: Do we need admin consent?*
  A: Only if the app requires delegated permissions that need admin consent (e.g., reading the full user profile). For basic token passthrough, user consent is usually sufficient. But organizational policy may require admin consent for all apps.
- *Q: v1 vs v2 tokens?*
  A: Entra ID issues v1 and v2 tokens depending on the `accessTokenAcceptedVersion` in the app manifest. v1 tokens include `upn` by default; v2 tokens use `preferred_username`. Ensure your mapping claim matches your token version. Most enterprise apps still use v1.

---

## Slide 6: AgentCore Relay Pattern

**Talking Points:**
- Show the Python code pattern for how AgentCore (or any middleware) relays the token.
- The key principle: don't decode, don't validate, don't modify. Just pass the raw Bearer token through.
- The HTTP request to Snowflake's agent:run endpoint includes `Authorization: Bearer <token>` — that's it.
- If using the Snowflake Python SDK, show how to create a connection with `authenticator='oauth'` and `token=<user_token>`.
- Contrast with the service-account approach: instead of using a fixed keypair or password, you use the user's token for each request.

**Key Insight:**
AgentCore's role is purely transport. It doesn't need to understand the token, validate it, or extract claims. Snowflake handles all validation. This keeps the middleware simple and stateless — it doesn't need access to Entra ID's public keys or any Snowflake credentials.

**Common Questions:**
- *Q: What if AgentCore needs to call other APIs with the same token?*
  A: That's fine — the token can be used against multiple audiences if Entra ID is configured with multiple app registrations. Or you can request multiple tokens (one per audience) during the initial auth flow.
- *Q: Does AgentCore need a Snowflake account?*
  A: No. AgentCore doesn't authenticate to Snowflake at all. It just forwards the user's token. Snowflake creates the session based on the token's identity.
- *Q: What about token size limits?*
  A: Snowflake accepts standard JWT sizes. Entra ID tokens with many group claims can be large (>4KB). If tokens exceed header limits, use the groups claim transformation in Entra ID to emit a groups endpoint URL instead.

---

## Slide 7: User Mapping in Practice

**Talking Points:**
- Show the Snowflake user creation: `CREATE USER ... LOGIN_NAME = 'user@domain.onmicrosoft.com'`
- Explain that the login_name is the bridge between the Entra ID identity and the Snowflake session.
- Discuss bulk user provisioning: SCIM (Entra ID → Snowflake SCIM endpoint) automates user creation and keeps login_names in sync.
- Walk through what happens when a token arrives for an unmapped user: Snowflake returns an auth error (the session cannot be established).

**Key Insight:**
User provisioning is the operational burden of token passthrough. Unlike multi-tenancy (where one service account handles everyone), token passthrough requires a Snowflake user per person. SCIM integration makes this manageable for workforce scenarios, but it's a consideration for the customer's ops team.

**Common Questions:**
- *Q: Can we automate user creation?*
  A: Yes — use SCIM. Entra ID has a native SCIM provisioning connector for Snowflake. It syncs users, groups, and deactivations automatically.
- *Q: What if a user's UPN changes (e.g., name change)?*
  A: You need to update the Snowflake user's login_name to match the new UPN. SCIM handles this automatically. If not using SCIM, build a sync process.
- *Q: Can multiple Entra ID users map to one Snowflake user?*
  A: No — login_name must be unique. Each Entra ID user maps to exactly one Snowflake user. This is intentional for audit trail integrity.

**References:**
- https://docs.snowflake.com/en/user-guide/admin-security-fed-auth-use#label-external-oauth-user-mapping
- https://docs.snowflake.com/en/user-guide/admin-security-fed-auth-configure-scim

---

## Slide 8: Failure Modes and Debugging

**Talking Points:**
- Walk through the three most common failure scenarios and how to diagnose them:
  1. **Wrong audience**: Token's `aud` doesn't match EXTERNAL_OAUTH_AUDIENCE_LIST → "OAuth access token is invalid" error. Fix: check app registration's Application ID URI matches.
  2. **Expired token**: Token's `exp` is in the past → auth failure. Fix: implement token refresh in your app/middleware.
  3. **Unmapped user**: Token's UPN doesn't match any Snowflake user's login_name → "User not found" error. Fix: create the user or fix the login_name.
- Show how to decode a JWT (jwt.io or Python's `jwt.decode(verify=False)`) to inspect claims for debugging.
- Mention SYSTEM$VERIFY_EXTERNAL_OAUTH_TOKEN() for validating tokens without establishing a full session.

**Key Insight:**
95% of External OAuth integration issues come down to three mismatches: issuer URL (trailing slash!), audience URI, or user mapping. Teach customers to always decode the token and compare claims against the security integration's configuration. The error messages from Snowflake are intentionally vague for security — you need to inspect the token to find the mismatch.

**Common Questions:**
- *Q: How do I test without a real application?*
  A: Use MSAL's device code flow (as shown in the lab notebook). It lets you obtain a real Entra ID token from a terminal without building a web app.
- *Q: Can I see failed auth attempts in Snowflake?*
  A: Yes — check LOGIN_HISTORY in ACCOUNT_USAGE. Failed External OAuth attempts appear with error details. Also check SESSIONS and look for EXTERNAL_OAUTH as the authentication method.
- *Q: The token works in jwt.io but Snowflake rejects it?*
  A: Common causes: (1) clock skew (token was just issued and Snowflake's clock disagrees), (2) wrong token version (v1 vs v2 issuer URL), (3) the integration is disabled (ENABLED = FALSE).

---

## Slide 9: Combining with Multi-Tenancy

**Talking Points:**
- This slide bridges to the multi-tenancy module. Show how both patterns can coexist.
- Pattern A: Token passthrough only (workforce users, each with a Snowflake account, RBAC via roles).
- Pattern B: Multi-tenancy only (external users, single service account, RBAC via session attributes + RAPs).
- Pattern C: Both together. Internal users authenticate via token passthrough, and the application ALSO sets session attributes (e.g., for A/B testing, feature flags, or department-level filtering). The token establishes identity; session attributes add context.
- Emphasize: with token passthrough, session attributes are STILL available. You can set them in the API call alongside the Bearer token.

**Key Insight:**
Token passthrough and multi-tenancy are complementary, not competing. Use token passthrough when you CAN create Snowflake users (workforce identity). Use multi-tenancy session attributes when you CANNOT (external users at scale). Use both when you need identity + additional context that isn't modeled in Snowflake roles.

**Common Questions:**
- *Q: If I use token passthrough, do I still need session attributes?*
  A: Not for identity — the token handles that. But session attributes are still useful for passing application context (tenant selection in multi-org apps, feature flags, request metadata for audit).
- *Q: Can I migrate from service-account + session attributes to token passthrough?*
  A: Yes, incrementally. Start by adding the security integration and mapping a few test users. Run both patterns in parallel — service account for most calls, token passthrough for test users. Once validated, migrate fully.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-multi-tenancy

---

## Slide 10: Audit and Compliance

**Talking Points:**
- With token passthrough, every agent call is attributed to a real user in audit logs.
- Show CORTEX_AGENT_USAGE_HISTORY — the USER_NAME column reflects the actual end user (not a service account).
- Show LOGIN_HISTORY — sessions authenticated via EXTERNAL_OAUTH are clearly labeled.
- This satisfies compliance requirements: SOC 2 (individual accountability), HIPAA (minimum necessary access), GDPR (data access logging per natural person).
- Compare audit fidelity: service account approach shows "SVC_AGENT_USER made 10,000 queries"; token passthrough shows "Jane made 3 queries, Bob made 7 queries."

**Key Insight:**
For regulated industries (healthcare, finance, government), per-user attribution isn't optional — it's a compliance requirement. Token passthrough provides this out of the box. No additional logging infrastructure needed. Snowflake's built-in audit captures everything.

**Common Questions:**
- *Q: Can we correlate Snowflake audit with our application logs?*
  A: Yes. The UPN/user identity is the join key. Your application logs the request with the user's email; Snowflake logs the query with the same email (via login_name). Correlate by timestamp + user.
- *Q: What about the agent's intermediate queries?*
  A: All SQL the agent generates runs under the authenticated user's session. Every intermediate query appears in QUERY_HISTORY attributed to that user. Nothing is hidden.
- *Q: Does this work with Access History (column-level tracking)?*
  A: Yes. ACCESS_HISTORY captures which columns each user's session accessed. Combined with token passthrough, you get per-user, per-column audit for agent interactions.

**References:**
- https://docs.snowflake.com/en/sql-reference/account-usage/cortex_agent_usage_history
- https://docs.snowflake.com/en/sql-reference/account-usage/login_history

---

## Slide 11: Best Practices and Recommendations

**Talking Points:**
- Summarize the key recommendations:
  1. Always use SCIM for user provisioning — manual user management doesn't scale.
  2. Set `EXTERNAL_OAUTH_ANY_ROLE_MODE = 'ENABLE'` for simplicity unless you have a specific reason to restrict.
  3. Monitor LOGIN_HISTORY for failed External OAuth attempts — they indicate misconfigurations.
  4. Use short-lived tokens (default Entra ID expiry is fine) and implement refresh in your middleware.
  5. Test with the MSAL device code flow before building the full integration.
  6. Document the audience URI and tenant ID — these are the two values needed for every environment.
- Anti-patterns to avoid:
  - Don't decode the token in your middleware to extract claims — let Snowflake handle it.
  - Don't share one Snowflake user across multiple Entra ID users (defeats the purpose).
  - Don't disable token signature validation (EXTERNAL_OAUTH_RSA_PUBLIC_KEY is not needed when JWKS URL is set).

**Key Insight:**
The simplest deployment is: one Entra ID app registration, one Snowflake security integration, SCIM for user sync, and AgentCore passing tokens verbatim. Avoid adding complexity unless you have a specific security or compliance requirement driving it.

---

## Slide 12: Summary / Call to Action

**Talking Points:**
- Recap the three takeaways:
  1. Token passthrough gives you per-user identity in Snowflake without building custom auth.
  2. The External OAuth security integration is the single configuration point — everything else is standard OAuth flow.
  3. Combine with multi-tenancy session attributes when you need both identity AND contextual filtering.
- Point attendees to the hands-on lab notebook for a guided walkthrough.
- Reference the multi-tenancy module as the complementary pattern for external users.
- Offer to pair with SEs on customer implementations — the configuration is straightforward once the Entra ID app registration is set up.

**Final Q&A Tips:**
- If asked about latency: token validation adds ~50ms to the first request (JWKS fetch is cached after that). Negligible for agent interactions.
- If asked about cost: no additional Snowflake cost. External OAuth is included. The only cost is agent compute (same as service-account approach).
- If asked about alternatives to Entra ID: Okta and Ping Identity follow the same pattern. Change EXTERNAL_OAUTH_TYPE and the issuer/JWKS URLs. The rest is identical.

**References:**
- Lab notebook: `lab/oauth-token-passthrough-lab.ipynb`
- Multi-tenancy module: `../cortex-agent-multi-tenancy/`
- Snowflake docs: https://docs.snowflake.com/en/user-guide/oauth-ext-overview
