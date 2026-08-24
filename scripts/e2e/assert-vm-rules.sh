#!/usr/bin/env bash
# Assert the vm-rules release produced VMRule objects the API server accepted.
# Only the CRDs are installed in e2e (no operator pod), so status.updateStatus is
# never populated -- what this proves is that the rendered spec is schema-valid.
set -euo pipefail

NS="${NS:-vm-rules-e2e}"
RELEASE="${RELEASE:-vm-rules-e2e}"

echo "-- VMRules in $NS"
kubectl get vmrule -n "$NS" -l "app.kubernetes.io/instance=$RELEASE"

# ci/default-values.yaml enables every group, redis included.
expected=6
actual=$(kubectl get vmrule -n "$NS" -l "app.kubernetes.io/instance=$RELEASE" -o name | wc -l | tr -d ' ')
[ "$actual" = "$expected" ] || { echo "FAIL: expected $expected VMRules, got $actual"; exit 1; }

# The rule body must round-trip through the API server as structured YAML.
alerts=$(kubectl get vmrule -n "$NS" -l "app.kubernetes.io/instance=$RELEASE" \
  -o jsonpath='{range .items[*].spec.groups[*].rules[*]}{.alert}{"\n"}{end}' | grep -c .)
[ "$alerts" -ge 27 ] || { echo "FAIL: expected >=27 alert rules, got $alerts"; exit 1; }

# Prometheus templating must have survived Helm rendering untouched. Look the
# object up by suffix -- the fullname helper collapses the chart name when the
# release name already contains it.
kubernetes_rule=$(kubectl get vmrule -n "$NS" -l "app.kubernetes.io/instance=$RELEASE" \
  -o name | grep -- '-kubernetes$' | head -1)
[ -n "$kubernetes_rule" ] || { echo "FAIL: no kubernetes VMRule found"; exit 1; }

kubectl get -n "$NS" "$kubernetes_rule" \
  -o jsonpath='{.spec.groups[0].rules[0].annotations.description}' \
  | grep -qF '{{ $labels.pod }}' || { echo "FAIL: Go template was evaluated away"; exit 1; }

echo "OK: $actual VMRules, $alerts alert rules, templating intact"
