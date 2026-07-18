# Service Map & Request Flows (with diagrams)

> Study this file until you can redraw the diagrams on a whiteboard from memory.  
> Index: [README.md](./README.md)

---

## 1. Full shop topology

```mermaid
flowchart TB
    subgraph Users["Users & traffic"]
        B[Browser]
        L[load-generator / Locust]
    end

    subgraph Edge["Edge"]
        P[frontend-proxy Envoy :8080]
    end

    subgraph UI["Presentation"]
        F[frontend Next.js]
        I[image-provider]
        FU[flagd-ui]
    end

    subgraph Core["Core commerce"]
        CAT[product-catalog]
        CART[cart]
        CHK[checkout]
        PAY[payment]
        SHIP[shipping]
        CUR[currency]
        MAIL[email]
        AD[ad]
        REC[recommendation]
        QUOTE[quote]
    end

    subgraph Data["State & messaging"]
        V[valkey]
        K[kafka]
    end

    subgraph Workers["Async workers"]
        ACC[accounting]
        FR[fraud-detection]
    end

    subgraph Flags["Feature flags"]
        FD[flagd]
    end

    B --> P
    L --> P
    P --> F
    P --> I
    P --> FU
    F --> CAT
    F --> CART
    F --> CHK
    F --> CUR
    F --> AD
    F --> REC
    F --> SHIP
    F --> FD
    CHK --> CART
    CHK --> CAT
    CHK --> PAY
    CHK --> CUR
    CHK --> MAIL
    CHK --> SHIP
    CHK --> K
    CHK --> FD
    CART --> V
    CART --> FD
    SHIP --> QUOTE
    REC --> CAT
    K --> ACC
    K --> FR
    FR --> FD
```

---

## 2. Place order — sequence (most important interview diagram)

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Proxy as frontend-proxy
    participant FE as frontend
    participant CHK as checkout
    participant Cart as cart
    participant Valkey as valkey
    participant Catalog as product-catalog
    participant Pay as payment
    participant Ship as shipping
    participant Quote as quote
    participant Cur as currency
    participant Mail as email
    participant Kafka as kafka
    participant Acc as accounting
    participant Fraud as fraud-detection

    User->>Proxy: POST checkout (HTTP)
    Proxy->>FE: route to frontend
    FE->>CHK: PlaceOrder (gRPC)
    CHK->>Cart: GetCart
    Cart->>Valkey: GET/SET cart data
    Valkey-->>Cart: cart items
    Cart-->>CHK: Cart
    CHK->>Catalog: GetProduct (per item)
    Catalog-->>CHK: Product
    CHK->>Cur: Convert (prices)
    Cur-->>CHK: Money
    CHK->>Ship: GetQuote / ShipOrder
    Ship->>Quote: HTTP quote
    Quote-->>Ship: cost
    Ship-->>CHK: shipping
    CHK->>Pay: Charge
    Pay-->>CHK: OK
    CHK->>Mail: SendOrderConfirmation (HTTP)
    Mail-->>CHK: OK
    CHK->>Kafka: Produce order event
    Kafka-->>Acc: Consume
    Kafka-->>Fraud: Consume
    CHK-->>FE: OrderResult
    FE-->>User: Confirmation page
```

**Say in interviews:** Checkout is the **orchestrator**. Kafka is **async fan-out** so accounting/fraud do not block the HTTP response path as hard as sync calls (still demo-scale).

---

## 3. Browse catalog — simpler path

```mermaid
sequenceDiagram
    actor User
    participant Proxy as frontend-proxy
    participant FE as frontend
    participant Catalog as product-catalog
    participant Rec as recommendation
    participant Ad as ad
    participant Flagd as flagd

    User->>Proxy: GET /
    Proxy->>FE: /
    FE->>Catalog: ListProducts / GetProduct
    Catalog-->>FE: products
    FE->>Rec: ListRecommendations
    Rec->>Catalog: GetProduct
    Catalog-->>Rec: products
    Rec-->>FE: recommendations
    FE->>Ad: GetAds
    Ad->>Flagd: evaluate flags
    Flagd-->>Ad: flag value
    Ad-->>FE: ads
    FE-->>User: HTML/JSON UI
```

---

## 4. Cart + Valkey

```mermaid
sequenceDiagram
    participant FE as frontend / checkout
    participant Cart as cart
    participant V as valkey :6379

    FE->>Cart: AddItem / GetCart (gRPC :8080)
    Cart->>V: Redis commands
    V-->>Cart: data
    Cart-->>FE: Cart proto
```

DNS in K8s: `VALKEY_ADDR` → typically `opentelemetry-demo-valkey:6379`.

---

## 5. Kubernetes discovery (how services find each other)

```mermaid
flowchart LR
    subgraph PodA["checkout Pod"]
        ENV["ENV CART_SERVICE_ADDR=<br/>opentelemetry-demo-cartservice:8080"]
    end
    subgraph DNS["CoreDNS"]
        Q[resolve name]
    end
    subgraph Svc["Service ClusterIP"]
        CIP[Virtual IP :8080]
    end
    subgraph Pods["cart Pods"]
        P1[cart Pod]
    end
    ENV --> Q
    Q --> CIP
    CIP --> P1
```

**Rule:** Service `selector` labels must match Pod template labels, or traffic goes nowhere.

---

## 6. GitOps deploy path (this fork)

```mermaid
flowchart TB
    Dev[Developer] -->|push/PR| GH[GitHub]
    GH --> GHA[GitHub Actions]
    GHA -->|push image| DH[Docker Hub]
    GHA -->|commit image tag| Man[kubernetes/svc/deploy.yaml]
    Man --> Argo[Argo CD otel-demo]
    Argo -->|apply| EKS[EKS otel-demo ns]
    EKS -->|pull| DH
```

---

## 7. Layers mentally (whiteboard)

```text
┌─────────────────────────────────────────────┐
│ Clients (browser, Locust)                   │
└─────────────────┬───────────────────────────┘
                  │ HTTP :8080
┌─────────────────▼───────────────────────────┐
│ frontend-proxy (Envoy)                      │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│ frontend (Next.js)                          │
└─────────────────┬───────────────────────────┘
                  │ gRPC / HTTP
┌─────────────────▼───────────────────────────┐
│ Business services (catalog, cart, checkout…)│
└───────┬─────────────────────┬───────────────┘
        │                     │
   ┌────▼────┐          ┌─────▼─────┐
   │ Valkey  │          │   Kafka   │
   └─────────┘          └─────┬─────┘
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
              accounting          fraud-detection
```

---

## 8. Which doc next?

| Goal | Open |
|------|------|
| Line-by-line YAML + Helm + Argo | [_KUBERNETES_YAML_HELM_ARGOCD.md](./_KUBERNETES_YAML_HELM_ARGOCD.md) |
| One service deep | e.g. [product-catalog.md](./product-catalog.md), [checkout.md](./checkout.md) |
| Interview drill | [../INTERVIEW_QUESTIONS.md](../INTERVIEW_QUESTIONS.md) |
