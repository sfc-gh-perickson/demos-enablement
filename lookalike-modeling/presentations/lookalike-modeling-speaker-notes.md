# Lookalike Modeling with Cortex Agent Skills — Speaker Notes

## Slide 1: Title

**Key message:** This is a two-sided architecture — an intelligent agent for self-service model creation, paired with a governed monitoring layer for the data science team.

**Talking points:**
- "Today we'll show how Snowflake enables self-service ML at scale — specifically lookalike modeling, one of the most common workloads in marketing analytics."
- "The unique angle: the agent doesn't just run a fixed template. It actually reasons about which features matter for each specific audience."
- "And the DS team doesn't just hope the agent gets it right — they have a full monitoring layer to validate at scale."

---

## Slide 2: The Challenge

**Key message:** Two user personas with conflicting needs. The platform must serve both.

**Talking points:**
- "Account managers want to say 'find me more people like my best customers' and get results in 5 minutes. They don't know Python, they don't know what XGBoost is, and they shouldn't have to."
- "Meanwhile, the DS team is thinking: if 50 people run models this month, how do I know they're good? How do I gut-check that the agent didn't select nonsense features?"
- "This is exactly the dynamic we heard from Quad/Rise — Lindsay's team builds the system, non-technical users consume it, and they need governance at scale."

**Quad context:** Lindsay: "If I have 50 users run models, I need a way to gut-check quickly."

---

## Slide 3: Architecture

**Key message:** The agent creates. The DS team governs. Full lineage connects them.

**Talking points:**
- Walk through the top flow: User asks in CoWork, agent discovers the skill, browses Feature Store, trains, scores, registers.
- Walk through the bottom flow: DS team queries experiments, runs lift analysis, audits feature choices, applies quality gates.
- "Everything is in one platform — the experiment tracker connects what the agent did to what the DS team reviews."

---

## Slide 4: What is Lookalike Modeling

**Key message:** It's binary classification where the target is "looks like my seed audience."

**Talking points:**
- "You start with a seed — say, your 1,000 best Home & Garden buyers. You want to find 10,000 more people just like them."
- "We train a classifier: seed=1, everyone else=0. The model learns what distinguishes the seed. Then we score the full universe and rank by probability."
- "Top decile = your lookalike audience. These are the people most similar to your seed."
- "The key metrics: 3-5x lift in the top decile means your model is 3-5x better than random selection."

**Discovery question:** "How are you currently doing audience expansion? Rules-based? External vendors? Manual analyst work?"

---

## Slide 5: Feature Store

**Key message:** The agent browses governed features, not raw tables. This prevents drift.

**Talking points:**
- "When 750 models all compute 'recency' slightly differently, you get feature drift. One analyst counts from last email, another from last purchase. Feature Store solves this."
- "The agent calls `fs.list_feature_views()` and reads feature descriptions. It understands that PURCHASE_RFM_FV has recency, frequency, monetary. It knows CHANNEL_ENGAGEMENT_FV has email_open_rate."
- "This is the catalog the agent browses. It's not guessing at column names in raw tables."
- "And because training uses `generate_training_set()`, features are point-in-time correct — no future data leaking into training."

**Quad context:** Lindsay mentioned 20,000+ attributes growing to 60,000. Feature Store is how you govern that scale.

---

## Slide 6: Agent Skills

**Key message:** Skills are portable, versionable intelligence packages — not hardcoded orchestration.

**Talking points:**
- "A skill is a SKILL.md file with instructions and Python scripts, stored on a stage or Git repo."
- "The agent doesn't hardcode the workflow. It discovers the skill by matching the description to the user's query."
- "Why not just put this in orchestration instructions? Skills are portable (use across agents), versionable (tag in Git), and scriptable (Python for heavy ML computation)."
- "The code_execution tool runs the Python scripts in a sandboxed environment with access to the session."

**Competitive note:** vs. DataRobot — not governed in Snowflake, no Feature Store integration. vs. SageMaker Canvas — no LLM-driven feature intelligence. vs. custom MLflow — scattered notebooks, no agent interface.

---

## Slide 7: Skill Workflow

**Key message:** Five steps, three intelligent decisions (profile interpretation, feature proposal, quality reporting).

**Talking points:**
- "Steps 1-2: Profile the seed. The script computes how the seed over-indexes vs. the universe across ALL feature views."
- "Step 3: This is where the LLM shines. It reads the profile and reasons: 'This seed is homeowners with high H&G spend. I should prioritize homeowner, category affinity, and mail response.' Then statistics confirm or prune."
- "Steps 4-5: Standard ML pipeline — but powered by Feature Store for governance and Experiment Tracker for auditability."

**Demo tip:** If running live, show notebook cells 33-34 (Run 1: H&G Buyers) to demonstrate profiling and feature selection.

---

## Slide 8: Feature Selection

**Key message:** LLM proposes, statistics dispose. Best of both worlds.

**Talking points:**
- "The LLM reads the seed profile and uses domain reasoning to propose features. It understands 'homeowners aged 35-44 with H&G spend' means HOMEOWNER and PCT_HOME_GARDEN are likely predictive."
- "But we don't trust the LLM blindly. We validate with mutual information (measures how much a feature tells us about the label) and correlation."
- "Features below threshold get dropped. If the LLM proposed something irrelevant, statistics catch it."
- "This is the same pattern Quad described wanting: 'an agent to help us find better splits in data.'"

---

## Slide 9: Demo Trace

**Key message:** Show the actual agent execution flow end-to-end.

**Demo flow:**
1. Show the SKILL.md content (notebook cell 22)
2. Run the H&G Buyers pipeline (cells 33-34)
3. Point out: which features the agent selected, what got pruned, final metrics

**Talking points:**
- "Notice the agent selects different features for different seeds. For H&G Buyers, it picks HOMEOWNER and PCT_HOME_GARDEN. For Digital-First Millennials, it picks EMAIL_OPEN_RATE and WEB_VISITS."
- "This is intelligence, not a template."

---

## Slide 10: Registry + Experiments

**Key message:** Every run is logged, versioned, and comparable. Nothing is lost.

**Talking points:**
- "Model Registry stores the trained model with metrics, version, and comments. You can always go back."
- "Experiment Tracker logs parameters (feature list, hyperparameters), metrics (AUC, lift), and allows side-by-side comparison."
- "The DS team doesn't need to ask 'what features did model X use?' — it's all logged."

**Demo tip:** Show notebook cell 39 (experiment dashboard) to demonstrate the comparison view.

---

## Slide 11: DS Monitoring

**Key message:** Four validation dimensions, each catching different problems.

**Talking points:**
- "Cumulative gains: Does the model actually concentrate seed members in the top deciles?"
- "Lift: How much better than random? Below 2x = probably not worth activating."
- "Feature audit: Does it make intuitive sense? If the H&G model is driven by SOCIAL_ENGAGEMENT_SCORE, something might be wrong."
- "PSI: Has the population shifted since training? If scoring distribution drifts, the model may need retraining."

**Quad context:** This is exactly their "gut-check quickly" workflow. They score into deciles, compare training vs. test with cumulative gains charts, and look at the top features.

---

## Slide 12: Quality Gates

**Key message:** Automated pass/fail prevents bad models from reaching production.

**Talking points:**
- "Five checks, all must pass for APPROVED status."
- "AUC >= 0.65: the model can discriminate at all."
- "Lift >= 2.0: worth using over random."
- "PSI < 0.2: distribution hasn't drifted significantly."
- "Feature count 8-30: guards against trivial models (too few) and overfitting (too many)."
- "Feature coherence: all features have MI > 0.01 — catches cases where the agent hallucinated a feature name."
- "Models that fail get NEEDS_REVIEW and escalate to the DS team. The agent can eventually be extended to auto-check before reporting to the user."

---

## Slide 13: Scale

**Key message:** This architecture handles real production scale.

**Talking points:**
- "Quad runs 750+ monthly models. Our architecture handles this because the Feature Store ensures consistency, experiments are queryable, and quality gates are automated."
- "5-minute target: with a MEDIUM warehouse and 100K universe, training + scoring completes in under 5 minutes. At 260M, you'd scale the warehouse — the architecture stays the same."
- "The key: non-technical users don't create a bottleneck for the DS team. The agent handles the routine work, the DS team handles exceptions."

**Quad context:** Sam: "Our team has really taken a liking to Snowflake and what we've been able to do with it."

---

## Slide 14: Next Steps

**Key message:** The lab is self-contained and runnable. Here's what comes after.

**Talking points:**
- "The hands-on lab takes 45-60 minutes. You'll build the Feature Store, create the skill, invoke the agent, and run the monitoring workflow."
- "After the lab: Streamlit dashboard for visual monitoring, online serving for real-time, and extending the skill with more engineering capabilities."
- "Questions?"

**Lab logistics:**
- Prerequisite: run `setup.sql` first (takes ~2 minutes)
- Notebook runs on MEDIUM warehouse
- Total compute cost: minimal (synthetic data, small universe)

---

## General Delivery Notes

**Audience calibration:**
- For DS-heavy audiences: spend more time on Feature Store internals and experiment tracking details.
- For business-heavy audiences: emphasize the CoWork user experience and the "5-minute model" story.
- For platform teams: focus on governance, RBAC, and the quality gate architecture.

**Known limitation:**
- Agent evaluations don't currently support skills. For now, monitoring relies on experiment tracking + quality gates rather than the native eval framework.

**Follow-up resources:**
- [Cortex Agent Skills docs](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-skills)
- [Feature Store overview](https://docs.snowflake.com/en/developer-guide/snowflake-ml/feature-store/overview)
- [Experiment Tracking](https://docs.snowflake.com/en/developer-guide/snowflake-ml/experiment-tracking)
- [Model Registry](https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/overview)
