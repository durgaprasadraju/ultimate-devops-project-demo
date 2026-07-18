# Valkey (Redis-compatible)

> **Mentor note:** Study this file with the source tree open. Diagrams first, then code, then YAML.  
> **Shared YAML deep-dive:** [_KUBERNETES_YAML_HELM_ARGOCD.md](./_KUBERNETES_YAML_HELM_ARGOCD.md) · **Map:** [_SERVICE_MAP.md](./_SERVICE_MAP.md) · **Index:** [README.md](./README.md)

---

## 1. Why this service exists

In-memory store for cart data.

| | |
|--|--|
| **Language** | Valkey |
| **Source** | `(upstream image, no app src)/` |
| **Entry** | `n/a` |
| **K8s folder** | `kubernetes/valkey/` |
| **Container name** | `valkey` |
| **Protocol** | Redis protocol :6379 |
| **Docker port** | 6379 |
| **K8s port** | 6379 |

---

## 2. Where it sits in the architecture

```mermaid
flowchart LR
  S["valkey"]
  cart["cart"] --> S
```

### Callers / callees

| Direction | Services |
|-----------|----------|
| **Who calls me** | `cart` |
| **Who I call** | _none_ |

---

## 3. Source code architecture (how to read the code)

1. Open `(upstream image, no app src)/` and locate `n/a`.
2. Find listen/bind port (env `*_PORT` or hardcoded) — in Docker often **6379**, in K8s usually **6379**.
3. Find outbound clients (gRPC stubs, HTTP, Kafka, Redis) matching the callees table.
4. Find OpenTelemetry setup (`OTEL_*` env, auto-instrumentation, or SDK init).
5. Shared API contracts live in `pb/demo.proto` for gRPC services.

```mermaid
flowchart TB
  subgraph Code["(upstream image, no app src)"]
    Main["n/a"]
    Biz[Business logic]
    Client[Outbound clients]
    OTel[Telemetry hooks]
  end
  Main --> Biz
  Biz --> Client
  Main --> OTel
  Client --> Net["Network: Redis protocol :6379"]
  OTel --> Collector[OTEL collector endpoint]
```

---

## 4. Request scenario

**cart GetCart/AddItem → VALKEY_ADDR.**

```mermaid
sequenceDiagram
  participant Caller as Caller
  participant S as valkey
  participant Dep as Downstream
  Caller->>S: Request (Redis protocol :6379)
  S->>Dep: Calls (if any)
  Dep-->>S: Response
  S-->>Caller: Response
```

---

## 5. Kubernetes: how this service is deployed

```mermaid
flowchart TB
  subgraph Git["Git: kubernetes/valkey/"]
    D[deploy.yaml]
    SV[svc.yaml]
  end
  subgraph Cluster["EKS namespace otel-demo"]
    Pod["Pod container: valkey"]
    Svc["Service ClusterIP :6379"]
  end
  D -->|Argo CD sync| Pod
  SV -->|Argo CD sync| Svc
  Svc -->|selects labels| Pod
```

### Files

| File | Purpose |
|------|---------|
| `kubernetes/valkey/deploy.yaml` | Deployment (Pods) |
| `kubernetes/valkey/svc.yaml` | ClusterIP Service |

### Deployment essentials (read `deploy.yaml`)

| Field | This service |
|-------|----------------|
| `metadata.name` | `opentelemetry-demo-valkey` (typical) |
| `spec.replicas` | Usually `1` |
| `spec.selector` / pod labels | Must match Service selector |
| `containers[].name` | `valkey` |
| `containers[].image` | CI sets `DOCKER_USERNAME/valkey:<run_id>` (or upstream `ghcr.io/...`) |
| `containerPort` | 6379 |
| `initContainers` | No |
| `serviceAccountName` | `opentelemetry-demo` |

### Environment variables present in deploy.yaml

| Env var | Notes |
|---------|-------|
| `OTEL_SERVICE_NAME` | See deploy.yaml / shared OTEL guide |
| `OTEL_COLLECTOR_NAME` | See deploy.yaml / shared OTEL guide |
| `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE` | See deploy.yaml / shared OTEL guide |
| `OTEL_RESOURCE_ATTRIBUTES` | See deploy.yaml / shared OTEL guide |

Boilerplate `OTEL_*` meaning: see [_KUBERNETES_YAML_HELM_ARGOCD.md](./_KUBERNETES_YAML_HELM_ARGOCD.md).

### Service (ClusterIP) — if present

```yaml\n# kubernetes/valkey/svc.yaml — key ideas:\n# type: ClusterIP\n# port/targetPort: 6379\n# selector: opentelemetry.io/name: opentelemetry-demo-valkey\n```

### DNS name used by other services

```text
opentelemetry-demo-valkey:6379
```

Example from another Deployment env: `PRODUCT_CATALOG_SERVICE_ADDR` / `CART_SERVICE_ADDR` style values use `opentelemetry-demo-<component>:8080`.

---

## 6. GitOps / CI for this service

| | |
|--|--|
| **CI workflow** | No app CI — vendor image in deploy.yaml |
| **Image update** | reusable job patches `image:` for container `valkey` in `deploy.yaml` |
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

- Role: In-memory store for cart data.
- Protocol: Redis protocol :6379 — Docker port 6379 vs K8s 6379.
- Dependencies: callers `cart`; callees `none`.
- Manifests: `kubernetes/valkey/` — has Service.
- Discovery: Kubernetes DNS `opentelemetry-demo-valkey:6379`.
- Observability: `OTEL_EXPORTER_OTLP_ENDPOINT` points at collector Service name.
- GitOps: CI never runs `kubectl apply`; it only updates Git for Argo.
- Chaos/demo: many services use `FLAGD_HOST` / `FLAGD_PORT` for Open Feature.

---

## 8. Quick quiz

**Q1.** Who calls `valkey` in the shop?  
**A:** cart.

**Q2.** What Kubernetes DNS would another Pod use (if any)?  
**A:** `opentelemetry-demo-valkey:6379`.

**Q3.** Does Argo deploy from `complete-deploy.yaml` or per-service folders?  
**A:** Per-service folders under `kubernetes/`; `complete-deploy.yaml` is excluded.

---

## 9. Related reading

- [README.md](./README.md) — learning path  
- [_SERVICE_MAP.md](./_SERVICE_MAP.md) — place-order sequence  
- [_KUBERNETES_YAML_HELM_ARGOCD.md](./_KUBERNETES_YAML_HELM_ARGOCD.md) — YAML line-by-line  
- [../INTERVIEW_QUESTIONS.md](../INTERVIEW_QUESTIONS.md)  
