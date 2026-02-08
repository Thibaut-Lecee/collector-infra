# collector-infra

Infra repository for local development (`docker-compose`) and Kubernetes local deployment (`minikube`).

## Structure

- `docker-compose.local.yml`: complete local stack (db, zitadel, api, frontend, loki, promtail, grafana, prometheus)
- `k8s/minikube/`: Kubernetes manifests (single source of truth for Minikube)
- `k8s/minikube/scripts/`: cert + deploy scripts
- `Makefile`: shortcuts for local and minikube workflows

## Local development (Docker)

```bash
cd infraBloc3
make dev-up
make dev-status
```

Main endpoints:

- Frontend: `http://localhost:3000`
- API health: `http://localhost:3001/health`
- Zitadel: `http://localhost:8080`
- Grafana: `http://localhost:3002/`
- Prometheus: `http://localhost:9090`

Stop stack:

```bash
make dev-down
```

Load testing (k6):

```bash
make k6-smoke
make k6-load
make k6-stress
```

Dashboards (Grafana):

- API metrics: `http://localhost:3002/d/api-metrics/api-metrics`
- k6 overview: `http://localhost:3002/d/k6-overview/k6-overview`

## Minikube deployment

```bash
cd infraBloc3
cp k8s/minikube/postgres/secret.example.yaml k8s/minikube/postgres/secret.yaml
cp k8s/minikube/api/secret.example.yaml k8s/minikube/api/secret.yaml
cp k8s/minikube/frontend/secret.example.yaml k8s/minikube/frontend/secret.yaml
cp k8s/minikube/zitadel/secret.example.yaml k8s/minikube/zitadel/secret.yaml

make minikube-deploy
```

Then add hosts:

```bash
echo "$(minikube ip) collector.local zitadel.collector.local" | sudo tee -a /etc/hosts
```

Endpoints:

- Frontend: `https://collector.local`
- API health: `https://collector.local/health`
- Zitadel: `https://zitadel.collector.local`

See `k8s/minikube/README.md` for details.
