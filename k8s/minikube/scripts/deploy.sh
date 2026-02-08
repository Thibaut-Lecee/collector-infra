#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MINIKUBE_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$(dirname "$MINIKUBE_DIR")")"
API_DIR="$PROJECT_DIR/../collector-api"
FRONTEND_DIR="$PROJECT_DIR/../collector-front"

echo "🚀 Deploying collector stack to Minikube"

require_secret_file() {
  local secret_file="$1"
  local example_file="${secret_file%.yaml}.example.yaml"

  if [ ! -f "$secret_file" ]; then
    echo ""
    echo "✗ Missing required secret manifest: $secret_file"
    if [ -f "$example_file" ]; then
      echo "  Create it from template:"
      echo "  cp \"$example_file\" \"$secret_file\""
      echo "  Then edit \"$secret_file\" with real values (do not commit it)."
    fi
    echo ""
    exit 1
  fi
}

require_secret_file "$MINIKUBE_DIR/postgres/secret.yaml"
require_secret_file "$MINIKUBE_DIR/api/secret.yaml"
require_secret_file "$MINIKUBE_DIR/frontend/secret.yaml"
require_secret_file "$MINIKUBE_DIR/zitadel/secret.yaml"

if ! minikube status >/dev/null 2>&1; then
  echo "▶ Starting Minikube..."
  minikube start --driver=docker --cpus=4 --memory=4096
else
  echo "▶ Minikube already running"
fi

echo "▶ Enabling ingress addon..."
minikube addons enable ingress >/dev/null

echo "▶ Building API images in Minikube daemon..."
eval "$(minikube docker-env)"
docker build -t collector-api:latest --target runner "$API_DIR"
docker build -t collector-api-migrate:latest --target migrate "$API_DIR"

echo "▶ Building frontend image in Minikube daemon..."
docker build -t collector-frontend:latest "$FRONTEND_DIR"

echo "▶ Generating TLS secret..."
"$SCRIPT_DIR/generate-cert.sh"

echo "▶ Creating namespace..."
kubectl apply -f "$MINIKUBE_DIR/namespace.yaml"

echo "▶ Applying secrets..."
kubectl apply -f "$MINIKUBE_DIR/postgres/secret.yaml"
kubectl apply -f "$MINIKUBE_DIR/api/secret.yaml"
kubectl apply -f "$MINIKUBE_DIR/frontend/secret.yaml"
kubectl apply -f "$MINIKUBE_DIR/zitadel/secret.yaml"
kubectl apply -f "$MINIKUBE_DIR/ingress/tls-secret.yaml"

echo "▶ Applying Kubernetes manifests..."
kubectl apply -k "$MINIKUBE_DIR"

echo "▶ Waiting for PostgreSQL..."
kubectl rollout status statefulset/postgres -n collector --timeout=300s
kubectl rollout status statefulset/zitadel-postgres -n collector --timeout=300s

echo "▶ Running database migrations..."
kubectl delete job prisma-migrate -n collector --ignore-not-found=true
kubectl apply -f "$MINIKUBE_DIR/api/migrate-job.yaml"
kubectl wait --for=condition=complete job/prisma-migrate -n collector --timeout=300s

echo "▶ Waiting for app deployments..."
kubectl rollout status deployment/zitadel -n collector --timeout=300s
kubectl rollout status deployment/api -n collector --timeout=300s
kubectl rollout status deployment/frontend -n collector --timeout=300s

MINIKUBE_IP="$(minikube ip)"

echo ""
echo "✅ Deployment complete"
echo ""
echo "Add this line to /etc/hosts (if missing):"
echo "$MINIKUBE_IP collector.local zitadel.collector.local"
echo ""
echo "Access:"
echo "- Frontend: https://collector.local"
echo "- API health: https://collector.local/health"
echo "- Zitadel: https://zitadel.collector.local"
echo ""
kubectl get pods -n collector
