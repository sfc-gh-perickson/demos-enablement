# Speaker Notes: PII Redaction on Snowflake

## Account Context Summary

This module covers PII redaction approaches on Snowflake, comparing AI_REDACT with AI_COMPLETE-based patterns. Targets SEs, data engineers, and compliance teams evaluating Snowflake for data privacy workloads.

---

## Slide 1: Hero

**Talking Points:**
- Frame the session: "We're going to cover how to build production-grade PII redaction pipelines on Snowflake — from managed functions to custom patterns that scale to millions of documents."
- The deck covers three approaches at increasing sophistication: AI_REDACT (managed), AI_COMPLETE extract+replace (custom), and pre-computed cache (enterprise).
- Set expectations: ~20 minutes, interactive. The lab that follows lets attendees try each approach hands-on.

**Internal Context:**
- This is a common entry point for customers evaluating Snowflake for data privacy workloads. The competitive angle is replacing regex/NER pipelines (spaCy, Presidio, AWS Comprehend) running outside Snowflake — zero data movement is the differentiator.
- Many customers start by asking about AI_REDACT and then discover its limitations mid-POC. This deck preempts that by laying out all options upfront.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/redact-pii

---

## Slide 2: The Problem (PII in Unstructured Text)

**Talking Points:**
- Walk through the pain points: organizations have PII scattered across free-text fields — support tickets, contracts, medical notes, chat logs, internal documents.
- Traditional approaches: regex (brittle, misses context-dependent PII), NER models (require ML infrastructure outside Snowflake), manual review (doesn't scale).
- The core problem is that PII detection requires language understanding — "Jordan" is a name in one context and a country in another. LLMs solve this naturally.
- Data movement is the hidden cost: extracting text to Python services for redaction means data leaves Snowflake's governance perimeter.

**Internal Context:**
- Compliance drivers vary by industry: GDPR (right to erasure), HIPAA (PHI de-identification), CCPA (consumer data protection), PCI-DSS (card numbers).
- The "data doesn't leave Snowflake" angle resonates strongly with regulated industries. No VPC peering, no API keys to external NER services, no data in transit.
- Common customer scenario: they have a data sharing or marketplace use case blocked by PII in free-text columns. Redaction unblocks the business case.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/redact-pii

---

## Slide 3: AI_REDACT (Managed Approach)

**Talking Points:**
- AI_REDACT is the "easy button" — single function call, no prompt engineering, no UDFs. `SELECT AI_REDACT(text_column) FROM my_table;`
- It handles 12 US-focused PII categories: names, emails, phone numbers, SSNs, addresses, dates of birth, credit card numbers, etc.
- Labels are generic (`[REDACTED]` or category-based like `[PERSON]`, `[EMAIL]`). You don't control the label format.
- Best for: quick compliance wins, internal dashboards, ad-hoc analysis where you need PII stripped without custom logic.

**Internal Context:**
- AI_REDACT is GA but has meaningful limitations: English-focused, 4096 token input cap, 12 US PII categories only. It's the "good enough for 80% of cases" path.
- The token cap is the most common surprise. Documents longer than ~3000 words need to be chunked before calling AI_REDACT — and it won't tell you it truncated, it just processes what fits.
- No custom categories. If the customer needs to redact product serial numbers, internal project codes, or domain-specific identifiers, AI_REDACT won't help.
- Under the hood it's a managed LLM call — you're paying inference credits. It's not cheaper than AI_COMPLETE, just simpler.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/redact-pii

---

## Slide 4: AI_COMPLETE Extract+Replace (Custom Approach)

**Talking Points:**
- This is the power-user path: use AI_COMPLETE to extract PII entities as structured JSON, then a Python UDF does the string replacement.
- Advantages over AI_REDACT: any model (mistral-large2, claude-sonnet, gpt-5), any language, custom categories, no token limit issues, typed labels (e.g., `[SSN_1]`, `[EMAIL_2]`).
- The prompt asks the model to return a JSON array of `{text, type, label}` — it does NOT ask the model to rewrite the full document. This is the key design decision.
- The UDF sorts replacements by length (longest first) to avoid partial match collisions and applies them in a single pass.

**Internal Context:**
- The structured output approach (`response_format` parameter) gives you guaranteed valid JSON with OpenAI models. For other models, wrap with TRY_PARSE_JSON and handle failures gracefully.
- Model recommendation: mistral-large2 or claude-sonnet for speed/cost balance, gpt-5 for quality/reliability on edge cases (e.g., disambiguating "Jordan" as name vs. country).
- This pattern is reusable beyond PII — same architecture works for extracting any entities: product mentions, legal citations, financial instruments, medical terms.
- Common question: "Why not just use AI_REDACT for everything?" Answer: token limit (4096), English-only, fixed 12 categories, generic labels, no model choice.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_complete
- https://docs.snowflake.com/en/developer-guide/udf/python/udf-python-creating

---

## Slide 5: The Key Insight (Output Tokens Are the Bottleneck)

**Talking Points:**
- This is the most important technical concept in the deck. LLM inference has two phases: prefill (input tokens, parallel) and decode (output tokens, sequential — one at a time).
- If you ask an LLM to "redact this text and return the full document," it must generate every token of the output sequentially. A 1000-character chunk becomes ~500 output tokens generated one at a time.
- If instead you ask "what PII did you find?" the output is a small JSON array — maybe 50 tokens. 10x less output = roughly 10x less latency.
- For chunks with no PII (typically 50-80% of real document content), the model returns `{"entities": []}` — essentially 5 tokens. This is where the speedup is massive.

**Internal Context:**
- The speedup is proportional to PII density:
  - 80% clean chunks: ~8x speedup vs. full-text regeneration
  - 50% PII density: ~1.8x speedup
  - Heavy PII (every chunk has multiple entities): minimal speedup (output is similar size either way)
- For typical enterprise documents (contracts, policies, reports), most content is boilerplate with PII scattered throughout — expect 1.5-3x range in practice.
- Cross-region note: accounts on Azure routing to AWS for inference see ~2x latency on every LLM call. Reducing output tokens directly reduces the impact of this overhead. The cache pattern (slide 7) eliminates it entirely.
- This insight applies broadly — any LLM pipeline that regenerates full text as output is leaving performance on the table.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_complete

---

## Slide 6: The REDACT_PII UDF

**Talking Points:**
- Walk through the UDF code. It takes original text + a JSON array of entities, and returns the redacted string.
- The replacement logic: sort entities by string length descending (prevents partial matches), then do sequential string replacement.
- Labels are typed and numbered: `[PERSON_1]`, `[EMAIL_2]`, etc. This preserves entity relationships in the redacted text — you can tell that `[PERSON_1]` in paragraph 1 is the same person referenced in paragraph 5.
- The UDF is pure Python string manipulation — executes in ~1ms per chunk. All the cost is in the LLM extraction step, not here.

**Internal Context:**
- The UDF runs on the warehouse, not on inference infrastructure. It scales linearly with warehouse size and has no concurrency limits.
- Typed labels are a major differentiator vs. AI_REDACT's generic `[REDACTED]`. Downstream analytics can reason about entity types and relationships in redacted text.
- Common enhancement: add a reverse-lookup table (entity → label mapping) stored separately with access controls. This enables authorized users to "un-redact" when needed for investigations.
- The UDF is deterministic given the same inputs — this matters for the cache pattern (slide 7) where you need consistent output.

**References:**
- https://docs.snowflake.com/en/developer-guide/udf/python/udf-python-creating

---

## Slide 7: Pre-Computed Cache (Zero LLM at Query Time)

**Talking Points:**
- This is the enterprise-grade answer for latency-sensitive workflows. Move PII extraction to ingestion time; query time is just a JOIN + UDF.
- The cache table stores extracted entities keyed by (document_id, chunk_id) with an MD5 hash of the source text for staleness detection.
- At query time: JOIN source text to cache, apply UDF. Measured performance: sub-2 seconds for hundreds of chunks. Zero inference credits at query time.
- The fallback pattern: `CASE WHEN cache.hash = MD5(source.text) THEN udf(source.text, cache.entities) ELSE ai_complete(...) END` — uncached or stale documents fall through to live extraction.

**Internal Context:**
- Most customers with real SLAs (sub-5 second response for redacted views) end up at this pattern. Live extraction is fine for batch/async workloads but not for interactive queries.
- Common question: "Is the cache stale?" Three answers: (1) MD5 hash comparison on content — if source changed, cache is invalidated. (2) Stream-based re-extraction — a Stream on the source table triggers re-extraction when rows change. (3) Periodic sweep — scheduled Task re-processes anything where hash mismatches.
- Cache storage cost is minimal — a JSON array per chunk is typically 200-500 bytes. Even at 100M chunks, that's ~50GB.
- The cache eliminates cross-region latency entirely. No LLM call = no routing to inference infrastructure = no cross-region penalty. This is the key win for Azure accounts.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_complete
- https://docs.snowflake.com/en/developer-guide/udf/python/udf-python-creating

---

## Slide 8: Comparison Table (When to Use Each)

**Talking Points:**
- Walk through the three columns: AI_REDACT, Extract+Replace (live), and Extract+Replace (cached).
- Key decision factors: language support, custom categories, latency requirements, token limits, label granularity.
- AI_REDACT: choose when you need quick results, English text under 4096 tokens, standard US PII categories, and don't need typed labels.
- Extract+Replace (live): choose when you need custom categories, multilingual support, specific models, or typed labels — and batch latency is acceptable.
- Extract+Replace (cached): choose when you have query-time SLAs, high-concurrency access patterns, or need zero-cost reads.

**Internal Context:**
- In practice, many organizations use a hybrid: AI_REDACT for quick internal dashboards, extract+replace cached for production data products and APIs.
- The "languages" row is a strong differentiator. Organizations with global data (EU customer support in 20+ languages, multilingual contracts) can't use AI_REDACT.
- Cost comparison at scale: AI_REDACT and live extract+replace have similar per-call costs (both are LLM calls). The cache amortizes extraction cost over all future reads.
- If someone asks "which should I start with?" — start with AI_REDACT to validate the use case, then graduate to extract+replace when you hit its limitations.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/redact-pii
- https://docs.snowflake.com/en/sql-reference/functions/ai_complete

---

## Slide 9: Cost Analysis

**Talking Points:**
- Walk through the cost model: inference credits per call, calls per document, documents per day, extrapolate to annual cost.
- AI_REDACT and live extract+replace have similar per-call costs (both invoke LLMs). The difference is that extract+replace produces less output → fewer output tokens → lower cost per call.
- The cache pattern flips the economics: one-time extraction cost at ingestion, then zero inference cost for all subsequent reads.
- Example at scale: 10,000 documents/day, 10 chunks each = 100,000 LLM calls/day for live approaches. Cached: 100,000 calls at ingestion once, then zero ongoing.

**Internal Context:**
- Credit consumption for AI_COMPLETE varies by model: gpt-5 is the most expensive per-token, mistral-large2 is ~3-4x cheaper. For bulk extraction (populating cache), mistral-large2 is often sufficient.
- The warehouse cost for the UDF is negligible compared to inference cost — a Medium warehouse processing 100K UDF calls takes seconds.
- For cost-conscious customers: run cache population on a scheduled Task during off-peak hours on a Small warehouse. The LLM calls are the bottleneck, not warehouse size.
- ROI framing: if redaction unblocks a data sharing or marketplace use case, the revenue from that use case typically dwarfs the inference cost by orders of magnitude.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_complete

---

## Slide 10: Production Patterns (Tasks, Streams, Dynamic Tables)

**Talking Points:**
- Three production orchestration options for keeping the cache populated:
  - **Tasks + Streams**: Stream detects new/changed rows in source table, Task fires on schedule (or when Stream has data) to run extraction. Most common pattern.
  - **Dynamic Tables**: Define the cache as a Dynamic Table with AI_COMPLETE in the definition. Auto-refreshes when source changes. Simplest to set up but less control over refresh timing and cost.
  - **External orchestration**: Trigger extraction from your ingestion pipeline (Airflow, dbt, custom) before making documents "searchable."
- The fallback pattern ensures zero downtime: uncached documents get live extraction while the cache catches up.

**Internal Context:**
- Tasks + Streams is the recommended pattern for most customers. You control when extraction runs, can set concurrency limits, and get clear cost attribution per Task run.
- Dynamic Tables are elegant but have a gotcha: if the source table has high churn, the Dynamic Table may continuously refresh and burn inference credits. Set an appropriate target lag (e.g., 1 hour) to batch updates.
- The `SYSTEM$STREAM_HAS_DATA` function as a Task WHEN condition prevents the Task from firing when there's nothing new to process — saves unnecessary warehouse spin-up.
- For organizations with strict SLAs: the ingestion pipeline approach guarantees no document is queryable until its cache is populated. This is the strongest consistency guarantee.

**References:**
- https://docs.snowflake.com/en/sql-reference/functions/ai_complete
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/redact-pii

---

## Slide 11: Decision Framework

**Talking Points:**
- Present this as a flowchart the audience can use after the session:
  1. Is your text English, under 4096 tokens, and standard US PII categories sufficient? → AI_REDACT.
  2. Do you need custom categories, multilingual, or typed labels? → Extract+Replace.
  3. Do you have query-time latency SLAs or high-concurrency access? → Add the cache layer.
- Emphasize that these aren't mutually exclusive — different tables or use cases within the same organization may use different approaches.
- The "start simple, graduate when needed" philosophy: don't over-engineer on day one. AI_REDACT is a valid production choice if it fits your requirements.

**Internal Context:**
- The most common migration path: customer starts with AI_REDACT → hits token limit or language limitation → moves to extract+replace → hits latency requirements → adds cache.
- For POC/evaluation scenarios: start with AI_REDACT to prove the concept in 30 minutes, then show extract+replace as the "what if you need more" path. This avoids overwhelming the customer with complexity upfront.
- Competitive framing: "On Snowflake, you have three levels of sophistication available natively. On other platforms, you'd need to build the extract+replace pattern from scratch with external services."

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/redact-pii
- https://docs.snowflake.com/en/sql-reference/functions/ai_complete

---

## Slide 12: Next Steps

**Talking Points:**
- Four concrete action items:
  1. Try AI_REDACT on a sample table — 5 minutes to first results.
  2. Run the lab notebook to compare approaches side-by-side with real timing data.
  3. Identify your highest-value PII redaction use case — what's blocked today by unredacted PII?
  4. Evaluate requirements: languages, categories, latency, scale. Use the decision framework to pick your approach.
- Offer follow-up resources: the lab environment stays available, documentation links are in these notes, reach out for architecture reviews on specific use cases.

**Internal Context:**
- The lab is designed to be self-contained — attendees can re-run it in their own accounts with their own data after the session.
- Common follow-up asks: "Can you help us estimate cost for our specific volume?" — use the cost model from slide 9 with their actual document counts and chunk sizes.
- If the audience includes compliance/legal stakeholders: emphasize that all processing stays within Snowflake's governance perimeter, audit trail via QUERY_HISTORY, and access controls via RBAC on the redacted views.
- For customers already using external NER services: frame the migration as simplification (fewer moving parts, no data egress, unified governance) rather than "your current approach is wrong."

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/redact-pii
- https://docs.snowflake.com/en/sql-reference/functions/ai_complete
- https://docs.snowflake.com/en/developer-guide/udf/python/udf-python-creating
