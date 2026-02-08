# Minikube Scripts

## `generate-cert.sh`

Generates a self-signed certificate for:

- `collector.local`
- `zitadel.collector.local`

and rewrites `k8s/minikube/ingress/tls-secret.yaml`.

That generated file is gitignored. The committed template is `tls-secret.example.yaml`.

## `deploy.sh`

Performs an end-to-end local Minikube deployment:

1. Starts Minikube (if needed)
2. Enables ingress addon
3. Builds `collector-api` (runtime) + `collector-api-migrate` (Prisma job) + `collector-frontend` images in Minikube Docker daemon
4. Applies required secrets (local-only)
5. Generates and applies TLS secret
6. Applies manifests from `k8s/minikube` (Kustomize)
7. Runs Prisma migration job
8. Waits for deployments to become ready

Required local secret manifests (gitignored, create from `*.example.yaml`):

- `k8s/minikube/postgres/secret.yaml`
- `k8s/minikube/api/secret.yaml`
- `k8s/minikube/frontend/secret.yaml`
- `k8s/minikube/zitadel/secret.yaml`
