"""
Synthetic data helpers for the Graph Fraud Detection demo.

Data generation for the base tables (ADDRESSES, APPLICANTS, APPLICATIONS, etc.)
is handled by setup/01_foundations.sql. This module provides Python helpers for:
  - Inserting new applicant batches (incremental / streaming demo flows)
  - Generating suspicious vs. clean applicant profiles
"""

import random
import time
from datetime import datetime, timezone


def generate_new_applicant_batch(
    session,
    n_suspicious: int = 5,
    n_clean: int = 5,
    *,
    database: str = "GRAPH_FRAUD_DEMO",
    ring_id: int = 0,
):
    """Insert a batch of new applicants into APPLICATIONS for incremental demo.

    Suspicious applicants share the address/IP of an existing fraud ring.
    Clean applicants get random attributes.

    Returns dict with inserted applicant IDs.
    """
    ring_row = session.sql(f"""
        SELECT RING_ADDRESS_ID, RING_IP, RING_DEVICE
        FROM {database}.RAW.FRAUD_RINGS
        WHERE RING_ID = {ring_id}
    """).collect()

    if not ring_row:
        raise ValueError(f"No fraud ring with RING_ID={ring_id}")

    shared_addr = ring_row[0]["RING_ADDRESS_ID"]
    shared_ip = ring_row[0]["RING_IP"]
    shared_device = ring_row[0]["RING_DEVICE"]

    max_id = session.sql(f"""
        SELECT COALESCE(MAX(APPLICANT_ID), 9000000)
        FROM {database}.RAW.APPLICATIONS
        WHERE APPLICANT_ID >= 9000000
    """).collect()[0][0]

    max_return = session.sql(f"""
        SELECT COALESCE(MAX(RETURN_ID), 0) FROM {database}.RAW.APPLICATIONS
    """).collect()[0][0]

    next_tp = max_id + 1
    next_ret = max_return + 1
    suspicious_ids = []
    clean_ids = []
    values = []

    for i in range(n_suspicious):
        tp_id = next_tp + i
        ret_id = next_ret + i
        claim = round(random.uniform(8000, 22000), 2)
        hour = random.choice([1, 2, 3, 4, 23])
        ts = f"2026-04-{random.randint(10, 15):02d} {hour:02d}:{random.randint(0,59):02d}:00"
        values.append(
            f"({ret_id}, {tp_id}, {shared_addr}, {claim}, "
            f"SHA2('{tp_id}_bank', 256), '{shared_ip}', '{shared_device}', "
            f"'{ts}'::TIMESTAMP_NTZ)"
        )
        suspicious_ids.append(tp_id)

    offset = n_suspicious
    for i in range(n_clean):
        tp_id = next_tp + offset + i
        ret_id = next_ret + offset + i
        claim = round(random.uniform(500, 6000), 2)
        addr = random.randint(0, 499999)
        ip = f"{random.randint(1,255)}.{random.randint(0,255)}.{random.randint(0,255)}.{random.randint(0,255)}"
        device = f"DEV_CLEAN_{tp_id}"
        hour = random.randint(8, 18)
        ts = f"2026-04-{random.randint(10, 15):02d} {hour:02d}:{random.randint(0,59):02d}:00"
        values.append(
            f"({ret_id}, {tp_id}, {addr}, {claim}, "
            f"SHA2('{tp_id}_bank', 256), '{ip}', '{device}', "
            f"'{ts}'::TIMESTAMP_NTZ)"
        )
        clean_ids.append(tp_id)

    insert_sql = f"""
        INSERT INTO {database}.RAW.APPLICATIONS
            (RETURN_ID, APPLICANT_ID, ADDRESS_ID, CLAIM_AMOUNT,
             BANK_ACCOUNT_HASH, IP_ADDRESS, DEVICE_ID, SUBMITTED_AT)
        VALUES {', '.join(values)}
    """
    session.sql(insert_sql).collect()

    return {
        "suspicious_ids": suspicious_ids,
        "clean_ids": clean_ids,
        "shared_address_id": shared_addr,
        "shared_ip": shared_ip,
        "ring_id": ring_id,
    }


def generate_stream_submission_event(applicant_id, claim_amount, address_id, ip_address):
    """Build a single submission event dict for stream ingest."""
    return {
        "APPLICANT_ID": str(applicant_id),
        "ADDRESS_ID": str(address_id),
        "IP_ADDRESS": ip_address,
        "CLAIM_AMOUNT": float(claim_amount),
        "SUBMISSION_HOUR": float(datetime.now(timezone.utc).hour),
        "IS_HIGH_CLAIM": float(1 if claim_amount > 10000 else 0),
        "IS_ODD_HOUR": float(1 if datetime.now(timezone.utc).hour in range(0, 6) else 0),
        "SUBMITTED_AT": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S"),
    }
