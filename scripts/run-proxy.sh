#!/usr/bin/env bash
# Start a TLS-inspecting explicit proxy (mitmproxy) on :8080.
#   scripts/run-proxy.sh h1   -> client side ALPN http/1.1 only (the "corporate proxy" problem)
#   scripts/run-proxy.sh h2   -> HTTP/2 enabled (the fix)
# The proxy's own CA lives in certs/mitmproxy/mitmproxy-ca-cert.pem (issuer CN "mitmproxy").
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-h1}"; PORT="${PROXY_PORT:-8080}"
case "$MODE" in h1) H2=false ;; h2) H2=true ;; *) echo "usage: $0 h1|h2"; exit 1 ;; esac
scripts/gen-certs.sh >/dev/null
mkdir -p certs/mitmproxy
exec .venv/bin/mitmdump --listen-host 127.0.0.1 --listen-port "$PORT" \
  --set confdir=certs/mitmproxy \
  --set http2="$H2" --set http3=false \
  --set ssl_verify_upstream_trusted_ca=certs/ca.pem \
  --set flow_detail=0 --quiet
