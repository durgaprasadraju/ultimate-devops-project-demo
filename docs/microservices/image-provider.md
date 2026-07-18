# Image Provider

> **Mentor note:** Study this file with the source tree open. Diagrams first, then code, then YAML.  
> **Shared YAML deep-dive:** [_KUBERNETES_YAML_HELM_ARGOCD.md](./_KUBERNETES_YAML_HELM_ARGOCD.md) · **Map:** [_SERVICE_MAP.md](./_SERVICE_MAP.md) · **Index:** [README.md](./README.md)

---

## 1. Why this service exists

Serves static product images.

| | |
|--|--|
| **Language** | Nginx + OTel module |
| **Source** | `src/image-provider/` |
| **Entry** | `nginx.conf.template, static/` |
| **K8s folder** | `kubernetes/imageprovider/` |
| **Container name** | `imageprovider` |
| **Protocol** | HTTP |
| **Docker port** | 8081 |
| **K8s port** | 8081 |

---

## 2. Where it sits in the architecture

```mermaid
flowchart LR
  S["image-provider"]
  frontend-proxy["frontend-proxy"] --> S
  S --> out_otel["otel"]
```

### Callers / callees

| Direction | Services |
|-----------|----------|
| **Who calls me** | `frontend-proxy` |
| **Who I call** | `otel` |

---

## 3. Source code architecture (how to read the code)

1. Open `src/image-provider/` and locate `nginx.conf.template, static/`.
2. Find listen/bind port (env `*_PORT` or hardcoded) — in Docker often **8081**, in K8s usually **8081**.
3. Find outbound clients (gRPC stubs, HTTP, Kafka, Redis) matching the callees table.
4. Find OpenTelemetry setup (`OTEL_*` env, auto-instrumentation, or SDK init).
5. Shared API contracts live in `pb/demo.proto` for gRPC services.

```mermaid
flowchart TB
  subgraph Code["src/image-provider"]
    Main["nginx.conf.template, static/"]
    Biz[Business logic]
    Client[Outbound clients]
    OTel[Telemetry hooks]
  end
  Main --> Biz
  Biz --> Client
  Main --> OTel
  Client --> Net["Network: HTTP"]
  OTel --> Collector[OTEL collector endpoint]
```

---

## 4. Request scenario

**Browser image URLs → proxy → image-provider.**

```mermaid
sequenceDiagram
  participant Caller as Caller
  participant S as image-provider
  participant Dep as Downstream
  Caller->>S: Request (HTTP)
  S->>Dep: Calls (if any)
  Dep-->>S: Response
  S-->>Caller: Response
```

---

## 5. Kubernetes: how this service is deployed

```mermaid
flowchart TB
  subgraph Git["Git: kubernetes/imageprovider/"]
    D[deploy.yaml]
    SV[svc.yaml]
  end
  subgraph Cluster["EKS namespace otel-demo"]
    Pod["Pod container: imageprovider"]
    Svc["Service ClusterIP :8081"]
  end
  D -->|Argo CD sync| Pod
  SV -->|Argo CD sync| Svc
  Svc -->|selects labels| Pod
```

### Files

| File | Purpose |
|------|---------|
| `kubernetes/imageprovider/deploy.yaml` | Deployment (Pods) |
| `kubernetes/imageprovider/svc.yaml` | ClusterIP Service |

### Deployment essentials (read `deploy.yaml`)

| Field | This service |
|-------|----------------|
| `metadata.name` | `opentelemetry-demo-imageprovider` (typical) |
| `spec.replicas` | Usually `1` |
| `spec.selector` / pod labels | Must match Service selector |
| `containers[].name` | `imageprovider` |
| `containers[].image` | CI sets `DOCKER_USERNAME/image-provider:<run_id>` (or upstream `ghcr.io/...`) |
| `containerPort` | 8081 |
| `initContainers` | No |
| `serviceAccountName` | `opentelemetry-demo` |

### Environment variables present in deploy.yaml

| Env var | Notes |
|---------|-------|
| `OTEL_SERVICE_NAME` | See deploy.yaml / shared OTEL guide |
| `OTEL_COLLECTOR_NAME` | See deploy.yaml / shared OTEL guide |
| `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE` | See deploy.yaml / shared OTEL guide |
| `IMAGE_PROVIDER_PORT` | See deploy.yaml / shared OTEL guide |
| `OTEL_COLLECTOR_PORT_GRPC` | See deploy.yaml / shared OTEL guide |
| `OTEL_COLLECTOR_HOST` | See deploy.yaml / shared OTEL guide |
| `OTEL_RESOURCE_ATTRIBUTES` | See deploy.yaml / shared OTEL guide |

Boilerplate `OTEL_*` meaning: see [_KUBERNETES_YAML_HELM_ARGOCD.md](./_KUBERNETES_YAML_HELM_ARGOCD.md).

### Service (ClusterIP) — if present

```yaml\n# kubernetes/imageprovider/svc.yaml — key ideas:\n# type: ClusterIP\n# port/targetPort: 8081\n# selector: opentelemetry.io/name: opentelemetry-demo-imageprovider\n```

### DNS name used by other services

```text
opentelemetry-demo-imageprovider:8081
```

Example from another Deployment env: `PRODUCT_CATALOG_SERVICE_ADDR` / `CART_SERVICE_ADDR` style values use `opentelemetry-demo-<component>:8080`.

---

## 6. GitOps / CI for this service

| | |
|--|--|
| **CI workflow** | microservices-ci |
| **Image update** | reusable job patches `image:` for container `imageprovider` in `deploy.yaml` |
| **Deploy** | Argo CD Application `otel-demo` syncs `kubernetes/` (excludes `complete-deploy.yaml`) |

```mermaid
flowchart LR
  Code[src change] --> GHA[GitHub Actions]
  GHA --> Hub[Docker Hub]
  GHA --> Git[Update deploy.yaml]
  Git --> Argo[Argo CD]
  Argo --> EKS[EKS Pod]
```

---

## 7. Interview talking points

- Role: Serves static product images.
- Protocol: HTTP — Docker port 8081 vs K8s 8081.
- Dependencies: callers `frontend-proxy`; callees `otel`.
- Manifests: `kubernetes/imageprovider/` — has Service.
- Discovery: Kubernetes DNS `opentelemetry-demo-imageprovider:8081`.
- Observability: `OTEL_EXPORTER_OTLP_ENDPOINT` points at collector Service name.
- GitOps: CI never runs `kubectl apply`; it only updates Git for Argo.
- Chaos/demo: many services use `FLAGD_HOST` / `FLAGD_PORT` for Open Feature.

---

## 8. Quick quiz

**Q1.** Who calls `image-provider` in the shop?  
**A:** frontend-proxy.

**Q2.** What Kubernetes DNS would another Pod use (if any)?  
**A:** `opentelemetry-demo-imageprovider:8081`.

**Q3.** Does Argo deploy from `complete-deploy.yaml` or per-service folders?  
**A:** Per-service folders under `kubernetes/`; `complete-deploy.yaml` is excluded.

---

## 9. Related reading

- [README.md](./README.md) — learning path  
- [_SERVICE_MAP.md](./_SERVICE_MAP.md) — place-order sequence  
- [_KUBERNETES_YAML_HELM_ARGOCD.md](./_KUBERNETES_YAML_HELM_ARGOCD.md) — YAML line-by-line  
- [../INTERVIEW_QUESTIONS.md](../INTERVIEW_QUESTIONS.md)  
