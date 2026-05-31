CHART ?= charts/mop

.PHONY: lint template e2e

lint: ## helm lint the mop chart (gRPC on + off)
	helm lint $(CHART) --set name=test
	helm lint $(CHART) --set name=test --set grpc.enabled=true --set slo.enabled=true

template: ## render the chart with gRPC enabled
	helm template test $(CHART) --set name=test --set image.repository=ghcr.io/duynhlab/x --set grpc.enabled=true

e2e: ## spin a KinD cluster, install, assert Services, helm test, teardown
	./scripts/e2e-kind.sh
