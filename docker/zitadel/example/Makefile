SHELL := /bin/bash

VENDOR_DIR  := .
SECRETS_DIR := .secrets

COMPOSE := ./docker-compose.yaml
MASTERKEY_FILE := $(SECRETS_DIR)/zitadel-masterkey

.PHONY: zitadel-init zitadel-up zitadel-down zitadel-logs zitadel-reset

## Télécharge les fichiers d'exemple Zitadel (une seule fois) + génère la masterkey
zitadel-init:
	mkdir -p $(VENDOR_DIR) $(SECRETS_DIR)
	@if [ ! -f $(VENDOR_DIR)/docker-compose.yaml ]; then \
		echo "Downloading Zitadel example files..."; \
		curl -sSL https://raw.githubusercontent.com/zitadel/zitadel/main/docs/docs/self-hosting/manage/configure/docker-compose.yaml \
			-o $(VENDOR_DIR)/docker-compose.yaml; \
		curl -sSL https://raw.githubusercontent.com/zitadel/zitadel/main/docs/docs/self-hosting/manage/configure/example-zitadel-config.yaml \
			-o $(VENDOR_DIR)/example-zitadel-config.yaml; \
		curl -sSL https://raw.githubusercontent.com/zitadel/zitadel/main/docs/docs/self-hosting/manage/configure/example-zitadel-secrets.yaml \
			-o $(VENDOR_DIR)/example-zitadel-secrets.yaml; \
		curl -sSL https://raw.githubusercontent.com/zitadel/zitadel/main/docs/docs/self-hosting/manage/configure/example-zitadel-init-steps.yaml \
			-o $(VENDOR_DIR)/example-zitadel-init-steps.yaml; \
	fi
	@if [ ! -f $(MASTERKEY_FILE) ]; then \
		echo "Generating Zitadel masterkey..."; \
		LC_ALL=C tr -dc '[:graph:]' </dev/urandom | head -c 32 > $(MASTERKEY_FILE); \
		chmod 600 $(MASTERKEY_FILE) || true; \
	fi

## Démarre Zitadel (nécessite la masterkey)
zitadel-up:
	@if [ ! -f $(MASTERKEY_FILE) ]; then \
		echo "Missing masterkey. Run: make zitadel-init"; \
		exit 1; \
	fi
	@export ZITADEL_MASTERKEY="$$(cat $(MASTERKEY_FILE))"; \
	docker compose -f $(COMPOSE) up -d

## Stoppe Zitadel
zitadel-down:
	@export ZITADEL_MASTERKEY="$$(cat $(MASTERKEY_FILE) 2>/dev/null || true)"; \
	docker compose -f $(COMPOSE) down

## Logs Zitadel
zitadel-logs:
	docker compose -f $(COMPOSE) logs -f --tail=200

## Reset complet (DANGER: supprime volumes)
zitadel-reset:
	@export ZITADEL_MASTERKEY="$$(cat $(MASTERKEY_FILE) 2>/dev/null || true)"; \
	docker compose -f $(COMPOSE) down -v