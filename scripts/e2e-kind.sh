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

echo "== Service (http + grpc on one ClusterIP) =="
kubectl -n "$NS" get svc "$RELEASE" -o jsonpath='{.spec.type}/{.spec.ports[0].name}:{.spec.ports[0].port}'; echo
# gRPC is a named port on the SAME Service (service.grpc.enabled).
gport=$(kubectl -n "$NS" get svc "$RELEASE" -o jsonpath='{.spec.ports[?(@.name=="grpc")].port}')
[ "$gport" = "9999" ] || { echo "FAIL: grpc port on $RELEASE is '$gport', expected 9999"; exit 1; }
echo "  $RELEASE: ports http + grpc:9999 (single Service) ✓"

echo "== Service endpoints populated =="
for _ in $(seq 1 20); do
  ip=$(kubectl -n "$NS" get endpoints "$RELEASE" -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || true)
  [ -n "$ip" ] && break; sleep 3
done
[ -n "${ip:-}" ] || { echo "FAIL: Service $RELEASE has no endpoints"; exit 1; }
echo "  endpoint: $ip ✓"

echo "== helm test =="
helm test "$RELEASE" -n "$NS" --timeout 120s

echo "== worker-as-release pattern (same chart, separate release, no Service) =="
# A worker is just this chart deployed again with a different name and no Service.
# In prod the worker carries args:["worker"]; the stub image has no worker subcommand,
# so here we only validate the multi-release + service.enabled=false wiring.
helm install "${RELEASE}-worker" "$CHART" -n "$NS" -f "$VALUES" \
  --set name="${RELEASE}-worker" \
  --set service.enabled=false \
  --set service.grpc.enabled=false \
  --wait --timeout 180s
kubectl -n "$NS" rollout status "deploy/${RELEASE}-worker" --timeout 120s
if kubectl -n "$NS" get svc "${RELEASE}-worker" >/dev/null 2>&1; then
  echo "FAIL: ${RELEASE}-worker should render no Service (service.enabled=false)"; exit 1
fi
echo "  ${RELEASE}-worker ready, no Service ✓"

echo "E2E PASS ✅"
