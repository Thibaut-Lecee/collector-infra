LOCAL_COMPOSE := ./docker-compose.local.yml
K8S_DIR := ./infra/k8s
K8S_SCRIPTS_DIR := $(K8S_DIR)/scripts
K8S_TLS_SECRET_MANIFEST := $(K8S_DIR)/.generated/tls-secret.yaml
K8S_K6_DIR := $(K8S_DIR)/observability/k6
K8S_K6_SCRIPTS_DIR := $(K8S_K6_DIR)/scripts
MINIKUBE_APP_DIR := $(K8S_DIR)/overlays/minikube
MINIKUBE_APP_ZITADEL_DIR := $(K8S_DIR)/overlays/minikube-with-zitadel
API_DIR := ../collector-api
FRONTEND_DIR := ../collector-front
MINIKUBE_PROFILE ?= collector
export MINIKUBE_PROFILE
MINIKUBE := minikube -p $(MINIKUBE_PROFILE)

.PHONY: dev-up dev-down dev-restart dev-status dev-logs \
		k6-smoke k6-load k6-stress \
		minikube-k6-scripts minikube-k6-smoke minikube-k6-load minikube-k6-stress \
		minikube-start minikube-context minikube-wait-ingress minikube-stop \
		minikube-cert minikube-build-api minikube-build-frontend minikube-build \
		minikube-apply-app minikube-apply-app-zitadel minikube-delete minikube-deploy-app minikube-deploy-app-zitadel minikube-status \
		minikube-logs-api-app minikube-logs-frontend-app minikube-logs-zitadel-app

dev-up:
	docker compose -f $(LOCAL_COMPOSE) up -d

dev-down:
	docker compose -f $(LOCAL_COMPOSE) down

dev-restart:
	docker compose -f $(LOCAL_COMPOSE) down
	docker compose -f $(LOCAL_COMPOSE) up -d

dev-status:
	docker compose -f $(LOCAL_COMPOSE) ps

dev-logs:
	docker compose -f $(LOCAL_COMPOSE) logs -f --tail=100

k6-smoke:
	docker compose -f $(LOCAL_COMPOSE) --profile tools run --rm k6 run -o experimental-prometheus-rw /scripts/smoke.js

k6-load:
	docker compose -f $(LOCAL_COMPOSE) --profile tools run --rm k6 run -o experimental-prometheus-rw /scripts/load.js

k6-stress:
	docker compose -f $(LOCAL_COMPOSE) --profile tools run --rm k6 run -o experimental-prometheus-rw /scripts/stress.js

minikube-k6-scripts: minikube-context
	@kubectl -n collector create configmap k6-scripts \
		--from-file=$(K8S_K6_SCRIPTS_DIR) \
		--dry-run=client -o yaml | kubectl apply -f -

minikube-k6-smoke: minikube-k6-scripts
	@bash $(K8S_SCRIPTS_DIR)/run-k6-job.sh k6-smoke $(K8S_K6_DIR)/job-smoke.yaml

minikube-k6-load: minikube-k6-scripts
	@bash $(K8S_SCRIPTS_DIR)/run-k6-job.sh k6-load $(K8S_K6_DIR)/job-load.yaml

minikube-k6-stress: minikube-k6-scripts
	@bash $(K8S_SCRIPTS_DIR)/run-k6-job.sh k6-stress $(K8S_K6_DIR)/job-stress.yaml

minikube-start:
	@$(MINIKUBE) start --driver=docker --cpus=4 --memory=4096
	@$(MINIKUBE) addons enable ingress >/dev/null
	@$(MINIKUBE) update-context >/dev/null
	@kubectl config use-context $(MINIKUBE_PROFILE) >/dev/null
	@$(MAKE) minikube-wait-ingress

minikube-context:
	@$(MINIKUBE) update-context >/dev/null
	@kubectl config use-context $(MINIKUBE_PROFILE) >/dev/null

minikube-wait-ingress: minikube-context
	@echo "▶ Waiting for ingress-nginx..."
	@kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=300s
	@i=0; \
	while [ $$i -lt 60 ]; do \
		ep=$$(kubectl -n ingress-nginx get endpoints ingress-nginx-controller-admission -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || true); \
		if [ -n "$$ep" ]; then \
			echo "✅ Ingress admission webhook is reachable"; \
			exit 0; \
		fi; \
		i=$$((i+1)); \
		sleep 2; \
	done; \
	echo "❌ Ingress admission webhook is not ready"; \
	kubectl -n ingress-nginx get pods,svc,endpoints || true; \
	exit 1

minikube-stop:
	@$(MINIKUBE) stop

minikube-cert: minikube-context
	@bash $(K8S_SCRIPTS_DIR)/generate-cert.sh
	kubectl apply -f $(K8S_TLS_SECRET_MANIFEST)

minikube-build-api:
	@eval "$$($(MINIKUBE) docker-env)" && \
		docker build -t collector-api:latest --target runner $(API_DIR) && \
		docker build -t collector-api-migrate:latest --target migrate $(API_DIR)

minikube-build-frontend:
	@eval "$$($(MINIKUBE) docker-env)" && docker build -t collector-frontend:latest $(FRONTEND_DIR)

minikube-build: minikube-build-api minikube-build-frontend

minikube-apply-app: minikube-context
	@$(MINIKUBE) addons enable ingress >/dev/null || true
	@$(MAKE) minikube-wait-ingress
	kubectl apply -f ./infra/k8s/base/namespace.yaml
	@$(MAKE) minikube-cert
	kubectl delete job collector-api-migrate -n collector --ignore-not-found=true
	@attempt=1; \
	while true; do \
		if kubectl apply -k $(MINIKUBE_APP_DIR); then break; fi; \
		if [ $$attempt -ge 5 ]; then echo "❌ kubectl apply failed after $$attempt attempts"; exit 1; fi; \
		echo "⚠️  kubectl apply failed (ingress webhook can be flaky). Retrying in 5s..."; \
		$(MAKE) minikube-wait-ingress; \
		attempt=$$((attempt+1)); \
		sleep 5; \
	done
	@# Optional local overrides (gitignored): infra/k8s/base/**/secret.yaml
	@if [ -f $(K8S_DIR)/base/postgres/secret.yaml ]; then kubectl -n collector apply -f $(K8S_DIR)/base/postgres/secret.yaml; fi
	@if [ -f $(K8S_DIR)/base/api/secret.yaml ]; then kubectl -n collector apply -f $(K8S_DIR)/base/api/secret.yaml; fi
	@if [ -f $(K8S_DIR)/base/frontend/secret.yaml ]; then kubectl -n collector apply -f $(K8S_DIR)/base/frontend/secret.yaml; fi
	kubectl wait --for=condition=complete job/collector-api-migrate -n collector --timeout=300s || (kubectl -n collector logs -l app=collector-api-migrate --tail=200 || true; exit 1)
	kubectl rollout restart deployment/collector-api -n collector || true
	kubectl rollout restart deployment/collector-front -n collector || true

minikube-apply-app-zitadel: minikube-context
	@$(MINIKUBE) addons enable ingress >/dev/null || true
	@$(MAKE) minikube-wait-ingress
	kubectl apply -f ./infra/k8s/base/namespace.yaml
	@$(MAKE) minikube-cert
	kubectl delete job collector-api-migrate -n collector --ignore-not-found=true
	@attempt=1; \
	while true; do \
		if kubectl apply -k $(MINIKUBE_APP_ZITADEL_DIR); then break; fi; \
		if [ $$attempt -ge 5 ]; then echo "❌ kubectl apply failed after $$attempt attempts"; exit 1; fi; \
		echo "⚠️  kubectl apply failed (ingress webhook can be flaky). Retrying in 5s..."; \
		$(MAKE) minikube-wait-ingress; \
		attempt=$$((attempt+1)); \
		sleep 5; \
	done
	@# Optional local overrides (gitignored): infra/k8s/base/**/secret.yaml
	@if [ -f $(K8S_DIR)/base/postgres/secret.yaml ]; then kubectl -n collector apply -f $(K8S_DIR)/base/postgres/secret.yaml; fi
	@if [ -f $(K8S_DIR)/base/api/secret.yaml ]; then kubectl -n collector apply -f $(K8S_DIR)/base/api/secret.yaml; fi
	@if [ -f $(K8S_DIR)/base/frontend/secret.yaml ]; then kubectl -n collector apply -f $(K8S_DIR)/base/frontend/secret.yaml; fi
	@# Optional local override (gitignored): infra/k8s/overlays/minikube-with-zitadel/zitadel/secret.yaml
	@if [ -f $(MINIKUBE_APP_ZITADEL_DIR)/zitadel/secret.yaml ]; then kubectl -n collector apply -f $(MINIKUBE_APP_ZITADEL_DIR)/zitadel/secret.yaml; fi
	kubectl wait --for=condition=complete job/collector-api-migrate -n collector --timeout=300s || (kubectl -n collector logs -l app=collector-api-migrate --tail=200 || true; exit 1)
	kubectl rollout restart deployment/collector-api -n collector || true
	kubectl rollout restart deployment/collector-front -n collector || true
	kubectl rollout status statefulset/zitadel-postgres -n collector --timeout=300s
	kubectl rollout status deployment/zitadel -n collector --timeout=300s

minikube-delete: minikube-context
	kubectl delete namespace collector --ignore-not-found

minikube-deploy-app: minikube-start minikube-build minikube-apply-app

minikube-deploy-app-zitadel: minikube-start minikube-build minikube-apply-app-zitadel

minikube-status:
	kubectl get all -n collector

minikube-logs-api-app:
	kubectl logs -f -l app=collector-api -n collector --tail=100

minikube-logs-frontend-app:
	kubectl logs -f -l app=collector-front -n collector --tail=100

minikube-logs-zitadel-app:
	kubectl logs -f -l app=zitadel -n collector --tail=100
