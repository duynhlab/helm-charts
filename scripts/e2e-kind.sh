#!/usr/bin/env bash
# Local KinD end-to-end test: spin a kind cluster, helmfile sync (mop + worker +
# grafana-dashboards), kubectl assert mop wiring, helmfile test, then tear down.
#
# Usage: scripts/e2e-kind.sh   (requires kind, kubectl, helm, helmfile, docker)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
E2E_DIR="$ROOT/scripts/e2e"
CLUSTER="${CLUSTER:-helm-charts-e2e}"

for cmd in kind kubectl helm helmfile; do
  command -v "$cmd" >/dev/null || { echo "missing: $cmd"; exit 1; }
done

cleanup() { kind delete cluster --name "$CLUSTER" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "== ensure clean cluster =="
kind delete cluster --name "$CLUSTER" 2>/dev/null || true

echo "== create kind cluster =="
kind create cluster --name "$CLUSTER" --wait 120s

echo "== helmfile sync =="
helmfile -f "$E2E_DIR/helmfile.yaml" sync

echo "== mop assertions =="
"$E2E_DIR/assert-mop.sh"

echo "== helmfile test =="
helmfile -f "$E2E_DIR/helmfile.yaml" test -l name=mop-e2e -l name=grafana-dashboards-e2e

echo "E2E PASS"
