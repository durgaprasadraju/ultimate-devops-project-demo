# All Issues Faced and How They Were Fixed

> Chronological log of every problem encountered while correcting the
> microservice CI/CD + Argo CD setup — from architecture misunderstanding
> through Git, Docker Hub, and GitHub Actions failures.
>
> Related: [GIT_ISSUES_EXPLAINED.md](./GIT_ISSUES_EXPLAINED.md) ·
> [CI_CD_PIPELINE.md](./CI_CD_PIPELINE.md) ·
> [ARGOCD_TF_EXPLAINED.md](./ARGOCD_TF_EXPLAINED.md) ·
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

Only `.github/workflows/ci.yaml` existed for **product-catalog**. Other
services (`email`, `cart`, `frontend`, …) had no automated build/push.

### How it was fixed

Added:

| File | Role |
|------|------|
| `.github/workflows/reusable-service-ci.yaml` | Shared: Docker build/push + update K8s + commit |
| `.github/workflows/microservices-ci.yaml` | Matrix for all other services + path filters |
| `.github/workflows/ci.yaml` | Product-catalog (Go build/test/lint) + reusable Docker job |

Flow per service:

```text
change src/<service>/
  → build image → push to Docker Hub
  → update kubernetes/<service>/deploy.yaml
  → commit to main
  → Argo CD syncs → EKS
```

---

## 4. CI anti-patterns in the original product-catalog workflow

### Issues

| Problem | Why it was bad |
|---------|----------------|
| `git push -f` to `main` | Rewrites shared history; can wipe CI/teammate commits |
| `sed` replacing any `image:` line | Could hit wrong container (e.g. busybox init) |
| Lint not required for Docker job | Bad code could still ship |
| No path filters | Docs-only PRs could still run full CI |
| Push image on PR | Unusual; manifests should update mainly from `main` |

### How it was fixed

- Normal `git push` + `git pull --rebase` inside reusable workflow (no `-f`).
- Python update targets the **named container** only.
- Product-catalog: `docker` job `needs: [build, code-quality]`.
- Path filters on `src/<service>/**`.
- Push image + update Git only on `push` / `workflow_dispatch` to `main`
  (PRs build without pushing).

---

## 5. Secrets: username/password pasted in chat

### Issue

Docker Hub username and a live PAT (`dckr_pat_...`) were shared in chat.
GitHub account password was also nearly shared.

### Risk

Tokens in chat logs are **compromised**. Never put secrets in:

- Git files
- Workflow YAML
- Chat / screenshots

### How it was fixed

1. Guidance: **revoke** the exposed Docker Hub token and create a new one.
2. Store only in GitHub: **Settings → Secrets and variables → Actions**:
   - `DOCKER_USERNAME` = Docker Hub username (e.g. `durganadimpalli`)
   - `DOCKER_TOKEN` = Docker Hub **access token** (Read & Write)
3. Manifest image owner updated to match Docker Hub user
   (`kubernetes/productcatalog/deploy.yaml`).
4. Workflows already reference `${{ secrets.DOCKER_* }}` — no secrets in repo.

---

## 6. Invalid workflow: `contents: write` not allowed

### Issue

```text
Error calling workflow '.../reusable-service-ci.yaml@...'
The nested job 'docker' is requesting 'contents: write',
but is only allowed 'contents: read'.
```

### Cause

Reusable (called) workflows may only use permissions the **caller** grants.
Callers default to `contents: read`, but the reusable job needs `write` to
commit image-tag updates.

### How it was fixed

Added on the calling jobs in:

- `.github/workflows/ci.yaml`
- `.github/workflows/microservices-ci.yaml`

```yaml
permissions:
  contents: write
```

Also fixed a broken matrix `if:` in `microservices-ci.yaml` by building the
matrix dynamically in the `changes` job (only changed services).

---

## 7. Two jobs / workflows triggered on every push

### Issue

Almost every push started both `product-catalog-ci` and `microservices-ci`,
even when neither service’s source changed.

### Cause

Both workflows listed workflow files themselves in `push` path filters
(e.g. `.github/workflows/reusable-service-ci.yaml`). Editing CI YAML
matched **both** filters.

### How it was fixed

Removed workflow-file paths from **`push`** triggers. Kept them on
**`pull_request`** so editing workflows in a PR still validates once.

Now:

- Push touching only `src/product-catalog/**` → product-catalog CI only
- Push touching only `src/email/**` → microservices CI only
- Push touching only docs → neither service build

---

## 8. Docker login failed: “Username and password required”

### Issue

```text
Run docker/login-action@v3
Error: Username and password required
```

(Node 20 deprecation lines above this were **warnings only**, not the failure.)

### Cause

`DOCKER_USERNAME` / `DOCKER_TOKEN` were empty or missing in repo secrets.

### How it was fixed

User added GitHub Actions secrets (after rotating any exposed token).
No workflow code change required for this specific error.

---

## 9. Docker Hub: “access token has insufficient scopes”

### Issue

```text
401 Unauthorized: access token has insufficient scopes
... scope=repository:***/email:pull,push ...
```

Build succeeded; **push** to Docker Hub failed.

### Cause

PAT was Read-only, or restricted to specific repos, so it could not
`pull,push` (or create) the `email` repository.

### How it was fixed

Create a new Docker Hub PAT with:

- **Read & Write**
- Access to **all repositories** (CI creates many image repos on first push)

Update GitHub secret `DOCKER_TOKEN` with the new token. Re-run via a **new**
commit (not an old re-run).

---

## 10. Docker build: `/src/email` or `Gemfile.lock` not found

### Issue (first form)

```text
COPY ./src/email/Gemfile ./src/email/Gemfile.lock ./
"/src/email/Gemfile.lock": not found
```

### Issue (second form, after partial fix / stale re-run)

```text
COPY ./src/email/ .
"/src/email": not found
```

### Cause

Most Dockerfiles in this project expect **repository root** as build context
(`COPY ./src/email/...`, `COPY ./pb/...`). CI originally passed
`context: src/email`, so Docker looked under the wrong path.

### How it was fixed

In `microservices-ci.yaml` matrix, set `src_context` correctly:

| Services | Build context |
|----------|---------------|
| Most (email, cart, frontend, payment, …) | `.` (repo root) |
| ad, recommendation, kafka | Their own `src/<service>` folder |
| product-catalog | `src/product-catalog` (own Dockerfile style) |

---

## 11. Re-running a failed Actions job kept the old bug

### Issue

Workflow YAML was already fixed on `main`, but clicking **Re-run jobs** on an
**old** failed run still failed with `/src/email` not found.

### Cause

“Re-run” uses the **workflow file from the original commit**, not the latest
`main`.

### How it was fixed (process)

1. Push a **new** commit that touches the service path (or use
   `workflow_dispatch` after the fix is on `main`).
2. Do not rely on re-running ancient failed runs after workflow changes.

---

## 12. Needed “build all services and deploy to EKS”

### Issue

Path filters meant only the **changed** service built. Initial bootstrap /
full rebuild of every image was awkward.

### How it was fixed

Added `workflow_dispatch` to:

- `microservices-ci.yaml` → builds **all** matrix services when run manually
- `ci.yaml` → builds product-catalog on demand

On manual run from `main`, `push_image` is true → push images + update
manifests → Argo CD deploys to EKS.

**How to use:**

1. Push the workflow commit to `main`.
2. GitHub → **Actions** → **microservices-ci** → **Run workflow**.
3. Same for **product-catalog-ci**.
4. Wait for CI commits; Argo CD syncs automatically (cluster must be up).

Note: builds are **serialized** (`max-parallel: 1`) so Git commits do not race.

---

## 13. Git: divergent branches on pull

### Issue

```text
fatal: Need to specify how to reconcile divergent branches
```

### Cause

Local commits + remote CI commits on the same branch; Git had no default
pull strategy configured.

### How it was fixed

```bash
git pull --rebase origin main
```

(Without changing global `git config`.)

Details: [GIT_ISSUES_EXPLAINED.md](./GIT_ISSUES_EXPLAINED.md).

---

## 14. Git: push rejected (non-fast-forward)

### Issue

```text
! [rejected] main -> main (non-fast-forward)
hint: tip of your current branch is behind its remote counterpart
```

### Cause

While you had local commits (e.g. `workflow_dispatch` change), CI pushed
`[CI]: Update email image tag...` to `origin/main`.

### How it was fixed

```bash
git pull --rebase origin main
git push origin main
```

Habit for this repo (shared `main` + CI writers):

```bash
git pull --rebase origin main && git push origin main
```

---

## 15. Cursor / agent cannot push to GitHub

### Issue

```text
fatal: could not read Username for 'https://github.com': No such device or address
```

### Cause

The agent environment has no stored GitHub credentials for HTTPS push.

### How it was fixed

Push from **your** authenticated terminal:

```bash
git push origin main
```

---

## 16. Currency Docker build: `git clone` exit code 128

### Issue

```text
RUN git clone --depth 1 --branch v${OPENTELEMETRY_CPP_VERSION} https://github.com/open-telemetry/opentelemetry-cpp
...
did not complete successfully: exit code: 128
```

### Cause

`src/currency/Dockerfile` needs build-arg `OPENTELEMETRY_CPP_VERSION` (set in
`.env` as `1.23.0` for docker-compose). GitHub Actions did not pass that arg,
so the clone target became branch `v` (empty version) → git exit 128.

### How it was fixed

1. Default in Dockerfile: `ARG OPENTELEMETRY_CPP_VERSION=1.23.0`
2. CI / reusable workflow always loads version args from `.env` (see issue 17)

**Status:** Fixed.

---

## 17. Fraud-detection / Kafka Docker build: Java agent URL 404

### Issue

```text
ADD .../releases/download/v/opentelemetry-javaagent.jar
ERROR: invalid response status 404
```

### Cause

Same class of bug as currency (#16): `OTEL_JAVA_AGENT_VERSION` was empty in CI,
so the download URL became `.../download/v/...` (missing version) → 404.
Affects `src/fraud-detection/Dockerfile` and `src/kafka/Dockerfile`.
`.env` defines `OTEL_JAVA_AGENT_VERSION=2.20.1` for docker-compose only.

### How it was fixed

1. Default in both Dockerfiles: `ARG OTEL_JAVA_AGENT_VERSION=2.20.1`
2. **Systemic fix:** `reusable-service-ci.yaml` now always reads `.env` and passes
   `OPENTELEMETRY_CPP_VERSION` and `OTEL_JAVA_AGENT_VERSION` as Docker build-args
   for **every** service build (same values docker-compose uses)
3. Builds pin `platforms: linux/amd64` so `TARGETARCH` is set for cart,
   accounting, and shipping (they need it for `dotnet` / `wget` paths)

**Status:** Fixed.

---

## 18. Currency CMake: `IN_LIST` / CMP0057 after otel-cpp installs

### Issue

After clone/build of opentelemetry-cpp succeeded, currency app configure failed:

```text
CMake Error at .../opentelemetry-cpp/find-package-support-functions.cmake:119 (if):
  if given arguments:
    "Microsoft.GSL" "IN_LIST" "COMPONENT_api_THIRDPARTY_DEPENDS"
  Unknown arguments specified
-- Configuring incomplete, errors occurred!
```

(Often preceded by a CMP0057 policy warning about `IN_LIST`.)

### Cause

- CI now builds with `OPENTELEMETRY_CPP_VERSION=1.23.0` (matches `.env` / demo 2.1.3).
- That package’s CMake config uses modern `if(... IN_LIST ...)` (policy CMP0057).
- This fork’s currency `CMakeLists.txt` still had `cmake_minimum_required(VERSION 3.1)`
  (old 1.12-era source), so CMake ran with legacy policy and rejected `IN_LIST`.
- Upstream demo 2.1.3 already requires `cmake_minimum_required(VERSION 3.26)`.

### How it was fixed

Aligned with upstream 2.1.3:

```cmake
# src/currency/CMakeLists.txt
# src/currency/genproto/CMakeLists.txt
cmake_minimum_required(VERSION 3.26)
```

Alpine 3.18 in the currency Dockerfile already provides CMake ≥ 3.26, so the
requirement is satisfiable in CI.

**Status:** Fixed (commit `fix(currency): require CMake 3.26...`).

---

## 19. Study docs for juniors / interviews (with diagrams)

### Issue

Need per-microservice learning material (architecture, service links, K8s YAML,
Helm/Argo, interview Q&A) so the project can be studied for interviews.

### How it was delivered

| Path | What it covers |
|------|----------------|
| [microservices/README.md](./microservices/README.md) | Learning path + shop topology |
| [microservices/_SERVICE_MAP.md](./microservices/_SERVICE_MAP.md) | Place-order & other Mermaid diagrams |
| [microservices/_KUBERNETES_YAML_HELM_ARGOCD.md](./microservices/_KUBERNETES_YAML_HELM_ARGOCD.md) | YAML / Helm / Argo line-by-line |
| [microservices/*.md](./microservices/) | One file per service (19 services) |
| [INTERVIEW_QUESTIONS.md](./INTERVIEW_QUESTIONS.md) | 50+ Q&A (TF / EKS / Docker / GitOps) |
| [GIT_ISSUES_EXPLAINED.md](./GIT_ISSUES_EXPLAINED.md) | Git divergence / rebase habits |

**Status:** Done.

---

## End state (what “fixed” looks like)

```text
Developer / workflow_dispatch
        │
        ▼
GitHub Actions
  • product-catalog-ci  (Go + Docker)
  • microservices-ci    (all other services; path filter OR build-all)
        │
        ├─► Docker Hub  (durganadimpalli/<service>:<run_id>)
        │
        └─► Commit image tag into kubernetes/<service>/deploy.yaml
                │
                ▼
         Argo CD (otel-demo)
           syncs kubernetes/* except complete-deploy.yaml
                │
                ▼
              EKS
```

### Key files after all fixes

| File | Purpose |
|------|---------|
| `.github/workflows/ci.yaml` | Product-catalog CI + manual run |
| `.github/workflows/microservices-ci.yaml` | Other services + manual build-all |
| `.github/workflows/reusable-service-ci.yaml` | Shared Docker + GitOps commit + `.env` build-args |
| `src/currency/CMakeLists.txt` | CMake ≥ 3.26 for otel-cpp 1.23 |
| `terraform/argocd.tf` | Argo syncs per-service manifests |
| `argocd/application.yaml` | Same for manual Argo bootstrap |
| GitHub secrets `DOCKER_USERNAME` / `DOCKER_TOKEN` | Registry auth |
| `docs/microservices/` | Per-service + diagram study guides |
| `docs/INTERVIEW_QUESTIONS.md` | Interview drill |

---

## Checklist if something breaks again

1. **Workflow invalid?** Callers must grant `permissions: contents: write`.
2. **Docker login fail?** Check Actions secrets exist and are non-empty.
3. **401 insufficient scopes?** New Docker Hub PAT with Read & Write, all repos.
4. **COPY path not found?** Build context must match Dockerfile (`.` vs `src/...`).
5. **Old failure after fix?** Don’t re-run old job; push new commit or Run workflow.
6. **Push rejected?** `git pull --rebase origin main && git push`.
7. **Cluster not updating?** Confirm Argo excludes `complete-deploy.yaml` and
   syncs the folder CI actually edits; check Argo UI for sync errors.
8. **Never** commit tokens or force-push `main`.
9. **Currency build exit 128?** Pass / default `OPENTELEMETRY_CPP_VERSION` (see issue 16).
10. **Java agent 404 (`.../download/v/...`)?** Pass / default `OTEL_JAVA_AGENT_VERSION` (see issue 17).
11. **Currency CMake `IN_LIST` / CMP0057?** `cmake_minimum_required(VERSION 3.26)` (see issue 18).

---

## Summary

From start to now, the work fixed a **broken GitOps loop** (CI writing a file
Argo ignored), expanded CI to **all microservices**, then chased operational
failures: **permissions**, **path filters**, **Docker Hub auth/scopes**,
**Docker build context**, **missing build-args**, **CMake / otel-cpp version
mismatch**, **manual build-all**, and **Git divergence** caused by CI
committing back to `main`. Study guides under `docs/microservices/` and
`docs/INTERVIEW_QUESTIONS.md` document the architecture for interviews.

The durable lesson: in this project, **Git is the deployment API**. CI, you,
and Argo CD all meet on `main` — so secrets stay in GitHub Secrets, manifests
must be what Argo watches, and you always rebase before pushing.
