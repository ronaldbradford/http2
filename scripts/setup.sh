#!/usr/bin/env bash
# One-time setup: python venv (mitmproxy, playwright, matplotlib) + certs.
set -euo pipefail
cd "$(dirname "$0")/.."
if command -v uv >/dev/null; then
  [ -d .venv ] || uv venv -q .venv
  uv pip install -q --python .venv/bin/python -r requirements.txt
else
  [ -d .venv ] || python3 -m venv .venv
  .venv/bin/pip install -q -r requirements.txt
fi
scripts/gen-certs.sh
# Generate the mitmproxy CA once so it can be trusted/inspected before first use
if [ ! -f certs/mitmproxy/mitmproxy-ca-cert.pem ]; then
  mkdir -p certs/mitmproxy
  .venv/bin/mitmdump --set confdir=certs/mitmproxy --listen-port 0 -n -q >/dev/null 2>&1 & p=$!; sleep 3; kill $p 2>/dev/null || true
fi
ls certs/mitmproxy/mitmproxy-ca-cert.pem
# Chrome: uses system google-chrome/chromium if found, else: .venv/bin/playwright install chromium
