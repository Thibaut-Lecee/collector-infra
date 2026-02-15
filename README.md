# collector-infra

Infra repository for local development (`docker-compose`) and Kubernetes local deployment (`minikube`).

## Structure

- `docker-compose.local.yml`: complete local stack (db, zitadel, api, frontend, loki, promtail, grafana, prometheus)
- `infra/k8s/`: Kubernetes manifests (Kustomize) for local Minikube deployment
- `Makefile`: shortcuts for local and minikube workflows

## Local development (Docker)

```bash
cd infraBloc3
cp .env.example .env
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
make minikube-deploy-app
# or (includes ZITADEL inside Minikube):
make minikube-deploy-app-zitadel
```

Load testing (k6, runs inside the cluster and remote-writes to Prometheus):

```bash
make minikube-k6-smoke
make minikube-k6-load
make minikube-k6-stress
```

Then add hosts (see the docs for tunnel vs minikube ip):

```bash
echo "127.0.0.1 collector.local zitadel.collector.local" | sudo tee -a /etc/hosts
```

Endpoints:

- Frontend: `https://collector.local`
- API health: `https://collector.local/health`
- Grafana (proxied): `https://collector.local/internal/grafana/`
- API metrics: `https://collector.local/metrics`
- Zitadel: `https://zitadel.collector.local`

See `infra/k8s/README_MINIKUBE.md` for details.
