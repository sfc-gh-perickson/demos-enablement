"""Tiny wrapper around the Snowflake CLI (`snow sql`) shared by deploy.py, run_evals.py and teardown.py.

Only the standard library is used, so the field needs nothing beyond Python 3.9+ and Snowflake CLI 3.14+.
"""
import json
import os
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ALIASES = ["V0_STUFFED", "V1_GOVERNED_SV", "V2_ONTOLOGY", "V3_SENSE", "V4_INSTRUCTIONS"]
AGENT = "AGENTS.REVENUE_ASSISTANT"


class Ctx:
    def __init__(self, connection, db, wh, role):
        self.connection, self.db, self.wh, self.role = connection, db.upper(), wh.upper(), role
        self.schema = None  # set once the database exists; some calls (EXECUTE_AI_EVALUATION) need a current DB

    def base(self):
        cmd = ["snow", "sql", "--format", "json"]
        if self.connection:
            cmd += ["-c", self.connection]
        if self.role:
            cmd += ["--role", self.role]
        if self.wh:
            cmd += ["--warehouse", self.wh]
        if self.schema:
            cmd += ["--database", self.db, "--schema", self.schema]
        return cmd

    def render(self, text):
        return text.replace("__DB__", self.db).replace("__WH__", self.wh)

    def _run(self, args, check=True, retries=4):
        """Runs snow sql, retrying the CLI's intermittent token errors. Returns parsed JSON (list of row lists)."""
        last = None
        for i in range(retries):
            r = subprocess.run(self.base() + args, capture_output=True, text=True)
            out, err = r.stdout.strip(), r.stderr.strip()
            if r.returncode == 0:
                try:
                    return json.loads(out) if out else []
                except json.JSONDecodeError:
                    return out
            last = (out + "\n" + err).strip()
            if "tokens invalid" in last or "Session no longer exists" in last:
                time.sleep(2 + 2 * i)
                continue
            break
        if check:
            sys.exit(f"\nSQL failed:\n{' '.join(args)[:400]}\n{last}")
        return {"error": last}

    def q(self, sql, check=True):
        """Single statement -> list of row dicts (or {'error': ...} when check=False)."""
        return self._run(["-q", sql], check=check)

    def scalar(self, sql, check=True):
        rows = self.q(sql, check=check)
        if isinstance(rows, dict):
            return rows
        return next(iter(rows[0].values())) if rows else None

    def run_file(self, path):
        """Renders a templated .sql file and runs it as one multi-statement script."""
        with open(os.path.join(ROOT, path)) as f:
            sql = self.render(f.read())
        with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as t:
            t.write(sql)
        try:
            self._run(["-f", t.name])
        finally:
            os.unlink(t.name)

    def put(self, local_path, stage_dir):
        """Uploads a rendered copy of a local text file to a stage directory, keeping the file name."""
        with open(os.path.join(ROOT, local_path)) as f:
            text = self.render(f.read())
        d = tempfile.mkdtemp()
        p = os.path.join(d, os.path.basename(local_path))
        with open(p, "w") as f:
            f.write(text)
        self.q(f"PUT 'file://{p}' '{stage_dir}' AUTO_COMPRESS=FALSE OVERWRITE=TRUE")


def common_args(parser):
    parser.add_argument("--connection", "-c", default=None, help="Snowflake CLI connection name (default: your default connection)")
    parser.add_argument("--database", default="CONTEXT_EVAL_DEMO", help="Database to create (default CONTEXT_EVAL_DEMO)")
    parser.add_argument("--warehouse", default="COMPUTE_WH", help="Warehouse for agents, semantic views and the app")
    parser.add_argument("--role", default=None, help="Role to run as (default: the connection's role)")
    return parser


def ctx_from(args):
    return Ctx(args.connection, args.database, args.warehouse, args.role)
