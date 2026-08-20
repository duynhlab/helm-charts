# duynh

`duynh` is a small reusable Helm application chart for stateless microservices on Amazon EKS. Install it once per microservice so deployments, rollbacks, scaling, and routing remain independent.

The chart targets Kubernetes 1.34 and works with Helm 3.21 or Helm 4.2. Envoy Gateway integration uses the stable Gateway API `HTTPRoute` resource.

## What it creates

- Deployment and ClusterIP Service
- Optional HorizontalPodAutoscaler (`autoscaling/v2`)
- Optional PodDisruptionBudget (`policy/v1`)
- Optional ServiceAccount
- Optional HTTPRoute (`gateway.networking.k8s.io/v1`)

The chart deliberately does not create a Gateway, GatewayClass, secrets, RBAC, monitoring CRDs, or Envoy-specific policies. Those belong to the platform layer or to an explicit service requirement.

## Requirements

- Kubernetes 1.30 or newer; CI renders against Kubernetes 1.34
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

Health probes are raw Kubernetes probe objects. A liveness probe should normally check only the process itself; use readiness for whether the pod should receive traffic.

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
