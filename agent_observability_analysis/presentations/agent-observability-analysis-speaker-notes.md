# Agent Observability & Analysis — Speaker Notes

## Account Context Summary

This presentation is designed for internal enablement and customer-facing workshops focused on the Cortex Agent improvement lifecycle. It bridges the strategic "why" from the Agent Data Flywheel narrative with the hands-on technical architecture demonstrated in the `observability-to-evals.ipynb` notebook. The audience is typically technical stakeholders (data engineers, ML engineers, platform teams) who have deployed or are about to deploy a Cortex Agent and want to understand how to systematically improve it using production data. Use this alongside a live notebook walkthrough for maximum impact.

---

## Slide: Overview (Hero)

**Talking Points:**
- Frame the presentation as answering: "You deployed an agent. Now what?"
- Three cards set up the narrative arc: Problem → Approach → Outcome
- Don't dwell here — this is a framing slide, move quickly to the flywheel

**Internal Context:**
- This deck is intentionally architecture-focused rather than stats-focused. The notebook produces real numbers when run against a live agent; the deck explains the *system* rather than the output of one particular run.

---

## Slide: The Data Flywheel

**Talking Points:**
- The flywheel metaphor: every interaction makes the next one better, but ONLY if the data is converged
- Most agent platforms treat deployment as the finish line — we treat it as the starting line
- Key message: "Fragmented data kills the flywheel." If observability is in CloudWatch, evals are in an MLOps tool, and business data is in Snowflake, closing the loop requires expensive integration work that most teams never complete.

**Internal Context:**
- This is the core differentiation narrative vs. AWS AgentCore, Azure AI Agent Service, and GCP Vertex Agent Builder — they sell a runtime, we sell a data system
- If asked "can't I just send logs to S3 and build this myself?" — yes, but the governance is the hard part. Who has access to user queries? How do you join feedback to traces without a shared key? These are solved problems in our platform.

---

## Slide: Three Data Pillars

**Talking Points:**
- Walk through each pillar and explain why all three are needed together
- Business Data: what the agent reasons over (already in Snowflake)
- Observability Data: how users interact with the agent (captured automatically)
- Evaluation Data: how good the agent actually is (generated from the other two)
- The JOIN capability is the key insight — correlate "user asked X" with "agent used tool Y" with "correctness was Z" in a single SQL query

**Internal Context:**
- Competitors require 3+ services to get this picture. Our governance story is strongest here — single RBAC model means you don't need separate access controls for "who can see user queries" vs "who can see eval results"

---

## Slide: The Demo Agent (CMO Assistant)

**Talking Points:**
- Introduce the CMO Assistant as the concrete example that the notebook is built around
- Two-tool agent: Cortex Analyst for structured data queries + Cortex Search for strategy documents
- The interesting failure modes come from orchestration: when should it use one tool vs. both? When does it give a partial answer because it only consulted one source?
- Show the CREATE AGENT syntax — it's concise and declarative

**Internal Context:**
- This agent is intentionally designed to be complex enough to fail in interesting ways (tool selection, multi-tool coordination, format adherence) while simple enough to explain in 2 minutes
- The semantic view + search service setup is in `setup.sql` — point customers there if they want to replicate the environment

---

## Slide: Notebook Architecture

**Talking Points:**
- The flow diagram shows the 6-step pipeline. Sections 1-4 simulate what happens organically in production. Sections 5-10 are the mining/eval logic you'd actually schedule.
- Emphasize: "In real life, you skip sections 1-4. Those exist because we can't wait weeks for organic traffic in a demo."
- The notebook uses the REST API (not SQL `DATA_AGENT_RUN`) to send queries — this captures request_ids needed for feedback submission
- Multi-turn conversations are sent with `thread_id` and `parent_message_id` to create proper thread structure in observability

**Internal Context:**
- The REST API approach is important: streaming must be disabled (`"stream": false`) to get JSON responses; the `x-snowflake-request-id` response header is what you pass to the feedback API
- Thread creation uses `/api/v2/cortex/threads` endpoint — this is how CoWork creates threads under the hood

---

## Slide: Observability Events Schema

**Talking Points:**
- `GET_AI_OBSERVABILITY_EVENTS` is the single entry point — no separate logging configuration needed
- Two key event types: `AgentV2RequestResponseInfo` for runs, `CORTEX_AGENT_FEEDBACK` for feedback
- Thread structure fields (`first_message_in_thread`, `parent_message_id`) are what enable rephrase detection
- Show the example SQL — this is copy-pasteable

**Internal Context:**
- Common mistake: people look for `CORTEX_AGENT_REQUEST` (doesn't exist) or try to use `session.id` for joins (not populated on run events)
- `READ UNREDACTED AI OBSERVABILITY EVENTS TABLE` privilege is needed for feedback message text. Without it, you get the boolean but not the written comments.
- There's no direct join key between feedback events and run events — the notebook works around this with a mapping table. This is a known friction point.

---

## Slide: Three Mining Techniques

**Talking Points:**
- Walk through each technique as a SQL pattern, not a result
- Explicit feedback: simple WHERE clause on `CORTEX_AGENT_FEEDBACK` events
- Rephrase detection: the most technically interesting — uses thread structure + embeddings + LLM classification
- Intent classification: CORTEX.COMPLETE with a classification prompt applied to all queries
- Priority ordering (High/Medium/Low) determines which questions take precedence in the deduplication step

**Internal Context:**
- The ~80% "no feedback" stat is well-established in production chat systems. This is why implicit signal mining matters — most users never click anything.
- If a customer asks "what if we have very few users?" — even 10-20 real interactions per week can feed the flywheel if you mine all three signal types.

---

## Slide: Rephrase Detection Technical Flow

**Talking Points:**
- This is the most novel technique in the notebook — spend time here
- Step 1 is cheap (embeddings are fast, cosine similarity is a single function call)
- Step 2 is expensive (LLM call per candidate) — but Step 1 filters out 90%+ of pairs so you only call the LLM on the remaining candidates
- The thread structure is the prerequisite: `parent_message_id > 0` identifies follow-up turns within a conversation
- Walk through the "why not similarity alone?" example

**Internal Context:**
- `snowflake-arctic-embed-m-v1.5` is the embedding model — fast, included in Cortex at no extra cost
- The 0.6 threshold is tunable. Lower = more candidates (higher recall, lower precision). Higher = fewer candidates (lower recall, higher precision). 0.6 is a reasonable starting point.
- `mistral-large2` for classification balances quality and cost. Could use more expensive models for higher accuracy.

---

## Slide: Assembling the Evaluation Dataset

**Talking Points:**
- Three sources → one table with priority column
- Ground truth generation is the key step: CORTEX.COMPLETE generates a JSON object with `ground_truth_output` and `expected_tools`
- The prompt incorporates the user's feedback text: "The user said the answer was wrong because X, so generate ground truth that addresses X"
- Human review is expected — this is a draft, not final ground truth
- Deduplication keeps the highest-priority row per unique query

**Internal Context:**
- `EXECUTE_AI_EVALUATION` requires unique INPUT_QUERY values — duplicates will error
- The auto-generated ground truth is "good enough" for a first pass. Plan for 30-60 minutes of SME time to review the top 10-15 questions.
- The JSON structure (`ground_truth_output` + `expected_tools`) is designed to work with both built-in and custom eval metrics

---

## Slide: Running the Evaluation

**Talking Points:**
- Show the YAML config structure — dataset mapping, agent params, and metrics
- Built-in metrics (answer_correctness, logical_consistency) require no configuration
- Custom metrics (tool_selection) use a prompt template with `{{ground_truth}}` and `{{tool_info}}` placeholders
- The per-source analysis (joining eval results back to mining source) validates that the mining approach works
- If negative-feedback queries consistently score lowest, the mining is working correctly

**Internal Context:**
- The eval runs asynchronously — the notebook polls `STATUS` every 10 seconds. Typical runtime is 5-15 minutes for ~40 questions.
- `EXECUTE_AI_EVALUATION` creates a DATASET object that persists — you can re-run the same dataset against different agent versions to track improvement over time

---

## Slide: From Evaluation to Improvement

**Talking Points:**
- This slide closes the loop: eval results → classified issues → concrete improvement actions
- The classification is done with CORTEX.COMPLETE over the feedback messages — one LLM call per feedback event
- Each category maps to a different improvement lever with different time-to-value
- Most fixes are immediate (instruction changes) or days (corpus enrichment) — not weeks
- The key insight: you don't need to fine-tune the model to improve the agent. Most failures are tool/instruction/corpus problems.

**Internal Context:**
- Fine-tuning is conspicuously absent from the "immediate" levers — it's a later-stage optimization once you've exhausted the fast levers
- For customers who ask "what about fine-tuning?" — start with instructions + verified queries, then corpus enrichment, then fine-tuning. The flywheel generates the training data for fine-tuning over time.

---

## Slide: Closing the Loop

**Talking Points:**
- Three actions: observe continuously (automatic), mine periodically (schedule with a Task), evaluate on every change (CI/CD gate)
- The technical prerequisites are minimal — most customers already have them
- End with the key differentiator: "One platform, no integration tax"
- Call to action: "Deploy an agent, turn on observability (it's automatic), accumulate a week of interactions, then run this notebook"

**Internal Context:**
- The Snowflake Task scheduling angle is important for enterprise customers who want this to run unattended
- The full pipeline (mine → generate ground truth → run eval → alert on regressions) can run as a scheduled Task graph. The notebook is the prototype; production is a few stored procedures.

---

## Documentation References

- [AI Observability Events](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agent/observability)
- [Cortex Agent Evaluations](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agent/evaluations)
- [CORTEX.COMPLETE Function](https://docs.snowflake.com/en/sql-reference/functions/complete-snowflake-cortex)
- [EMBED_TEXT_768 Function](https://docs.snowflake.com/en/sql-reference/functions/embed_text_768-snowflake-cortex)
- [VECTOR_COSINE_SIMILARITY](https://docs.snowflake.com/en/sql-reference/functions/vector_cosine_similarity)
- [Cortex Agent REST API](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agent/rest-api)
- [Cortex Agent Feedback API](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agent/feedback)
- [Snowflake Tasks](https://docs.snowflake.com/en/user-guide/tasks-intro)
