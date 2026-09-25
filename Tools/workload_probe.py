#!/usr/bin/env python3
"""Small, opt-in single-process CPU/hash and disk-heartbeat probe. No speed guarantee.

Compare several alternating baseline/curtain runs with identical power/thermal state.
NDJSON contains one-second buckets and a summary; --heartbeat-dir must be a NEW path.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import time

def positive_seconds(text: str) -> float:
    value = float(text)
    if not math.isfinite(value) or not 1 <= value <= 3600:
        raise argparse.ArgumentTypeError('seconds must be finite, in 1...3600')
    return value

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds', type=positive_seconds, default=60)
    parser.add_argument('--label', default='baseline')
    parser.add_argument('--heartbeat-dir', type=Path)
    args = parser.parse_args()
    if args.heartbeat_dir:
        args.heartbeat_dir.mkdir(parents=True, exist_ok=False)
    payload = b'PawsOff-workload-probe\0' * 4096
    start = last = time.monotonic()
    cpu_start = time.process_time()
    count = bucket = sequence = 0
    elapsed = 0.0
    while elapsed < args.seconds:
        hashlib.sha256(payload).digest()
        count += 1; bucket += 1
        now = time.monotonic()
        elapsed = now - start
        if now - last >= 1 or elapsed >= args.seconds:
            sequence += 1
            row = {'kind':'bucket','label':args.label,'sequence':sequence,'monotonic':now,
                   'seconds':now-last,'hashes':bucket,'hashes_per_second':bucket/(now-last)}
            print(json.dumps(row, sort_keys=True), flush=True)
            if args.heartbeat_dir:
                temp = args.heartbeat_dir / '.next.json'
                with temp.open('x') as handle:
                    json.dump(row, handle, sort_keys=True)
                    handle.flush(); os.fsync(handle.fileno())
                os.replace(temp, args.heartbeat_dir/'heartbeat.json')
            last = now; bucket = 0
    print(json.dumps({'kind':'summary','label':args.label,'wall_seconds':time.monotonic()-start,
                      'cpu_seconds':time.process_time()-cpu_start,'total_hashes':count,
                      'hashes_per_second':count/(time.monotonic()-start)}, sort_keys=True), flush=True)

if __name__ == '__main__':
    main()
