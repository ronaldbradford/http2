#!/usr/bin/env bash
# Open a real (headed) Chrome with a throwaway profile against one mode, so you can look at DevTools.
#   scripts/chrome.sh direct|proxy-h1|proxy-h2      (start run-origin.sh / run-proxy.sh first)
# Env: CHROME=/path/to/chrome   NETLOG=/tmp/x.json (also write a netlog)   URL=https://localhost:8443/
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-direct}"; URL="${URL:-https://localhost:8443/}"
CHROME="${CHROME:-$(command -v google-chrome || command -v google-chrome-stable || command -v chromium || command -v chromium-browser || true)}"
[ -z "$CHROME" ] && [ -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ] && CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -z "$CHROME" ] && { echo "set CHROME=/path/to/chrome"; exit 1; }
spki() { openssl x509 -in "$1" -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64; }
SPKI="$(spki certs/origin.pem),$(spki certs/mitmproxy/mitmproxy-ca-cert.pem)"
PROFILE="$(mktemp -d /tmp/h2demo-chrome.XXXXXX)"
args=(--user-data-dir="$PROFILE" --no-first-run --no-default-browser-check --disable-quic
      --ignore-certificate-errors-spki-list="$SPKI" --auto-open-devtools-for-tabs)
case "$MODE" in
  direct)   ;;
  proxy-h1) args+=(--proxy-server=http://127.0.0.1:8080 "--proxy-bypass-list=<-loopback>") ;;
  proxy-h2) args+=(--proxy-server=http://127.0.0.1:8081 "--proxy-bypass-list=<-loopback>") ;;
  *) echo "usage: $0 direct|proxy-h1|proxy-h2"; exit 1 ;;
esac
[ -n "${NETLOG:-}" ] && args+=(--log-net-log="$NETLOG" --net-log-capture-mode=Everything)
echo "profile: $PROFILE"; exec "$CHROME" "${args[@]}" "$URL"
