# Graph-Powered Fraud Ring Detection — Speaker Notes

## Account Context

This demo was built for a financial services organization detecting fraud rings in benefit applications. They process ~3M applications per period and are specifically interested in Leiden community detection for fraud ring identification. They've seen graph analytics demos and loved them ("We have never seen anything like this before"). The customer's current pain point is data ingestion for real-time ML. They are having difficulty installing igraph locally — our SPCS approach sidesteps this entirely.

---

## Slide-by-Slide Notes

### Overview (Hero)

**Talking points:**
- Frame this as "everything runs on Snowflake" — no external infrastructure, no data movement
- The four stats are the headline: 3M scale, 9M edges, sub-100ms scoring, sub-1-min new applicant assignment
- This is a complete pipeline, not a point solution

**Internal context:**
- The customer specifically asked for Leiden (not Louvain). They know the difference. Don't suggest alternatives.
- Expect technical questions about resolution parameters and modularity scores
- They mentioned one pain lies in the data ingestion piece — this pipeline addresses that with Snowpipe Streaming + Dynamic Tables

### The Problem

**Talking points:**
- Lead with the specific pattern: "multiple fraudsters submitting from the same address"
- Emphasize that rules-based systems catch obvious cases but miss sophisticated rings
- Graph analytics finds structural patterns that individual transaction analysis misses

**Internal context:**
- Don't oversell real-time graph — true real-time Leiden recomputation isn't practical. The hybrid approach (heuristic DT + periodic full Leiden) is the honest story
- If asked about igraph: "SPCS gives you GPU-accelerated cuGraph without any local package installation headaches"

### Architecture

**Talking points:**
- Walk through the flow left-to-right
- Emphasize that every component is a Snowflake-native service — no external orchestration
- Dynamic Tables are the backbone for incremental processing

**References:**
- Dynamic Tables: https://docs.snowflake.com/en/user-guide/dynamic-tables-about
- SPCS: https://docs.snowflake.com/en/developer-guide/snowpark-container-services/overview
- Feature Store: https://docs.snowflake.com/en/developer-guide/snowflake-ml/feature-store/overview
- ML Jobs: https://docs.snowflake.com/en/developer-guide/snowflake-ml/jobs
- Model Registry: https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/overview

### Data Scale

**Talking points:**
- 3M per period (not the cumulative 30M) — this matches a typical application volume
- 9M+ edges from 4 shared-attribute types
- 100 planted fraud rings for ground truth validation

**Internal context:**
- Confirmed: "The address table holds 30,058,213 distinct records, but a single period is roughly 3,033,939 applications. If you scale from 30M instead of 3M, baseline entity reuse comes out unrealistically sparse and every planted fraud ring becomes trivially obvious. Use the period."
- If they ask about scaling beyond 3M: cuGraph on GPU_NV_S handles 10M+ edges comfortably. For 100M+ edges, use GPU_NV_M (4x A10G) or GPU_NV_L (8x A100)

### Leiden on GPU

**Talking points:**
- Leiden itself runs in single-digit seconds on GPU — the bottleneck is I/O
- SPCS Job Service pattern: start, process, exit. No idle GPU cost
- Show the actual benchmark numbers from the job logs

**Internal context:**
- We had CUDA compatibility issues with the RAPIDS base image on SPCS. Fixed by using `nvidia/cuda:12.4.1-runtime` base + pip-installed cuGraph wheels. If they ask about RAPIDS on SPCS, be upfront that the full RAPIDS conda image can have driver conflicts — pip wheels are the reliable path
- The benchmark bars in the slide are approximate — actual numbers come from `SYSTEM$GET_SERVICE_LOGS()` after running the job. Update the slide with real numbers before the demo
- If asked "why not run Leiden natively in Snowflake SQL?": recursive graph traversal in SQL is O(n^2) for community detection. cuGraph uses GPU-parallel algorithms that are orders of magnitude faster at this scale

**References:**
- SPCS Job Service: https://docs.snowflake.com/en/developer-guide/snowpark-container-services/working-with-jobs
- cuGraph Leiden: https://docs.rapids.ai/api/cugraph/stable/api_docs/cugraph/community/leiden/

### Incremental Heuristic

**Talking points:**
- "New applicants don't wait 15 minutes for the next Leiden run"
- Dynamic Table refreshes incrementally — matching a new applicant to an existing community is a simple join
- Two confidence tiers: address match (0.8) vs IP match (0.6) vs pending (0.0)
- Full Leiden corrects drift every 15 minutes

**Internal context:**
- This was originally a Stream + Task (1-min minimum latency). Converted to Dynamic Table for sub-minute incremental refresh
- If asked about truly real-time (sub-second) community assignment: the DT refresh is ~1 minute. For sub-second, you'd need Snowpipe Streaming + a trigger, which is more complex. The 1-minute DT is good enough for application processing (applications aren't processed in milliseconds anyway)

**References:**
- Dynamic Tables incremental refresh: https://docs.snowflake.com/en/user-guide/dynamic-tables-refresh
- Streams: https://docs.snowflake.com/en/user-guide/streams-intro

### Feature Store

**Talking points:**
- Two feature views: graph-structural and behavioral
- "Define once, serve everywhere" — same features for training and inference
- Online serving via hybrid tables for sub-second lookups

**Internal context:**
- Feature Store requires `CreationMode.CREATE_IF_NOT_EXIST` on first initialization (creates internal tags). This tripped us up — make sure setup script has it
- Online serving uses hybrid tables under the hood. There's a small sync delay (~30s-1min) between the DT refresh and the online store update

**References:**
- Feature Store: https://docs.snowflake.com/en/developer-guide/snowflake-ml/feature-store/overview
- Online Feature Store: https://docs.snowflake.com/en/developer-guide/snowflake-ml/feature-store/online

### Model Training

**Talking points:**
- ML Jobs run training on Snowflake compute — no data leaves the platform
- Feature Store's `generate_dataset()` ensures point-in-time correctness
- Model automatically registered with metrics and versioning

**Internal context:**
- `log_model()` needs `target_platforms=["WAREHOUSE", "SNOWPARK_CONTAINER_SERVICES"]` to enable both warehouse and SPCS inference. Without it, you get a ValueError when calling `mv.run()` without a service_name
- The training script uses Snowflake ML's server-side XGBClassifier, not open-source xgboost. This runs on the warehouse/compute pool, not locally

**References:**
- ML Jobs: https://docs.snowflake.com/en/developer-guide/snowflake-ml/jobs
- Model Registry: https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/overview

### Real-Time Inference

**Talking points:**
- Model Service on SPCS with REST API endpoint
- Tuned for low latency: warm instances, parallel workers, no batching
- `feature_sources_per_function` means callers send only APPLICANT_ID

**Internal context:**
- `num_workers=4` and `max_batch_rows=1` are key for single-request latency. Without these, the service batches requests and adds latency
- `min_instances=1` keeps the service warm but costs money (continuous CPU allocation). For a demo this is fine. In production, discuss cost tradeoffs
- Service creation takes 5-15 minutes (container image build). Start this before the demo if possible

**References:**
- SPCS Inference: https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/container
- Model Services: https://docs.snowflake.com/en/developer-guide/snowflake-ml/inference/inference-overview

### Net-New Application Flow

**Talking points:**
- This is the "real-time ML" story — walk through both cases live in the notebook
- Case A (suspicious): shares address with ring → heuristic assigns → high fraud score
- Case B (clean): no shared attributes → no community → low score based on behavioral only
- Emphasize the time-to-score: <1 min for community assignment, <5 min for feature refresh, <100ms for scoring

**Internal context:**
- This slide directly answers the question: "what's the link between graph analytics and real-time ML?"
- The notebook has a live demo of this — insert a suspicious applicant and a clean applicant, trigger the heuristic DT refresh, then score both
- If asked about false positives: the heuristic is conservative (only matches on shared address/IP with known community members). New applicants with no matches get scored on behavioral features only, which has lower recall but also lower false positive rate

### Next Steps

**Talking points:**
- Emphasize we can connect to actual customer data quickly
- A/B testing via SPCS Gateways is the path to production deployment
- The whole pipeline is designed to be production-ready, not just a demo

**Internal context:**
- Timeline is aggressive — plan accordingly
- We usually have good funding for ML takeouts
- The A/B testing slide is forward-looking — reference the Snowflake quickstart if they want to see it in action: https://www.snowflake.com/en/developers/guides/build-real-time-fraud-detection-model-with-natural-language-in-snowflake-ml/

**References:**
- SPCS Gateways: https://docs.snowflake.com/en/developer-guide/snowpark-container-services/working-with-gateways
- Gateway Model Monitor: https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/container#a-b-testing
- Snowpipe Streaming: https://docs.snowflake.com/en/user-guide/data-load-snowpipe-streaming-overview
