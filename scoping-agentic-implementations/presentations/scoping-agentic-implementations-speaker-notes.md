# Speaker Notes: Scoping Agentic Implementations

## Presentation Context

This is a customer-facing workshop that teaches how to scope agentic AI implementations using a structured discovery process. It targets technical leaders and PMs who are planning or beginning agent projects. The session moves from broad business aspirations through a funnel of increasing specificity, ending with a completed agent spec and seed evaluation dataset.

The presentation is structured in three parts: Discovery (slides 1-4) covers persona and question mapping; Specification (slides 5-7) covers tool selection, the agent spec template, and seed eval generation; Iteration (slides 8-12) covers measurement, observability-driven improvement, and phased delivery.

**Flexible timing:**
- 30-min overview: Slides 1-6 (funnel through spec), skip workshop
- 60-min with workshop: All slides, compressed talking points, full workshop exercise
- Half-day deep dive: All slides with extended discussion, workshop exercise, plus live notebook walkthrough

---

## Slide 1: Hero / Overview

**Talking Points:**
- Frame the session: "We're going to work through a methodology for turning vague AI goals into scoped, measurable agent projects. By the end, you'll have a spec document for your own use case."
- The four stat cards represent the progression: Vision (what you want), Personas (who uses it), Spec (what exactly to build), Iterate (how to improve it).
- Set expectations: this is not a product demo. It's a scoping exercise. The output is a document that tells your team exactly what to build and how to know if it's working.
- Acknowledge the starting point: "talk to your data" is a valid aspiration, but it's not buildable. We need to decompose it into something an engineering team can scope, estimate, and evaluate.

**Key Insight:**
The gap between "we want AI" and "we shipped a useful agent" is almost always a scoping gap, not a technology gap. The primitives exist. What's missing is the discipline of asking: who will use this, what will they ask, and how will we know it's working?

**Common Questions:**
- *Q: What if we don't know what users will ask?*
  A: That's exactly why we do persona mapping and question brainstorming. You don't need production data -- you need PM/analyst intuition formalized into a taxonomy. Production data comes later and refines it.
- *Q: Is this specific to Snowflake agents?*
  A: The scoping methodology is universal. The tool mapping (slides 5-6) and observability iteration (slide 9) are Snowflake-specific. The framework works whether you're building on Cortex Agents, LangGraph, or any other platform.

---

## Slide 2: The Scoping Funnel

**Talking Points:**
- Walk through the funnel top-to-bottom. Each layer narrows scope and increases specificity.
- Layer 1 (Vision): Where most conversations start and stall. "Talk to your data" is a billboard, not a spec.
- Layer 2 (Personas): Forces the question "who specifically?" A VP of Sales and a Regional Sales Manager ask fundamentally different questions at different frequencies.
- Layer 3 (Questions): The most critical layer. Brainstorming actual questions converts vague intent into testable requirements.
- Layer 4 (Tools): Only now do we talk technology. Each question category maps to a specific primitive.
- Layer 5 (Spec): The complete contract -- boundaries, metrics, eval dataset, Phase 1 scope.

**Anti-pattern callout:**
The warning box addresses the most common failure mode: jumping from Layer 1 to Layer 4. "We want to talk to our data, so let's set up Cortex Agent with Analyst and Search and a Skill." This builds something that looks good in a demo but doesn't match what users actually need. The funnel forces you to earn each layer.

**Key Insight:**
The funnel is sequential for a reason. Each layer constrains the next. If you don't know your personas, you can't build a question taxonomy. If you don't have questions, you can't select tools. If you don't have tools, you can't define success metrics. Skip a layer and the downstream decisions are guesses.

**Common Questions:**
- *Q: How long does this funnel take in practice?*
  A: For a focused team, you can get through Layers 1-4 in a single afternoon with the right people in the room (PM, analyst, 1-2 target users). Layer 5 (spec) takes another day to formalize. Total: 2-3 days from vision to spec.
- *Q: What if leadership just wants a demo first?*
  A: Build a demo AND do the scoping in parallel. The demo shows what's possible; the spec defines what's needed. They serve different audiences. But don't mistake the demo for the product.

---

## Slide 3: Persona Mapping

**Talking Points:**
- Left card: Walk through each attribute. "Data literacy" is the most overlooked -- it determines whether the agent should return raw numbers, formatted tables, or narrative explanations.
- Right card: The example persona card makes it concrete. The Regional Sales Manager's success signal ("I got the answer without filing a ticket") becomes the north star metric for evaluation.
- Emphasize frequency and stakes together. A daily user with low stakes (browsing metrics) needs fast, approximate answers. A monthly user with high stakes (quota decisions) needs verified, precise answers. These require different evaluation rubrics.
- "Current workflow" is gold. If the persona currently asks an analyst and waits 2 days, even a 70% accurate agent that responds instantly is a massive improvement. That context shapes your success threshold.

**Key Insight:**
Success signals differ by persona. A data analyst's success signal is "the SQL is correct." A VP's success signal is "I got the insight I needed for my board meeting." An agent evaluated only on SQL correctness will fail the VP even when every query is technically perfect -- because the VP needed narrative, not numbers.

**Facilitation Guidance:**
- In the workshop, have participants fill in 2-3 persona cards. Push them to be specific about "current workflow" -- this reveals what they're actually replacing.
- If participants struggle to name personas, ask: "Who files the most data requests with your analytics team?" and "Who looks at dashboards most frequently?"

**Common Questions:**
- *Q: What if there's only one persona?*
  A: That's great -- it simplifies your Phase 1. But probe: is it really one persona or one team with multiple roles? A "sales team" might contain managers (aggregation), reps (lookup), and ops (reporting) -- three distinct question patterns.
- *Q: Should we talk to actual users during scoping?*
  A: Ideally yes -- even 15-minute interviews with 3-5 users per persona dramatically improve your question taxonomy. But don't block on it. PM intuition is a valid starting point; user interviews refine it.

---

## Slide 4: Question Taxonomy

**Talking Points:**
- Walk through the table row by row. The "Wrong-Answer Cost" column is what makes this actionable for prioritization:
  - Lookup: medium cost (user can cross-check with a dashboard)
  - Aggregation: high cost (used in decisions, harder to verify)
  - Reasoning: high cost (multi-step, harder to debug)
  - Policy: very high cost (wrong policy advice = compliance risk)
  - Out of scope: reputational (agent doing something it shouldn't)
- The two-column bottom section: "Why This Matters" connects taxonomy to downstream decisions. "How to Build" gives participants concrete techniques.
- The "implicit questions" technique is powerful: every dashboard chart answers a question. "Revenue by Region" answers "What was revenue by region?" These are your easiest seed eval questions because ground truth already exists (the dashboard numbers).

**Key Insight:**
Your question taxonomy IS your evaluation dataset in embryonic form. Each row in the taxonomy generates 3-5 specific eval questions. A taxonomy with 5 categories and 4 questions each gives you a 20-question seed dataset -- enough to start evaluating immediately.

**Facilitation Guidance:**
- In the workshop, give participants 15 minutes to brainstorm. Target 15-20 questions. The most common failure is questions that are too general ("How is the business doing?"). Push for specificity: "What was conversion rate for the enterprise segment in Q2?"
- If a group gets stuck, prompt them with: "What's the first thing your CEO asks about on Monday?" and "What question would you be nervous about the agent getting wrong?"

**Common Questions:**
- *Q: How do we handle questions that span multiple categories?*
  A: Multi-category questions (e.g., "Why did revenue drop?" = aggregation + reasoning) belong in the "Reasoning" row. They're Phase 2/3 targets because they require multi-tool orchestration.
- *Q: What about questions we can't answer today?*
  A: Flag them separately. Some are truly new capabilities (agent can do what no existing process does). These are high-value but high-risk -- evaluate whether the data exists to answer them before committing.

---

## Slide 5: From Questions to Tools

**Talking Points:**
- Walk through the mapping table. The key insight is that question category determines tool selection -- not the other way around.
- Lookup + Aggregation = Semantic View + Cortex Analyst: This is the starting point for most implementations because structured data questions are highest frequency and have clear ground truth.
- Policy/Process = Cortex Search: Document retrieval. Prerequisite is chunked, indexed documents. If documents don't exist in Snowflake yet, that's a prerequisite to address before building the agent.
- Reasoning = Multi-tool Agent: Only needed when questions require combining structured and unstructured data or multi-step reasoning. This is Phase 2/3, not Phase 1.
- Out of Scope = Agent Instructions: Explicit refusal boundaries. Don't underestimate the importance of this -- a well-defined "no" is as important as a correct "yes."

**Anti-pattern callout:**
The warning box addresses over-tooling. Every tool you add creates: (1) evaluation surface area (need test questions for each tool), (2) potential for wrong tool selection, (3) latency from unnecessary tool calls. If 80% of your questions are structured lookups, you don't need Cortex Search in Phase 1.

**Prerequisite audit guidance:**
The highlight box addresses the #1 cause of POC delays: missing prerequisites. Before committing to a tool, verify:
- Semantic View: Do the tables exist with good column descriptions? Are there clear dimension/metric relationships?
- Cortex Search: Are documents in a stage? Are they parseable (PDF, HTML, markdown)?
- Skills: Is there a well-defined API or function the skill needs to wrap?

**Key Insight:**
Tool selection is a constraint satisfaction problem, not a feature selection problem. You're not choosing tools because they're cool -- you're choosing the minimum set that covers your Phase 1 question taxonomy. Every additional tool must justify itself against a specific question category.

**Common Questions:**
- *Q: Should we start with Cortex Agent or build individual tools first?*
  A: Build and validate tools individually first. A Semantic View should pass its own evaluation (VQRs) before being wired into an agent. Cortex Search retrieval quality should be validated independently. Then compose them in an agent. This is "unit test your tools, then integration test the agent."
- *Q: What about custom Python tools (agent skills)?*
  A: Skills are appropriate when you need computation the LLM can't do (API calls, complex calculations, formatting). They're Phase 2+ for most implementations. Start with the declarative tools (Analyst, Search) first.

---

## Slide 6: The Agent Spec Document

**Talking Points:**
- Walk through each field in the spec template. Emphasize that this is a living document, not a one-time artifact -- it gets updated as you move through phases.
- "Owner" is critical. Without a named owner, agent quality degrades because nobody is accountable for eval scores or production monitoring.
- "Out of Scope" is the most important defensive field. It prevents scope creep and gives you a clear "that's Phase N" response to feature requests.
- "Business Success Metric" vs "Technical Success Metrics" -- these serve different audiences. The business metric goes in the executive update ("80% of users self-serve now"). The technical metrics go in the engineering review ("answer_correctness is 0.82, up from 0.75 last sprint").
- "Phase 1 Scope" forces prioritization. You cannot ship everything at once. Which persona + which question categories + which tools = Phase 1?

**Key Insight:**
The spec is the contract between "what business wants" and "what engineering builds." Without it, business says "the agent isn't good enough" with no specifics, and engineering says "it passes our tests" with no business context. The spec bridges that gap by defining measurable criteria both sides agree to.

**Facilitation Guidance:**
- In the workshop, have participants fill in the spec template for their Phase 1 scope. Push them to commit to numbers on success metrics -- even if they're rough estimates. "answer_correctness >= 0.75" is better than "good enough." The number can change; the habit of defining measurable targets cannot.

**Common Questions:**
- *Q: What if stakeholders won't commit to specific metrics?*
  A: Start with relative metrics: "better than the current process." If users currently wait 2 days for an analyst answer, even "answers 60% of questions correctly within 30 seconds" is a massive improvement. Frame the metric as a starting point that you'll refine with data.
- *Q: How does this relate to the evaluation configuration YAML?*
  A: The spec's "Technical Success Metrics" become the threshold values in your eval config. The spec's "Eval Dataset" pointer becomes the dataset reference. The spec generates the eval config, not the other way around.

---

## Slide 7: Seed Eval Generation

**Talking Points:**
- Walk through the flow diagram: Brainstorm -> Categorize -> Draft Ground Truth -> SME Validate -> Ship & Iterate
- Left card (Where Seed Questions Come From): These are all pre-production sources. You don't need users in production to build a seed dataset. PM intuition, analyst ticket backlog, and dashboard implicit questions give you 30-50 seed questions in an afternoon.
- Right card (Target Coverage): The 60/20/10/10 split is a starting point, not a rule. Adjust based on your taxonomy: if you have high-risk policy questions, weight them more heavily.
- The CORTEX.COMPLETE technique for drafting ground truth: run each seed question against your data using a powerful model, then have an SME validate the output. This is faster than writing ground truth from scratch and catches cases where the "obvious" answer is wrong.
- "Speed over perfection" highlight: The biggest enemy of evaluation adoption is perfectionism. A 30-question dataset with rough ground truth that ships this week catches more regressions than a 200-question dataset that takes a month.

**Key Insight:**
Seed evals are a forcing function for clarity. Writing a ground-truth answer forces you to define what "correct" means for each question. This surfaces ambiguities in your data model ("do we mean fiscal quarter or calendar quarter?"), metric definitions ("is revenue gross or net?"), and scope boundaries ("should the agent know about competitors?") far earlier than building the agent would.

**Facilitation Guidance:**
- In the workshop, have participants select 10 questions from their brainstorm list and write one-sentence ground-truth descriptions. Don't aim for SQL-level precision -- aim for "a correct answer would include X and NOT include Y."
- Common failure: ground truth that's too specific (brittle) or too vague (untestable). Good example: "Should report Q2 2024 revenue for West region as approximately $4.2M, from the SALES_REVENUE table, filtered to fiscal Q2."

**Common Questions:**
- *Q: Won't the ground truth go stale?*
  A: Yes, if anchored to specific values that change. Anchor to methodology ("sum of revenue column, filtered by region and quarter") rather than specific numbers. Or refresh quarterly by re-running the ground-truth generation process.
- *Q: How many questions do we really need?*
  A: 30-50 for a meaningful signal. 10 per question category minimum. But even 10 total is better than zero -- you can catch obvious regressions with 10 questions. Grow the dataset over time from production observations.

---

## Slide 8: Measuring What Matters

**Talking Points:**
- Walk through the table row by row. The key is the "How to Measure" column -- every business goal maps to a concrete Snowflake-queryable signal.
- "Users self-serve instead of filing tickets" -- measure both completion (did they get an answer?) and correctness (was it right?). Completion without correctness is dangerous; correctness without completion means the UX needs work.
- "Reduce time to insight" -- latency matters for user experience, but tool_selection_accuracy matters for quality. A fast wrong answer is worse than a slow right answer.
- "Trust the numbers" -- this requires per-category eval scoring, not just aggregate. An agent with 85% aggregate correctness might have 95% on lookups and 50% on aggregations -- the aggregate masks a category-level failure.
- "Predictable cost at scale" -- often overlooked during scoping. An agent that costs $0.02/query at pilot scale (100 queries/day) costs $2,000/day at enterprise scale (100,000 queries/day). Cost metrics in the spec prevent surprises.

**Key Insight:**
The context box makes the crucial connection: the scoping funnel generates the spec, the spec defines success criteria, and the success criteria become eval metrics. The entire chain is traceable. When a stakeholder asks "is the agent working?", you can point to specific metrics tied to specific business goals defined in the spec.

**Common Questions:**
- *Q: What if our business goal is vague ("improve productivity")?*
  A: Decompose it. "Improve productivity" for whom? Doing what? The persona mapping (slide 3) forces this decomposition. A Regional Sales Manager's productivity = fewer tickets filed + faster quota decisions. Now you can measure both.
- *Q: Should we track all these metrics from day one?*
  A: No. Phase 1 tracks the basics: answer_correctness on your primary category + cost/query. Add metrics as you add capabilities. Don't let measurement overhead slow delivery.

---

## Slide 9: Observability-Driven Iteration

**Talking Points:**
- The two-column comparison is the core message: your taxonomy is a hypothesis, production data is reality. They will differ.
- Left card: What you assumed based on persona mapping and brainstorming.
- Right card: What actually happens. Surprise personas ("Finance team discovered it"), unexpected question distributions, and silent failures (questions the agent handles but handles poorly).
- The highlight box walks through the iteration flywheel in 6 steps. Each step is concrete and queryable.
- The SQL example shows how to find "confused" queries -- those with unusually high token usage, which typically indicates the agent is struggling (multiple retries, long reasoning chains, tool call failures).

**Key Insight:**
Observability is not just for debugging -- it's for scoping the next phase. When you see that 15% of questions are hitting refusal or failing silently, those questions become your Phase 2 scope. When you see a surprise persona, their questions become Phase 3 inputs. Observability turns production into a continuous scoping exercise.

**Facilitation Guidance:**
- For customers who haven't deployed yet, show the mock observability data from setup.sql. The pattern is the same -- you're comparing expected vs. actual question distributions.
- Point customers to the companion "Cortex AI Observability" module for the full implementation of unified cost views and surface identification.

**Common Questions:**
- *Q: How long before we have enough observability data to iterate?*
  A: One week of pilot usage (5-10 active users) typically generates enough signal to identify the top 3-5 gaps. You don't need statistical significance for directional signals.
- *Q: How do we get the actual user questions from observability?*
  A: CORTEX_AGENT_USAGE_HISTORY captures the input in the METADATA column. Query it to see exactly what users are asking, how much compute it costs, and which tools were invoked.

---

## Slide 10: Phased Delivery

**Talking Points:**
- Walk through each phase card. Emphasize that phases are eval-gated, not time-gated. You move to Phase 2 when Phase 1 metrics are met, not when 4 weeks have passed.
- Phase 1: The "prove value" phase. Narrowest possible scope that delivers real user value. If this fails, you've invested minimally. If it succeeds, you have eval data that de-risks everything after.
- Phase 2: Expand tools and question coverage. The entry criteria prevent premature expansion -- you don't add Cortex Search until Analyst-only is working well.
- Phase 3: Multi-persona. This is where routing (supervisor agent) and RBAC (row-level security on semantic views) become necessary. The taxonomy from new personas feeds new eval questions.
- Phase 4: Production hardening. Resource budgets, CI/CD gates, scheduled regression testing, SLAs. Only worth doing once you've proven business value in Phases 1-3.

**Key Insight:**
Each phase delivers user value independently. The biggest risk in agent projects is building for months before any user sees it. Phased delivery ensures that if the project gets deprioritized after Phase 1, you still delivered something useful. And each phase generates the observability data and eval baselines that de-risk the next phase.

**Common Questions:**
- *Q: How long is each phase typically?*
  A: Phase 1: 2-4 weeks (depends on data readiness). Phase 2: 3-6 weeks (adding tools requires new eval coverage). Phase 3: 4-8 weeks (RBAC and routing add complexity). Phase 4: ongoing (hardening is continuous). But these are directional -- actual timelines depend on data maturity, team capacity, and how quickly eval scores converge.
- *Q: Can we skip phases?*
  A: You can compress phases if prerequisites are met. If you already have a validated Semantic View and Cortex Search service, you might combine Phases 1 and 2. But don't skip the eval-gating -- each phase's exit criteria exist to prevent "it works in demo" from becoming "it fails in production."
- *Q: What if Phase 1 metrics don't converge?*
  A: This is a signal, not a failure. If answer_correctness on lookups can't reach 0.75, the issue is usually upstream: poor semantic view descriptions, missing verified queries, or ambiguous metric definitions. Fix the data model, not just the agent prompt.

---

## Slide 11: Workshop Exercise

**Talking Points:**
- Frame as: "Everything we've discussed becomes concrete in the next 60 minutes. You'll walk out with a draft spec for your own use case."
- Activity 1 (Persona Mapping): Have participants fill in 2-3 persona cards. The key push: "Pick ONE persona for Phase 1." Forced prioritization is the point.
- Activity 2 (Question Brainstorm): 15-20 questions for the Phase 1 persona. Encourage specificity. If someone writes "revenue questions," push them to write actual questions: "What was total revenue last quarter?" "How does revenue compare to budget?"
- Activity 3 (Tool Selection): Map question categories to Snowflake tools. Critical checkpoint: "Do the prerequisites exist today?" If not, that's a Phase 0 (data preparation) that must happen before the agent work starts.
- Activity 4 (Seed Eval Draft): Select 10 questions and write ground-truth descriptions. This is the hardest activity because it forces precision about what "correct" means.

**Facilitation Guidance:**
- If running with a group, have participants pair up for Activities 2 and 4. Explaining your questions to someone else surfaces ambiguity.
- Time-box strictly. The goal is a rough draft, not a perfect document. Perfection comes through iteration.
- At the end, have 2-3 participants share their Phase 1 scope with the group. This calibrates expectations and often sparks "oh, we should do that too" insights.

**Key Insight:**
The workshop output is deliberately minimal -- 1 persona, 10 eval questions, Phase 1 tool set. This is intentional. A minimal spec that ships in days is worth more than a comprehensive spec that takes weeks. The flywheel (observe, add to eval set, improve, deploy) is where the real work happens.

---

## Slide 12: Key Takeaways

**Talking Points:**
- Walk through the flow diagram: Discover -> Categorize -> Match -> Define -> Seed -> Iterate. Each step feeds the next; the last step feeds back to the first.
- Left card (Core Principles): These are the five rules of thumb. If a customer remembers nothing else, these five principles prevent the most common failures.
- Right card (Companion Modules): Point customers to the deeper dives. This session is the "how to scope" -- the companion modules are the "how to implement" for each downstream capability.
- Close with the next-steps box: the workshop notebook formalizes what they produced in the exercise, setup.sql gives them a running environment, and the seed eval dataset kickstarts the flywheel.

**Key Insight:**
Scoping is not a one-time exercise -- it's the first rotation of a continuous flywheel. The initial spec is a hypothesis. Production data validates or invalidates it. The best agent teams run this funnel quarterly: re-examine personas, refresh the question taxonomy, update eval datasets, and adjust tool selection based on what observability reveals.

**Common Questions:**
- *Q: Where do we go from here?*
  A: Three immediate actions: (1) Formalize your workshop output into the spec template, (2) Set up the seed eval dataset in Snowflake using the notebook, (3) Build your Phase 1 agent against the spec and run evals before any user sees it.
- *Q: How do we get buy-in from leadership for this approach?*
  A: The spec document IS the buy-in tool. It translates "we want AI" into "here's exactly what we're building, for whom, with these measurable success criteria, delivered in these phases." That's a fundable, trackable project -- not a science experiment.

---

## General Facilitation Notes

**Room setup:**
- Whiteboard or shared doc for persona mapping (group brainstorm)
- Individual worksheets or notebook access for Activities 2-4
- Timer visible to the room (strict time-boxing matters)

**Who should be in the room:**
- Product Manager or business stakeholder (persona validation)
- Data analyst or analytics engineer (question validation, data availability)
- Technical lead (tool selection feasibility, prerequisite audit)
- Optional: 1-2 actual target users (question brainstorm quality)

**If the session runs short (30 min):**
- Cover slides 1-6 (funnel through spec template)
- Leave spec template and workshop instructions as homework
- Schedule a 30-min follow-up to review their completed specs

**If the session runs long (half-day):**
- Extend workshop to 90 minutes
- Add live notebook walkthrough (seed eval generation with CORTEX.COMPLETE)
- Add group discussion: "What's your biggest concern about Phase 1?"
- Add Q&A on companion modules (evals, observability, versioning)
