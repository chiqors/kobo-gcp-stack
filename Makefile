SHELL := /usr/bin/env bash
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

render:
	$(ROOT)/scripts/render-config.sh $(ROOT)/.env

preflight: render
	$(ROOT)/scripts/preflight-host.sh

config: render
	docker compose --env-file $(ROOT)/.env -f $(ROOT)/compose/compose.yaml config >/dev/null

up: preflight
	$(ROOT)/scripts/deploy.sh up

down:
	docker compose --env-file $(ROOT)/.env -f $(ROOT)/compose/compose.yaml down

smoke:
	$(ROOT)/scripts/smoke-test.sh

helm-config: render
	$(ROOT)/scripts/deploy-helm.sh config

helm-up: render
	$(ROOT)/scripts/deploy-helm.sh up

helm-down:
	$(ROOT)/scripts/deploy-helm.sh down

gke-validate:
	$(ROOT)/scripts/provision-gke.sh validate $(ROOT)/.env

gke-provision:
	$(ROOT)/scripts/provision-gke.sh apply $(ROOT)/.env

test-gke-provision:
	$(ROOT)/tests/gke-provision.sh
