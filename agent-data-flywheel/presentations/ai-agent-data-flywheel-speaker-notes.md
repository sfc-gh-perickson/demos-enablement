# AI Agent Data Flywheel — Speaker Notes

## Account Context Summary

This presentation makes the strategic case for why Snowflake is the right platform for AI agents that get better over time. The core argument: the data flywheel (business data + evaluation data + observability data → improvement) only works when all three data types are converged in a single governed platform. This is a CxO/VP-level conversation designed to reframe the agent discussion from "which orchestration runtime should we use?" to "where does the improvement data live?" — a question that inherently favors Snowflake. Use this when customers are evaluating AWS AgentCore, Azure AI Agent Service, or GCP Vertex Agent Builder alongside Snowflake Cortex Agents.

---

## Slide: Overview (Hero)

**Talking points:**
- Open with the thesis: "The question isn't which agent framework is best for day one. The question is which platform makes day 100 dramatically better than day one."
- Frame "flywheel" as borrowed from Amazon's business model concept (Bezos wheel) — applied to AI agent improvement. Audience knows this metaphor.
- The three stats are provocative anchors: 3 data pillars, 1 platform, infinite compounding. They set up the structure of the rest of the deck.

**Candid internal context:**
- This is a positioning deck, not a product demo. If they want a demo, pivot to Cortex Agent creation + CoWork + evaluations as the live flow.
- "Compounding returns" is aspirational — most customers are still on agent #1. The argument is about architecture choice lock-in, not proven compounding at scale.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents

---

## Slide: The Strategic Problem

**Talking points:**
- Frame this as something they're already feeling: "You've probably built an agent prototype. It works okay. Now what? How does it get better?" 
- The four pain points should resonate with anyone past prototype stage.
- "Governance gaps" is the sleeper issue — when you capture user queries and feedback, that's sensitive data. If it's in a logging service with no RBAC, you have a compliance problem.
- "Manual iteration" — this is where you draw the contrast with a flywheel. Manual = linear. Flywheel = exponential.

**Candid internal context:**
- AWS AgentCore launched at re:Invent 2024 with a focus on runtime guardrails and memory. They do NOT have a story for converged improvement data. Their "evaluation" story is SageMaker Clarify (separate service, separate data store).
- Azure AI Agent Service leans on Azure AI Studio for evals, but data still lives in Azure Monitor / App Insights — not in the same warehouse as customer data.
- GCP's story is slightly better because BigQuery can ingest Cloud Logging, but it's still a multi-service assembly, not native convergence.

---

## Slide: The Converged Data Advantage

**Talking points:**
- This is the key structural slide. Pause here. Make sure they internalize the three pillars and WHY convergence matters.
- The "Key Insight" box is the money quote: you can JOIN these datasets. That's impossible if they're in separate services.
- Example: "Show me all queries where the agent scored <0.5 on correctness, where the user gave a thumbs-down, and where Analyst generated a query against the REVENUE table" — that's a 3-way join across all three pillars. Trivial in Snowflake. Impossible in a fragmented stack without a data engineering project.

**Candid internal context:**
- The "JOIN them" argument is technically true but requires the customer to actually build these queries. We don't have a pre-built dashboard that does this automatically (yet). Position it as "the platform makes it possible" rather than "it's turnkey."
- Competitive angle: this is genuinely hard for hyperscalers to replicate because their agent services and their analytics services are fundamentally different teams/products. Convergence isn't on their roadmap — it contradicts their service-per-billing-unit model.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview

---

## Slide: Pillar 1 — Business Data

**Talking points:**
- Don't spend too long here if the audience already has data in Snowflake. This slide validates what they already know.
- Key differentiator: "Always Current" — contrast with the typical RAG pattern where someone exported data to Pinecone/Weaviate three weeks ago and it's already stale.
- Cortex Search indexes are refreshed automatically as underlying data changes. No manual re-embedding.

**Candid internal context:**
- If customer pushes back on "always current," note that Cortex Search refresh cadence depends on the source (streaming tables = near-real-time, batch loads = on next load). It's not truly real-time in all cases.
- Semantic views are the linchpin for Cortex Analyst accuracy. If the customer doesn't invest in a good semantic view, the agent will struggle. Position improvement data as helping them identify WHERE their semantic view is weak.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst/semantic-view
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview
- https://docs.snowflake.com/en/user-guide/dynamic-tables-about

---

## Slide: Pillar 2 — Evaluation Data

**Talking points:**
- Cortex Agent Evaluations is the native eval framework. You define test cases, run them, and results land in Snowflake tables.
- Verified Queries are gold-standard Q&A pairs for Cortex Analyst. They serve as both guardrails (agent uses them at inference) and test fixtures (evals check against them).
- Human feedback: CoWork and custom apps can capture ratings + free-text. This data lands in the same governed environment.

**Candid internal context:**
- Agent evaluations is still maturing. The current eval metrics focus on SQL correctness (for Analyst) and retrieval relevance (for Search). More general "response quality" metrics are coming but not GA.
- Verified Queries are extremely high-value but labor-intensive to create. Position the flywheel as helping prioritize WHICH verified queries to create next (use observability to find the most common failing queries).
- If customer asks "how does this compare to LangSmith/Braintrust/Arize?" — our answer is governance and convergence. Those tools are great at observability in isolation, but the data lives outside your warehouse. You can't join it with business data or use it for fine-tuning without ETL.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst/verified-queries

---

## Slide: Pillar 3 — Observability Data

**Talking points:**
- Threads API gives you full conversation state. Traces show the plan→execute→reflect loop.
- This is not just logs — it's structured data you can query with SQL.
- User behavior signals: what are people ACTUALLY asking? Is it what you designed for? If 40% of queries are about topics your semantic view doesn't cover, that's an immediate improvement target.

**Candid internal context:**
- Thread/trace data access: customers need to query SNOWFLAKE.ACCOUNT_USAGE views or use the monitoring REST API. There's no pre-built "agent analytics dashboard" yet in Snowsight. This is a build-it-yourself situation, which is fine for technical teams but might be a gap for less mature orgs.
- Token cost visibility: you can see per-request token usage. This is important for cost management conversations — fine-tuning a smaller model can reduce per-request costs while maintaining quality.

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-monitor

---

## Slide: The Flywheel in Action

**Talking points:**
- Walk through the cycle: Deploy → Interact → Observe → Evaluate → Analyze → Improve → Validate → Redeploy.
- Emphasize that the ring spins faster over time. Early cycles might take weeks. Mature teams run daily.
- The center of the flywheel is Snowflake — not because it's the orchestrator, but because it's the data gravity. Every step reads from or writes to Snowflake tables.

**Candid internal context:**
- Most customers will start with a very slow flywheel (monthly improvement cycles). That's fine. The argument is that the architecture supports acceleration — not that it happens automatically.
- If customer is sophisticated, mention that you can automate parts of the flywheel: a Snowflake Task that runs evals nightly, surfaces regressions, and generates suggested verified queries. This is aspirational but architecturally sound.

---

## Slide: Improvement Levers

**Talking points:**
- Walk through the table from fastest-to-value to longest-to-value.
- Start with "Refine Instructions" — literally editing the natural-language instructions in the agent spec. Zero code, immediate impact.
- "Add Verified Queries" — use eval + observability data to find the 10 most-asked questions that get wrong answers, then create gold-standard pairs.
- "Fine-Tune Model" — the big gun. Use interaction data (observability) as training pairs. Snowflake's FINETUNE function reads directly from tables.
- The highlight box frames the sequencing: don't try to fine-tune on day 1. Start fast, graduate to heavier levers as data accumulates.

**Candid internal context:**
- Fine-tuning with Snowflake: currently supports Llama and Mistral base models. Does NOT support fine-tuning Claude/GPT directly (those are proprietary). If agent uses Claude for orchestration, the fine-tuning story is about downstream tasks (e.g., fine-tuning a smaller model for a specific skill, not the orchestrator itself).
- Skills are a genuine differentiator. Modular, portable, versioned via Git. No other hyperscaler agent platform has an equivalent concept this clean.
- MCP connectors for extending agent reach to external tools — this is a growing ecosystem and a strong counter to "but AgentCore has Bedrock integrations."

**References:**
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-finetuning
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-skills
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst/verified-queries

---

## Slide: Why Snowflake Wins (Differentiation)

**Talking points:**
- This is the competitive slide. Be direct but professional.
- Lead with the structural argument: "They sell a runtime. We deliver a data system."
- Don't bash individual hyperscalers by name unless the customer brings them up. Keep it category-level: "hyperscaler agent platforms."
- If pressed on specifics:
  - **AWS AgentCore:** Good runtime guardrails, memory management. But improvement data goes to CloudWatch/S3. Fine-tuning via SageMaker is a completely separate workflow with its own IAM, networking, and data prep.
  - **Azure AI Agent Service:** Tight integration with Azure OpenAI for model access. But evaluation lives in Azure AI Studio, observability in App Insights, business data in Synapse/Fabric. Three services, three billing models, three governance surfaces.
  - **GCP Vertex Agent Builder:** Closest to converged (BigQuery + Gemini). But agent observability still goes through Cloud Logging, and fine-tuning through Vertex AI — not from the same tables the agent reads.

**Candid internal context:**
- The honest gap: Snowflake's model selection is narrower than Bedrock or Azure OpenAI for orchestration. We support Claude, GPT, Gemini, Grok — but not every variant/size. If customer has a strong preference for a specific model that we don't support, this is a real trade-off.
- Another honest gap: hyperscaler agent platforms have deeper native integrations with their own infra (Lambda triggers, Event Grid, Pub/Sub). Snowflake's external tool story via MCP + custom tools is solid but requires more explicit setup.
- The governance argument is our strongest card. Unified RBAC is genuinely something no hyperscaler can match because their agent services, analytics services, and ML services all have separate IAM models.

---

## Slide: Strategic Takeaway (Closing)

**Talking points:**
- Three cards, three messages:
  1. Consolidation = Velocity — fewer integration points means faster iteration.
  2. Compound, Don't Iterate — the improvement data itself becomes a moat. If they build the flywheel on Snowflake, their agent quality becomes tied to their Snowflake data gravity.
  3. Start Now — don't wait for the "perfect" agent. Deploy, observe, improve. The data you collect today is the training data for tomorrow.
- Close with the highlight box quote. Let it land.

**Candid internal context:**
- The lock-in argument ("improvement data IS the moat") is powerful for us but also what makes customers nervous. Be careful not to say "lock-in" — say "compounding advantage" or "data gravity."
- If they push back on starting now: the minimum viable flywheel is just turning on agent monitoring. It costs nearly nothing, and the data accumulates passively. The improvement steps come later when they have enough signal.

---

## Q&A Prep: Likely Executive Questions

**"Why can't I just export my Snowflake data to AWS and use AgentCore?"**
→ You can. But then your observability data lives in CloudWatch, your eval data in SageMaker, and your business data is a copy in S3. To close the improvement loop, you're building data pipelines between 4 services. Every pipeline is a governance risk and a latency penalty. The flywheel works because the data is ALREADY converged.

**"What if we want to use a model you don't support?"**
→ Cortex Agents supports models from Anthropic, OpenAI, Google, and xAI. For specialized models, you can fine-tune Llama/Mistral on your data for specific tasks. The orchestration model is one part of the system — the data convergence advantage applies regardless of which model powers the reasoning loop.

**"How mature is this? Are customers actually doing this today?"**
→ Each individual component (Cortex Agents, evaluations, fine-tuning, observability) is GA or in advanced preview. The "flywheel" is the strategic pattern for combining them. Early adopters are running evaluation suites and feeding results back into verified queries and instruction refinement. Full fine-tuning loops from interaction data are emerging.

**"What about LangChain / LangSmith / CrewAI / other OSS agent frameworks?"**
→ Great tools for prototyping. The gap is production governance and the improvement data problem. Where does LangSmith store your traces? In their cloud. Can you join those traces to your Snowflake business data? Not without ETL. Can you use those traces for fine-tuning? You'd need to export them, clean them, format them, and load them somewhere. The flywheel requires convergence.
