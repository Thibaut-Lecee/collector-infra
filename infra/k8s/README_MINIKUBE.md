# Minikube deployment (Kustomize)

This folder provides a minimal, demo-oriented Kubernetes deployment for:

- `collector-front` (Next.js)
- `collector-api` (Fastify + Prisma)
- `postgres`

Ingress (nginx) exposes:

- `https://collector.local` -> frontend
- `https://collector.local/api/*` -> backend API

Note: Next.js routes under `/api/auth/*` and `/api/userinfo` must stay on the frontend service (NextAuth + userinfo).

## Prerequisites

- `minikube`
- `kubectl`
- `docker`
- `openssl` (for the self-signed TLS cert)

## 1) Start Minikube + enable ingress

```bash
minikube start --driver=docker --cpus=4 --memory=4096
minikube addons enable ingress
```

## 2) Build images (into Minikube)

Option A (recommended): build directly into Minikube's Docker daemon:

```bash
eval "$(minikube -p minikube docker-env)"

docker build -t collector-api:latest --target runner ../collector-api
docker build -t collector-api-migrate:latest --target migrate ../collector-api
docker build -t collector-frontend:latest ../collector-front
```

Option B: build on the host, then load into Minikube:

```bash
docker build -t collector-api:latest --target runner ../collector-api
docker build -t collector-api-migrate:latest --target migrate ../collector-api
docker build -t collector-frontend:latest ../collector-front

minikube image load collector-api:latest
minikube image load collector-api-migrate:latest
minikube image load collector-frontend:latest
```

## 3) Configure secrets (placeholders)

Manifests ship with placeholder values. For a real demo, update at least:

- `infra/k8s/base/postgres/secret.yaml` (`POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`)
- `infra/k8s/base/api/secret.yaml` (`DATABASE_URL`, `ZITADEL_CLIENT_SECRET`)
- `infra/k8s/base/api/configmap.yaml` (`ZITADEL_CLIENT_ID`, `ZITADEL_ISSUER`, `CORS_ORIGIN`)
- `infra/k8s/base/frontend/secret.yaml` (`SESSION_SECRET`, `ZITADEL_CLIENT_SECRET`)
- `infra/k8s/base/frontend/configmap.yaml` (`ZITADEL_CLIENT_ID`, `ZITADEL_ISSUER`, `NEXT_PUBLIC_API_URL`)

Minikube overlay sets:

- `NEXTAUTH_URL=https://collector.local`
- `ZITADEL_INTERNAL_ISSUER=http://host.minikube.internal:8080`

Make sure your ZITADEL instance is reachable on your host at `http://localhost:8080` and that it allows redirect URIs to `https://collector.local/...`.

## 4) TLS (self-signed) + hosts entry

Create the namespace and TLS secret:

```bash
kubectl apply -f infra/k8s/base/namespace.yaml

openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout collector.key -out collector.crt \
  -subj "/CN=collector.local"

kubectl -n collector create secret tls collector-tls \
  --cert=collector.crt --key=collector.key \
  --dry-run=client -o yaml | kubectl apply -f -

rm -f collector.crt collector.key
```

Add a hosts entry (use `minikube ip`):

```bash
echo "$(minikube ip) collector.local" | sudo tee -a /etc/hosts
```

If you use the `docker` driver and the Minikube IP is not reachable, run a tunnel in another terminal and map `collector.local` to `127.0.0.1` instead:

```bash
minikube tunnel
echo "127.0.0.1 collector.local" | sudo tee -a /etc/hosts
```

## 5) Deploy with Kustomize

```bash
kubectl apply -k infra/k8s/overlays/minikube
kubectl -n collector get pods
```

The migration job runs once (`collector-api-migrate`). Check it with:

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

## Cleanup

```bash
kubectl delete namespace collector --ignore-not-found
```
