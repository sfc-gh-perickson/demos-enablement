#!/usr/bin/env python3
"""
Graph Fraud Simulator — Load Test

Runs N concurrent applications through the full OFS + Gateway pipeline and
reports TPS, p50/p95/p99 latencies for OFS feature lookup and model inference.

Usage:
    export SNOWFLAKE_PAT=<token>
    export GRAPH_FRAUD_OFS_QUERY_URL=<ofs_query_url>
    export GRAPH_FRAUD_GATEWAY_URL=<gateway_url>
    python simulator/load_test.py -n 100 -c 10
"""

import argparse
import os
import sys
import time
import random
from concurrent.futures import ThreadPoolExecutor, as_completed

import numpy as np
import requests
from snowflake.snowpark import Session
import snowflake.connector

sys.path.insert(0, os.path.dirname(__file__))
from config import (
    CONNECTION_NAME, DATABASE, SCHEMA, FEATURE_SCHEMA, WAREHOUSE,
    MODEL_NAME, GATEWAY_NAME, ENTITY_KEY,
)
from predict import (
    get_session, resolve_urls, fetch_all_features,
    build_feature_vector, call_gateway,
)
import predict as predict_module


def score_application(applicant_id, address_id, ip_address, is_suspicious=None):
    """Score a single application — returns (decision, fs_ms, inf_ms, prob, error)."""
    if is_suspicious is None:
        is_suspicious = random.random() < 0.25
    if is_suspicious:
        claim = float(np.random.uniform(15000, 50000))
    else:
        claim = float(np.abs(np.random.lognormal(8, 0.8)))

    try:
        features, latencies = fetch_all_features(applicant_id, address_id, ip_address)
        fs_ms = max(latencies.values()) if latencies else 0

        if not features:
            return None, 0, 0, 0.0, 'No features returned'

        vec = build_feature_vector(features, claim)
        prob, inf_ms = call_gateway(vec)
        decision = 'DECLINE' if prob >= 0.7 else 'REVIEW' if prob >= 0.3 else 'APPROVE'
        return decision, fs_ms, inf_ms, prob, None
    except Exception as e:
        return None, 0, 0, 0.0, str(e)


def percentile(arr, p):
    if not arr:
        return 0
    arr_sorted = sorted(arr)
    idx = int(len(arr_sorted) * p / 100)
    return arr_sorted[min(idx, len(arr_sorted) - 1)]


def main():
    parser = argparse.ArgumentParser(description='Graph fraud load test')
    parser.add_argument('-n', '--num',         type=int, default=100, help='Total applications (default: 100)')
    parser.add_argument('-c', '--concurrency', type=int, default=5,   help='Concurrent workers (default: 5)')
    args = parser.parse_args()

    if not predict_module.PAT_TOKEN:
        print('ERROR: Set SNOWFLAKE_PAT environment variable')
        return

    print(f'=== Graph Fraud Load Test: {args.num} applications, {args.concurrency} concurrent ===\n')

    session = get_session()
    session.sql('USE ROLE ACCOUNTADMIN').collect()
    session.sql(f'USE DATABASE {DATABASE}').collect()
    session.sql(f'USE WAREHOUSE {WAREHOUSE}').collect()
    resolve_urls(session)

    print('Sampling applicants with addresses and IPs...')
    rows = session.sql(f"""
        SELECT t.APPLICANT_ID, r.ADDRESS_ID, r.IP_ADDRESS
        FROM {DATABASE}.RAW.APPLICANTS t
        JOIN {DATABASE}.RAW.APPLICATIONS r ON t.APPLICANT_ID = r.APPLICANT_ID
        LIMIT 500
    """).collect()
    applicant_data = [(str(r[0]), str(r[1]), str(r[2])) for r in rows]
    session.close()
    print(f'  {len(applicant_data)} applicant records available\n')

    decisions = {'APPROVE': 0, 'REVIEW': 0, 'DECLINE': 0}
    fs_latencies = []
    inf_latencies = []
    errors = 0
    completed = 0

    start_time = time.time()
    tasks = [random.choice(applicant_data) for _ in range(args.num)]

    print('Scoring applications...')
    with ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        futs = [pool.submit(score_application, tid, aid, ip) for tid, aid, ip in tasks]
        for fut in as_completed(futs):
            decision, fs_ms, inf_ms, prob, err = fut.result()
            if err:
                errors += 1
            else:
                completed += 1
                if decision in decisions:
                    decisions[decision] += 1
                fs_latencies.append(fs_ms)
                inf_latencies.append(inf_ms)
            if (completed + errors) % 10 == 0:
                elapsed = time.time() - start_time
                tps = completed / max(elapsed, 0.001)
                print(f'  {completed + errors}/{args.num} | {tps:.1f} TPS | errors={errors}')

    elapsed = time.time() - start_time
    tps = completed / max(elapsed, 0.001)
    total_lat = [f + i for f, i in zip(fs_latencies, inf_latencies)]

    print(f'\n{"=" * 72}')
    print(f'RESULTS: {completed}/{args.num} successful | {tps:.1f} TPS\n')

    print(f'  {"Latency (ms)":<20} {"Avg":>8} {"p50":>8} {"p95":>8} {"p99":>8}')
    print(f'  {"─" * 52}')
    for label, lat in [('Feature Store (OFS)', fs_latencies), ('Gateway Inference', inf_latencies), ('Total', total_lat)]:
        if lat:
            avg = sum(lat) / len(lat)
            print(f'  {label:<20} {avg:>8.0f} {percentile(lat, 50):>8.0f} {percentile(lat, 95):>8.0f} {percentile(lat, 99):>8.0f}')

    print(f'\n  Decisions: ' + '  '.join(f'{k}={v}' for k, v in decisions.items()))
    if errors:
        print(f'  Errors   : {errors}')
    print(f'{"=" * 72}')


if __name__ == '__main__':
    main()
