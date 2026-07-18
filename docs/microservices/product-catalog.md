# Product Catalog Service

> **Mentor note:** Study this file with the source tree open. Diagrams first, then code, then YAML.  
> **Shared YAML deep-dive:** [_KUBERNETES_YAML_HELM_ARGOCD.md](./_KUBERNETES_YAML_HELM_ARGOCD.md) · **Map:** [_SERVICE_MAP.md](./_SERVICE_MAP.md) · **Index:** [README.md](./README.md)

---

## 1. Why this service exists

Serves product listings over gRPC from JSON product files.

| | |
|--|--|
| **Language** | Go |
| **Source** | `src/product-catalog/` |
| **Entry** | `main.go` |
| **K8s folder** | `kubernetes/productcatalog/` |
| **Container name** | `productcatalogservice` |
| **Protocol** | gRPC |
| **Docker port** | 3550 |
| **K8s port** | 8080 |

---

## 2. Where it sits in the architecture

```mermaid
flowchart LR
  S["product-catalog"]
  frontend["frontend"] --> S
  checkout["checkout"] --> S
  recommendation["recommendation"] --> S
  S --> out_flagd["flagd"]
  S --> out_otel_collector["otel-collector"]
```

### Callers / callees

| Direction | Services |
|-----------|----------|
| **Who calls me** | `frontend`, `checkout`, `recommendation` |
| **Who I call** | `flagd`, `otel-collector` |

---

## 3. Source code architecture (how to read the code)

1. Open `src/product-catalog/` and locate `main.go`.
2. Find listen/bind port (env `*_PORT` or hardcoded) — in Docker often **3550**, in K8s usually **8080**.
3. Find outbound clients (gRPC stubs, HTTP, Kafka, Redis) matching the callees table.
4. Find OpenTelemetry setup (`OTEL_*` env, auto-instrumentation, or SDK init).
5. Shared API contracts live in `pb/demo.proto` for gRPC services.

```mermaid
flowchart TB
  subgraph Code["src/product-catalog"]
    Main["main.go"]
    Biz[Business logic]
    Client[Outbound clients]
    OTel[Telemetry hooks]
  end
  Main --> Biz
  Biz --> Client
  Main --> OTel
  Client --> Net["Network: gRPC"]
  OTel --> Collector[OTEL collector endpoint]
```

---

## 4. Request scenario

**User browses catalog → frontend → product-catalog.ListProducts / GetProduct.**

```mermaid
sequenceDiagram
  actor User
  participant Proxy as frontend-proxy
  participant FE as frontend
  participant PC as product-catalog
  participant Flagd as flagd
  User->>Proxy: GET / / product page
  Proxy->>FE: route
  FE->>PC: ListProducts / GetProduct (gRPC :8080)
  PC->>Flagd: optional flag eval
  Flagd-->>PC: flag
  PC-->>FE: Product(s)
  FE-->>User: UI
```

Also used by **checkout** (validate items) and **recommendation** (load product details):

```mermaid
flowchart LR
  FE[frontend] --> PC[product-catalog]
  CHK[checkout] --> PC
  REC[recommendation] --> PC
  PC --> FLAG[flagd]
  PC --> OTEL[otel collector]
```

---

## 5. Kubernetes: how this service is deployed

```mermaid
flowchart TB
  subgraph Git["Git: kubernetes/productcatalog/"]
    D[deploy.yaml]
    SV[svc.yaml]
  end
  subgraph Cluster["EKS namespace otel-demo"]
    Pod["Pod container: productcatalogservice"]
    Svc["Service ClusterIP :8080"]
  end
  D -->|Argo CD sync| Pod
  SV -->|Argo CD sync| Svc
  Svc -->|selects labels| Pod
```

### Files

| File | Purpose |
|------|---------|
| `kubernetes/productcatalog/deploy.yaml` | Deployment (Pods) |
| `kubernetes/productcatalog/svc.yaml` | ClusterIP Service |

### Deployment essentials (read `deploy.yaml`)

| Field | This service |
|-------|----------------|
| `metadata.name` | `opentelemetry-demo-productcatalogservice` (typical) |
| `spec.replicas` | Usually `1` |
| `spec.selector` / pod labels | Must match Service selector |
| `containers[].name` | `productcatalogservice` |
| `containers[].image` | CI sets `DOCKER_USERNAME/product-catalog:<run_id>` (or upstream `ghcr.io/...`) |
| `containerPort` | 8080 |
| `initContainers` | No |
| `serviceAccountName` | `opentelemetry-demo` |

### Environment variables present in deploy.yaml

| Env var | Notes |
|---------|-------|
| `OTEL_SERVICE_NAME` | See deploy.yaml / shared OTEL guide |
| `OTEL_COLLECTOR_NAME` | See deploy.yaml / shared OTEL guide |
| `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE` | See deploy.yaml / shared OTEL guide |
| `PRODUCT_CATALOG_SERVICE_PORT` | See deploy.yaml / shared OTEL guide |
| `FLAGD_HOST` | See deploy.yaml / shared OTEL guide |
| `FLAGD_PORT` | See deploy.yaml / shared OTEL guide |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | See deploy.yaml / shared OTEL guide |
| `OTEL_RESOURCE_ATTRIBUTES` | See deploy.yaml / shared OTEL guide |

Boilerplate `OTEL_*` meaning: see [_KUBERNETES_YAML_HELM_ARGOCD.md](./_KUBERNETES_YAML_HELM_ARGOCD.md).

### Service (ClusterIP) — if present

```yaml\n# kubernetes/productcatalog/svc.yaml — key ideas:\n# type: ClusterIP\n# port/targetPort: 8080\n# selector: opentelemetry.io/name: opentelemetry-demo-productcatalogservice\n```

### DNS name used by other services

```text
opentelemetry-demo-productcatalogservice:8080
```

Example from another Deployment env: `PRODUCT_CATALOG_SERVICE_ADDR` / `CART_SERVICE_ADDR` style values use `opentelemetry-demo-<component>:8080`.

---

## 6. GitOps / CI for this service

| | |
|--|--|
| **CI workflow** | product-catalog-ci (.github/workflows/ci.yaml) — Go build/test/lint + Docker |
| **Image update** | reusable job patches `image:` for container `productcatalogservice` in `deploy.yaml` |
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

- Role: Serves product listings over gRPC from JSON product files.
- Protocol: gRPC — Docker port 3550 vs K8s 8080.
- Dependencies: callers `frontend, checkout, recommendation`; callees `flagd, otel-collector`.
- Manifests: `kubernetes/productcatalog/` — has Service.
- Discovery: Kubernetes DNS `opentelemetry-demo-productcatalogservice:8080`.
- Observability: `OTEL_EXPORTER_OTLP_ENDPOINT` points at collector Service name.
- GitOps: CI never runs `kubectl apply`; it only updates Git for Argo.
- Chaos/demo: many services use `FLAGD_HOST` / `FLAGD_PORT` for Open Feature.

---

## 8. Quick quiz

**Q1.** Who calls `product-catalog` in the shop?  
**A:** frontend, checkout, recommendation.

**Q2.** What Kubernetes DNS would another Pod use (if any)?  
**A:** `opentelemetry-demo-productcatalogservice:8080`.

**Q3.** Does Argo deploy from `complete-deploy.yaml` or per-service folders?  
**A:** Per-service folders under `kubernetes/`; `complete-deploy.yaml` is excluded.

---

## 9. Related reading

- [README.md](./README.md) — learning path  
- [_SERVICE_MAP.md](./_SERVICE_MAP.md) — place-order sequence  
- [_KUBERNETES_YAML_HELM_ARGOCD.md](./_KUBERNETES_YAML_HELM_ARGOCD.md) — YAML line-by-line  
- [../INTERVIEW_QUESTIONS.md](../INTERVIEW_QUESTIONS.md)  
