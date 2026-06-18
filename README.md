# Helm charts

Helm charts for the duynhlab microservices platform.

## Charts

| Chart | Description |
|-------|-------------|
| [`mop`](charts/mop) | Generic chart for the Go microservices (Microservices Observability Platform) — single Deployment, one multi-port Service (http + optional grpc), golang-migrate init container, Sloth SLO. |

## Install

**OCI (GHCR):**

```bash
helm install <release> oci://ghcr.io/duynhlab/helm-charts/mop --version 0.12.0 \
  --set name=<svc> --set image.repository=ghcr.io/duynhlab/<svc>-service/<svc>
```

**Helm repo (GitHub Pages):**

```bash
helm repo add duynhlab https://duynhlab.github.io/helm-charts
helm repo update
helm install <release> duynhlab/mop --version 0.12.0 --set name=<svc> ...
```

## Develop

```bash
make lint       # helm lint (gRPC on/off)
make template   # render with gRPC enabled
make e2e        # KinD: install + assert Services + helm test + teardown
```

CI: `lint.yml` (helm lint/template on PR), `e2e.yml` (chart-testing `lint-and-install`
on a KinD cluster), `release.yml` (publishes to GitHub Pages + `oci://ghcr.io/duynhlab/helm-charts` on merge to `main`).
