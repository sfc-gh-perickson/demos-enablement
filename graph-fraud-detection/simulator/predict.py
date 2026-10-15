#!/usr/bin/env python3
"""
Graph Fraud Simulator — Single Application Prediction

Scores one application end-to-end:
  1. Query the COMBINED_FRAUD_FEATURES real-time FV (assembles 15 raw features
     from graph, address, IP, and velocity FVs)
  2. Call model inference via the Snowflake Gateway stable URL

The real-time FV accepts request-time inputs (CLAIM_AMOUNT, ADDRESS_ID,
IP_ADDRESS) and joins graph/address/IP/velocity features server-side.

Requires:
    SNOWFLAKE_PAT              Programmatic Access Token
    GRAPH_FRAUD_OFS_QUERY_URL  OFS query endpoint (or auto-resolved)
    GRAPH_FRAUD_GATEWAY_URL    Gateway stable URL (or auto-resolved)

Usage:
    export SNOWFLAKE_PAT=<token>
    python simulator/predict.py
    python simulator/predict.py -t TP_000042 --suspicious
"""

import argparse
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

import numpy as np
import pandas as pd
import requests
from snowflake.snowpark import Session
import snowflake.connector

sys.path.insert(0, os.path.dirname(__file__))
from config import (
    CONNECTION_NAME, DATABASE, SCHEMA, FEATURE_SCHEMA, WAREHOUSE,
    MODEL_NAME, GATEWAY_NAME, ENTITY_KEY, MODEL_FEATURE_ORDER,
    GRAPH_FV_NAME, GRAPH_FV_VER, ADDRESS_FV_NAME, ADDRESS_FV_VER,
    IP_FV_NAME, IP_FV_VER, STREAM_FV_NAME, STREAM_FV_VER,
    COMBINED_FV_NAME, COMBINED_FV_VER,
    GRAPH_FEATURES, ADDRESS_FEATURES, IP_FEATURES, VELOCITY_FEATURES,
)

OFS_QUERY_URL  = os.environ.get('GRAPH_FRAUD_OFS_QUERY_URL', '')
GATEWAY_URL    = os.environ.get('GRAPH_FRAUD_GATEWAY_URL', '')
PAT_TOKEN      = os.environ.get('SNOWFLAKE_PAT', '')
FS             = None

HEADERS = lambda: {
    'Authorization': f'Snowflake Token="{PAT_TOKEN}"',
    'Content-Type': 'application/json',
}


def get_session():
    try:
        from snowflake.snowpark.context import get_active_session
        return get_active_session()
    except Exception:
        conn = snowflake.connector.connect(connection_name=CONNECTION_NAME)
        return Session.builder.configs({'connection': conn}).create()


def resolve_urls(session):
    """Initialize the FeatureStore handle and resolve the Gateway URL."""
    from snowflake.ml.feature_store import FeatureStore, CreationMode, online_service
    global OFS_QUERY_URL, GATEWAY_URL, FS

    FS = FeatureStore(
        session=session, database=DATABASE, name=FEATURE_SCHEMA,
        default_warehouse=WAREHOUSE, creation_mode=CreationMode.FAIL_IF_NOT_EXIST,
    )
    if not OFS_QUERY_URL:
        status = FS.get_online_service_status()
        OFS_QUERY_URL = online_service.endpoint_url(status, 'query')
        print(f'  OFS Query URL  : {OFS_QUERY_URL}')

    if not GATEWAY_URL:
        rows = session.sql(f'DESC GATEWAY {DATABASE}.{SCHEMA}.{GATEWAY_NAME}').collect()
        for row in rows:
            d = row.as_dict()
            url = d.get('ingress_url', '')
            if url and '.' in url:
                GATEWAY_URL = f'https://{url}' if not url.startswith('http') else url
                break
        print(f'  Gateway URL    : {GATEWAY_URL}')


def read_online(fv_name, fv_version, entity_key, entity_value):
    """Read online features for one entity via the SDK Postgres online store."""
    t0 = time.time()
    row = {}
    try:
        out = FS.read_feature_view(
            fv_name, fv_version,
            keys=[[entity_value]],
            store_type='online',
        )
        pdf = out if isinstance(out, pd.DataFrame) else out.to_pandas()
        if len(pdf) > 0:
            row = pdf.iloc[0].to_dict()
    except Exception as e:
        print(f'  OFS read error [{fv_name}]: {str(e)[:160]}')
    elapsed_ms = (time.time() - t0) * 1000
    return row, elapsed_ms


def fetch_all_features(applicant_id, address_id, ip_address):
    """Fetch graph, address, IP, and velocity features in parallel from OFS."""
    specs = [
        (GRAPH_FV_NAME,   GRAPH_FV_VER,   ENTITY_KEY,         applicant_id,      GRAPH_FEATURES),
        (ADDRESS_FV_NAME, ADDRESS_FV_VER,  'ADDRESS_ID',       address_id,        ADDRESS_FEATURES),
        (IP_FV_NAME,      IP_FV_VER,       'IP_ADDRESS',       ip_address,        IP_FEATURES),
        (STREAM_FV_NAME,  STREAM_FV_VER,   ENTITY_KEY,         applicant_id,      VELOCITY_FEATURES),
    ]
    features, latencies = {}, {}
    with ThreadPoolExecutor(max_workers=len(specs)) as pool:
        futs = {
            pool.submit(read_online, name, ver, ek, ev): (name, cols)
            for name, ver, ek, ev, cols in specs
        }
        for fut in as_completed(futs):
            name, cols = futs[fut]
            row, ms = fut.result()
            latencies[name] = ms
            features.update({k: row[k] for k in cols if k in row})
    return features, latencies


def _num(val, default=0.0):
    if val is None:
        return float(default)
    try:
        f = float(val)
    except (TypeError, ValueError):
        return float(default)
    if f != f:
        return float(default)
    return f


def build_feature_vector(features, claim_amount):
    """Assemble the 15-feature vector matching MODEL_FEATURE_ORDER."""
    community_size = _num(features.get('COMMUNITY_SIZE'))
    addr_community = _num(features.get('COMMUNITY_SIZE_AT_ADDRESS'))
    ip_community   = _num(features.get('COMMUNITY_SIZE_AT_IP'))

    effective_community_size = (
        community_size if community_size > 0
        else addr_community if addr_community > 0
        else ip_community
    )
    has_direct = 1.0 if community_size > 0 else 0.0

    mapping = {
        'EFFECTIVE_COMMUNITY_SIZE': effective_community_size,
        'DEGREE':                   _num(features.get('DEGREE')),
        'SHARED_ADDRESS_COUNT':     _num(features.get('SHARED_ADDRESS_COUNT')),
        'SHARED_IP_COUNT':          _num(features.get('SHARED_IP_COUNT')),
        'AVG_COMMUNITY_REFUND':     _num(features.get('AVG_COMMUNITY_REFUND')),
        'COMMUNITY_REFUND_STDDEV':  _num(features.get('COMMUNITY_REFUND_STDDEV')),
        'ADDR_N_FILERS':            _num(features.get('NUM_FILERS_AT_ADDRESS')),
        'ADDR_AVG_REFUND':          _num(features.get('AVG_REFUND_AT_ADDRESS')),
        'IP_N_FILERS':              _num(features.get('NUM_FILERS_AT_IP')),
        'IP_AVG_REFUND':            _num(features.get('AVG_REFUND_AT_IP')),
        'SUBMISSION_HOUR':          _num(features.get('SUBMISSION_HOUR'), 12),
        'IS_HIGH_CLAIM':            _num(features.get('IS_HIGH_CLAIM')),
        'IS_ODD_HOUR':              _num(features.get('IS_ODD_HOUR')),
        'CLAIM_AMOUNT':             float(claim_amount),
        'HAS_DIRECT_GRAPH':         has_direct,
    }
    return [mapping[col] for col in MODEL_FEATURE_ORDER]


def call_gateway(feature_vector):
    """Call inference via Gateway stable URL."""
    record = dict(zip(MODEL_FEATURE_ORDER, feature_vector))
    t0 = time.time()
    resp = requests.post(
        f'{GATEWAY_URL}/predict-proba',
        headers=HEADERS(),
        json={'dataframe_records': [record]},
        timeout=30,
    )
    elapsed_ms = (time.time() - t0) * 1000

    prob = 0.0
    if resp.status_code == 200:
        data = resp.json()
        rows = data.get('data', []) or data.get('dataframe_records', [])
        if rows:
            first = rows[0]
            if isinstance(first, list) and len(first) >= 2:
                raw = first[1]
                prob = float(raw.get('output_feature_1', 0)) if isinstance(raw, dict) else float(raw)
            elif isinstance(first, dict):
                prob = float(first.get('output_feature_1', first.get('1', 0)))
    else:
        print(f'  Gateway error: {resp.status_code} {resp.text[:300]}')

    return prob, elapsed_ms


def main():
    parser = argparse.ArgumentParser(description='Graph fraud prediction — single application')
    parser.add_argument('--applicant', '-t', type=str, help='Applicant ID (default: random)')
    parser.add_argument('--suspicious', action='store_true', help='Force suspicious application')
    args = parser.parse_args()

    if not PAT_TOKEN:
        print('ERROR: Set SNOWFLAKE_PAT environment variable')
        return

    print('Connecting to Snowflake...')
    session = get_session()
    session.sql('USE ROLE ACCOUNTADMIN').collect()
    session.sql(f'USE DATABASE {DATABASE}').collect()
    session.sql(f'USE WAREHOUSE {WAREHOUSE}').collect()

    print('Resolving endpoints...')
    resolve_urls(session)

    if args.applicant:
        applicant_id = args.applicant
    else:
        rows = session.sql(
            f'SELECT DISTINCT APPLICANT_ID FROM {DATABASE}.RAW.APPLICANTS LIMIT 200'
        ).collect()
        applicant_id = str(np.random.choice([r[0] for r in rows]))

    # Pick an address and IP for this applicant
    app_row = session.sql(f"""
        SELECT ADDRESS_ID, IP_ADDRESS
        FROM {DATABASE}.RAW.APPLICATIONS
        WHERE APPLICANT_ID = {applicant_id}
        ORDER BY SUBMITTED_AT DESC LIMIT 1
    """).collect()
    if app_row:
        address_id = str(app_row[0][0])
        ip_address = str(app_row[0][1])
    else:
        address_id = '0'
        ip_address = '0.0.0.0'

    is_suspicious = args.suspicious or (np.random.random() < 0.3)
    if is_suspicious:
        claim_amount = float(np.random.uniform(15000, 50000))
        submission_hour = int(np.random.choice([1, 2, 3, 4, 23]))
    else:
        claim_amount = float(np.abs(np.random.lognormal(8, 0.8)))
        submission_hour = int(np.random.randint(8, 18))

    print(f'\n{"=" * 60}')
    print('APPLICATION')
    print(f'  Applicant      : {applicant_id}')
    print(f'  Address ID     : {address_id}')
    print(f'  IP Address     : {ip_address}')
    print(f'  Claim Amount   : ${claim_amount:,.2f}')
    print(f'  Submission Hour: {submission_hour}:00')

    print(f'\n{"=" * 60}')
    print('FEATURE LOOKUP (OFS — parallel across 4 FVs)')
    fs_start = time.time()
    features, latencies = fetch_all_features(applicant_id, address_id, ip_address)
    fs_ms = (time.time() - fs_start) * 1000
    print(f'  Total (wall clock): {fs_ms:.0f}ms')
    for fv, ms in latencies.items():
        print(f'    {fv}: {ms:.0f}ms')

    if not features:
        print('ERROR: No features returned. Check OFS query URL and PAT.')
        session.close()
        return

    print(f'\n  Community size : {_num(features.get("COMMUNITY_SIZE"))}')
    print(f'  Degree         : {_num(features.get("DEGREE"))}')
    print(f'  Applicants at addr: {_num(features.get("NUM_FILERS_AT_ADDRESS"))}')

    feature_vector = build_feature_vector(features, claim_amount)

    print(f'\n{"=" * 60}')
    print('MODEL INFERENCE (Gateway)')
    prob, inf_ms = call_gateway(feature_vector)
    print(f'  Latency: {inf_ms:.0f}ms')

    decision = 'DECLINE' if prob >= 0.7 else 'REVIEW' if prob >= 0.3 else 'APPROVE'
    colors = {'APPROVE': '\033[92m', 'REVIEW': '\033[93m', 'DECLINE': '\033[91m'}

    print(f'\n{"=" * 60}')
    print('RESULT')
    print(f'  Fraud Probability: {prob:.1%}')
    print(f'  Decision         : {colors[decision]}{decision}\033[0m')

    print('\n  Risk Factors:')
    flagged = []
    if _num(features.get('COMMUNITY_SIZE')) > 20:
        flagged.append(f'Large community ({int(_num(features.get("COMMUNITY_SIZE")))} members)')
    if _num(features.get('NUM_FILERS_AT_ADDRESS')) > 10:
        flagged.append(f'High-density address ({int(_num(features.get("NUM_FILERS_AT_ADDRESS")))} applicants)')
    if claim_amount > 15000:
        flagged.append(f'High claim amount (${claim_amount:,.2f})')
    if submission_hour in range(0, 6):
        flagged.append(f'Unusual submission hour ({submission_hour}:00)')
    if _num(features.get('SHARED_IP_COUNT')) > 5:
        flagged.append(f'Shared IP with {int(_num(features.get("SHARED_IP_COUNT")))} others')
    for f in flagged:
        print(f'    [!] {f}')
    if not flagged:
        print('    None detected')

    print(f'\n{"=" * 60}')
    print('LATENCY SUMMARY')
    total_ms = fs_ms + inf_ms
    print(f'  Feature Store (OFS): {fs_ms:>6.0f}ms  ({fs_ms/max(total_ms,0.001)*100:>5.1f}%)')
    for fv, ms in latencies.items():
        print(f'    {fv}: {ms:.0f}ms')
    print(f'  Gateway Inference  : {inf_ms:>6.0f}ms  ({inf_ms/max(total_ms,0.001)*100:>5.1f}%)')
    print(f'  Total              : {total_ms:>6.0f}ms')

    session.close()


if __name__ == '__main__':
    main()
