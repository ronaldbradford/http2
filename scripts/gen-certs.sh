#!/usr/bin/env bash
# Generate a throwaway local CA + origin server cert (localhost / 127.0.0.1).
set -euo pipefail
cd "$(dirname "$0")/../certs"
[ -f origin.pem ] && { echo "certs exist (rm certs/* to regenerate)"; exit 0; }
openssl req -x509 -newkey rsa:2048 -nodes -days 825 -subj "/CN=H2 Demo Origin CA" \
  -keyout ca.key -out ca.pem -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null
openssl req -newkey rsa:2048 -nodes -subj "/CN=localhost" -keyout origin.key -out origin.csr 2>/dev/null
printf "subjectAltName=DNS:localhost,IP:127.0.0.1\nextendedKeyUsage=serverAuth\nbasicConstraints=CA:FALSE\n" > ext.cnf
openssl x509 -req -in origin.csr -CA ca.pem -CAkey ca.key -CAcreateserial -days 825 -extfile ext.cnf -out origin.pem 2>/dev/null
rm -f origin.csr ext.cnf
echo "created certs/ca.pem (origin CA) and certs/origin.{pem,key}"
