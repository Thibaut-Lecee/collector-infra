#!/bin/bash
set -euo pipefail

echo "Generating self-signed TLS certificate for collector.local and zitadel.collector.local..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

OUTPUT_DIR="${OUTPUT_DIR:-$K8S_DIR/.generated}"
OUTPUT_FILE="${OUTPUT_FILE:-$OUTPUT_DIR/tls-secret.yaml}"
CERT_FILE="${CERT_FILE:-$OUTPUT_DIR/tls.crt}"
KEY_FILE="${KEY_FILE:-$OUTPUT_DIR/tls.key}"

TEMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"
cd "$TEMP_DIR"

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key \
  -out tls.crt \
  -subj "/CN=collector.local/O=Collector/C=FR" \
  -addext "subjectAltName=DNS:collector.local,DNS:zitadel.collector.local"

TLS_CRT="$(base64 < tls.crt | tr -d '\n')"
TLS_KEY="$(base64 < tls.key | tr -d '\n')"

cp tls.crt "$CERT_FILE"
cp tls.key "$KEY_FILE"

cat >"$OUTPUT_FILE" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: collector-tls
  namespace: collector
type: kubernetes.io/tls
data:
  tls.crt: $TLS_CRT
  tls.key: $TLS_KEY
EOF

echo "TLS secret manifest written to $OUTPUT_FILE"
echo "TLS certificate written to $CERT_FILE"
