# Minikube Deployment Guide

## Prerequisites

- `minikube`
- `kubectl`
- `docker`
- `openssl`

Recommended Minikube profile:

```bash
minikube start --driver=docker --cpus=4 --memory=4096
```

## Automated deployment

```bash
cd infraBloc3
cp k8s/minikube/postgres/secret.example.yaml k8s/minikube/postgres/secret.yaml
cp k8s/minikube/api/secret.example.yaml k8s/minikube/api/secret.yaml
cp k8s/minikube/frontend/secret.example.yaml k8s/minikube/frontend/secret.yaml
cp k8s/minikube/zitadel/secret.example.yaml k8s/minikube/zitadel/secret.yaml

make minikube-deploy
```

This command:

1. starts Minikube (if needed)
2. enables ingress addon
3. builds `collector-api` (runtime) + `collector-api-migrate` (Prisma job) + `collector-frontend` images in Minikube Docker daemon
4. generates TLS cert secret
5. applies `k8s/minikube` manifests with Kustomize
6. runs Prisma migration job
7. waits for pods readiness

## DNS / hosts setup

```bash
echo "$(minikube ip) collector.local zitadel.collector.local" | sudo tee -a /etc/hosts
```

## Validation

```bash
kubectl get pods -n collector
curl -k https://collector.local/health
```

Expected health response:

```json
{"status":"ok"}
```

## Key files

- `k8s/minikube/kustomization.yaml`
- `k8s/minikube/api/*`
- `k8s/minikube/frontend/*`
- `k8s/minikube/postgres/*`
- `k8s/minikube/zitadel/*`
- `k8s/minikube/ingress/*`
- `k8s/minikube/scripts/deploy.sh`

## Troubleshooting

Check pods and events:

```bash
kubectl get all -n collector
kubectl get events -n collector --sort-by='.lastTimestamp'
```

Check logs:

```bash
kubectl logs -f -l app=api -n collector
kubectl logs -f -l app=frontend -n collector
kubectl logs -f -l app=zitadel -n collector
```

Re-run migrations:

```bash
kubectl delete job prisma-migrate -n collector --ignore-not-found
kubectl apply -f k8s/minikube/api/migrate-job.yaml
kubectl wait --for=condition=complete job/prisma-migrate -n collector --timeout=300s
```

## Cleanup

```bash
make minikube-delete
```
