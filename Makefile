CHART ?= charts/mop
# promtool runs in a container; podman works as a drop-in for docker here.
CONTAINER ?= docker

.PHONY: lint lint-mop lint-duynh lint-vm-rules lint-all template template-mop template-duynh template-vm-rules check-rules unittest e2e e2e-sync docs help

help: ## show available targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-16s %s\n", $$1, $$2}'

docs: ## regenerate chart READMEs with helm-docs
	helm-docs --chart-search-root charts

lint-all: ## helm lint + template all charts (matches CI lint.yml)
	@for d in charts/*/; do \
	  echo "== $$d =="; \
	  helm lint "$$d" && helm template test "$$d" --namespace test; \
	done

lint: ## helm lint $(CHART): default + chart-specific feature sets
	helm lint $(CHART) --set name=test

lint-mop: ## helm lint charts/mop: default + gRPC+SLO
	helm lint charts/mop --set name=test
	helm lint charts/mop --set name=test --set service.grpc.enabled=true --set slo.enabled=true

lint-duynh: ## helm lint charts/duynh: default + HTTPRoute+HPA+PDB+Sloth
	helm lint charts/duynh --set name=test
	helm lint charts/duynh --set name=test --set httpRoute.enabled=true
	helm lint charts/duynh --set name=test --set autoscaling.enabled=true --set pdb.enabled=true
	helm lint charts/duynh --set name=test --set sloth.enabled=true \
	  --set sloth.service=test --set sloth.slos[0].name=availability --set sloth.slos[0].objective=99.9

lint-vm-rules: ## helm lint charts/vm-rules: default + all rule groups enabled
	helm lint charts/vm-rules
	helm lint charts/vm-rules -f charts/vm-rules/ci/default-values.yaml

check-rules: ## promtool check charts/vm-rules/rules/*.yml (needs docker or podman)
	$(CONTAINER) run --rm -v "$(PWD)/charts/vm-rules/rules:/rules:ro" \
	  --entrypoint promtool prom/prometheus:v3.7.3 check rules \
	  /rules/certmanager.yml /rules/fluxcd.yml /rules/kubelet.yml \
	  /rules/kubernetes.yml /rules/node-exporter.yml /rules/redis.yml

template: ## render the chart with gRPC enabled
	helm template test $(CHART) --set name=test --set image.repository=ghcr.io/duynhlab/x --set service.grpc.enabled=true

template-mop: ## render charts/mop with gRPC + SLO enabled
	helm template test charts/mop --set name=test --set service.grpc.enabled=true --set slo.enabled=true --namespace test

template-duynh: ## render charts/duynh with HTTPRoute + HPA + Sloth
	helm template test charts/duynh --set name=test \
	  --set httpRoute.enabled=true \
	  --set httpRoute.parentRefs[0].name=public-gateway \
	  --set httpRoute.rules[0].matches[0].path.type=PathPrefix \
	  --set httpRoute.rules[0].matches[0].path.value=/ \
	  --set autoscaling.enabled=true --set sloth.enabled=true \
	  --set sloth.service=test --set sloth.slos[0].name=availability --set sloth.slos[0].objective=99.9 \
	  --namespace test

template-vm-rules: ## render charts/vm-rules with every rule group enabled
	helm template test charts/vm-rules --namespace monitoring \
	  -f charts/vm-rules/ci/default-values.yaml

unittest: ## run helm-unittest suites
	helm unittest $(CHART) --strict

e2e: ## KinD + VM CRDs + helmfile sync/test (requires kind, kubectl, helm, helmfile, docker)
	./scripts/e2e-kind.sh

e2e-sync: ## helmfile sync only (cluster must already exist)
	helmfile -f scripts/e2e/helmfile.yaml sync
