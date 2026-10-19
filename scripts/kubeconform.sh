#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

cd "$(dirname "${BASH_SOURCE[0]}")/.."
KUBERNETES_VERSION=${KUBERNETES_VERSION:-1.35.8}
CRD_CATALOG_REVISION=501527ab9c40c827144c8f45945b25a023e344ce
crd_schema="https://raw.githubusercontent.com/datreeio/CRDs-catalog/${CRD_CATALOG_REVISION}/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"

command -v helm >/dev/null
command -v kubeconform >/dev/null
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
mkdir "$work_dir/cache"

validate() {
  local chart=$1 scenario=$2
  shift 2
  echo "::group::${chart}: ${scenario} (Kubernetes ${KUBERNETES_VERSION})"
  helm template test "$chart" --namespace test --kube-version "$KUBERNETES_VERSION" \
    "$@" > "$work_dir/rendered.yaml"
  # An empty render would otherwise pass kubeconform without validating anything.
  if ! grep -q '^kind:' "$work_dir/rendered.yaml"; then
    echo "No resources rendered for ${chart}: ${scenario}" >&2
    return 1
  fi
  kubeconform -strict -summary -verbose \
    -kubernetes-version "$KUBERNETES_VERSION" -cache "$work_dir/cache" \
    -schema-location default -schema-location "$crd_schema" "$work_dir/rendered.yaml"
  echo '::endgroup::'
}

for chart in charts/*; do
  [[ -f "$chart/Chart.yaml" ]] || continue
  if [[ "$chart" == charts/slo ]]; then
    # This chart requires a service; its raw defaults intentionally cannot render.
    validate "$chart" default -f "$chart/ci/default-values.yaml"
  else
    validate "$chart" default
  fi
  for values in "$chart"/ci/*-values.yaml; do
    validate "$chart" "$values" -f "$values"
  done
done

validate charts/mop slo --set name=test --set slo.enabled=true
validate charts/mop grpc --set name=test --set service.grpc.enabled=true
validate charts/duynh optional-features \
  -f charts/duynh/ci/monitoring-values.yaml \
  --set httpRoute.enabled=true --set 'httpRoute.parentRefs[0].name=public-gateway' \
  --set 'httpRoute.rules[0].matches[0].path.type=PathPrefix' \
  --set 'httpRoute.rules[0].matches[0].path.value=/' \
  --set autoscaling.enabled=true --set pdb.enabled=true
validate charts/duynh orders -f charts/duynh/examples/values-orders.yaml
validate charts/duynh homelab -f charts/duynh/examples/values-homelab.yaml
validate charts/vm-rules job-remap --namespace monitoring \
  --set jobNames.kubelet=kubernetes-nodes --set jobNames.node-exporter=prometheus-node-exporter
validate charts/slo availability-only --set service=test \
  --set latency.enabled=false --set selector.job=test-api
validate charts/slo monitoring-namespace --set service=test --set namespace=monitoring
