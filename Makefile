LOCAL_COMPOSE := ./docker-compose.local.yml
MINIKUBE_DIR := ./k8s/minikube
API_DIR := ../collector-api
FRONTEND_DIR := ../collector-front

.PHONY: dev-up dev-down dev-restart dev-status dev-logs \
		k6-smoke k6-load k6-stress \
		minikube-cert minikube-build-api minikube-build-frontend minikube-build \
		minikube-apply minikube-delete minikube-deploy minikube-status \
		minikube-logs-api minikube-logs-frontend

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

minikube-cert:
	@cd $(MINIKUBE_DIR)/scripts && ./generate-cert.sh

minikube-build-api:
	@eval "$$(minikube docker-env)" && \
		docker build -t collector-api:latest --target runner $(API_DIR) && \
		docker build -t collector-api-migrate:latest --target migrate $(API_DIR)

minikube-build-frontend:
	@eval "$$(minikube docker-env)" && docker build -t collector-frontend:latest $(FRONTEND_DIR)

minikube-build: minikube-build-api minikube-build-frontend

minikube-apply:
	kubectl apply -f $(MINIKUBE_DIR)/namespace.yaml
	kubectl apply -f $(MINIKUBE_DIR)/postgres/secret.yaml
	kubectl apply -f $(MINIKUBE_DIR)/api/secret.yaml
	kubectl apply -f $(MINIKUBE_DIR)/frontend/secret.yaml
	kubectl apply -f $(MINIKUBE_DIR)/zitadel/secret.yaml
	kubectl apply -f $(MINIKUBE_DIR)/ingress/tls-secret.yaml
	kubectl apply -k $(MINIKUBE_DIR)

minikube-delete:
	kubectl delete namespace collector --ignore-not-found

minikube-deploy:
	@cd $(MINIKUBE_DIR)/scripts && ./deploy.sh

minikube-status:
	kubectl get all -n collector

minikube-logs-api:
	kubectl logs -f -l app=api -n collector --tail=100

minikube-logs-frontend:
	kubectl logs -f -l app=frontend -n collector --tail=100
