#!/usr/bin/env bash
# Local KinD end-to-end test for the mop chart: spin a kind cluster, install with
# the gRPC test values, assert the HTTP Service + the headless gRPC Service render
# and select the ready pod, run `helm test`, then tear down.
#
# Usage: scripts/e2e-kind.sh   (requires kind, kubectl, helm, docker)
set -euo pipefail

CLUSTER="${CLUSTER:-mop-e2e}"
CHART="${CHART:-charts/mop}"
VALUES="${VALUES:-charts/mop/ci/grpc-values.yaml}"
RELEASE="mop-e2e"
NS="mop-e2e"

cleanup() { kind delete cluster --name "$CLUSTER" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "== create kind cluster =="
kind create cluster --name "$CLUSTER" --wait 120s

echo "== helm install (grpc enabled) =="
kubectl create namespace "$NS" >/dev/null
helm install "$RELEASE" "$CHART" -n "$NS" -f "$VALUES" --wait --timeout 180s

echo "== deployment ready =="
kubectl -n "$NS" rollout status "deploy/$RELEASE" --timeout 120s

echo "== HTTP Service =="
kubectl -n "$NS" get svc "$RELEASE" -o jsonpath='{.spec.type}/{.spec.ports[0].name}:{.spec.ports[0].port}'; echo

echo "== headless gRPC Service =="
cip=$(kubectl -n "$NS" get svc "${RELEASE}-grpc" -o jsonpath='{.spec.clusterIP}')
[ "$cip" = "None" ] || { echo "FAIL: ${RELEASE}-grpc clusterIP is '$cip', expected None"; exit 1; }
gport=$(kubectl -n "$NS" get svc "${RELEASE}-grpc" -o jsonpath='{.spec.ports[0].port}')
[ "$gport" = "9090" ] || { echo "FAIL: gRPC port is '$gport', expected 9090"; exit 1; }
echo "  ${RELEASE}-grpc: clusterIP=None port=9090 (headless) ✓"

echo "== gRPC Service endpoints populated =="
for _ in $(seq 1 20); do
  ip=$(kubectl -n "$NS" get endpoints "${RELEASE}-grpc" -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || true)
  [ -n "$ip" ] && break; sleep 3
done
[ -n "${ip:-}" ] || { echo "FAIL: headless gRPC Service has no endpoints"; exit 1; }
echo "  endpoint: $ip ✓"

echo "== helm test =="
helm test "$RELEASE" -n "$NS" --timeout 120s

echo "E2E PASS ✅"
