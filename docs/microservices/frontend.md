# Frontend (Next.js UI)

> **Mentor note:** Study this file with the source tree open. Diagrams first, then code, then YAML.  
> **Shared YAML deep-dive:** [_KUBERNETES_YAML_HELM_ARGOCD.md](./_KUBERNETES_YAML_HELM_ARGOCD.md) · **Map:** [_SERVICE_MAP.md](./_SERVICE_MAP.md) · **Index:** [README.md](./README.md)

---

## 1. Why this service exists

Shop UI and BFF-style gateways calling backend gRPC/HTTP services.

| | |
|--|--|
| **Language** | Next.js / TypeScript |
| **Source** | `src/frontend/` |
| **Entry** | `pages/, gateways/` |
| **K8s folder** | `kubernetes/frontend/` |
| **Container name** | `frontend` |
| **Protocol** | HTTP |
| **Docker port** | 8080 |
| **K8s port** | 8080 |

---

## 2. Where it sits in the architecture

```mermaid
flowchart LR
  S["frontend"]
  frontend-proxy["frontend-proxy"] --> S
  load-generator["load-generator"] --> S
  S --> out_ad["ad"]
  S --> out_cart["cart"]
  S --> out_checkout["checkout"]
  S --> out_currency["currency"]
  S --> out_product_catalog["product-catalog"]
  S --> out_recommendation["recommendation"]
  S --> out_shipping["shipping"]
  S --> out_flagd["flagd"]
  S --> out_otel["otel"]
```

### Callers / callees

| Direction | Services |
|-----------|----------|
| **Who calls me** | `frontend-proxy`, `load-generator` |
| **Who I call** | `ad`, `cart`, `checkout`, `currency`, `product-catalog`, `recommendation`, `shipping`, `flagd`, `otel` |

---

## 3. Source code architecture (how to read the code)

1. Open `src/frontend/` and locate `pages/, gateways/`.
2. Find listen/bind port (env `*_PORT` or hardcoded) — in Docker often **8080**, in K8s usually **8080**.
3. Find outbound clients (gRPC stubs, HTTP, Kafka, Redis) matching the callees table.
4. Find OpenTelemetry setup (`OTEL_*` env, auto-instrumentation, or SDK init).
5. Shared API contracts live in `pb/demo.proto` for gRPC services.

```mermaid
flowchart TB
  subgraph Code["src/frontend"]
    Main["pages/, gateways/"]
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

**Browser hits Envoy → frontend pages → gateways call microservices.**

```mermaid
sequenceDiagram
  participant Caller as Caller
  participant S as frontend
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
  subgraph Git["Git: kubernetes/frontend/"]
    D[deploy.yaml]
    SV[svc.yaml]
  end
  subgraph Cluster["EKS namespace otel-demo"]
    Pod["Pod container: frontend"]
    Svc["Service ClusterIP :8080"]
  end
  D -->|Argo CD sync| Pod
  SV -->|Argo CD sync| Svc
  Svc -->|selects labels| Pod
```

### Files

| File | Purpose |
|------|---------|
| `kubernetes/frontend/deploy.yaml` | Deployment (Pods) |
| `kubernetes/frontend/svc.yaml` | ClusterIP Service |

### Deployment essentials (read `deploy.yaml`)

| Field | This service |
|-------|----------------|
| `metadata.name` | `opentelemetry-demo-frontend` (typical) |
| `spec.replicas` | Usually `1` |
| `spec.selector` / pod labels | Must match Service selector |
| `containers[].name` | `frontend` |
| `containers[].image` | CI sets `DOCKER_USERNAME/frontend:<run_id>` (or upstream `ghcr.io/...`) |
| `containerPort` | 8080 |
| `initContainers` | No |
| `serviceAccountName` | `opentelemetry-demo` |

### Environment variables present in deploy.yaml

| Env var | Notes |
|---------|-------|
| `OTEL_SERVICE_NAME` | See deploy.yaml / shared OTEL guide |
| `OTEL_COLLECTOR_NAME` | See deploy.yaml / shared OTEL guide |
| `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE` | See deploy.yaml / shared OTEL guide |
| `FRONTEND_PORT` | See deploy.yaml / shared OTEL guide |
| `FRONTEND_ADDR` | See deploy.yaml / shared OTEL guide |
| `AD_SERVICE_ADDR` | See deploy.yaml / shared OTEL guide |
| `CART_SERVICE_ADDR` | See deploy.yaml / shared OTEL guide |
| `CHECKOUT_SERVICE_ADDR` | See deploy.yaml / shared OTEL guide |
| `CURRENCY_SERVICE_ADDR` | See deploy.yaml / shared OTEL guide |
| `PRODUCT_CATALOG_SERVICE_ADDR` | See deploy.yaml / shared OTEL guide |
| `RECOMMENDATION_SERVICE_ADDR` | See deploy.yaml / shared OTEL guide |
| `SHIPPING_SERVICE_ADDR` | See deploy.yaml / shared OTEL guide |
| `FLAGD_HOST` | See deploy.yaml / shared OTEL guide |
| `FLAGD_PORT` | See deploy.yaml / shared OTEL guide |
| `OTEL_COLLECTOR_HOST` | See deploy.yaml / shared OTEL guide |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | See deploy.yaml / shared OTEL guide |
| `WEB_OTEL_SERVICE_NAME` | See deploy.yaml / shared OTEL guide |
| `PUBLIC_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | See deploy.yaml / shared OTEL guide |
| `OTEL_RESOURCE_ATTRIBUTES` | See deploy.yaml / shared OTEL guide |

Boilerplate `OTEL_*` meaning: see [_KUBERNETES_YAML_HELM_ARGOCD.md](./_KUBERNETES_YAML_HELM_ARGOCD.md).

### Service (ClusterIP) — if present

```yaml\n# kubernetes/frontend/svc.yaml — key ideas:\n# type: ClusterIP\n# port/targetPort: 8080\n# selector: opentelemetry.io/name: opentelemetry-demo-frontend\n```

### DNS name used by other services

```text
opentelemetry-demo-frontend:8080
```

Example from another Deployment env: `PRODUCT_CATALOG_SERVICE_ADDR` / `CART_SERVICE_ADDR` style values use `opentelemetry-demo-<component>:8080`.

---

## 6. GitOps / CI for this service

| | |
|--|--|
| **CI workflow** | microservices-ci |
| **Image update** | reusable job patches `image:` for container `frontend` in `deploy.yaml` |
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

- Role: Shop UI and BFF-style gateways calling backend gRPC/HTTP services.
- Protocol: HTTP — Docker port 8080 vs K8s 8080.
- Dependencies: callers `frontend-proxy, load-generator`; callees `ad, cart, checkout, currency, product-catalog, recommendation, shipping, flagd, otel`.
- Manifests: `kubernetes/frontend/` — has Service.
- Discovery: Kubernetes DNS `opentelemetry-demo-frontend:8080`.
- Observability: `OTEL_EXPORTER_OTLP_ENDPOINT` points at collector Service name.
- GitOps: CI never runs `kubectl apply`; it only updates Git for Argo.
- Chaos/demo: many services use `FLAGD_HOST` / `FLAGD_PORT` for Open Feature.

---

## 8. Quick quiz

**Q1.** Who calls `frontend` in the shop?  
**A:** frontend-proxy, load-generator.

**Q2.** What Kubernetes DNS would another Pod use (if any)?  
**A:** `opentelemetry-demo-frontend:8080`.

**Q3.** Does Argo deploy from `complete-deploy.yaml` or per-service folders?  
**A:** Per-service folders under `kubernetes/`; `complete-deploy.yaml` is excluded.

---

## 9. Related reading

- [README.md](./README.md) — learning path  
- [_SERVICE_MAP.md](./_SERVICE_MAP.md) — place-order sequence  
- [_KUBERNETES_YAML_HELM_ARGOCD.md](./_KUBERNETES_YAML_HELM_ARGOCD.md) — YAML line-by-line  
- [../INTERVIEW_QUESTIONS.md](../INTERVIEW_QUESTIONS.md)  
