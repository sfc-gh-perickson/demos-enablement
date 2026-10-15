"""
Multiprocess QPS load generator for the OFS REST query endpoint.

A single Python process (threads or asyncio) is GIL/event-loop bound and tops out
at a few hundred QPS in a notebook kernel. To generate 1000+ QPS we mirror the
official benchmark kit's design: spread the load across multiple OS processes
(the kit uses Locust workers across CPU cores).

`proc_worker` runs in each child process. It drives `n_threads` paced workers
(constant_throughput model) using a per-thread `requests.Session` with a
keep-alive connection pool, warms up, then measures steady state. Functions are
module-level so they pickle cleanly for ProcessPoolExecutor (fork or spawn).
"""
import time
import random
import threading
from concurrent.futures import ThreadPoolExecutor

import requests


def _thread_loop(endpoint, headers, body_base, applicant_ids, entity_key,
                 interval, rec_start, deadline, lat, statuses, errors, lock):
    sess = requests.Session()
    adapter = requests.adapters.HTTPAdapter(pool_connections=4, pool_maxsize=4, max_retries=0)
    sess.mount('http://', adapter)
    sess.mount('https://', adapter)
    try:
        while time.perf_counter() < deadline:
            t0 = time.perf_counter()
            body = dict(body_base)
            body['request_rows'] = [{'entity': {entity_key: random.choice(applicant_ids)}}]
            try:
                r = sess.post(endpoint, headers=headers, json=body, timeout=30)
                dt = (time.perf_counter() - t0) * 1000
                if time.perf_counter() >= rec_start:
                    with lock:
                        statuses[r.status_code] = statuses.get(r.status_code, 0) + 1
                        if r.status_code in (200, 207):
                            lat.append(dt)
                        else:
                            errors[0] += 1
            except Exception:
                if time.perf_counter() >= rec_start:
                    with lock:
                        errors[0] += 1
            sleep = interval - (time.perf_counter() - t0)
            if sleep > 0:
                time.sleep(sleep)
    finally:
        sess.close()


def proc_worker(endpoint, pat, fv_name, fv_ver, entity_key, applicant_ids,
                proc_qps, duration_s, warmup_s, per_worker_qps=8):
    """Run a paced, multi-threaded load for this process. Returns aggregated stats."""
    headers = {'Authorization': f'Snowflake Token="{pat}"', 'Content-Type': 'application/json'}
    body_base = {'name': fv_name, 'version': fv_ver, 'object_type': 'feature_view'}

    n_threads = max(1, round(proc_qps / per_worker_qps))
    eff_per_wk = proc_qps / n_threads
    interval = 1.0 / eff_per_wk

    lat, statuses, errors = [], {}, [0]
    lock = threading.Lock()
    start = time.perf_counter()
    rec_start = start + warmup_s
    deadline = start + warmup_s + duration_s

    with ThreadPoolExecutor(max_workers=n_threads) as pool:
        futs = [
            pool.submit(_thread_loop, endpoint, headers, body_base, applicant_ids,
                        entity_key, interval, rec_start, deadline,
                        lat, statuses, errors, lock)
            for _ in range(n_threads)
        ]
        for f in futs:
            f.result()

    return {
        'lat': lat,
        'completed': len(lat),
        'errors': errors[0],
        'statuses': statuses,
        'n_threads': n_threads,
        'measure_s': duration_s,
    }
