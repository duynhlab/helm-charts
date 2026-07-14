CHART ?= charts/mop

.PHONY: lint lint-all template unittest e2e e2e-sync docs help

help: ## show available targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-12s %s\n", $$1, $$2}'

docs: ## regenerate chart READMEs with helm-docs
	helm-docs --chart-search-root charts

lint-all: ## helm lint + template all charts (matches CI lint.yml)
	@for d in charts/*/; do \
	  echo "== $$d =="; \
	  helm lint "$$d" && helm template test "$$d" --namespace test; \
	done

lint: ## helm lint $(CHART): default + gRPC+SLO (mop-specific sets)
	helm lint $(CHART) --set name=test
	helm lint $(CHART) --set name=test --set service.grpc.enabled=true --set slo.enabled=true

template: ## render the chart with gRPC enabled
	helm template test $(CHART) --set name=test --set image.repository=ghcr.io/duynhlab/x --set service.grpc.enabled=true

unittest: ## run helm-unittest suites
	helm unittest $(CHART) --strict

e2e: ## KinD + helmfile sync/test (requires kind, kubectl, helm, helmfile, docker)
	./scripts/e2e-kind.sh

e2e-sync: ## helmfile sync only (cluster must already exist)
	helmfile -f scripts/e2e/helmfile.yaml sync
