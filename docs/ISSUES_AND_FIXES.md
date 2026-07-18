# All Issues Faced and How They Were Fixed

> Chronological log of every problem encountered while bringing this fork from
> broken CI/GitOps through Terraform EKS bootstrap to a running Astronomy Shop
> on EKS — architecture, Git, Docker Hub, GitHub Actions, Terraform/Helm,
> image builds, CrashLoopBackOff env mismatches, public LoadBalancer access,
> OTel Collector, EC2 vs Fargate, and clean `terraform destroy`.
>
> Related: [GIT_ISSUES_EXPLAINED.md](./GIT_ISSUES_EXPLAINED.md) ·
> [CI_CD_PIPELINE.md](./CI_CD_PIPELINE.md) ·
> [ARGOCD_TF_EXPLAINED.md](./ARGOCD_TF_EXPLAINED.md) ·
> [TERRAFORM_ARGOCD_DEPLOYMENT.md](./TERRAFORM_ARGOCD_DEPLOYMENT.md) ·
> [microservices/README.md](./microservices/README.md) ·
> [INTERVIEW_QUESTIONS.md](./INTERVIEW_QUESTIONS.md)

---

## Timeline overview

| # | Area | Issue (short) | Status |
|---|------|---------------|--------|
| 1 | Architecture | Wrong mental model of CI vs Argo CD | Clarified + fixed in config |
| 2 | GitOps gap | CI updated a file Argo CD did not sync | Fixed |
| 3 | CI coverage | Only product-catalog had a pipeline | Fixed |
| 4 | CI anti-patterns | Force-push, brittle `sed`, lint not required | Fixed |
| 5 | Secrets | Password/token shared in chat | Guidance + rotate |
| 6 | GitHub Actions | Reusable workflow `contents: write` denied | Fixed |
| 7 | GitHub Actions | Two workflows on every push | Fixed |
| 8 | Docker Hub | Missing / empty login secrets | Fixed (user secrets) |
| 9 | Docker Hub | Token insufficient scopes | Fixed (user new token) |
| 10 | Docker build | Wrong build context (`/src/email` not found) | Fixed |
| 11 | GitHub Actions | Re-running old failed job ignored workflow fix | Process clarified |
| 12 | CI usage | Needed build-all-services, not one-at-a-time | Fixed (`workflow_dispatch`) |
| 13 | Git | Divergent branches on pull | Fixed with rebase |
| 14 | Git | Non-fast-forward push rejected | Fixed with rebase + push |
| 15 | Git | Cursor agent cannot push to GitHub | Use local terminal |
| 16 | Docker build | Currency `git clone` exit 128 (missing CPP version) | Fixed |
| 17 | Docker build | Java agent URL 404 (missing OTEL_JAVA_AGENT_VERSION) | Fixed |
| 18 | Docker build | Currency CMake `IN_LIST` / CMP0057 (cmake 3.1 vs otel-cpp 1.23) | Fixed |
| 19 | Docs | Per-service + interview study guides with diagrams | Done |
| 20 | Docker build | Recommendation: `No module named pkg_resources` | Fixed (`setuptools<82`) |
| 21 | Terraform | Helm `~> 7.6` rejected by Helm provider v3 | Fixed (pin `7.6.12`) |
| 22 | Terraform | EKS addon `resolve_conflicts` deprecation warning | Harmless / known |
| 23 | Docker build | Currency missing `semantic_conventions.h` (otel-cpp 1.23) | Fixed (new semconv API) |
| 24 | Docker build | Load-generator same `pkg_resources` / setuptools 82+ | Fixed |
| 25 | CI lint | Product-catalog golangci-lint (unused / gosimple / SA1019) | Fixed |
| 26 | EKS runtime | Mass CrashLoopBackOff — wrong env var names in manifests | Fixed |
| 27 | GitOps | Argo `selfHeal` reverted kubectl-only fixes | Push to Git required |
| 28 | Ops | Accidental `kubectl apply` into `default` namespace | Clean up default |
| 29 | Access | `frontendproxy` ClusterIP → LoadBalancer (`svc.yaml`) | Fixed (NLB URL) |
| 30 | Observability | Missing `otelcol` — OTLP export DNS errors | Fixed (`kubernetes/otelcol/`) |
| 31 | Observability | Stale OTLP DNS errors after otelcol created | Fixed (restart / wait) |
| 32 | Terraform | `terraform destroy` hung / VPC `DependencyViolation` (orphan ELB + SG) | Fixed (`cleanup.tf`) |
| 33 | Terraform | Need EC2 **or** Fargate workers via tfvars | Fixed (`compute_type`) |
| 34 | Access / Fargate | Classic ELB incompatible with Fargate-only | Fixed (AWS LB Controller + NLB IP) |
| 35 | Ops | AWS `SignatureDoesNotMatch` on Terraform | Credentials (not code) |

---

## 1. Architecture misunderstanding: “each service needs its own Argo CD sync?”

### Issue

Assumption: every microservice should have its own CI **and** its own Argo CD
Application / sync.

### Reality

| Layer | Correct model in this repo |
|-------|----------------------------|
| **CI** | Per microservice (own image build/push) |
| **Argo CD** | One Application (`otel-demo`) for the whole shop |

### How it was fixed

Documented and implemented:

- CI builds **one image per service** (`product-catalog`, `email`, `cart`, …).
- **One** Argo CD app syncs all per-service manifests under `kubernetes/`.
- Argo CD does **not** rebuild images; it applies whatever image tag is in Git.

---

## 2. GitOps gap: CI updated a file Argo CD ignored

### Issue

Old setup:

- CI wrote the new image tag into `kubernetes/productcatalog/deploy.yaml`.
- Argo CD was configured to sync **only** `kubernetes/complete-deploy.yaml`.

So images built successfully but **never rolled out** via Argo CD.

### How it was fixed

Changed Argo CD (Terraform + standalone Application) to:

```yaml
directory:
  recurse: true
  exclude: complete-deploy.yaml
```

Files:

- `terraform/argocd.tf`
- `argocd/application.yaml`

CI updates per-service `deploy.yaml` → Argo CD picks it up → EKS rolls pods.
`complete-deploy.yaml` remains as a monolithic / kubectl convenience file, but
is **excluded** from Argo so resources are not duplicated.

---

## 3. Only one service had CI

### Issue

Only `product-catalog` had GitHub Actions. Other services had no automated
build/push/GitOps update.

### How it was fixed

| Workflow | Role |
|----------|------|
| `.github/workflows/ci.yaml` | Product-catalog |
| `.github/workflows/microservices-ci.yaml` | Matrix of other services |
| `.github/workflows/reusable-service-ci.yaml` | Shared Docker Hub + commit image tag |

---

## 4. CI anti-patterns

### Issues

- Force-pushing `main` from CI
- Brittle `sed` for image tags
- Lint not required to pass

### How it was fixed

Safer commit-back to `main`, clearer image-tag update, lint as a required job
where applicable. See [CI_CD_PIPELINE.md](./CI_CD_PIPELINE.md).

---

## 5. Secrets shared in chat

### Issue

Docker Hub password / token pasted into chat (security risk).

### How it was fixed

**Rotate** the token. Store only in GitHub Actions secrets (`DOCKER_USERNAME`,
`DOCKER_TOKEN`). Never commit secrets.

---

## 6. Reusable workflow `contents: write` denied

### Issue

Caller workflow did not grant `permissions: contents: write`, so the reusable
workflow could not commit image-tag updates back to the repo.

### How it was fixed

Callers set:

```yaml
permissions:
  contents: write
```

---

## 7. Two workflows on every push

### Issue

Both product-catalog and microservices workflows fired too broadly.

### How it was fixed

Path filters so each workflow runs only when its service (or shared workflow)
paths change; plus `workflow_dispatch` for manual full builds.

---

## 8–9. Docker Hub login failures

### Issues

```text
Error: Username and password required
401 Unauthorized: access token has insufficient scopes
```

### How it was fixed

1. Create GitHub secrets `DOCKER_USERNAME` / `DOCKER_TOKEN` (non-empty).
2. Docker Hub PAT with **Read & Write** (and access to the needed repos).
3. Re-run with a **new** workflow run (not an old failed job).

---

## 10. Docker build context: `/src/email` not found

### Issue

```text
COPY ./src/email/ ... → "/src/email": not found
```

### Cause

Dockerfile expects repo-root context (`.`), but CI used `src/email` as context.

### How it was fixed

Matrix `src_context` / dockerfile paths aligned: most services build from `.`;
only a few (e.g. ad, recommendation) use their own folder as context.

---

## 11. Re-running an old failed Actions job

### Issue

After fixing the workflow YAML, “Re-run failed jobs” on an **old** run still used
the old workflow definition.

### How it was fixed

Push the fix (or use **Run workflow**). Do not rely on re-running the stale job
for workflow-file changes.

---

## 12. Need to build all services at once

### Issue

Path filters meant only changed services built; first EKS bring-up needed every image.

### How it was fixed

Added `workflow_dispatch` to `microservices-ci.yaml` / `ci.yaml`. Manual run
builds the full matrix and pushes tags on `main`.

---

## 13–15. Git divergence and agent push limits

### Issues

- Local `main` behind/ahead of `origin/main` (CI commits image tags).
- `non-fast-forward` push rejected.
- Cursor agent: `could not read Username for 'https://github.com'`.

### How it was fixed

```bash
git pull --rebase origin main
git push origin main
```

Always rebase before pushing when CI also writes to `main`. Push from a
**local terminal** with GitHub credentials when the agent cannot authenticate.
See [GIT_ISSUES_EXPLAINED.md](./GIT_ISSUES_EXPLAINED.md).

---

## 16. Currency: `git clone` exit 128 (empty CPP version)

### Issue

```text
git clone --branch v${OPENTELEMETRY_CPP_VERSION} ...
# OPENTELEMETRY_CPP_VERSION empty → branch "v" → exit 128
```

### Cause

`.env` has `OPENTELEMETRY_CPP_VERSION=1.23.0` for compose; CI did not pass the
build-arg.

### How it was fixed

1. Dockerfile default: `ARG OPENTELEMETRY_CPP_VERSION=1.23.0`
2. `reusable-service-ci.yaml` loads `.env` and passes version build-args to every build

---

## 17. Fraud-detection / Kafka: Java agent URL 404

### Issue

```text
ADD .../releases/download/v/opentelemetry-javaagent.jar → 404
```

### Cause

Same class as #16: empty `OTEL_JAVA_AGENT_VERSION` → URL `.../download/v/...`.

### How it was fixed

1. Dockerfile defaults `ARG OTEL_JAVA_AGENT_VERSION=2.20.1`
2. CI injects the value from `.env` for all builds
3. `platforms: linux/amd64` so `TARGETARCH` is set for .NET/Rust images

---

## 18. Currency CMake: `IN_LIST` / CMP0057

### Issue

```text
CMake Error: if given arguments: "Microsoft.GSL" "IN_LIST" ...
Unknown arguments specified
```

### Cause

otel-cpp 1.23 CMake config needs policy CMP0057; currency still had
`cmake_minimum_required(VERSION 3.1)`.

### How it was fixed

```cmake
cmake_minimum_required(VERSION 3.26)
```

in `src/currency/CMakeLists.txt` and `genproto/CMakeLists.txt`.

---

## 19. Study docs for juniors / interviews

### Delivered

| Path | What it covers |
|------|----------------|
| [microservices/README.md](./microservices/README.md) | Learning path + shop topology |
| [microservices/_SERVICE_MAP.md](./microservices/_SERVICE_MAP.md) | Place-order & other Mermaid diagrams |
| [microservices/_KUBERNETES_YAML_HELM_ARGOCD.md](./microservices/_KUBERNETES_YAML_HELM_ARGOCD.md) | YAML / Helm / Argo |
| [microservices/*.md](./microservices/) | One file per service |
| [INTERVIEW_QUESTIONS.md](./INTERVIEW_QUESTIONS.md) | Interview Q&A |

---

## 20. Recommendation Docker build: `No module named pkg_resources`

### Issue

```text
RUN opentelemetry-bootstrap -a install
ModuleNotFoundError: No module named 'pkg_resources'
```

### Cause (refined)

- `opentelemetry-instrumentation` **0.46b0** still imports `pkg_resources`.
- First fix added `setuptools>=69.0.0`, but that allowed **setuptools 82+**.
- Setuptools **82 removed `pkg_resources`**, so CI still failed with setuptools 83.

### How it was fixed

```text
# src/recommendation/requirements.txt
setuptools>=69.0.0,<82
```

Same pin later applied to load-generator (#24).

**Status:** Fixed.

---

## 21. Terraform: Helm chart version constraint rejected

### Issue

After `terraform plan` / `apply` with Helm provider **v3**:

```text
Error: Planned version is different from configured version
  with helm_release.argocd
The version in the configuration is "~> 7.6" but the planned version is "7.6.12".
You should update the version in your configuration to "7.6.12"
```

### Cause

Helm provider v3 requires an **exact** chart version string. Constraints like
`~> 7.6` or `~> 2.0` are rejected at plan time.

### How it was fixed

In `terraform/argocd.tf`:

| Release | Before | After |
|---------|--------|-------|
| `helm_release.argocd` (chart `argo-cd`) | `~> 7.6` | `7.6.12` |
| `helm_release.argocd_apps` (chart `argocd-apps`) | `~> 2.0` | `2.0.5` |

Then `terraform apply` succeeded and installed Argo CD + the `otel-demo`
Application on EKS.

**Status:** Fixed.

**Note:** Do **not** re-run Terraform for normal app deploys — only when
`terraform/` (infra) itself changes. Day-2 = CI → Git → Argo.

---

## 22. Terraform warning: EKS addon `resolve_conflicts` deprecated

### Issue

```text
Warning: Deprecated resource attribute "resolve_conflicts" used
  (coredns / kube-proxy / vpc-cni — and 2 more similar warnings)
```

### Cause

The AWS provider deprecated `resolve_conflicts` in favor of
`resolve_conflicts_on_create` / `resolve_conflicts_on_update`. The
`terraform-aws-modules/eks` module still **exports** addon objects that expose
the old attribute in outputs — so Terraform warns when reading them.

### How it was fixed

**No code change required.** Warning is non-blocking; apply still succeeds.
Upgrading the EKS module later may silence it.

**Status:** Accepted / harmless.

---

## 23. Currency Docker build: missing `semantic_conventions.h`

### Issue

```text
/currency/src/server.cpp:11:10: fatal error:
  opentelemetry/trace/semantic_conventions.h: No such file or directory
```

### Cause

- `.env` / CI build with **otel-cpp 1.23.0**.
- That version **removed** `api/include/opentelemetry/trace/semantic_conventions.h`
  (gone as of ~1.22; last present in 1.21.x).
- Fork’s `server.cpp` still used the old API (`SemanticConventions::kRpcSystem`).
- Upstream demo already uses `opentelemetry/semconv/incubating/rpc_attributes.h`.

### How it was fixed

Updated `src/currency/src/server.cpp` to the new API:

```cpp
#include "opentelemetry/semconv/incubating/rpc_attributes.h"
namespace semconv = opentelemetry::semconv;
// ...
{semconv::rpc::kRpcSystem, "grpc"},
{semconv::rpc::kRpcGrpcStatusCode, semconv::rpc::RpcGrpcStatusCodeValues::kOk},
```

Kept `OPENTELEMETRY_CPP_VERSION=1.23.0`.

**Status:** Fixed.

---

## 24. Load-generator: same `pkg_resources` failure

### Issue

Same stack as #20 when building/running load-generator with setuptools 82+.

### How it was fixed

Pinned in `src/load-generator/requirements.txt`:

```text
setuptools>=69.0.0,<82
```

CI rebuilt the image; load-generator pod became Running.

**Status:** Fixed.

---

## 25. Product-catalog CI: golangci-lint failures

### Issue

```text
func createClient is unused (unused)
S1039: unnecessary use of fmt.Sprintf (gosimple)
SA1019: grpc.DialContext is deprecated (staticcheck)
```

### How it was fixed

In `src/product-catalog/main.go`:

1. Removed unused `createClient` (also removed deprecated `DialContext` usage).
2. Replaced `fmt.Sprintf("literal")` with a plain string.
3. Dropped unused `insecure` import.

**Status:** Fixed.

---

## 26. Mass CrashLoopBackOff after first Argo sync (env var names)

### Issue

Many pods crashed right after Terraform + Argo deployed the shop:

| Symptom in logs | Missing / wrong env |
|-----------------|---------------------|
| `Usage: currency <port>` | Needed `CURRENCY_PORT`, had `CURRENCY_SERVICE_PORT` |
| `CHECKOUT_PORT` not set | Had `CHECKOUT_SERVICE_PORT` |
| `PAYMENT_PORT` → bind `0.0.0.0:undefined` | Had `PAYMENT_SERVICE_PORT` |
| `QUOTE_PORT` → `tcp://0.0.0.0:` | Had `QUOTE_SERVICE_PORT` |
| `$SHIPPING_PORT is not set` | Had `SHIPPING_SERVICE_PORT` |
| `PRODUCT_CATALOG_ADDR` must be set | Had `PRODUCT_CATALOG_SERVICE_ADDR` |
| `KAFKA_ADDR` null / not supplied | Had `KAFKA_SERVICE_ADDR` |
| Frontendproxy Envoy bad config | Needed `GRAFANA_HOST` / `JAEGER_HOST`, had `*_SERVICE_*` |

Services that looked “Running” (ad, product-catalog) often only worked because
**Dockerfile `ENV` defaults** (e.g. `PRODUCT_CATALOG_PORT=8088`, `AD_PORT=9099`)
filled gaps — sometimes on the **wrong port** vs the Kubernetes Service (8080).

### Cause

Helm-rendered manifests (demo chart ~1.12 style) used `*_SERVICE_PORT` /
`*_SERVICE_ADDR`. Application source (aligned with `docker-compose` / `.env`)
expects `*_PORT`, `*_ADDR`, `KAFKA_ADDR`.

### How it was fixed

Renamed env keys across `kubernetes/*/deploy.yaml` (14 files), for example:

| Old (Helm) | New (app / compose) |
|------------|---------------------|
| `CURRENCY_SERVICE_PORT` | `CURRENCY_PORT` |
| `CHECKOUT_SERVICE_PORT` | `CHECKOUT_PORT` |
| `PAYMENT_SERVICE_PORT` | `PAYMENT_PORT` |
| `PRODUCT_CATALOG_SERVICE_ADDR` | `PRODUCT_CATALOG_ADDR` |
| `CART_SERVICE_ADDR` | `CART_ADDR` |
| `KAFKA_SERVICE_ADDR` | `KAFKA_ADDR` |
| `GRAFANA_SERVICE_HOST` | `GRAFANA_HOST` |
| `JAEGER_SERVICE_HOST` | `JAEGER_HOST` |

Pushed to `main` (e.g. commit `fix port num`). Argo synced → pods Running;
checkout logs showed successful PlaceOrder / payment / Kafka writes.

**Status:** Fixed.

---

## 27. Argo CD `selfHeal` reverted kubectl-only fixes

### Issue

`kubectl apply` / `kubectl patch` on Deployments fixed CrashLoops briefly, then
Argo restored the old Git desired state (`PAYMENT_SERVICE_PORT` again, etc.).

### Cause

Application sync policy includes:

```yaml
automated:
  prune: true
  selfHeal: true
```

Cluster must match **Git**, not ad-hoc kubectl.

### How it was fixed / lesson

1. Change manifests in the repo.
2. `git push origin main`.
3. Let Argo sync.

kubectl is for **debug**, not durable config (unless you also update Git).

**Status:** Process clarified; durable fix via Git.

---

## 28. Accidental Deployments in `default` namespace

### Issue

`kubectl apply -f kubernetes/*/deploy.yaml` without `-n otel-demo` created
Deployments in **`default`** (manifests have no `metadata.namespace`). Those
sat at `0/1` and caused confusion / resource pressure.

### How it was fixed

Always apply with namespace:

```bash
kubectl apply -n otel-demo -f kubernetes/<service>/deploy.yaml
```

Clean up if needed:

```bash
kubectl delete deploy -n default -l app.kubernetes.io/instance=opentelemetry-demo
```

**Status:** Operational lesson documented.

---

## 29. No public “domain” URL — `frontendproxy` ClusterIP → LoadBalancer

### Issue

User wanted a browser URL “on EKS”. Every shop Service was originally
`ClusterIP`. That is correct for **internal** gRPC/HTTP between pods, but the
**entry point** (`frontendproxy`) was also ClusterIP — so the UI was only
reachable via `kubectl port-forward` (`http://localhost:8080`), not from the
internet.

### What changed (and what did *not*)

| File | Before | After | Why |
|------|--------|-------|-----|
| `kubernetes/frontendproxy/svc.yaml` | `type: ClusterIP` | `type: LoadBalancer` | Public shop UI via AWS ELB |
| All other `kubernetes/*/svc.yaml` | `type: ClusterIP` | **Still ClusterIP** | Internal-only; no public ELB per microservice |

Do **not** turn cart/checkout/catalog/etc. into LoadBalancers — that would
create many ELBs (cost) and expose internal APIs. Only the Envoy front door
needs a public Service (or an Ingress/ALB later).

### Before / after (`frontendproxy` only)

```yaml
# BEFORE — kubernetes/frontendproxy/svc.yaml
spec:
  type: ClusterIP
  ports:
    - port: 8080
      name: tcp-service
      targetPort: 8080

# AFTER
spec:
  type: LoadBalancer
  ports:
    - port: 8080
      name: tcp-service
      targetPort: 8080
      protocol: TCP
```

### How it was fixed operationally

1. Edited `kubernetes/frontendproxy/svc.yaml` → `type: LoadBalancer`.
2. Temporarily paused Argo auto-sync so selfHeal would not revert to ClusterIP
   before Git caught up.
3. Applied the Service; AWS provisioned an ELB hostname, for example:

```text
http://a471d5657bc0e44a696f15002ae49c27-2086886514.us-east-1.elb.amazonaws.com:8080
```

4. Committed to Git (`Cluster to LB`) so Argo’s desired state matches the
   LoadBalancer Service.

There is **no custom DNS domain** unless you add Route53 + Ingress/ALB separately.
Get the current public URL anytime with:

```bash
kubectl get svc opentelemetry-demo-frontendproxy -n otel-demo \
  -o jsonpath='http://{.status.loadBalancer.ingress[0].hostname}:8080{"\n"}'
```

Optional local access (still works):

```bash
kubectl -n otel-demo port-forward svc/opentelemetry-demo-frontendproxy 8080:8080
# http://localhost:8080
```

**Status:** Fixed (public NLB on `frontendproxy` only; IP target type via AWS LB
Controller — see issue 34). Other Services remain ClusterIP by design.

---

## 30. Missing OpenTelemetry Collector (`otelcol`)

### Issue

Pods logged:

```text
failed to upload metrics / traces export: ...
name resolver error ... produced zero addresses
```

Services already pointed at `opentelemetry-demo-otelcol:4317` / `:4318`, but this
fork had **no** collector Deployment/Service under `kubernetes/` for Argo to sync
(only Docker Compose configs in `src/otel-collector/`).

### Impact

- Shopping still worked (non-fatal).
- Traces/metrics/logs could not be exported until a collector existed.

### How it was fixed

Added GitOps manifests:

| File | Purpose |
|------|---------|
| `kubernetes/otelcol/configmap.yaml` | Minimal OTLP→debug pipeline (4317/4318) |
| `kubernetes/otelcol/deploy.yaml` | `opentelemetry-collector-contrib:0.133.0` |
| `kubernetes/otelcol/svc.yaml` | ClusterIP `opentelemetry-demo-otelcol` ports 4317 + 4318 |

Collector accepts OTLP and logs to stdout via the `debug` exporter (Jaeger /
Prometheus / OpenSearch are **not** required for this fix). After deploy, otelcol
logs show `Traces` / `Metrics` / `Logs` batches arriving.

If a service still prints resolver errors right after create, restart that
Deployment once (gRPC clients may cache failed DNS from before the Service existed).

**Status:** Fixed. Manifests are under `kubernetes/otelcol/` and synced by Argo.
Optional later: add Jaeger/Grafana and change exporters from `debug` to OTLP.

---

## 31. Stale OTLP resolver errors after otelcol came up

### Issue

After deploying `opentelemetry-demo-otelcol`, some pods (e.g. product-catalog,
checkout) still showed:

```text
name resolver error: produced zero addresses
```

Collector logs already showed Traces/Metrics/Logs arriving. Product-catalog
also looked “silent” in `kubectl logs` because handlers log to **spans**, not
stdout (only startup lines are printed).

### How it was fixed

- Wait for DNS / gRPC clients to recover, **or** restart noisy Deployments once
  (`kubectl rollout restart deploy/… -n otel-demo`).
- Scanned all Deployments: errors stopped after the Service existed; no further
  manifest change required.

**Status:** Fixed (operational).

---

## 32. `terraform destroy` hung — orphan Classic ELB + `k8s-elb-*` SG

### Issue

`terraform destroy` stuck for minutes on public subnets / IGW, then failed:

```text
Error: deleting EC2 VPC (...): DependencyViolation:
The vpc '...' has dependencies and cannot be deleted.
```

Root cause: `frontendproxy` `type: LoadBalancer` created a **Classic ELB** (and
later ENIs / `k8s-elb-*` security group) **outside Terraform state**. Public
subnets tried to delete while ELB ENIs still existed; after manual ELB delete,
the leftover SG still blocked VPC delete.

### How it was fixed

| Piece | Role |
|-------|------|
| `terraform/cleanup.tf` | Destroy-time `null_resource`: **actively** deletes Classic/NLB ELBs in the VPC, waits for ELB ENIs, deletes `k8s-elb-*` SGs |
| `terraform/eks.tf` `depends_on` | Destroy order: EKS → cleanup → VPC (so public subnets wait) |
| Argo `resources-finalizer` | Still deletes the LoadBalancer Service when the Application is destroyed |

One-time recovery used during the hung destroy:

```bash
aws elb delete-load-balancer --load-balancer-name <classic-elb-name>
aws ec2 delete-security-group --group-id sg-...   # k8s-elb-*
# then re-run terraform destroy (or state-rm VPC if already deleted in AWS)
```

**Status:** Fixed. Apply once so `wait_for_elb_cleanup` is in state; future
destroys should clean ELBs/SGs automatically.

---

## 33. EC2 vs Fargate selectable via `compute_type`

### Issue

Needed one Terraform stack that can run workers as either managed EC2 nodes or
EKS Fargate, without maintaining two separate root modules.

### How it was fixed

| File | Change |
|------|--------|
| `terraform/variables.tf` | `compute_type` = `"ec2"` \| `"fargate"` (validated) |
| `terraform/terraform.tfvars` | `compute_type = "ec2"` or `"fargate"` |
| `terraform/locals.tf` | Conditional `eks_managed_node_groups` **xor** `fargate_profiles`; CoreDNS `computeType=Fargate` when Fargate |
| `terraform/eks.tf` | Passes those maps into the EKS module |

Fargate profiles (when `compute_type = "fargate"`): `kube_system`, `argocd`,
`app` (`otel-demo`). EC2 node sizing vars are ignored on Fargate.

**Do not flip modes on a live cluster** — prefer destroy → edit tfvars → apply.

List Fargate profiles (AWS API, not kubectl):

```bash
aws eks list-fargate-profiles --cluster-name otel-demo --region us-east-1
kubectl get nodes -o wide   # fargate-ip-… nodes appear when pods schedule
```

**Status:** Fixed.

---

## 34. Classic ELB does not work on Fargate — AWS LB Controller + NLB IP

### Issue

In-tree Classic Load Balancers target **EC2 instances**. On a Fargate-only
cluster there are no worker instances, so `type: LoadBalancer` without IP
targets never works correctly.

### How it was fixed

| File | Change |
|------|--------|
| `terraform/aws_lb_controller.tf` | Install AWS Load Balancer Controller + IRSA (both compute modes) |
| `kubernetes/frontendproxy/svc.yaml` | Annotations: `aws-load-balancer-type: external`, `nlb-target-type: ip`, `scheme: internet-facing` |

Browser URL (port **8080**):

```bash
kubectl get svc -n otel-demo opentelemetry-demo-frontendproxy
# http://<EXTERNAL-IP-or-hostname>:8080
```

**Status:** Fixed.

---

## 35. Terraform / AWS `SignatureDoesNotMatch`

### Issue

```text
api error SignatureDoesNotMatch: The request signature we calculated does not
match the signature you provided. Check your AWS Secret Access Key ...
```

### Cause / fix

Bad or mismatched AWS credentials (typo, wrong secret, mixed key pair, missing
session token). **Not** a `providers.tf` bug.

```bash
aws sts get-caller-identity   # must succeed before terraform apply/destroy
```

**Status:** Operational / credentials — not a repo code fix.

---

## End state (what “up and running” looks like)

```text
Developer / workflow_dispatch / push to main
        │
        ▼
GitHub Actions
  • product-catalog-ci
  • microservices-ci
        │
        ├─► Docker Hub  (durganadimpalli/<service>:<run_id>)
        │
        └─► Commit image tag → kubernetes/<service>/deploy.yaml
                │
                ▼
         Argo CD Application otel-demo
           syncs kubernetes/* (exclude complete-deploy.yaml)
                │
                ▼
              EKS namespace otel-demo
                • Shop Deployments Running (EC2 nodes or Fargate)
                • frontendproxy Service type LoadBalancer (NLB IP targets)
                • otelcol Receiving OTLP (debug exporter)
                • Public URL: http://<nlb-dns>:8080
```

### What Terraform did (once)

| Resource | Role |
|----------|------|
| VPC + NAT | Network for EKS |
| EKS + **EC2 node group or Fargate profiles** (`compute_type`) | Cluster compute |
| `null_resource.wait_for_elb_cleanup` | Destroy-time ELB/SG cleanup |
| `helm_release.aws_lb_controller` | NLB with IP targets (Fargate-safe) |
| `helm_release.argocd` | Install Argo CD (chart `7.6.12`) |
| `helm_release.argocd_apps` | Bootstrap Application `otel-demo` |

**Day-2 deploys do not need `terraform apply`.**

### Key files after all fixes

| File | Purpose |
|------|---------|
| `.github/workflows/*.yaml` | CI + GitOps image tag commits |
| `terraform/argocd.tf` | Exact Helm versions; Argo app source |
| `terraform/locals.tf` / `eks.tf` | `compute_type` → EC2 xor Fargate |
| `terraform/cleanup.tf` | Force-delete orphan ELBs/SGs on destroy |
| `terraform/aws_lb_controller.tf` | AWS Load Balancer Controller + IRSA |
| `kubernetes/*/deploy.yaml` | Env names matching app code |
| `kubernetes/frontendproxy/svc.yaml` | **LoadBalancer** + NLB IP annotations |
| `kubernetes/otelcol/` | OTLP collector (ConfigMap + Deployment + Service) |
| `src/currency/src/server.cpp` | New otel-cpp semconv API |
| `src/recommendation/requirements.txt` | `setuptools>=69,<82` |
| `src/load-generator/requirements.txt` | Same setuptools pin |
| `src/product-catalog/main.go` | Lint-clean |

### Useful verification commands

```bash
kubectl get pods -n otel-demo -o wide
kubectl get nodes -o wide
kubectl get applications -n argocd
kubectl get svc opentelemetry-demo-frontendproxy -n otel-demo
aws eks list-fargate-profiles --cluster-name otel-demo --region us-east-1   # if Fargate
kubectl logs -n otel-demo deploy/opentelemetry-demo-otelcol --tail=30
kubectl logs -n otel-demo deploy/opentelemetry-demo-checkoutservice --tail=50
```

---

## Checklist if something breaks again

1. **Workflow invalid?** Callers must grant `permissions: contents: write`.
2. **Docker login fail?** Check Actions secrets exist and are non-empty.
3. **401 insufficient scopes?** New Docker Hub PAT with Read & Write.
4. **COPY path not found?** Build context must match Dockerfile (`.` vs `src/...`).
5. **Old failure after fix?** Don’t re-run old job; new commit or Run workflow.
6. **Push rejected?** `git pull --rebase origin main && git push`.
7. **Cluster not updating?** Argo syncs `kubernetes/*` excluding `complete-deploy.yaml`;
   confirm Application Synced/Healthy; selfHeal means **Git wins**.
8. **Never** commit tokens, `*.tfstate`, or force-push `main`.
9. **Currency git exit 128?** `OPENTELEMETRY_CPP_VERSION` (issue 16).
10. **Java agent 404?** `OTEL_JAVA_AGENT_VERSION` (issue 17).
11. **Currency CMake IN_LIST?** CMake ≥ 3.26 (issue 18).
12. **`pkg_resources` missing?** `setuptools>=69.0.0,<82` (issues 20, 24).
13. **Helm `~> x.y` plan error?** Pin exact chart version for Helm provider v3 (issue 21).
14. **CrashLoop + “PORT not set”?** Manifest env names must match app (`*_PORT` / `*_ADDR`) (issue 26).
15. **kubectl fix disappeared?** Push the same change to Git (issue 27).
16. **No public URL?** Confirm `frontendproxy` is LoadBalancer + NLB annotations;
    wait for `EXTERNAL-IP`; open `http://…:8080` (issues 29, 34).
17. **OTLP DNS / export errors?** Ensure `kubernetes/otelcol/` exists; restart
    Deployments once if needed (issues 30–31).
18. **Destroy hung on subnet/VPC?** Orphan ELB/SG — `cleanup.tf` should delete them;
    otherwise delete Classic/NLB + `k8s-elb-*` SG manually (issue 32).
19. **Empty Fargate profiles / only EC2 nodes?** Check `compute_type` in tfvars and
    that the last apply used it; `kubectl get fargateprofile` is invalid — use AWS CLI
    (issue 33).
20. **`SignatureDoesNotMatch`?** Fix AWS keys / session token; `aws sts get-caller-identity`
    (issue 35).

---

## Summary

Work progressed in layers:

1. **GitOps correctness** — CI must edit the manifests Argo watches; one Argo app for the shop.
2. **CI reliability** — secrets, permissions, build contexts, build-args from `.env`.
3. **Image build compatibility** — otel-cpp versions, CMake, setuptools, semconv API, Go lint.
4. **Terraform bootstrap** — exact Helm chart pins; EKS + Argo once; later EC2/Fargate switch.
5. **Runtime on EKS** — rename Helm-era env vars to compose-era names; push to Git so selfHeal helps instead of hurts.
6. **Access** — `frontendproxy` LoadBalancer with AWS LB Controller NLB (IP targets) for EC2 and Fargate.
7. **Observability** — minimal `otelcol` under GitOps so OTLP exports succeed.
8. **Destroy hygiene** — actively remove orphan ELBs and `k8s-elb-*` SGs before VPC teardown.

**Durable lesson:** in this project, **Git is the deployment API**. CI, Terraform
(bootstrap), kubectl (debug), and Argo CD all meet on `main`. Prefer fixing
manifests/code in Git over fighting Argo with one-off kubectl patches.
