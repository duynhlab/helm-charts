#!/usr/bin/env bash
# Local KinD end-to-end test: spin a kind cluster, install the VictoriaMetrics
# operator CRDs, helmfile sync (mop + worker + grafana-dashboards + vm-rules),
# kubectl assert mop wiring, helmfile test, then tear down.
#
# Usage: scripts/e2e-kind.sh   (requires kind, kubectl, helm, helmfile, docker)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
E2E_DIR="$ROOT/scripts/e2e"
CLUSTER="${CLUSTER:-helm-charts-e2e}"
# charts/vm-rules renders VMRule objects, so the CRDs must exist before install.
VM_OPERATOR_VERSION="${VM_OPERATOR_VERSION:-v0.74.1}"

for cmd in kind kubectl helm helmfile; do
  command -v "$cmd" >/dev/null || { echo "missing: $cmd"; exit 1; }
done

cleanup() { kind delete cluster --name "$CLUSTER" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "== ensure clean cluster =="
kind delete cluster --name "$CLUSTER" 2>/dev/null || true

echo "== create kind cluster =="
kind create cluster --name "$CLUSTER" --wait 120s

echo "== install VictoriaMetrics operator CRDs ($VM_OPERATOR_VERSION) =="
# Server-side apply: the bundle is ~9MB, well over the client-side
# last-applied-configuration annotation limit.
kubectl apply --server-side --force-conflicts -f \
  "https://github.com/VictoriaMetrics/operator/releases/download/${VM_OPERATOR_VERSION}/crd.yaml" >/dev/null
kubectl wait --for condition=established --timeout=60s crd/vmrules.operator.victoriametrics.com

echo "== helmfile sync =="
helmfile -f "$E2E_DIR/helmfile.yaml" sync

echo "== mop assertions =="
"$E2E_DIR/assert-mop.sh"

echo "== vm-rules assertions =="
"$E2E_DIR/assert-vm-rules.sh"

echo "== helmfile test =="
helmfile -f "$E2E_DIR/helmfile.yaml" test -l name=mop-e2e -l name=grafana-dashboards-e2e

echo "E2E PASS"
