#!/usr/bin/env python3
"""
Graph Fraud Simulator — Stream Ingest

Demonstrates the streaming feature view by pushing live application events
through the REST Ingest API and measuring end-to-end freshness.

Steps:
  1. Read current online feature state for an applicant (BEFORE)
  2. Ingest a suspicious application event via REST Ingest API
  3. Poll the online store until the feature updates (AFTER)
  4. Report freshness (ingest -> queryable feature update)

Usage:
    export SNOWFLAKE_PAT=<token>
    export GRAPH_FRAUD_OFS_QUERY_URL=<ofs_query_url>
    export GRAPH_FRAUD_OFS_INGEST_URL=<ofs_ingest_url>
    python simulator/ingest.py
    python simulator/ingest.py -t TP_000042 -n 5
"""

import argparse
import os
import sys
import time
import json
import random
from datetime import datetime, timezone

import numpy as np
import requests
from snowflake.snowpark import Session
import snowflake.connector

sys.path.insert(0, os.path.dirname(__file__))
from config import (
    CONNECTION_NAME, DATABASE, SCHEMA, FEATURE_SCHEMA, WAREHOUSE,
    STREAM_SOURCE, STREAM_FV_NAME, STREAM_FV_VER, ENTITY_KEY,
)

OFS_QUERY_URL  = os.environ.get('GRAPH_FRAUD_OFS_QUERY_URL', '')
OFS_INGEST_URL = os.environ.get('GRAPH_FRAUD_OFS_INGEST_URL', '')
PAT_TOKEN      = os.environ.get('SNOWFLAKE_PAT', '')

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
    global OFS_QUERY_URL, OFS_INGEST_URL
    from snowflake.ml.feature_store import FeatureStore, CreationMode, online_service

    if not OFS_QUERY_URL or not OFS_INGEST_URL:
        fs = FeatureStore(
            session=session, database=DATABASE, name=FEATURE_SCHEMA,
            default_warehouse=WAREHOUSE, creation_mode=CreationMode.FAIL_IF_NOT_EXIST,
        )
        status = fs.get_online_service_status()
        if not OFS_QUERY_URL:
            OFS_QUERY_URL  = online_service.endpoint_url(status, 'query')
        if not OFS_INGEST_URL:
            OFS_INGEST_URL = online_service.endpoint_url(status, 'ingest')
        print(f'  Query  : {OFS_QUERY_URL}')
        print(f'  Ingest : {OFS_INGEST_URL}')


def read_stream_fv_online(applicant_id):
    """Read current online state of STREAM_VELOCITY for an applicant."""
    resp = requests.post(
        f'{OFS_QUERY_URL}/api/v1/query',
        headers=HEADERS(),
        json={
            'name':        STREAM_FV_NAME,
            'version':     STREAM_FV_VER,
            'object_type': 'feature_view',
            'request_rows': [{'entity': {ENTITY_KEY: applicant_id}}],
        },
        timeout=10,
    )
    if resp.status_code == 200:
        data = resp.json()
        rows = data.get('rows', []) or data.get('data', [])
        return rows[0] if rows else None
    return None


def ingest_events(events):
    """Push events to the stream feature view via REST Ingest API."""
    payload = {
        'records': {
            STREAM_SOURCE: events
        }
    }
    resp = requests.post(
        f'{OFS_INGEST_URL}/api/v1/ingest',
        headers=HEADERS(),
        json=payload,
        timeout=10,
    )
    if resp.status_code == 200:
        data = resp.json()
        return data.get('accepted', len(events))
    else:
        print(f'  Ingest error: {resp.status_code} {resp.text[:200]}')
        return 0


def main():
    parser = argparse.ArgumentParser(description='OFS stream ingest + freshness demo')
    parser.add_argument('--applicant', '-t', type=str, help='Applicant ID (default: random)')
    parser.add_argument('--num', '-n', type=int, default=3, help='Number of events to ingest (default: 3)')
    parser.add_argument('--suspicious', action='store_true', help='Generate suspicious application events')
    args = parser.parse_args()

    if not PAT_TOKEN:
        print('ERROR: Set SNOWFLAKE_PAT environment variable')
        return

    session = get_session()
    session.sql('USE ROLE ACCOUNTADMIN').collect()
    session.sql(f'USE DATABASE {DATABASE}').collect()
    session.sql(f'USE WAREHOUSE {WAREHOUSE}').collect()

    print('Resolving OFS endpoints...')
    resolve_urls(session)

    if args.applicant:
        applicant_id = args.applicant
    else:
        rows = session.sql(
            f'SELECT DISTINCT APPLICANT_ID FROM {DATABASE}.RAW.APPLICANTS LIMIT 100'
        ).collect()
        applicant_id = str(np.random.choice([r[0] for r in rows]))

    session.close()
    print(f'\nApplicant: {applicant_id}')

    print('\n--- BEFORE: Online state ---')
    before = read_stream_fv_online(applicant_id)
    print(f'  {before}')

    now_ts = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')
    events = []
    for i in range(args.num):
        if args.suspicious:
            evt = {
                'APPLICANT_ID':   applicant_id,
                'APPLICATION_ID': f'APP_INGEST_{int(time.time())}_{i}',
                'SUBMITTED_AT':   now_ts,
                'CLAIM_AMOUNT':   float(np.random.uniform(15000, 50000)),
                'SUBMISSION_HOUR': float(random.choice([1, 2, 3, 4])),
            }
        else:
            evt = {
                'APPLICANT_ID':   applicant_id,
                'APPLICATION_ID': f'APP_INGEST_{int(time.time())}_{i}',
                'SUBMITTED_AT':   now_ts,
                'CLAIM_AMOUNT':   float(np.abs(np.random.lognormal(8, 0.8))),
                'SUBMISSION_HOUR': float(np.random.randint(8, 18)),
            }
        events.append(evt)

    print(f'\n--- Ingesting {len(events)} event(s) ---')
    for e in events:
        print(f'  ${e["CLAIM_AMOUNT"]:>10,.2f}  hour={int(e["SUBMISSION_HOUR"])}')

    ingest_start = time.time()
    accepted = ingest_events(events)
    ingest_ms = (time.time() - ingest_start) * 1000
    print(f'\n  Accepted: {accepted} events  ({ingest_ms:.0f}ms round-trip)')

    print('\n--- Polling for freshness ---')
    poll_start = time.time()
    freshness_s = None
    for attempt in range(30):
        time.sleep(1)
        after = read_stream_fv_online(applicant_id)
        if after != before:
            freshness_s = time.time() - poll_start
            break

    if freshness_s is not None:
        print(f'\nEnd-to-end freshness: {freshness_s:.1f}s  (ingest -> online store)')
        print('\n--- AFTER: Online state ---')
        print(f'  {after}')
    else:
        print('Feature unchanged after 30s — stream may still be processing backfill')


if __name__ == '__main__':
    main()
