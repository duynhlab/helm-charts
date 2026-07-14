#!/usr/bin/env bash
# kubectl assertions for mop e2e releases (not covered by helm test hooks).
set -euo pipefail

NS="${NS:-mop-e2e}"
RELEASE="${RELEASE:-mop-e2e}"
WORKER="${WORKER:-mop-e2e-worker}"

echo "== deployment ready =="
kubectl -n "$NS" rollout status "deploy/$RELEASE" --timeout 120s
kubectl -n "$NS" rollout status "deploy/$WORKER" --timeout 120s

echo "== Service (http + grpc on one ClusterIP) =="
kubectl -n "$NS" get svc "$RELEASE" -o jsonpath='{.spec.type}/{.spec.ports[0].name}:{.spec.ports[0].port}'; echo
gport=$(kubectl -n "$NS" get svc "$RELEASE" -o jsonpath='{.spec.ports[?(@.name=="grpc")].port}')
[ "$gport" = "9999" ] || { echo "FAIL: grpc port on $RELEASE is '$gport', expected 9999"; exit 1; }
echo "  $RELEASE: ports http + grpc:9999 (single Service) ok"

echo "== Service endpoints populated =="
for _ in $(seq 1 20); do
  ip=$(kubectl -n "$NS" get endpoints "$RELEASE" -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || true)
  [ -n "$ip" ] && break
  sleep 3
done
[ -n "${ip:-}" ] || { echo "FAIL: Service $RELEASE has no endpoints"; exit 1; }
echo "  endpoint: $ip ok"

echo "== worker-as-release (no Service) =="
if kubectl -n "$NS" get svc "$WORKER" >/dev/null 2>&1; then
  echo "FAIL: $WORKER should render no Service (service.enabled=false)"
  exit 1
fi
echo "  $WORKER ready, no Service ok"
