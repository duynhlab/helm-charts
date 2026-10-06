# duynh

`duynh` is a small reusable Helm application chart for stateless microservices on Amazon EKS. Install it once per microservice so deployments, rollbacks, scaling, and routing remain independent.

The chart targets Kubernetes 1.34 and works with Helm 3.21 or Helm 4.2. Envoy Gateway integration uses the stable Gateway API `HTTPRoute` resource.

## What it creates

- Deployment, with optional init containers (`initContainers`)
- ClusterIP Service (optional, `service.enabled`), with extra ports such as gRPC
- Optional HorizontalPodAutoscaler (`autoscaling/v2`)
- Optional PodDisruptionBudget (`policy/v1`)
- Optional ServiceAccount
- Optional HTTPRoute (`gateway.networking.k8s.io/v1`)
- Optional Sloth `PrometheusServiceLevel`, in the release namespace or `sloth.namespace`
- Optional extra manifests (`extraObjects`), rendered through `tpl`

The chart deliberately does not create a Gateway, GatewayClass, secrets, RBAC, monitoring CRDs, or Envoy-specific policies. Those belong to the platform layer or to an explicit service requirement.

## Requirements

- Kubernetes 1.24+ (CI templates against the default Helm version)
- Helm 3.21.4 or Helm 4.2.4
- Metrics Server when HPA is enabled
- Gateway API CRDs and Envoy Gateway when HTTPRoute is enabled
- A shared Gateway listener that permits routes from the application namespace

## Install one microservice

Copy and edit the example first; it contains placeholder AWS account, IAM role, image, hostname, and Gateway values.

```bash
helm upgrade --install orders-api ./charts/duynh \
  --namespace apps \
  --create-namespace \
  --values charts/duynh/examples/values-orders.yaml
```

Render before installing:

```bash
helm lint ./charts/duynh --strict --kube-version 1.34.0
helm template orders-api ./charts/duynh \
  --namespace apps \
  --kube-version 1.34.0 \
  --values charts/duynh/examples/values-orders.yaml
```

## Important values

| Value | Default | Purpose |
| --- | --- | --- |
| `replicaCount` | `2` | Desired replicas when HPA is disabled |
| `image.repository` | `nginx` | Container image repository |
| `image.tag` | chart `appVersion` | Container image tag |
| `containerPort` | `80` | Named `http` container port |
| `resources` | `{}` | Requests and limits; set these before enabling HPA |
| `autoscaling.enabled` | `false` | Create an HPA and omit Deployment replicas |
| `pdb.enabled` | `false` | Create a PDB for voluntary disruptions |
| `httpRoute.enabled` | `false` | Attach the Service to a shared Gateway |
| `topologySpreadConstraints` | `[]` | Pass Kubernetes placement constraints through unchanged |
| `containerName` | chart name | Name of the main container |
| `extraPorts` | `[]` | More named container ports, e.g. `grpc` on 9090 |
| `service.enabled` | `true` | Set `false` for a workload that serves no traffic |
| `service.extraPorts` | `[]` | More Service ports; `targetPort` defaults to the port name |
| `initContainers` | `[]` | Init containers, rendered through `tpl` (e.g. a schema migration) |
| `extraSelectorLabels` | `{}` | Added to the selector and pod labels; only to keep an existing selector |
| `sloth.namespace` | release namespace | Where the `PrometheusServiceLevel` is created |
| `extraObjects` | `[]` | Extra manifests (maps or strings), rendered through `tpl` |

Health probes are raw Kubernetes probe objects. A liveness probe should normally check only the process itself; use readiness for whether the pod should receive traffic.

## Migrating from mop

`charts/duynh/examples/values-homelab.yaml` is a complete microservice in the shape
the `mop` chart used to render. The mapping:

| `mop` value | `duynh` value |
| --- | --- |
| `name` | `nameOverride` (and `containerName` for the container) |
| `service.http.port` / `containerPort` | `service.port` / `containerPort` |
| `service.grpc.*` | `extraPorts` + `service.extraPorts` |
| `labels` | `podLabels` |
| `migrations.*` | an `initContainers` entry, with its own credential |
| `dbCredentials.*` | `volumes` + `volumeMounts` + a `DB_PASSWORD_FILE` env |
| `livenessProbe.enabled: false` | `livenessProbe: null` |
| `slo.*` | `sloth.*` with `sloth.namespace`, burn-rate rules in `extraObjects` |

A Deployment selector is immutable. `mop` selected on `app.kubernetes.io/name`,
`app.kubernetes.io/instance` and `app`, so keep the same release name, set
`nameOverride` to the old `name`, and set `extraSelectorLabels: {app: <name>}`;
the release then upgrades in place instead of failing on the selector.

## Envoy Gateway

The chart creates only an HTTPRoute. A minimal values fragment is:

```yaml
httpRoute:
  enabled: true
  parentRefs:
    - name: public-gateway
      namespace: envoy-gateway-system
      sectionName: https
  hostnames:
    - api.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
      timeouts:
        request: 30s
        backendRequest: 5s
```

Check that the route was accepted:

```bash
kubectl get httproute -n apps -o wide
kubectl describe httproute orders-api -n apps
```

## Tests

Install the pinned unit-test plugin and run the same checks as CI:

```bash
# Helm 3
helm plugin install https://github.com/helm-unittest/helm-unittest.git --version 1.1.2

# Helm 4
helm plugin install https://github.com/helm-unittest/helm-unittest.git \
  --version 1.1.2 --verify=false

helm lint ./charts/duynh --strict --kube-version 1.34.0
helm unittest --strict ./charts/duynh
helm template test ./charts/duynh --kube-version 1.34.0 > /dev/null
helm package ./charts/duynh --destination dist
```

`.github/workflows/ci.yaml` runs these checks against Helm 3.21.4 and 4.2.4 on pull requests and pushes to `main`.

## OCI release

Set `Chart.yaml.version`, commit it, then create the matching tag:

```bash
git tag duynh-v0.1.0
git push origin duynh-v0.1.0
```

The release workflow publishes the package to:

```text
oci://ghcr.io/OWNER/charts/duynh
```

Install it with:

```bash
helm upgrade --install orders-api \
  oci://ghcr.io/OWNER/charts/duynh \
  --version 0.1.0 \
  --namespace apps \
  --create-namespace \
  --values values-orders.yaml
```

The same package can be stored in Amazon ECR:

```bash
aws ecr get-login-password --region ap-southeast-1 | \
  helm registry login ACCOUNT_ID.dkr.ecr.ap-southeast-1.amazonaws.com \
  --username AWS --password-stdin

helm push duynh-0.1.0.tgz \
  oci://ACCOUNT_ID.dkr.ecr.ap-southeast-1.amazonaws.com/helm
```

For ECR, create the target repository first and grant the publishing identity permission to push artifacts.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| args | list | `[]` |  |
| autoscaling.behavior | object | `{}` |  |
| autoscaling.enabled | bool | `false` |  |
| autoscaling.maxReplicas | int | `10` |  |
| autoscaling.minReplicas | int | `2` |  |
| autoscaling.targetCPUUtilizationPercentage | int | `75` |  |
| autoscaling.targetMemoryUtilizationPercentage | string | `nil` |  |
| command | list | `[]` |  |
| containerName | string | `""` |  |
| containerPort | int | `80` |  |
| deploymentAnnotations | object | `{}` |  |
| env | list | `[]` |  |
| envFrom | list | `[]` |  |
| extraObjects | list | `[]` |  |
| extraPorts | list | `[]` |  |
| extraSelectorLabels | object | `{}` |  |
| fullnameOverride | string | `""` |  |
| httpRoute.annotations | object | `{}` |  |
| httpRoute.enabled | bool | `false` |  |
| httpRoute.hostnames | list | `[]` |  |
| httpRoute.parentRefs[0].name | string | `"envoy-gateway"` |  |
| httpRoute.parentRefs[0].namespace | string | `"envoy-gateway-system"` |  |
| httpRoute.parentRefs[0].sectionName | string | `"http"` |  |
| httpRoute.rules[0].matches[0].path.type | string | `"PathPrefix"` |  |
| httpRoute.rules[0].matches[0].path.value | string | `"/"` |  |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.repository | string | `"nginx"` |  |
| image.tag | string | `""` |  |
| imagePullSecrets | list | `[]` |  |
| initContainers | list | `[]` |  |
| livenessProbe.failureThreshold | int | `3` |  |
| livenessProbe.httpGet.path | string | `"/"` |  |
| livenessProbe.httpGet.port | string | `"http"` |  |
| livenessProbe.periodSeconds | int | `10` |  |
| nameOverride | string | `""` |  |
| nodeSelector | object | `{}` |  |
| pdb.enabled | bool | `false` |  |
| pdb.maxUnavailable | int | `1` |  |
| pdb.minAvailable | string | `nil` |  |
| podAnnotations | object | `{}` |  |
| podLabels | object | `{}` |  |
| podSecurityContext | object | `{}` |  |
| readinessProbe.failureThreshold | int | `2` |  |
| readinessProbe.httpGet.path | string | `"/"` |  |
| readinessProbe.httpGet.port | string | `"http"` |  |
| readinessProbe.periodSeconds | int | `5` |  |
| replicaCount | int | `2` |  |
| resources | object | `{}` |  |
| securityContext | object | `{}` |  |
| service.annotations | object | `{}` |  |
| service.enabled | bool | `true` |  |
| service.extraPorts | list | `[]` |  |
| service.port | int | `80` |  |
| service.type | string | `"ClusterIP"` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.automount | bool | `false` |  |
| serviceAccount.create | bool | `true` |  |
| serviceAccount.name | string | `""` |  |
| sloth.annotations | object | `{}` |  |
| sloth.enabled | bool | `false` |  |
| sloth.labels | object | `{}` |  |
| sloth.namespace | string | `""` |  |
| sloth.service | string | `""` |  |
| sloth.slos | list | `[]` |  |
| startupProbe | object | `{}` |  |
| terminationGracePeriodSeconds | int | `30` |  |
| tolerations | list | `[]` |  |
| topologySpreadConstraints | list | `[]` |  |
| updateStrategy.rollingUpdate.maxSurge | int | `1` |  |
| updateStrategy.rollingUpdate.maxUnavailable | int | `0` |  |
| updateStrategy.type | string | `"RollingUpdate"` |  |
| volumeMounts | list | `[]` |  |
| volumes | list | `[]` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
