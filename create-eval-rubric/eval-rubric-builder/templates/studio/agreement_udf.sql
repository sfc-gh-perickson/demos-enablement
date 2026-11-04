-- Deterministic agreement metric for judge calibration (studio custom metrics must not call LLMs).
-- EXPECTED = human score (0..1); PREDICTED = judge output {"score": x, "reason": "..."}.
CREATE FUNCTION IF NOT EXISTS {{ db }}.{{ schema }}.JUDGE_AGREEMENT(EXPECTED VARCHAR, PREDICTED VARCHAR)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.12'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'evaluate'
AS $$
import ast, json, re

BANDS = [0.0, 0.25, 0.5, 0.75, 1.0]

def _parse_json(text):
    try:
        return json.loads(text)
    except (json.JSONDecodeError, TypeError):
        pass
    try:
        return ast.literal_eval(text)
    except (ValueError, SyntaxError):
        pass
    return None

def _num(v):
    if isinstance(v, dict):
        v = v.get("score")
    if v is None:
        return None
    if isinstance(v, (int, float)):
        return float(v)
    m = re.search(r"-?\d+(?:\.\d+)?", str(v))
    return float(m.group()) if m else None

def _band(x):
    return min(range(len(BANDS)), key=lambda i: abs(BANDS[i] - x))

def evaluate(expected, predicted):
    exp = _num(_parse_json(expected) if expected and expected.strip()[:1] in "{[" else expected)
    pv = _parse_json(predicted)
    pred = _num(pv if pv is not None else predicted)
    if exp is None or pred is None:
        return {"score": 0.0, "feedback": "Could not parse a score from expected or predicted output"}
    d = _band(pred) - _band(exp)
    reason = pv.get("reason", "") if isinstance(pv, dict) else ""
    if d == 0:
        return {"score": 1.0, "feedback": f"Judge matched human score {exp}."}
    direction = "too lenient" if d > 0 else "too strict"
    score = 0.5 if abs(d) == 1 else 0.0
    return {"score": score,
            "feedback": f"Judge was {direction}: gave {pred} vs human {exp}. Judge reason: {reason}"}
$$;
