# One entry point for everything. Run `make` to list targets.
SHELL := /usr/bin/env bash
TF    := infra/terraform
ENV   := $(TF)/envs/dev
REGION ?= us-east-1
CLUSTER ?= reelops-dev

.DEFAULT_GOAL := help
.PHONY: help bootstrap doctor hooks up down logs smoke test lint \
        tf-bootstrap aws-up kubeconfig argocd argocd-password aws-down cost-check

help: ## list targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

## ---------- phase 00: toolchain ----------
bootstrap: ## install pinned toolchain
	./scripts/bootstrap.sh
doctor: ## verify toolchain + AWS login
	./scripts/doctor.sh
hooks: ## install git pre-commit hooks
	pre-commit install && pre-commit run --all-files

## ---------- phases 01-02: local ----------
up: ## run the full stack locally (LocalStack, no AWS cost)
	docker compose up -d --build
down: ## stop the local stack
	docker compose down -v
logs: ## tail local logs
	docker compose logs -f ingest-api transcode-worker
smoke: ## upload a clip and wait for DONE (BASE=http://... to target AWS)
	./scripts/smoke-test.sh $(BASE)
test: ## unit tests for both services
	cd services/ingest-api && python -m pytest -q
	cd services/transcode-worker && python -m pytest -q
lint: ## ruff + helm lint + terraform fmt
	ruff check services
	helm lint charts/reelops
	terraform fmt -check -recursive $(TF)

## ---------- phase 03-04: AWS ----------
tf-bootstrap: ## one-time: state bucket, lock table, ECR, OIDC roles, budget
	terraform -chdir=$(TF)/bootstrap init
	terraform -chdir=$(TF)/bootstrap apply
aws-up: ## create network -> data -> EKS (about 20 minutes)
	for s in network data platform; do \
	  terraform -chdir=$(ENV)/$$s init -input=false && \
	  terraform -chdir=$(ENV)/$$s apply || exit 1; \
	done
	$(MAKE) kubeconfig
kubeconfig: ## point kubectl at the EKS cluster
	aws eks update-kubeconfig --region $(REGION) --name $(CLUSTER)

## ---------- phase 07: GitOps ----------
argocd: ## install Argo CD and hand the cluster to the gitops repo
	helm repo add argo https://argoproj.github.io/argo-helm >/dev/null && helm repo update >/dev/null
	helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace --version 10.11.1 --wait
	kubectl apply -f ../reelops-gitops/bootstrap/root.yaml
argocd-password: ## print the initial Argo CD admin password
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

## ---------- teardown ----------
aws-down: ## destroy everything that costs money (run after every session)
	./scripts/aws-down.sh
cost-check: ## month-to-date AWS spend
	aws ce get-cost-and-usage --time-period Start=$$(date +%Y-%m-01),End=$$(date -d tomorrow +%F 2>/dev/null || date -v+1d +%F) \
	  --granularity MONTHLY --metrics UnblendedCost --query 'ResultsByTime[0].Total.UnblendedCost'
