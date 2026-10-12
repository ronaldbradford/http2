#!/usr/bin/env bash
# Start the HTTPS origin (h2 + http/1.1). Env: PORT N_JS N_IMG N_API DELAY_MIN DELAY_MAX
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/gen-certs.sh >/dev/null
exec node origin/server.js
