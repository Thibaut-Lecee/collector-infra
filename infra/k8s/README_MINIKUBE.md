# Minikube deployment (Kustomize)

This folder provides a minimal, demo-oriented Kubernetes deployment for:

- `collector-front` (Next.js)
- `collector-api` (Fastify + Prisma)
- `postgres`
- `grafana` (dashboards)
- `loki` + `promtail` (centralized logs)
- `prometheus` (scraping `/metrics`, remote-write receiver for k6)

Two Minikube overlays are available:

- `infra/k8s/overlays/minikube`: app + postgres only (expects ZITADEL running on your host)
- `infra/k8s/overlays/minikube-with-zitadel`: app + postgres + ZITADEL (runs ZITADEL inside Minikube)

Ingress (nginx) exposes:

- `https://collector.local` -> frontend
- `https://collector.local/api/*` -> backend API
- `https://collector.local/internal/grafana/*` -> Grafana (via Ingress path routing)
- `https://collector.local/metrics` -> API Prometheus metrics endpoint

Note: Next.js routes under `/api/auth/*` and `/api/userinfo` must stay on the frontend service (NextAuth + userinfo).

## Prerequisites

- `minikube`
- `kubectl`
- `docker`
- `openssl` (for the self-signed TLS cert)

## 1) Start Minikube + enable ingress

```bash
MINIKUBE_PROFILE=collector

minikube start -p "$MINIKUBE_PROFILE" --driver=docker --cpus=4 --memory=4096
minikube addons enable ingress -p "$MINIKUBE_PROFILE"

minikube update-context -p "$MINIKUBE_PROFILE"
kubectl config use-context "$MINIKUBE_PROFILE"
```

## 1b) Start ZITADEL locally (outside Minikube)

If you use `infra/k8s/overlays/minikube`, start only ZITADEL + its database:

```bash
cd infraBloc3
docker compose -f docker-compose.local.yml up -d db-zitadel zitadel
```

Expected endpoints:

- ZITADEL: `http://localhost:8080`
- Console: `http://localhost:8080/ui/console`

If you want ZITADEL inside Minikube, use `infra/k8s/overlays/minikube-with-zitadel` and skip this step.

## 2) Build images (into Minikube)

Option A (recommended): build directly into Minikube's Docker daemon:

```bash
MINIKUBE_PROFILE=collector
eval "$(minikube -p "$MINIKUBE_PROFILE" docker-env)"

docker build -t collector-api:latest --target runner ../collector-api
docker build -t collector-api-migrate:latest --target migrate ../collector-api
docker build -t collector-frontend:latest ../collector-front
```

Option B: build on the host, then load into Minikube:

```bash
docker build -t collector-api:latest --target runner ../collector-api
docker build -t collector-api-migrate:latest --target migrate ../collector-api
docker build -t collector-frontend:latest ../collector-front

MINIKUBE_PROFILE=collector
minikube image load -p "$MINIKUBE_PROFILE" collector-api:latest
minikube image load -p "$MINIKUBE_PROFILE" collector-api-migrate:latest
minikube image load -p "$MINIKUBE_PROFILE" collector-frontend:latest
```

## 3) Configure secrets (placeholders)

Manifests ship with placeholder values (`*.example.yaml`). **Do not commit real secrets**.
For a real demo, apply at least:

- `infra/k8s/base/postgres/secret.example.yaml` (`POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`)
- `infra/k8s/base/api/secret.example.yaml` (`DATABASE_URL`, `ZITADEL_CLIENT_SECRET`)
- `infra/k8s/base/api/configmap.yaml` (`ZITADEL_CLIENT_ID`, `ZITADEL_ISSUER`, `CORS_ORIGIN`)
- `infra/k8s/base/frontend/secret.example.yaml` (`SESSION_SECRET`, `ZITADEL_CLIENT_SECRET`)
- `infra/k8s/base/frontend/configmap.yaml` (`ZITADEL_CLIENT_ID`, `ZITADEL_ISSUER`, `NEXT_PUBLIC_API_URL`)

To keep real values out of git, create local override files (gitignored):

- `infra/k8s/base/postgres/secret.yaml`
- `infra/k8s/base/api/secret.yaml`
- `infra/k8s/base/frontend/secret.yaml`

The Makefile targets (`make minikube-apply-app*`) automatically apply these files if they exist.

Minikube overlay sets:

- `NEXTAUTH_URL=https://collector.local`
- `ZITADEL_INTERNAL_ISSUER=http://host.minikube.internal:8080`

Make sure your ZITADEL instance is reachable on your host at `http://localhost:8080` and that it allows redirect URIs to `https://collector.local/...`.

## 4) TLS (self-signed) + hosts entry

Create the namespace and TLS secret:

```bash
kubectl apply -f infra/k8s/base/namespace.yaml

# Self-signed cert (works for demo, but your browser will not trust it by default).
# SAN is required by modern browsers and we include both local hostnames.
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout collector.key \
  -out collector.crt \
  -subj "/CN=collector.local/O=Collector/C=FR" \
  -addext "subjectAltName=DNS:collector.local,DNS:zitadel.collector.local"

kubectl -n collector create secret tls collector-tls \
  --cert=collector.crt --key=collector.key \
  --dry-run=client -o yaml | kubectl apply -f -

rm -f collector.crt collector.key
```

Or generate + apply the TLS secret via the Makefile (recommended):

```bash
cd infraBloc3
make minikube-cert
```

Note: This is a self-signed certificate. Browsers will show `ERR_CERT_AUTHORITY_INVALID` unless you trust the cert locally.

On macOS (recommended): import the generated cert into Keychain and set it to "Always Trust":

```bash
open infra/k8s/.generated/tls.crt
```

Quick validation (ignores trust): `curl -k https://collector.local/health`.

Add a hosts entry (use `minikube ip`):

```bash
MINIKUBE_PROFILE=collector
echo "$(minikube ip -p "$MINIKUBE_PROFILE") collector.local zitadel.collector.local" | sudo tee -a /etc/hosts
```

If you use the `docker` driver and the Minikube IP is not reachable, run a tunnel in another terminal and map `collector.local` to `127.0.0.1` instead:

```bash
MINIKUBE_PROFILE=collector
minikube tunnel -p "$MINIKUBE_PROFILE"
echo "127.0.0.1 collector.local zitadel.collector.local" | sudo tee -a /etc/hosts
```

## 5) Deploy with Kustomize

```bash
kubectl apply -k infra/k8s/overlays/minikube
# or (includes ZITADEL):
kubectl apply -k infra/k8s/overlays/minikube-with-zitadel
kubectl -n collector get pods
```

Or via the Makefile (recommended):

```bash
cd infraBloc3
make minikube-deploy-app
# or (includes ZITADEL):
make minikube-deploy-app-zitadel
```

If you deployed `minikube-with-zitadel`, access the console at `https://zitadel.collector.local/ui/console`.
Default first-instance credentials (demo):

- login: `zitadel-admin@collector.zitadel.collector.local`
- password: configured in the `zitadel-secret` Kubernetes Secret (see `infra/k8s/overlays/minikube-with-zitadel/zitadel/secret.example.yaml`)

Then create an OIDC application for the frontend:

- Redirect URI: `https://collector.local/api/auth/callback/zitadel`
- Post logout redirect URI: `https://collector.local/api/auth/logout/callback`
- Copy `Client ID` into:
  - `infra/k8s/base/frontend/configmap.yaml` (`ZITADEL_CLIENT_ID`)
  - `infra/k8s/base/api/configmap.yaml` (`ZITADEL_CLIENT_ID`)
- Apply `Client Secret` locally (do not commit secrets):
  - `kubectl -n collector create secret generic collector-front-secret --from-literal=ZITADEL_CLIENT_SECRET='...' --from-literal=SESSION_SECRET='...' --dry-run=client -o yaml | kubectl apply -f -`

Then apply + restart:

```bash
kubectl apply -k infra/k8s/overlays/minikube-with-zitadel
kubectl -n collector rollout restart deployment/collector-front deployment/collector-api
```

The bootstrap job runs once (`collector-api-migrate`) and, on the Minikube overlay, it also seeds demo data. Check it with:

```bash
kubectl -n collector get jobs
kubectl -n collector logs -l app=collector-api-migrate --tail=200
```

## 6) Verify

Frontend health:

```bash
curl -k https://collector.local/health
```

Backend API (returns `204` when empty, or JSON when seeded):

```bash
curl -k https://collector.local/api/v1/articles/findAll -i
```

## 7) Load testing (k6)

Run load tests directly inside the cluster. Results are sent to Prometheus via remote-write, and are visible in Grafana (`k6-overview`).

```bash
cd infraBloc3
make minikube-k6-smoke
make minikube-k6-load
make minikube-k6-stress
```

Note: the **API Logs** dashboard can legitimately show **No data** until you generate traffic (e.g. with one of the k6 targets above).

## Troubleshooting

If `kubectl apply` fails with:

- `failed calling webhook "validate.nginx.ingress.kubernetes.io"... no route to host`

This is usually a transient ingress-nginx admission issue (addon starting/restarting). Wait a few seconds and retry, or run:

```bash
cd infraBloc3
make minikube-wait-ingress
make minikube-apply-app-zitadel
```

If login redirects to ZITADEL and shows:

- `{"error":"invalid_request","error_description":"Errors.App.NotFound"}`

It means the `client_id` sent by the frontend does not match any ZITADEL application (often because `ZITADEL_CLIENT_ID` is still `replace-me`).
Create an OIDC Web app in the ZITADEL console and copy its `Client ID` + `Client Secret` into the frontend `ConfigMap`/`Secret`, then restart the frontend pod.

## Cleanup

```bash
kubectl delete namespace collector --ignore-not-found
```
