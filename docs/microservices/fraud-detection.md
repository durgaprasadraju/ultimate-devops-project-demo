# Fraud Detection Service

> **Mentor note:** Study this file with the source tree open. Diagrams first, then code, then YAML.  
> **Shared YAML deep-dive:** [_KUBERNETES_YAML_HELM_ARGOCD.md](./_KUBERNETES_YAML_HELM_ARGOCD.md) · **Map:** [_SERVICE_MAP.md](./_SERVICE_MAP.md) · **Index:** [README.md](./README.md)

---

## 1. Why this service exists

Kafka consumer inspecting orders for fraud demos.

| | |
|--|--|
| **Language** | Kotlin |
| **Source** | `src/fraud-detection/` |
| **Entry** | `src/main/kotlin/frauddetection/main.kt` |
| **K8s folder** | `kubernetes/frauddetection/` |
| **Container name** | `frauddetectionservice` |
| **Protocol** | Kafka consumer |
| **Docker port** | n/a |
| **K8s port** | n/a |

---

## 2. Where it sits in the architecture

```mermaid
flowchart LR
  S["fraud-detection"]
  kafka_orders_topic["kafka (orders topic)"] --> S
  S --> out_kafka["kafka"]
  S --> out_flagd["flagd"]
  S --> out_otel["otel"]
```

### Callers / callees

| Direction | Services |
|-----------|----------|
| **Who calls me** | `kafka (orders topic)` |
| **Who I call** | `kafka`, `flagd`, `otel` |

---

## 3. Source code architecture (how to read the code)

1. Open `src/fraud-detection/` and locate `src/main/kotlin/frauddetection/main.kt`.
2. Find listen/bind port (env `*_PORT` or hardcoded) — in Docker often **n/a**, in K8s usually **n/a**.
3. Find outbound clients (gRPC stubs, HTTP, Kafka, Redis) matching the callees table.
4. Find OpenTelemetry setup (`OTEL_*` env, auto-instrumentation, or SDK init).
5. Shared API contracts live in `pb/demo.proto` for gRPC services.

```mermaid
flowchart TB
  subgraph Code["src/fraud-detection"]
    Main["src/main/kotlin/frauddetection/main.kt"]
    Biz[Business logic]
    Client[Outbound clients]
    OTel[Telemetry hooks]
  end
  Main --> Biz
  Biz --> Client
  Main --> OTel
  Client --> Net["Network: Kafka consumer"]
  OTel --> Collector[OTEL collector endpoint]
```

---

## 4. Request scenario

**checkout → Kafka → fraud-detection.**

```mermaid
sequenceDiagram
  participant Caller as Caller
  participant S as fraud-detection
  participant Dep as Downstream
  Caller->>S: Request (Kafka consumer)
  S->>Dep: Calls (if any)
  Dep-->>S: Response
  S-->>Caller: Response
```

---

## 5. Kubernetes: how this service is deployed

```mermaid
flowchart TB
  subgraph Git["Git: kubernetes/frauddetection/"]
    D[deploy.yaml]
    SV[svc.yaml]
  end
  subgraph Cluster["EKS namespace otel-demo"]
    Pod["Pod container: frauddetectionservice"]
    Svc["Service ClusterIP :n/a"]
  end
  D -->|Argo CD sync| Pod
  SV -->|Argo CD sync| Svc
  Svc -->|selects labels| Pod
```

### Files

| File | Purpose |
|------|---------|
| `kubernetes/frauddetection/deploy.yaml` | Deployment (Pods) |
| `kubernetes/frauddetection/svc.yaml` | **None** — no ClusterIP (worker/consumer or special case) |

### Deployment essentials (read `deploy.yaml`)

| Field | This service |
|-------|----------------|
| `metadata.name` | `opentelemetry-demo-frauddetectionservice` (typical) |
| `spec.replicas` | Usually `1` |
| `spec.selector` / pod labels | Must match Service selector |
| `containers[].name` | `frauddetectionservice` |
| `containers[].image` | CI sets `DOCKER_USERNAME/fraud-detection:<run_id>` (or upstream `ghcr.io/...`) |
| `containerPort` | n/a |
| `initContainers` | Yes — wait for dependency (see YAML) |
| `serviceAccountName` | `opentelemetry-demo` |

### Environment variables present in deploy.yaml

| Env var | Notes |
|---------|-------|
| `OTEL_SERVICE_NAME` | See deploy.yaml / shared OTEL guide |
| `OTEL_COLLECTOR_NAME` | See deploy.yaml / shared OTEL guide |
| `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE` | See deploy.yaml / shared OTEL guide |
| `KAFKA_SERVICE_ADDR` | See deploy.yaml / shared OTEL guide |
| `FLAGD_HOST` | See deploy.yaml / shared OTEL guide |
| `FLAGD_PORT` | See deploy.yaml / shared OTEL guide |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | See deploy.yaml / shared OTEL guide |
| `OTEL_RESOURCE_ATTRIBUTES` | See deploy.yaml / shared OTEL guide |

Boilerplate `OTEL_*` meaning: see [_KUBERNETES_YAML_HELM_ARGOCD.md](./_KUBERNETES_YAML_HELM_ARGOCD.md).

### Service (ClusterIP) — if present

_No svc.yaml — other pods do not dial this service by ClusterIP DNS._

### DNS name used by other services

```text
n/a (no Service)
```

Example from another Deployment env: `PRODUCT_CATALOG_SERVICE_ADDR` / `CART_SERVICE_ADDR` style values use `opentelemetry-demo-<component>:8080`.

---

## 6. GitOps / CI for this service

| | |
|--|--|
| **CI workflow** | microservices-ci (needs OTEL_JAVA_AGENT_VERSION) |
| **Image update** | reusable job patches `image:` for container `frauddetectionservice` in `deploy.yaml` |
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

- Role: Kafka consumer inspecting orders for fraud demos.
- Protocol: Kafka consumer — Docker port n/a vs K8s n/a.
- Dependencies: callers `kafka (orders topic)`; callees `kafka, flagd, otel`.
- Manifests: `kubernetes/frauddetection/` — no Service (consumer/worker).
- Discovery: Kubernetes DNS `n/a (no Service)`.
- Observability: `OTEL_EXPORTER_OTLP_ENDPOINT` points at collector Service name.
- GitOps: CI never runs `kubectl apply`; it only updates Git for Argo.
- Chaos/demo: many services use `FLAGD_HOST` / `FLAGD_PORT` for Open Feature.

---

## 8. Quick quiz

**Q1.** Who calls `fraud-detection` in the shop?  
**A:** kafka (orders topic).

**Q2.** What Kubernetes DNS would another Pod use (if any)?  
**A:** `n/a (no Service)`.

**Q3.** Does Argo deploy from `complete-deploy.yaml` or per-service folders?  
**A:** Per-service folders under `kubernetes/`; `complete-deploy.yaml` is excluded.

---

## 9. Related reading

- [README.md](./README.md) — learning path  
- [_SERVICE_MAP.md](./_SERVICE_MAP.md) — place-order sequence  
- [_KUBERNETES_YAML_HELM_ARGOCD.md](./_KUBERNETES_YAML_HELM_ARGOCD.md) — YAML line-by-line  
- [../INTERVIEW_QUESTIONS.md](../INTERVIEW_QUESTIONS.md)  
