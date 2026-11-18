#!/usr/bin/env python3
"""Install the context-eval demo into a Snowflake account.

    python3 scripts/deploy.py -c <connection>                 # everything available in your account
    python3 scripts/deploy.py -c <connection> --steps agent   # rebuild the agent versions only (e.g. after Cortex Sense finishes building)

Steps, in order: data, ontology, agent, app. Pass --steps to run a subset.
Business Ontology and Cortex Sense are optional: when either is missing the agent still gets
V0, V1 and V4, and V4 is built without the missing tool.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sf import AGENT, ALIASES, ROOT, common_args, ctx_from  # noqa: E402

ONTOLOGY_DOMAIN = "Revenue Demo"
ONTOLOGY_TERM = "Bookings"
SPEC_DIRS = {a: a.lower() for a in ALIASES}  # V0_STUFFED -> agent/specs/v0_stuffed/
SENSE_SENTENCE = "If a question needs data the semantic view does not model, call revenue_demo_context first"
ONTOLOGY_SENTENCES = ("Before you query any business metric", "If the business_ontology search does not return")


def step_data(c):
    print("• data, semantic views, eval set")
    for f in ["setup/01_data.sql", "setup/02_semantic_views.sql", "setup/03_eval_set.sql", "setup/05_results_snapshot.sql"]:
        print("   ", f)
        c.run_file(f)
    # Seed query history several times so Cortex Sense sees the partner-attribution join as a habit, not a one-off.
    print("    setup/04_seed_query_history.sql (x6)")
    for _ in range(6):
        c.run_file("setup/04_seed_query_history.sql")
    for s in ["AGENTS", "SENSE", "APP"]:
        c.q(f"CREATE SCHEMA IF NOT EXISTS {c.db}.{s}")
    c.q(f"CREATE STAGE IF NOT EXISTS {c.db}.AGENTS.SPECS")
    c.q(f"CREATE STAGE IF NOT EXISTS {c.db}.EVALS.CONFIGS")


# The governed concepts behind the questions. Partner sourcing (Q3) and the rep-ranking rule (Q4) are left out on
# purpose: they are the long tail and the behavior gap that V3 and V4 exist to fix.
ONTOLOGY_NODES = [
    dict(name="Bookings", itemKind="METRIC", bind=("METRIC", "OPPORTUNITIES", "NET_NEW_ACV_BOOKED"),
         synonyms=["booked ACV", "net new bookings", "quarterly bookings"],
         formula="SUM(NET_NEW_ACV) WHERE STAGE = 'Closed Won' AND BOOKING_TYPE IN ('New','Expansion')", source="OPPORTUNITIES",
         description="Bookings is the company (Finance) definition of sales performance: the net-new annual contract value (ACV) "
                     "of Closed Won deals whose booking type is New or Expansion, attributed to the quarter of the close date. "
                     "Renewals and multi-year total contract value (TCV) are not bookings. The Sales team's TCV view is a "
                     "different measure and must not be reported as bookings."),
    dict(name="TCV Bookings", itemKind="METRIC", bind=("METRIC", "OPPORTUNITIES", "TCV_BOOKINGS"),
         synonyms=["sales bookings", "total contract value booked"],
         formula="SUM(AMOUNT_TCV) WHERE STAGE = 'Closed Won'", source="OPPORTUNITIES",
         description="The Sales team's view: total contract value across all contract years of every Closed Won deal, renewals "
                     "included. Used for quota and commission. It is not Bookings; report it only when TCV is asked for by name."),
    dict(name="ARR", itemKind="METRIC", bind=("METRIC", "SUBSCRIPTIONS", "ARR"),
         synonyms=["annual recurring revenue", "run-rate revenue"],
         formula="SUM(MRR * 12) WHERE PRODUCT_TYPE = 'Subscription' AND STATUS = 'Active'", source="SUBSCRIPTIONS",
         description="Annual recurring revenue: 12 x MRR of Active Subscription lines. Services lines and churned "
                     "subscriptions are excluded. The ARR snapshot draft tables are not certified and must not be used."),
    dict(name="Open Pipeline", itemKind="METRIC", bind=("METRIC", "OPPORTUNITIES", "OPEN_PIPELINE"),
         synonyms=["pipeline", "open pipe"],
         formula="SUM(ACV) WHERE STAGE IN ('Proposal','Negotiation')", source="OPPORTUNITIES",
         description="ACV of opportunities in the Proposal or Negotiation stage, excluding test accounts."),
    dict(name="Booking Type", itemKind="DIMENSION", bind=("DIMENSION", "OPPORTUNITIES", "BOOKING_TYPE"),
         synonyms=["deal type"],
         description="Classifies each opportunity as New (new logo), Expansion (upsell to an existing customer) or Renewal. "
                     "Only New and Expansion count toward Bookings."),
    dict(name="Test Account Exclusion", itemKind="POLICY", synonyms=["exclude test accounts", "sandbox accounts"],
         description="Accounts flagged IS_TEST_ACCOUNT (named 'TEST - Sandbox ...') are internal sandboxes. Exclude them from "
                     "every revenue metric: Bookings, ARR and pipeline."),
]
ONTOLOGY_EDGES = [
    ("Booking Type", "Bookings", "CLASSIFIES", None),
    ("Bookings", "TCV Bookings", "CUSTOM", "is not the same as"),
    ("Test Account Exclusion", "Bookings", "APPLIES_TO", None),
    ("Test Account Exclusion", "ARR", "APPLIES_TO", None),
    ("Test Account Exclusion", "Open Pipeline", "APPLIES_TO", None),
]


def ontology_term(c, name):
    t = c.scalar(f"SELECT SYSTEM$GET_GLOSSARY_TERM('{ONTOLOGY_DOMAIN}.{name}')", check=False)
    if isinstance(t, dict) or not t:
        return None
    try:
        t = json.loads(t)
    except ValueError:
        return None
    return t if t.get("status") == "ACTIVE" else None


def ontology_ready(c):
    return ontology_term(c, ONTOLOGY_TERM) is not None


def step_ontology(c):
    print("• business ontology")
    summary = c.scalar("SELECT SYSTEM$GET_GLOSSARY_SUMMARY()", check=False)
    if isinstance(summary, dict):
        print("    Business Ontology is not available in this account; skipping (V2 will not be created).")
        return
    domains = {d["name"]: d["domainId"] for d in json.loads(summary).get("domains", [])}
    if ONTOLOGY_DOMAIN not in domains:
        r = json.loads(c.scalar(f"SELECT SYSTEM$CREATE_GLOSSARY_DOMAIN('{ONTOLOGY_DOMAIN}', 'Governed revenue definitions for the context-eval demo')"))
        domains[ONTOLOGY_DOMAIN] = r["domainId"]
    for n in ONTOLOGY_NODES:
        if ontology_term(c, n["name"]):
            print(f"    {n['name']}: exists (ontology is account-wide); reusing it")
            continue
        term = {"name": n["name"], "domainId": str(domains[ONTOLOGY_DOMAIN]), "itemKind": n["itemKind"], "sourceType": "MANUAL",
                "description": n["description"], "synonyms": n["synonyms"]}
        if n["itemKind"] == "METRIC":
            term.update(formula=n["formula"], formulaSource=f"{c.db}.CRM.{n['source']}")
        draft = json.loads(c.scalar(f"SELECT SYSTEM$DRAFT_GLOSSARY_TERM($${json.dumps(term)}$$)"))
        term_id = draft.get("termId") or draft.get("id")
        c.scalar(f"SELECT SYSTEM$APPROVE_GLOSSARY_TERM('{term_id}')")
        if n.get("bind"):
            kind, entity, member = n["bind"]
            ref = {"refType": "SEMANTIC_VIEW", "fqn": f"{c.db}.CRM.REVENUE_GOVERNED_SV", "subObjectType": kind,
                   "entityQualifier": entity, "subObjectName": member}
            c.scalar(f"SELECT SYSTEM$CREATE_GLOSSARY_ASSOCIATION('{term_id}', $${json.dumps(ref)}$$, 'RELATED_SEMANTIC_VIEW')")
        print(f"    {n['name']}: created ({n['itemKind']}{', bound to ' + '.'.join(n['bind'][1:]) if n.get('bind') else ''})")
    for src, tgt, kind, label in ONTOLOGY_EDGES:
        # This account rejects a NULL label ("inputs may not be null"), so non-CUSTOM edges use the 3-argument form.
        extra = f", '{label}', 'MANUAL'" if label else ""
        r = c.scalar(f"SELECT SYSTEM$CREATE_GLOSSARY_RELATIONSHIP('{ONTOLOGY_DOMAIN}.{src}', '{ONTOLOGY_DOMAIN}.{tgt}', '{kind}'{extra})", check=False)
        ok = not isinstance(r, dict) and '"error":true' not in str(r).replace(" ", "")
        print(f"    {src} -{kind}-> {tgt}: {'created' if ok else 'exists or failed: ' + str(r)[:120]}")


def sense_ready(c):
    r = c.scalar("""SELECT SYSTEM$CORTEX_AGENT_CORTEX_CONTEXT_BUILDER('{"action":"list-contexts"}')""", check=False)
    if isinstance(r, dict) or not r:
        return False
    ctxs = json.loads(r).get("response_structured", {}).get("cortex_contexts", [])
    return any((x.get("database_name"), x.get("schema_name"), x.get("name")) == (c.db, "SENSE", "REVENUE_DEMO") for x in ctxs)


def strip_tool(spec, tool_type, sentences):
    """Removes a tool (by type), its tool_resources entry and the instruction sentences that mention it."""
    names = [t["tool_spec"]["name"] for t in spec["tools"] if t["tool_spec"]["type"] == tool_type]
    spec["tools"] = [t for t in spec["tools"] if t["tool_spec"]["type"] != tool_type]
    for n in names:
        spec.get("tool_resources", {}).pop(n, None)
    orch = spec["instructions"]["orchestration"]
    spec["instructions"]["orchestration"] = " ".join(s for s in orch.split(". ") if not s.startswith(sentences)).strip()
    return spec


def latest_version(c):
    rows = c.q(f"SHOW VERSIONS IN AGENT {c.db}.{AGENT}")
    named = [r["name"] for r in rows if r["name"].upper().startswith("VERSION$")]
    return max(named, key=lambda n: int(n.split("$")[1]))


def step_agent(c):
    print("• agent REVENUE_ASSISTANT")
    # Agent specs must sit on a server-side-encrypted stage for CREATE AGENT / ADD VERSION FROM to read them.
    c.q(f"CREATE OR REPLACE STAGE {c.db}.AGENTS.SPECS ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')")
    has_ont, has_sense = ontology_ready(c), sense_ready(c)
    print(f"    business ontology: {'yes' if has_ont else 'no'}   cortex sense context: {'yes' if has_sense else 'no (see setup/CORTEX_SENSE.md)'}")
    plan = [a for a in ALIASES if (a != "V2_ONTOLOGY" or has_ont) and (a != "V3_SENSE" or (has_sense and has_ont))]
    for a in plan:
        with open(os.path.join(ROOT, "agent/specs", SPEC_DIRS[a], "agent_spec.yaml")) as f:
            spec = json.loads(c.render(f.read()))
        if a == "V4_INSTRUCTIONS":
            if not has_sense:
                spec = strip_tool(spec, "cortex_sense", (SENSE_SENTENCE,))
            if not has_ont:
                spec = strip_tool(spec, "snowscope_search", ONTOLOGY_SENTENCES)
        d = tempfile.mkdtemp()
        p = os.path.join(d, "agent_spec.yaml")
        with open(p, "w") as f:
            json.dump(spec, f, indent=2)  # JSON is valid YAML
        c.q(f"PUT 'file://{p}' '@{c.db}.AGENTS.SPECS/{SPEC_DIRS[a]}/' AUTO_COMPRESS=FALSE OVERWRITE=TRUE")
        shutil.rmtree(d)

    fqn = f"{c.db}.{AGENT}"
    c.q(f"CREATE OR REPLACE AGENT {fqn} COMMENT = 'Context-eval demo: one agent, one tagged version per context layer' "
        f"FROM @{c.db}.AGENTS.SPECS/{SPEC_DIRS[plan[0]]}/")
    # CREATE AGENT makes VERSION$1 plus a LIVE copy; ADD VERSION FROM fails while LIVE exists, so commit it and drop the duplicate.
    c.q(f"ALTER AGENT {fqn} COMMIT COMMENT = 'duplicate of VERSION$1'")
    c.q(f"ALTER AGENT {fqn} DROP VERSION {latest_version(c)}", check=False)
    c.q(f"ALTER AGENT {fqn} MODIFY VERSION VERSION$1 SET ALIAS = {plan[0]}")
    c.q(f"ALTER AGENT {fqn} MODIFY VERSION VERSION$1 SET COMMENT = '{plan[0]}'")
    print(f"    VERSION$1 -> {plan[0]}")
    for a in plan[1:]:
        c.q(f"ALTER AGENT {fqn} ADD VERSION FROM @{c.db}.AGENTS.SPECS/{SPEC_DIRS[a]}/ COMMENT = '{a}'")
        v = latest_version(c)
        c.q(f"ALTER AGENT {fqn} MODIFY VERSION {v} SET ALIAS = {a}")
        print(f"    {v} -> {a}")
    v4 = [r["name"] for r in c.q(f"SHOW VERSIONS IN AGENT {fqn}") if (r.get("alias") or r.get("aliases") or "").upper().find("V4_INSTRUCTIONS") >= 0]
    if v4:
        c.q(f"ALTER AGENT {fqn} SET DEFAULT_VERSION = '{v4[0]}'")
    skipped = [a for a in ALIASES if a not in plan]
    if skipped:
        print(f"    skipped {', '.join(skipped)} (feature not available yet); rerun with --steps agent once it is.")


def compute_pool(c, override):
    if override:
        return override
    r = c.q("SHOW PARAMETERS LIKE 'DEFAULT_STREAMLIT_COMPUTE_POOL' IN ACCOUNT", check=False)
    if isinstance(r, list) and r and (r[0].get("value") or r[0].get("default")):
        return r[0].get("value") or r[0].get("default")
    return "SYSTEM_COMPUTE_POOL_CPU"


def step_app(c, pool):
    print("• streamlit app")
    c.q(f"CREATE SCHEMA IF NOT EXISTS {c.db}.APP")
    d = tempfile.mkdtemp()
    shutil.copytree(os.path.join(ROOT, "app"), d, dirs_exist_ok=True)
    with open(os.path.join(d, "snowflake.yml")) as f:
        yml = c.render(f.read()).replace("__POOL__", pool)
    with open(os.path.join(d, "snowflake.yml"), "w") as f:
        f.write(yml)
    cmd = ["snow", "streamlit", "deploy", "--replace", "-p", d]
    if c.connection:
        cmd += ["-c", c.connection]
    if c.role:
        cmd += ["--role", c.role]
    r = subprocess.run(cmd, capture_output=True, text=True)
    print("   ", (r.stdout or r.stderr).strip().splitlines()[-1] if (r.stdout or r.stderr) else "")
    if r.returncode != 0:
        sys.exit(r.stderr)
    shutil.rmtree(d)
    rows = c.q(f"SHOW STREAMLITS LIKE 'CONTEXT_EVAL_DEMO_APP' IN SCHEMA {c.db}.APP")
    if not rows:
        sys.exit("    app deploy did not create the STREAMLIT object")


def main():
    p = common_args(argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter))
    p.add_argument("--steps", default="data,ontology,agent,app", help="comma-separated subset of data,ontology,agent,app")
    p.add_argument("--compute-pool", default=None, help="compute pool for the Streamlit container runtime")
    a = p.parse_args()
    c = ctx_from(a)
    steps = a.steps.split(",")
    if "data" in steps:
        step_data(c)
    if "ontology" in steps:
        step_ontology(c)
    if "agent" in steps:
        step_agent(c)
    if "app" in steps:
        step_app(c, compute_pool(c, a.compute_pool))
    print(f"\nDone. Open Snowsight > Projects > Streamlit > CONTEXT_EVAL_DEMO_APP (database {c.db}).")


if __name__ == "__main__":
    main()
