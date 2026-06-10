# Speaker Notes: Evaluating Cortex Agents — From Theory to Production

## Presentation Context

This is a customer-facing presentation covering the full evaluation lifecycle for Cortex Agents in Snowflake. It targets a mixed audience of technical leaders, data engineers, data scientists, and AI/ML practitioners who are building or planning to build production-grade agents. The goal is to establish a shared understanding of how to systematically evaluate agent quality, iterate safely using versioning, and maintain quality in production through monitoring and automated gates.

The presentation is structured in two parts: Theory (slides 1-6) covers the "why" and "what" of evaluation; Practice (slides 7-12) covers the "how" within Snowflake's platform.

---

## Slide 1: Hero / Overview

**Talking Points:**
- Frame the session: "We're going to cover how to build trust in your AI agents through systematic evaluation — from the foundational theory of what to measure, through practical implementation in Snowflake."
- The four stats on the hero slide come from Snowflake AI Research's GPA framework benchmarks against the TRAIL/GAIA dataset: 95% error detection, 86% localization, 1.8x improvement over baseline approaches.
- Set expectations: the presentation moves from theory to practice. Part 1 answers "why evaluate and what to measure." Part 2 answers "how to do it in Snowflake."

**Key Insight:**
- Evaluation is not just about checking if the answer is right. It's about understanding the full reasoning chain and building systems that maintain quality over time.

---

## Slide 2: The Trust Problem

**Talking Points:**
- Walk through each card as a pain point the audience has likely encountered or will encounter:
  - "Has your agent ever given a correct-looking answer that you later discovered was based on hallucinated intermediate reasoning?"
  - "How do you know your agent isn't wasting compute on redundant tool calls?"
- The highlight box frames the core challenge: outcome-only evaluation is insufficient for enterprise-grade agents.
- Emphasize that this isn't about catching bad answers — it's about catching agents that arrive at answers through unreliable paths, which will eventually fail unpredictably.

**Key Insight:**
- An agent can produce a correct final answer through incorrect reasoning. This creates a ticking time bomb: the agent appears reliable until the incorrect reasoning path leads to a visible failure. Evaluation must cover the full pipeline.

---

## Slide 3: Agent GPA Framework

**Talking Points:**
- Introduce the framework as developed by Snowflake AI Research and published as an open-source implementation in TruLens.
- Walk through the three columns (Goal, Plan, Action) and explain each alignment:
  - **Goal alignment:** Does the output match what the user needed? (correctness, relevance, groundedness)
  - **Plan alignment:** Did the agent design a good strategy? (plan quality, tool selection)
  - **Action alignment:** Did the agent execute its plan faithfully? (plan adherence, tool calling)
- The cross-cutting metrics (logical consistency, execution efficiency) span the full chain and catch issues that single-phase metrics miss.
- Benchmark results: tested against 570 human-annotated errors in the TRAIL/GAIA dataset. GPA judges detected 95% of errors vs. 55% for baseline LLM judges. GPA localized 86% of errors to the exact trace span vs. 49% for baselines.

**Key Insight:**
- The GPA framework makes agent behavior observable and debuggable. When Plan Adherence is low, you know the agent is deviating from its own plan — that's a specific, actionable signal pointing to orchestration-layer fixes, not a vague "the agent is bad."

**References:**
- https://www.snowflake.com/en/blog/engineering/ai-agent-evaluation-gpa-framework/
- https://arxiv.org/abs/2510.08847
- https://github.com/truera/trulens

---

## Slide 4: Designing Evaluation Datasets

**Talking Points:**
- The dataset is the foundation of your evaluation. A biased or incomplete dataset gives you false confidence.
- Three key principles:
  1. **Represent all intent types** — happy paths, edge cases, high-risk, out-of-scope. Don't just test the easy cases.
  2. **Prioritize high-stakes areas** — measure performance specifically on queries that matter most (financial, compliance, safety). Track intent-level metrics, not just aggregate scores.
  3. **Start from real users** — let actual users try a prototype. Their queries are more representative than anything you'll generate synthetically.
- Ground truth guidance:
  - Be specific enough to validate but not so specific that LLM non-determinism causes false negatives.
  - Anchor to fixed time periods to avoid staleness.
  - Describe what a correct response should AND should NOT contain.
- The SQL example shows the Snowflake dataset format: a VARCHAR column for the input query and a VARIANT column for ground truth.

**Key Insight:**
- If you can only do one thing, get real user queries. A small dataset of 50 real queries beats a large dataset of 500 synthetic ones. The distribution of real usage is the hardest thing to replicate synthetically.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations

---

## Slide 5: Evaluation Rubrics & Metrics

**Talking Points:**
- A rubric is simply a collection of metrics. The key decision is which metrics align with your specific business requirements.
- Built-in metrics cover the basics:
  - **Answer correctness** — requires ground truth. Compares the agent's streamed reply to expected output.
  - **Logical consistency** — reference-free. No ground truth needed. Checks internal coherence across instructions, planning, and tool calls.
- Custom metrics are where domain-specific quality lives. Walk through examples: brand compliance, groundedness, tool selection accuracy.
- The YAML example shows how to define a custom metric with score ranges and an LLM prompt. Template variables like `{{input}}`, `{{output}}`, `{{tool_info}}` let you reference specific parts of the trace in your scoring prompt.
- Important: the full execution trace is always provided to the LLM judge regardless of which template variables you use. Variables just let you emphasize specific fields.

**Key Insight:**
- Custom metrics are what make evaluation actionable for your specific use case. A generic "is this correct?" metric tells you something went wrong. A "did the agent cite the right policy document?" metric tells you exactly what to fix.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations

---

## Slide 6: LLM-as-a-Judge Methodology

**Talking Points:**
- At scale, you can't have humans grade every response. LLM-as-a-Judge (LLMAJ) automates the scoring process using another LLM to evaluate agent traces.
- Two evaluation levels:
  - **Trace-level**: Did the agent produce the right final output?
  - **Step-level**: Did it take the right steps to get there?
  - Both are necessary — you need to verify the answer AND the path.
- The calibration process is critical:
  1. Collect agent traces (question + full trace + response)
  2. Have human SMEs grade them across your rubric
  3. Run LLM judges with initial prompts on the same data
  4. Measure agreement using Cohen's Kappa (inter-rater reliability)
  5. Iterate judge prompts until you reach 80%+ correlation
  - This process effectively validates that your automated judges produce scores you can trust.
- Cost awareness: each evaluation run invokes CORTEX.COMPLETE for every metric on every question. A modest dataset of 50 questions with 3 metrics = 150 judge calls per run. Plan your iteration cadence accordingly.

**Key Insight:**
- An uncalibrated LLM judge is just another opinion. A calibrated judge — one that demonstrably agrees with human experts 80%+ of the time — is a reliable, scalable measurement tool. The investment in calibration pays for itself by giving you confidence in every subsequent metric you measure.

---

## Slide: Monitoring is Not Evaluation

**Talking Points:**
- This slide addresses the three most common reasons teams delay or skip evaluation. Present each as a "myth vs. reality" and use the framing of business risk rather than technical purity.
- **"It costs too much"** — Do the math with the audience: 50 questions x 3 metrics = 150 LLM judge calls. That's pennies. Compare it to the cost of one wrong business decision delivered to thousands of users with no signal that it was wrong. The cost of not evaluating is invisible until it becomes a crisis.
- **"VQRs make evals redundant"** — This is the most nuanced objection. Acknowledge that VQRs and eval datasets overlap on known high-value queries. Then reframe: VQRs are a production guardrail (deterministic answers for known queries). Evaluations measure reasoning quality on the long tail — novel queries, edge cases, multi-tool coordination, and the inputs your VQRs DON'T cover. An agent with 50 perfect VQRs can still hallucinate on query 51. Evals catch that.
- **"Monitoring is sufficient"** — Walk through the two-column comparison. Monitoring tells you the SQL executed successfully and took 2.3 seconds. Evaluation tells you the SQL returned the wrong answer because it used calendar year instead of fiscal year. One is operational health; the other is correctness. You need both.
- Close with the warning box: if you've decided the agent is worth deploying to business users, you've already decided it's important enough to evaluate. The question is never "can we afford to?" — it's "can we afford not to?"

**Key Insight:**
- The most dangerous failure mode is an agent that produces wrong answers with high confidence and no errors. Monitoring will show green across the board — low latency, no SQL failures, high availability. Only evaluation reveals that 20% of answers are incorrect. This is the "silent failure" problem that evaluation solves and monitoring cannot.

---

## Slide 7: Agent Versioning for Safe Iteration

**Talking Points:**
- Transition from theory to practice: "Now we know what to evaluate — let's talk about how to do it safely in Snowflake."
- Evaluation without version control is like testing without source control. You need stable reference points.
- Three concepts: Live (mutable scratchpad), Named (immutable snapshot), Alias (routing pointer).
- The workflow: develop on Live, commit to create a Named version, run evals against the Named version, promote by assigning an alias.
- Critical warning: always use `ALTER AGENT` to iterate. `CREATE OR REPLACE AGENT` deletes all evaluation history, monitoring traces, and version lineage. This is the most common mistake teams make.

**Key Insight:**
- The alias model means your application code never changes during promotion. Your app always calls the `production` alias. You promote and rollback by moving the pointer — a metadata operation that takes effect immediately.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-versioning

---

## Slide 8: Running Evaluations in Snowflake

**Talking Points:**
- Three paths to run evaluations — all produce identical results:
  - **Snowsight UI**: visual workflow, great for initial exploration and result inspection
  - **SQL**: EXECUTE_AI_EVALUATION function, best for CI/CD and scheduled tasks
  - **Cortex Code**: conversational interface that can generate datasets, run evals, and suggest optimizations
- Walk through the YAML configuration structure:
  - `dataset`: defines or references your evaluation data
  - `evaluation`: points to the agent and dataset
  - `metrics`: lists built-in metrics (as strings) and custom metrics (as objects with name, score_ranges, prompt)
- The SQL example shows how to start and check status of an evaluation run.
- Note: once a dataset is created, remove the `dataset:` block from your YAML for subsequent runs to avoid "dataset already exists" errors.

**Key Insight:**
- Start with the UI to understand what evaluation produces. Move to SQL for automation. The YAML config becomes a versioned artifact in your repo that defines exactly how your agent is evaluated.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations
- https://www.snowflake.com/en/developers/guides/getting-started-with-cortex-agent-evaluations/

---

## Slide 9: Iterating on Your Agent

**Talking Points:**
- The iteration loop: make one change, run evals, check scores, repeat.
- "One change at a time" is critical for isolating cause and effect. If you change the prompt AND swap tools AND update the model in one commit, you can't tell what moved the score.
- LLM selection strategy: start with the most powerful model (Claude Opus, etc.) to find the performance ceiling. Then test cheaper models against that baseline. Pin a specific model to avoid non-determinism from model rotation.
- Evaluation explanations: the LLM judge produces reasoning for each score. Read these. They tell you specifically what went wrong and point directly at fixes.
- Goal setting philosophy: a stable score beats a high score. 100% accuracy usually means your dataset is too easy. Variance (80% -> 65% -> 90%) means the agent lacks consistency — address with more explicit instructions or verified queries.

**Key Insight:**
- The diagnostic signals table on the slide maps specific metric failures to specific fix strategies. Low answer correctness = improve instructions/tools. Low logical consistency = simplify the system prompt. Low groundedness = improve retrieval. This turns evaluation from "we have a problem" into "we know exactly what to fix."

---

## Slide 10: CI/CD Quality Gates

**Talking Points:**
- The CI/CD pipeline flow: PR opened → deploy candidate to staging → run evaluation → check against threshold → allow/block merge.
- Source control everything: agent spec YAML, semantic views, eval config, dataset definitions, custom metric prompts. Git history gives you an audit trail; PRs give you review gates.
- Progressive thresholds: lenient in dev (advisory only, don't block experimentation), stricter in QA (hard gate, e.g., correctness >= 0.70), strictest in production (e.g., >= 0.80, with automatic rollback).
- Tips: pin the LLM for reproducibility; use a dedicated warehouse to avoid contention; version your datasets alongside agent specs; budget for judge costs.
- Scheduled cadence testing is the complement to CI/CD: CI/CD catches regressions from your changes; scheduled testing catches regressions from external factors (model updates, data drift, tool config changes). Both are necessary.

**Key Insight:**
- Set thresholds based on observed baselines, not aspirational targets. Run several evaluations to establish what "normal" looks like before defining quality gates. Thresholds set too aggressively create flaky gates that erode trust in the pipeline.

**References:**
- https://www.snowflake.com/en/developers/guides/best-practices-for-evaluating-cortex-agents/

---

## Slide 11: Production Deployment & Monitoring

**Talking Points:**
- Deployment strategies: alias promotion (single command, zero client changes), shadow testing (run both versions, compare offline), A/B cohort split (app-layer routing), instant rollback (reassign alias).
- What to monitor: usage patterns, latency percentiles, token cost, error rates, tool execution patterns, user feedback, conversation completion rates.
- All observability data lands in `SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS` — append-only, queryable with SQL.
- Production alerts: set up thresholds for eval accuracy drops, latency spikes, reliability degradation, and user satisfaction.
- From evaluations to guardrails: once your LLM judges are calibrated, you can use them in production monitoring (offline scoring of sampled traffic) or even distill them into smaller, faster ML models that act as real-time guardrails.
- The improvement loop: production failures and negative feedback become new entries in your evaluation dataset. This closes the loop and ensures your eval set stays representative of actual usage over time.

**Key Insight:**
- The most powerful feedback loop is: detect production issue → add that query to eval set → improve agent → verify fix with evaluation → deploy improved version → continue monitoring. Each iteration makes the system more robust because real failures drive evaluation coverage.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-monitor
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/ai-observability

---

## Slide 12: Closing / Key Takeaways

**Talking Points:**
- Walk through the lifecycle diagram: Build Dataset → Define Metrics → Run Evals → Iterate Agent → Deploy & Monitor → Feed Back (loop)
- Emphasize that evaluation is continuous, not a one-time gate. The loop never stops.
- Key takeaways to land:
  1. Evaluate the full reasoning chain (GPA: Goal, Plan, Action), not just the final answer
  2. Start with real user queries — synthetic is a fallback
  3. Calibrate your LLM judges to match human expert judgment (80%+ Kappa)
  4. One change at a time, evaluate after each
  5. Combine CI/CD gates (catch your changes) with scheduled testing (catch external drift)
  6. Production failures feed back into your evaluation dataset
- Getting started steps: concrete, sequential actions the audience can take immediately.
- Resources section: point to docs, quickstarts, the GPA blog post, TruLens open source, and versioning docs.

**Key Insight:**
- The #1 thing to take away: evaluation is not just quality assurance — it's the primary mechanism for understanding and improving your agent. Without evaluation, you're guessing. With it, you have measurable, reproducible, comparable progress.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations
- https://www.snowflake.com/en/developers/guides/best-practices-for-evaluating-cortex-agents/
- https://www.snowflake.com/en/blog/engineering/ai-agent-evaluation-gpa-framework/
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-versioning
- https://github.com/truera/trulens
