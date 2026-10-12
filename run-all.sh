#!/usr/bin/env bash
# Start origin + both proxies, measure all three modes in headless Chrome, build report, stop everything.
#   ./run-all.sh [RUNS]      (env: N_JS N_IMG N_API DELAY_MIN DELAY_MAX are passed to the origin)
set -euo pipefail
cd "$(dirname "$0")"
RUNS="${1:-3}"
[ -x .venv/bin/python ] || scripts/setup.sh
scripts/gen-certs.sh >/dev/null
mkdir -p results logs && rm -f results/*
pids=()
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done; wait 2>/dev/null || true; }
trap cleanup EXIT
scripts/run-origin.sh            > logs/origin.log   2>&1 & pids+=($!)
scripts/run-proxy.sh h1          > logs/proxy-h1.log 2>&1 & pids+=($!)
PROXY_PORT=8081 scripts/run-proxy.sh h2 > logs/proxy-h2.log 2>&1 & pids+=($!)
for port in 8443 8080 8081; do
  for i in $(seq 50); do (exec 3<>/dev/tcp/127.0.0.1/$port) 2>/dev/null && break; sleep 0.2; done
done
for mode in direct proxy-h1 proxy-h2; do
  echo "== $mode"; .venv/bin/python measure/measure.py "$mode" --runs "$RUNS"
done
.venv/bin/python measure/report.py
