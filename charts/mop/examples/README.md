# mop — example values

Ready-to-use values files for common deploy cases. Pass one with `-f`:

```bash
helm install <release> ./charts/mop -f charts/mop/examples/<file>.yaml
```

| File | Case | Renders |
|------|------|---------|
| `auth-api.yaml` | Basic HTTP API service | Deployment + ClusterIP Service |
| `product-grpc.yaml` | API + gRPC east-west (`grpc.enabled`) | Deployment + HTTP Service + headless gRPC Service |
| `order-api.yaml` | API + DB migrations init container (`migrations.enabled`) | Deployment (with `migrate` initContainer) + Service |
| `order-worker.yaml` | Background worker (`args: ["worker"]`, `service.enabled: false`) | Deployment only (no Service) |
| `auth-with-slo.yaml` | API + Sloth SLOs (`slo.enabled`) | Deployment + Service + PrometheusServiceLevel |

## API + worker = two releases of the same chart

A worker is not a special chart construct — it is the **same image** run as a
separate release with different `args` and no Service. Deploy the order API and
its worker side by side:

```bash
helm install order        ./charts/mop -f charts/mop/examples/order-api.yaml
helm install order-worker ./charts/mop -f charts/mop/examples/order-worker.yaml
```

> Update the `image.repository` / `image.tag` and the `env` secret references to
> match your environment before installing.
