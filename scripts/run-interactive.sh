#!/usr/bin/env bash
# Start the origin (:8443) and both TLS-inspecting proxies (:8080 h1, :8081 h2).
# Binds LISTEN_HOST (default 0.0.0.0) so a published Docker port is reachable from the host.
set -euo pipefail
cd "$(dirname "$0")/.."
export LISTEN_HOST="${LISTEN_HOST:-0.0.0.0}"
mkdir -p logs
scripts/gen-certs.sh >/dev/null

pids=()
cleanup() {
  trap - EXIT INT TERM
  for p in "${pids[@]+"${pids[@]}"}"; do kill "$p" 2>/dev/null || true; done
  wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

scripts/run-origin.sh >logs/origin.log 2>&1 & pids+=($!)
scripts/run-proxy.sh h1 >logs/proxy-h1.log 2>&1 & pids+=($!)
PROXY_PORT=8081 scripts/run-proxy.sh h2 >logs/proxy-h2.log 2>&1 & pids+=($!)

for port in 8443 8080 8081; do
  ok=0
  for _ in $(seq 50); do
    if (exec 3<>/dev/tcp/127.0.0.1/"$port") 2>/dev/null; then ok=1; break; fi
    sleep 0.2
  done
  if [ "$ok" != 1 ]; then
    echo "port $port did not open; logs:" >&2
    echo "----- origin -----"; cat logs/origin.log >&2 || true
    echo "----- proxy-h1 -----"; cat logs/proxy-h1.log >&2 || true
    echo "----- proxy-h2 -----"; cat logs/proxy-h2.log >&2 || true
    exit 1
  fi
done

spki() {
  openssl x509 -in "$1" -pubkey -noout \
    | openssl pkey -pubin -outform der \
    | openssl dgst -sha256 -binary \
    | openssl enc -base64
}
SPKI="$(spki certs/origin.pem),$(spki certs/mitmproxy/mitmproxy-ca-cert.pem)"

cat <<EOF
Origin and both proxies are listening on ${LISTEN_HOST}.
  https://localhost:8443/     origin (ALPN h2, http/1.1)
  8080                        TLS-inspecting proxy, HTTP/1.1 only
  8081                        TLS-inspecting proxy, HTTP/2 enabled

Publish 8443, 8080 and 8081. On the host, keep the page URL as
https://localhost:8443/ and point Chrome at the published proxy with
--proxy-bypass-list=<-loopback> so loopback is not exempt from the proxy.

Certs were generated at start (not stored in the image):
  /app/certs/ca.pem
  /app/certs/mitmproxy/mitmproxy-ca-cert.pem
Copy them out to import, or pass the SPKI list below with a throwaway
--user-data-dir. From the repo, after copying certs onto the host:
  rm -rf certs && docker cp <container>:/app/certs ./certs
  scripts/chrome.sh direct
  scripts/chrome.sh proxy-h1
  scripts/chrome.sh proxy-h2

Direct:
  google-chrome --user-data-dir=/tmp/h2demo-direct --no-first-run --no-default-browser-check --disable-quic --ignore-certificate-errors-spki-list='${SPKI}' https://localhost:8443/

proxy-h1 (the downgrade):
  google-chrome --user-data-dir=/tmp/h2demo-h1 --no-first-run --no-default-browser-check --disable-quic --ignore-certificate-errors-spki-list='${SPKI}' --proxy-server=http://127.0.0.1:8080 --proxy-bypass-list='<-loopback>' https://localhost:8443/

proxy-h2 (HTTP/2 left on):
  google-chrome --user-data-dir=/tmp/h2demo-h2 --no-first-run --no-default-browser-check --disable-quic --ignore-certificate-errors-spki-list='${SPKI}' --proxy-server=http://127.0.0.1:8081 --proxy-bypass-list='<-loopback>' https://localhost:8443/
EOF

# Stay in the foreground until one of the servers exits or the container is stopped.
wait -n
status=$?
cleanup
exit "$status"
