#!/usr/bin/env bash
# Validate the final expressions, including CNPG substitutions and legacy job remapping.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
mkdir "$work_dir/rules" "$work_dir/promql"
for scenario in all remapped; do
  args=(--set defaultRules.enabled=true)
  if [[ "$scenario" == remapped ]]; then
    args+=(--set jobNames.kubelet=kubernetes-nodes --set jobNames.node-exporter=prometheus-node-exporter)
  fi
  helm template test charts/vm-rules --namespace monitoring \
    -f charts/vm-rules/ci/bundles-values.yaml \
    --set rules.redis.enabled=true \
    "${args[@]}" > "$work_dir/$scenario.yaml"
done
python3 - "$work_dir" <<'PY'
from pathlib import Path
import copy
import sys
import yaml

root = Path(sys.argv[1])
count = 0
# These upstream CNPG expressions use MetricsQL implicit subqueries/range-vector
# operations. Preserve them and validate with VMAlert, not Prometheus's parser.
metricsql_alerts = {
    'CNPGClusterLogicalReplicationErrors',
    'CNPGClusterLogicalReplicationErrorsCritical',
    'CNPGClusterLogicalReplicationStopped',
    'CNPGClusterLogicalReplicationStoppedCritical',
}
delegated = 0
for scenario in ('all', 'remapped'):
    for index, doc in enumerate(yaml.safe_load_all((root / f'{scenario}.yaml').read_text())):
        if doc and doc.get('kind') == 'VMRule':
            (root / 'rules' / f'{scenario}-{index}.yaml').write_text(yaml.safe_dump(doc['spec']))
            spec = copy.deepcopy(doc['spec'])
            for group in spec['groups']:
                before = len(group['rules'])
                group['rules'] = [r for r in group['rules'] if r.get('alert') not in metricsql_alerts]
                delegated += before - len(group['rules'])
            spec['groups'] = [g for g in spec['groups'] if g['rules']]
            if spec['groups']:
                (root / 'promql' / f'{scenario}-{index}.yaml').write_text(yaml.safe_dump(spec))
            count += 1
if not count:
    raise SystemExit('No VMRule specs rendered')
print(f'Checking {count} rendered VMRule specs')
print(f'{delegated} CNPG MetricsQL rules checked by VMAlert only; all other rules also checked by promtool')
PY
if command -v promtool >/dev/null; then
  promtool check rules "$work_dir"/promql/*.yaml
else
  "${CONTAINER:-docker}" run --rm -v "$work_dir/promql:/rules:ro" \
    --entrypoint /bin/sh prom/prometheus:v3.7.3 \
    -c 'promtool check rules /rules/*.yaml'
fi
"${CONTAINER:-docker}" run --rm -v "$work_dir/rules:/rules:ro" \
  victoriametrics/vmalert:v1.152.0 -dryRun '-rule=/rules/*.yaml'
