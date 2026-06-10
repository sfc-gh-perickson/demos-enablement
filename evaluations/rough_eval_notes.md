## Creating an Evaluation Dataset
* Create a dataset that reflects the distribution of usage that you expect the agent to recieve from users
    - happy paths
    - bad paths
    - high-risk
    - low-risk
* Make sure to represent high-risk paths in the eval dataset, and keep track of the agent's performance across the different intents. We need to measure not only the macro correctness, etc, but also the intent-level to gain confidence that the agent will behave in high-value and high-stakes areas.

## What is a Rubric?
A **rubric** is a collection of **metrics** that we would want to score the AI agent's performance on. This may be things like:
1) Overall correctness: did the agent get a correct answer?
2) Brand compliance: is the agent speaking in the brand's voice, not recommending competitors, etc.?
3) Context relevance: did our RAG system retrieve the correct context in order for the agent to make a good decision?
4) Many, many more that align with specific business needs.

## How to Evaluate
* Most evaluation is done with an LLM as a Judge (LLMAJ), where another LLM recieves the agent's trace and determines if it successfully completed the task at hand. 

* There is both trace-level and step-level evaluations to be performed. E.g. we want to make sure we are getting the correct output, and that we got the correct output through using the correct tools with the correct parameters

* A downside of LLMAJ is that you are trusting the LLM to make the decisions that a human would when grading a response - this is where LLMAJ tuning comes in. This process looks like:
    1) Starting with a dataset containing question, trace, and response triples from the AI agent and a rubric defining the base set of metrics
    2) Asking humans to label the same dataset across the rubric
    3) Starting with basic LLMAJ prompts, ask the LLMAJ that cover the rubric to grade the triples as well
    4) In a dev/test split, calculate the correlation between the human-graded and LLMAJ-graded scores on each data point in the dataset. Use a metric like Cohen's Kappa for this. We are shooting for an 80+% correlation score at both the dataset level as well as within the intents that we identified in creating the dataset
    5) Iterate upon the LLMAJ prompts in order to get the correlation score on the dev and test sets into that 80+% range. This effectively reduces the error bars on your metrics coming from the LLMAJ as it becomes more in-line with human SME judgement.

## Translating Evaluations into Guardrails and Monitoring
Once an LLMAJ is aligned to SME judgement, we can utilize it in a variety of different ways. The most simple way is to utilize it in offline monitoring situations, where we can sample a subset of agent traffic (maybe prioritizing areas where we get thumbs-down feedback from the user, a proportional traffic split, etc.) and keep track of the judge's scores across those outputs. Another thing that can be done to add robustness to the agent is potentially distilling some critical LLMAJs into smaller ML models that can become guardrails for the agent.

## Iterating upon the Agent Using Evaluation Metrics
Evaluations are the #1 way to effectively understand the behavior of your AI agent. This means that they are also critical in understanding how to better improve your agent over time, and making sure that no regressions are introduced. Utilize agent versioning to confidently iterate, test, and promote new agents into production.