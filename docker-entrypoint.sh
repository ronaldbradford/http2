#!/usr/bin/env bash
# Container entrypoint.
#   benchmark [RUNS]    headless comparison (default; ./run-all.sh)
#   interactive         origin + both proxies, for a browser on the host
#   <cmd> [args...]     anything else is executed as-is
set -euo pipefail
cd /app

mkdir -p certs logs results
scripts/gen-certs.sh >/dev/null
if [ ! -f certs/mitmproxy/mitmproxy-ca-cert.pem ]; then
  # Same CA mitmdump would write on first start (issuer CN "mitmproxy").
  .venv/bin/python - <<'PY'
from pathlib import Path
from mitmproxy.certs import CertStore
CertStore.from_store(Path("certs/mitmproxy"), "mitmproxy", 2048)
PY
fi

cmd="${1:-benchmark}"
case "$cmd" in
  benchmark|run-all)
    shift
    set +e
    ./run-all.sh "$@"
    status=$?
    set -e
    chmod -R a+rX /app/results 2>/dev/null || true
    exit "$status"
    ;;
  interactive|serve)
    shift
    exec scripts/run-interactive.sh "$@"
    ;;
  *)
    exec "$@"
    ;;
esac
