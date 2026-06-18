CHART ?= charts/mop

.PHONY: lint template unittest e2e

lint: ## helm lint the mop chart (gRPC on + off, SLO on)
	helm lint $(CHART) --set name=test
	helm lint $(CHART) --set name=test --set service.grpc.enabled=true --set slo.enabled=true

template: ## render the chart with gRPC enabled
	helm template test $(CHART) --set name=test --set image.repository=ghcr.io/duynhlab/x --set service.grpc.enabled=true

unittest: ## run helm-unittest suites
	helm unittest $(CHART) --strict

e2e: ## spin a KinD cluster, install, assert Services, helm test, teardown
	./scripts/e2e-kind.sh
