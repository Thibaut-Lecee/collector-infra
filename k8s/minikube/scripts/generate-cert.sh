#!/bin/bash
set -euo pipefail

echo "🔐 Generating self-signed TLS certificate for collector.local and zitadel.collector.local..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MINIKUBE_DIR="$(dirname "$SCRIPT_DIR")"
TEMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

cd "$TEMP_DIR"

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key \
  -out tls.crt \
  -subj "/CN=collector.local/O=Collector/C=FR" \
  -addext "subjectAltName=DNS:collector.local,DNS:zitadel.collector.local"

TLS_CRT="$(base64 < tls.crt | tr -d '\n')"
TLS_KEY="$(base64 < tls.key | tr -d '\n')"

cat > "$MINIKUBE_DIR/ingress/tls-secret.yaml" <<EOF
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

echo "✅ TLS secret updated at $MINIKUBE_DIR/ingress/tls-secret.yaml"
