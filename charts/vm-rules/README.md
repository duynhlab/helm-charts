# vm-rules

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.0.0](https://img.shields.io/badge/AppVersion-1.0.0-informational?style=flat-square)

Static VictoriaMetrics alerting rules packaged as VMRule custom resources.
Each rule group ships as a standalone Prometheus rule file and renders into
one VMRule, discovered by VMAlert through its ruleSelector.

## Prerequisites

The [VictoriaMetrics operator](https://docs.victoriametrics.com/operator/) must be installed
(it owns the `VMRule` CRD), and a `VMAlert` instance must select these rules.

VMAlert picks up rules through `ruleSelector` / `ruleNamespaceSelector`. The simplest setup
selects everything:

```yaml
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMAlert
spec:
  ruleSelector: {}
  ruleNamespaceSelector: {}
```

If your VMAlert filters by label instead, mirror that label through `ruleSelectorLabels`:

```yaml
ruleSelectorLabels:
  app.kubernetes.io/part-of: victoria-metrics
```

> Already running prometheus-operator too? Keep using `VMRule` — the operator's
> `prometheus-converter` only flows `PrometheusRule` → `VMRule`, so native `VMRule`
> objects are never duplicated.

## Bundled rule groups

| Group | File | Alerts | Enabled by default | Metrics source |
|-------|------|--------|--------------------|----------------|
| `certmanager` | `rules/certmanager.yml` | 2 | yes | cert-manager controller |
| `fluxcd` | `rules/fluxcd.yml` | 3 | yes | Flux GitOps Toolkit (`gotk_*`) |
| `kubelet` | `rules/kubelet.yml` | 3 | yes | kubelet + kube-state-metrics |
| `kubernetes` | `rules/kubernetes.yml` | 5 | yes | cadvisor + kube-state-metrics |
| `node-exporter` | `rules/node-exporter.yml` | 5 | yes | node-exporter |
| `redis` | `rules/redis.yml` | 9 | **no** | redis_exporter |

`redis` is opt-in because not every cluster runs `redis_exporter`:

```yaml
rules:
  redis:
    enabled: true
```

### Label expectations

Rules were normalised for the label conventions that `vmagent` /
`victoria-metrics-k8s-stack` produce:

| Metrics from | Grouped by |
|--------------|------------|
| kube-state-metrics, cadvisor | `namespace`, `pod`, `container`, `node` |
| node-exporter | `instance` — `node` is not guaranteed on node-exporter series |
| redis_exporter | `namespace`, `pod`, `service` |

### Job names

Three rules match on a `job` label. If your scrape config produces different job names,
those rules silently never fire -- so check them before relying on this chart.

| Rule file | Matcher |
|-----------|---------|
| `rules/kubelet.yml` | `job="kubelet"` |
| `rules/node-exporter.yml` | `job="node-exporter"` (2 rules) |

Find the job names your cluster actually produces:

```promql
count by (job) (rest_client_requests_total)
count by (job) (node_time_seconds)
```

Then remap them without touching the rule files:

```yaml
jobNames:
  kubelet: kubernetes-nodes
  node-exporter: prom-stack-prometheus-node-exporter
```

The key is the job name as written in `rules/*.yml`; the value is yours. Leaving
`jobNames` empty changes nothing.

`kubelet` is a safe default -- `victoria-metrics-k8s-stack` scrapes it with a
`VMNodeScrape` that relabels `job` to exactly `kubelet`. **`node-exporter` is the one to
check**: it is scraped through a `VMServiceScrape`, where the job label follows the
Service name and commonly ends up as `<release>-prometheus-node-exporter`.

## Installation

### List available versions (OCI)

```console
crane ls ghcr.io/duynhlab/helm-charts/vm-rules
```

### OCI (GHCR)

```console
helm install vm-rules oci://ghcr.io/duynhlab/helm-charts/vm-rules --version 0.1.0 -n monitoring
```

### Helm repo (GitHub Pages)

```console
helm repo add duynhlab https://duynhlab.github.io/helm-charts
helm repo update
helm install vm-rules duynhlab/vm-rules --version 0.1.0 -n monitoring
```

### Install from local chart

```console
helm pull oci://ghcr.io/duynhlab/helm-charts/vm-rules --untar --version 0.1.0
helm install vm-rules ./vm-rules -n monitoring
```

## Verify

```console
kubectl get vmrule -n monitoring -l app.kubernetes.io/instance=vm-rules
kubectl get vmrule -n monitoring -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.updateStatus}{"\n"}{end}'
```

Every VMRule should report `updateStatus: operational`. An empty status means no VMAlert
selected it — compare its `ruleSelector` against the labels on these objects.

## Add or change a rule group

1. Drop a rule file under `rules/`. It must be a **standalone Prometheus rule file** with a
   top-level `groups:` key, so `promtool` can check it and so it can be used as the VMRule
   spec verbatim.
2. Register it in `values.yaml` under `rules.<name>`.
3. Validate: `make check-rules` then `helm unittest charts/vm-rules --strict`.
4. Bump `version` in `Chart.yaml` before merging to `main` (triggers a release).

Rule files are read with `.Files.Get`, which does **not** evaluate Go templates — so
`{{ $labels.pod }}` and `{{ $value | humanizeDuration }}`
reach VMAlert untouched and need no escaping.

## Upgrade

```console
helm upgrade vm-rules oci://ghcr.io/duynhlab/helm-charts/vm-rules -n monitoring
```

## Uninstall

```console
helm uninstall vm-rules -n monitoring
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| fullnameOverride | string | `""` |  |
| jobNames | map | `{}` | Remap the job names the bundled rules match on. Key = job name as written in rules/*.yml, value = the job name your scrape config actually produces. Leave empty when the defaults already match. Find your real job names with:   count by (job) (rest_client_requests_total)   count by (job) (node_time_seconds) |
| nameOverride | string | `""` |  |
| ruleSelectorLabels | map | `{}` | Labels added to every VMRule so VMAlert's `ruleSelector` can discover them. Leave empty when VMAlert uses `ruleSelector: {}` (selects everything). |
| rules | object | `{"certmanager":{"annotations":{},"enabled":true,"file":"certmanager.yml","labels":{}},"fluxcd":{"annotations":{},"enabled":true,"file":"fluxcd.yml","labels":{}},"kubelet":{"annotations":{},"enabled":true,"file":"kubelet.yml","labels":{}},"kubernetes":{"annotations":{},"enabled":true,"file":"kubernetes.yml","labels":{}},"node-exporter":{"annotations":{},"enabled":true,"file":"node-exporter.yml","labels":{}},"redis":{"annotations":{},"enabled":false,"file":"redis.yml","labels":{}}}` | Rule groups. Each entry renders one VMRule from the matching file under `rules/`. |
| rules.certmanager.annotations | map | `{}` | Additional annotations for this VMRule |
| rules.certmanager.enabled | bool | `true` | Enable or disable this rule group |
| rules.certmanager.file | string | `"certmanager.yml"` | Rule file path under rules/ |
| rules.certmanager.labels | map | `{}` | Additional labels for this VMRule |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
