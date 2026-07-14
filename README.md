# Helm charts

Helm charts for the duynhlab microservices platform.
Published to GHCR (OCI) and [GitHub Pages](https://duynhlab.github.io/helm-charts).

## Charts

| Chart | Version | Description |
|-------|---------|-------------|
| [`mop`](charts/mop) | 0.16.1 | Generic chart for Go microservices — Deployment, multi-port Service (HTTP + optional gRPC), golang-migrate, Sloth SLO. |
| [`grafana-dashboards`](charts/grafana-dashboards) | 0.1.1 | Grafana dashboards as ConfigMaps for sidecar auto-provisioning. |

See each chart's README for configuration details.

## Installation

### List available versions (OCI)

```console
crane ls ghcr.io/duynhlab/helm-charts/mop
crane ls ghcr.io/duynhlab/helm-charts/grafana-dashboards
```

### OCI (GHCR)

```console
# mop
helm install <release> oci://ghcr.io/duynhlab/helm-charts/mop --version 0.16.1 \
  --set name=<svc> --set image.repository=ghcr.io/duynhlab/<svc>-service/<svc>

# grafana-dashboards
helm install grafana-dashboards oci://ghcr.io/duynhlab/helm-charts/grafana-dashboards --version 0.1.1
```

### Helm repo (GitHub Pages)

```console
helm repo add duynhlab https://duynhlab.github.io/helm-charts
helm repo update
helm install <release> duynhlab/mop --version 0.16.1 --set name=<svc> ...
helm install grafana-dashboards duynhlab/grafana-dashboards --version 0.1.1
```

### Install from local chart

```console
helm install <release> ./charts/mop --set name=<svc> ...
helm install grafana-dashboards ./charts/grafana-dashboards
```

## Upgrade

```console
helm upgrade <release> oci://ghcr.io/duynhlab/helm-charts/<chart>
```

## Uninstall

```console
helm uninstall <release>
```

## Develop

Prerequisites for local e2e: `kind`, `kubectl`, `helm`, `helmfile`, `docker`.

```bash
# helmfile (one-time)
go install github.com/helmfile/helmfile/v2/cmd/helmfile@latest
```

```bash
make help       # list targets
make lint-all   # lint + template every chart (like CI)
make lint       # helm lint $(CHART): default + gRPC+SLO
make template   # render mop with gRPC enabled
make docs       # regenerate chart READMEs (helm-docs)
make e2e        # KinD: helmfile sync (mop + worker + grafana-dashboards), assert, test, teardown
make e2e-sync   # helmfile sync only (existing cluster)
```
