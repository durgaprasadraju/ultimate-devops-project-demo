# Checkout Service

> **Mentor note:** Study this file with the source tree open. Diagrams first, then code, then YAML.  
> **Shared YAML deep-dive:** [_KUBERNETES_YAML_HELM_ARGOCD.md](./_KUBERNETES_YAML_HELM_ARGOCD.md) · **Map:** [_SERVICE_MAP.md](./_SERVICE_MAP.md) · **Index:** [README.md](./README.md)

---

## 1. Why this service exists

Order orchestrator: charges, ships, emails, publishes Kafka events.

| | |
|--|--|
| **Language** | Go |
| **Source** | `src/checkout/` |
| **Entry** | `main.go` |
| **K8s folder** | `kubernetes/checkout/` |
| **Container name** | `checkoutservice` |
| **Protocol** | gRPC |
| **Docker port** | 5050 |
| **K8s port** | 8080 |

---

## 2. Where it sits in the architecture

```mermaid
flowchart LR
  S["checkout"]
  frontend["frontend"] --> S
  S --> out_cart["cart"]
  S --> out_currency["currency"]
  S --> out_email["email"]
  S --> out_payment["payment"]
  S --> out_product_catalog["product-catalog"]
  S --> out_shipping["shipping"]
  S --> out_kafka["kafka"]
  S --> out_flagd["flagd"]
  S --> out_otel["otel"]
```

### Callers / callees

| Direction | Services |
|-----------|----------|
| **Who calls me** | `frontend` |
| **Who I call** | `cart`, `currency`, `email`, `payment`, `product-catalog`, `shipping`, `kafka`, `flagd`, `otel` |

---

## 3. Source code architecture (how to read the code)

1. Open `src/checkout/` and locate `main.go`.
2. Find listen/bind port (env `*_PORT` or hardcoded) — in Docker often **5050**, in K8s usually **8080**.
3. Find outbound clients (gRPC stubs, HTTP, Kafka, Redis) matching the callees table.
4. Find OpenTelemetry setup (`OTEL_*` env, auto-instrumentation, or SDK init).
5. Shared API contracts live in `pb/demo.proto` for gRPC services.

```mermaid
flowchart TB
  subgraph Code["src/checkout"]
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

**Place order → frontend → checkout → fans out to cart/payment/shipping/… → Kafka.**

Full diagram: [_SERVICE_MAP.md § Place order](./_SERVICE_MAP.md). Short form:

```mermaid
sequenceDiagram
  participant FE as frontend
  participant CHK as checkout
  participant Cart as cart
  participant Pay as payment
  participant Ship as shipping
  participant Kafka as kafka
  FE->>CHK: PlaceOrder
  CHK->>Cart: GetCart
  CHK->>Pay: Charge
  CHK->>Ship: ShipOrder / quote path
  CHK->>Kafka: Produce order
  CHK-->>FE: OrderResult
```

```mermaid
flowchart TB
  CHK[checkout]
  CHK --> Cart
  CHK --> Catalog[product-catalog]
  CHK --> Currency
  CHK --> Payment
  CHK --> Shipping
  CHK --> Email
  CHK --> Kafka
  CHK --> Flagd
  Shipping --> Quote
```

---

## 5. Kubernetes: how this service is deployed

```mermaid
flowchart TB
  subgraph Git["Git: kubernetes/checkout/"]
    D[deploy.yaml]
    SV[svc.yaml]
  end
  subgraph Cluster["EKS namespace otel-demo"]
    Pod["Pod container: checkoutservice"]
    Svc["Service ClusterIP :8080"]
  end
  D -->|Argo CD sync| Pod
  SV -->|Argo CD sync| Svc
  Svc -->|selects labels| Pod
```

### Files

| File | Purpose |
|------|---------|
| `kubernetes/checkout/deploy.yaml` | Deployment (Pods) |
| `kubernetes/checkout/svc.yaml` | ClusterIP Service |

### Deployment essentials (read `deploy.yaml`)

| Field | This service |
|-------|----------------|
| `metadata.name` | `opentelemetry-demo-checkoutservice` (typical) |
| `spec.replicas` | Usually `1` |
| `spec.selector` / pod labels | Must match Service selector |
| `containers[].name` | `checkoutservice` |
| `containers[].image` | CI sets `DOCKER_USERNAME/checkout:<run_id>` (or upstream `ghcr.io/...`) |
| `containerPort` | 8080 |
| `initContainers` | Yes — wait for dependency (see YAML) |
| `serviceAccountName` | `opentelemetry-demo` |

### Environment variables present in deploy.yaml

| Env var | Notes |
|---------|-------|
| `OTEL_SERVICE_NAME` | See deploy.yaml / shared OTEL guide |
| `OTEL_COLLECTOR_NAME` | See deploy.yaml / shared OTEL guide |
| `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE` | See deploy.yaml / shared OTEL guide |
| `CHECKOUT_SERVICE_PORT` | See deploy.yaml / shared OTEL guide |
| `CART_SERVICE_ADDR` | See deploy.yaml / shared OTEL guide |
| `CURRENCY_SERVICE_ADDR` | See deploy.yaml / shared OTEL guide |
| `EMAIL_SERVICE_ADDR` | See deploy.yaml / shared OTEL guide |
| `PAYMENT_SERVICE_ADDR` | See deploy.yaml / shared OTEL guide |
| `PRODUCT_CATALOG_SERVICE_ADDR` | See deploy.yaml / shared OTEL guide |
| `SHIPPING_SERVICE_ADDR` | See deploy.yaml / shared OTEL guide |
| `KAFKA_SERVICE_ADDR` | See deploy.yaml / shared OTEL guide |
| `FLAGD_HOST` | See deploy.yaml / shared OTEL guide |
| `FLAGD_PORT` | See deploy.yaml / shared OTEL guide |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | See deploy.yaml / shared OTEL guide |
| `OTEL_RESOURCE_ATTRIBUTES` | See deploy.yaml / shared OTEL guide |

Boilerplate `OTEL_*` meaning: see [_KUBERNETES_YAML_HELM_ARGOCD.md](./_KUBERNETES_YAML_HELM_ARGOCD.md).

### Service (ClusterIP) — if present

```yaml\n# kubernetes/checkout/svc.yaml — key ideas:\n# type: ClusterIP\n# port/targetPort: 8080\n# selector: opentelemetry.io/name: opentelemetry-demo-checkoutservice\n```

### DNS name used by other services

```text
opentelemetry-demo-checkoutservice:8080
```

Example from another Deployment env: `PRODUCT_CATALOG_SERVICE_ADDR` / `CART_SERVICE_ADDR` style values use `opentelemetry-demo-<component>:8080`.

---

## 6. GitOps / CI for this service

| | |
|--|--|
| **CI workflow** | microservices-ci |
| **Image update** | reusable job patches `image:` for container `checkoutservice` in `deploy.yaml` |
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

- Role: Order orchestrator: charges, ships, emails, publishes Kafka events.
- Protocol: gRPC — Docker port 5050 vs K8s 8080.
- Dependencies: callers `frontend`; callees `cart, currency, email, payment, product-catalog, shipping, kafka, flagd, otel`.
- Manifests: `kubernetes/checkout/` — has Service.
- Discovery: Kubernetes DNS `opentelemetry-demo-checkoutservice:8080`.
- Observability: `OTEL_EXPORTER_OTLP_ENDPOINT` points at collector Service name.
- GitOps: CI never runs `kubectl apply`; it only updates Git for Argo.
- Chaos/demo: many services use `FLAGD_HOST` / `FLAGD_PORT` for Open Feature.

---

## 8. Quick quiz

**Q1.** Who calls `checkout` in the shop?  
**A:** frontend.

**Q2.** What Kubernetes DNS would another Pod use (if any)?  
**A:** `opentelemetry-demo-checkoutservice:8080`.

**Q3.** Does Argo deploy from `complete-deploy.yaml` or per-service folders?  
**A:** Per-service folders under `kubernetes/`; `complete-deploy.yaml` is excluded.

---

## 9. Related reading

- [README.md](./README.md) — learning path  
- [_SERVICE_MAP.md](./_SERVICE_MAP.md) — place-order sequence  
- [_KUBERNETES_YAML_HELM_ARGOCD.md](./_KUBERNETES_YAML_HELM_ARGOCD.md) — YAML line-by-line  
- [../INTERVIEW_QUESTIONS.md](../INTERVIEW_QUESTIONS.md)  
