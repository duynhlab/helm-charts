CHART ?= charts/mop

.PHONY: lint lint-all template unittest e2e e2e-sync docs help \
        lint-mop lint-duynh template-mop template-duynh unittest-mop unittest-duynh

help: ## show available targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-16s %s\n", $$1, $$2}'

docs: ## regenerate chart READMEs with helm-docs
	helm-docs --chart-search-root charts

lint-all: ## helm lint + template all charts (matches CI lint.yml)
	@for d in charts/*/; do \
	  echo "== $$d =="; \
	  helm lint "$$d" && helm template test "$$d" --namespace test; \
	done

# ── Generic targets (use CHART variable) ──────────────────────────────

lint: ## helm lint $(CHART): default values
	helm lint $(CHART)

template: ## render the chart with default values
	helm template test $(CHART) --namespace test

unittest: ## run helm-unittest suites for $(CHART)
	helm unittest $(CHART) --strict

# ── Per-chart targets ─────────────────────────────────────────────────

lint-mop: ## helm lint mop: default + gRPC + SLO
	helm lint charts/mop --set name=test
	helm lint charts/mop --set name=test --set service.grpc.enabled=true --set slo.enabled=true

template-mop: ## render mop with gRPC + SLO enabled
	helm template test charts/mop --set name=test \
	  --set image.repository=ghcr.io/duynhlab/x \
	  --set service.grpc.enabled=true --set slo.enabled=true --namespace test

unittest-mop: ## run mop helm-unittest suites
	helm unittest charts/mop --strict

lint-duynh: ## helm lint duynh: default + HTTPRoute + HPA + Sloth (examples)
	helm lint charts/duynh
	helm lint charts/duynh --values charts/duynh/examples/values-orders.yaml

template-duynh: ## render duynh with examples (HTTPRoute + HPA + Sloth)
	helm template test charts/duynh --namespace test \
	  --values charts/duynh/examples/values-orders.yaml

unittest-duynh: ## run duynh helm-unittest suites
	helm unittest charts/duynh --strict

# ── E2E ────────────────────────────────────────────────────────────────

e2e: ## KinD + helmfile sync/test (requires kind, kubectl, helm, helmfile, docker)
	./scripts/e2e-kind.sh

e2e-sync: ## helmfile sync only (cluster must already exist)
	helmfile -f scripts/e2e/helmfile.yaml sync
