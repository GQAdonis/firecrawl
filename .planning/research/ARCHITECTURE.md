# Architecture Patterns: GitHub Actions + Argo CD + GKE GitOps

**Domain:** Kubernetes GitOps Deployment Pipeline
**Researched:** 2026-03-27
**Confidence:** MEDIUM (based on established GitOps patterns and official documentation patterns)

## Recommended Architecture

GitOps architecture follows a **pull-based deployment model** where the CI system (GitHub Actions) is responsible for building and pushing artifacts, while the CD system (Argo CD) continuously monitors the desired state in Git and reconciles it with the actual cluster state.

```
┌─────────────────────────────────────────────────────────────────┐
│                        GitHub Repository                         │
│  ┌────────────────┐              ┌─────────────────┐            │
│  │  Source Code   │              │  k8s Manifests  │            │
│  │  (apps/*)      │              │  (k8s/*.yaml)   │            │
│  └────────────────┘              └─────────────────┘            │
└─────────────────────────────────────────────────────────────────┘
         │                                      ▲
         │ (1) Push to main                     │ (4) Commit updated
         │     triggers workflow                │     manifests
         ▼                                      │
┌─────────────────────────────────────────────────────────────────┐
│                      GitHub Actions (CI)                         │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐        │
│  │ Build Images │──▶│  Push to GCR │──▶│ Update k8s/  │        │
│  │ (Docker)     │   │              │   │ manifests    │        │
│  └──────────────┘   └──────────────┘   └──────────────┘        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ (2) Image push
                              ▼
                   ┌─────────────────────┐
                   │ Google Container    │
                   │ Registry (GCR)      │
                   │ prometheus-461323   │
                   └─────────────────────┘
                              │
                              │ (6) Pull images
                              │
         ┌────────────────────┴────────────────────┐
         │                                          │
         │ (3) Poll Git repo                       │ (5) Sync/Deploy
         ▼                                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Argo CD (CD System)                           │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐        │
│  │ Git Monitor  │──▶│ State Compare│──▶│   Kubectl    │        │
│  │ (k8s/*.yaml) │   │              │   │   Apply      │        │
│  └──────────────┘   └──────────────┘   └──────────────┘        │
│                                                  │               │
│  ┌──────────────────────────────────────────────┘               │
│  │                                                               │
│  │           Argo CD Components (in-cluster):                   │
│  │  • argocd-server (UI/API)                                    │
│  │  • argocd-repo-server (Git/Helm/Kustomize)                   │
│  │  • argocd-application-controller (Reconciliation)            │
│  │  • argocd-redis (Cache)                                      │
│  └───────────────────────────────────────────┐                  │
└────────────────────────────────────────────────────────────────┘
                                                │
                                                │ (7) Apply manifests
                                                ▼
┌─────────────────────────────────────────────────────────────────┐
│              Google Kubernetes Engine (GKE)                      │
│                     client-cluster                               │
│  ┌─────────────────────────────────────────────────────┐        │
│  │               Namespace: firecrawl                   │        │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐    │        │
│  │  │ API Pods   │  │ Worker Pods│  │ Playwright │    │        │
│  │  └────────────┘  └────────────┘  └────────────┘    │        │
│  │  ┌────────────┐  ┌────────────┐                    │        │
│  │  │ Postgres   │  │   Redis    │                    │        │
│  │  │(StatefulSet│  │(StatefulSet│                    │        │
│  │  └────────────┘  └────────────┘                    │        │
│  └─────────────────────────────────────────────────────┘        │
│  ┌─────────────────────────────────────────────────────┐        │
│  │               Envoy Gateway                          │        │
│  │  HTTPRoute: firecrawl-api.prometheusags.ai          │        │
│  │  HTTPRoute: firecrawl.prometheusags.ai              │        │
│  └─────────────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow Sequence

1. **Code Change** → Developer pushes to `main` branch
2. **CI Trigger** → GitHub Actions workflow starts
3. **Build Phase** → Actions builds Docker images for API and ingestion-ui
4. **Publish Phase** → Images pushed to GCR with SHA-based tags
5. **Manifest Update** → Actions updates `k8s/*.yaml` with new image tags
6. **Git Commit** → Actions commits manifest changes back to repo
7. **Git Poll** → Argo CD detects manifest changes (default: 3-minute poll)
8. **Reconciliation** → Argo CD compares desired state (Git) vs actual state (cluster)
9. **Deployment** → Argo CD applies changes via kubectl
10. **Verification** → Argo CD monitors pod health and reports status

### Component Boundaries

| Component | Responsibility | Does NOT Do | Communicates With |
|-----------|---------------|-------------|-------------------|
| **GitHub Actions** | Build images, run tests, push to registry, update manifests, commit changes | Does NOT deploy to cluster, does NOT have cluster credentials | GitHub (source), GCR (push), Git repo (commit) |
| **Google Container Registry** | Store container images, serve images to GKE | Does NOT trigger deployments, does NOT know about manifests | GitHub Actions (receive), GKE nodes (serve) |
| **Argo CD Application Controller** | Continuously reconcile Git state with cluster state, execute deployments | Does NOT build images, does NOT run tests | Git repo (read), Kubernetes API (write) |
| **Argo CD Repo Server** | Clone Git repos, render manifests (Kustomize/Helm), cache repo state | Does NOT apply manifests to cluster | Git repo (read), Application Controller (provide manifests) |
| **Argo CD Server** | Provide UI/API, handle user auth, expose deployment status | Does NOT perform deployments directly | Application Controller (read status), Users (serve UI/API) |
| **Kubernetes API** | Accept manifest changes, schedule pods, manage resources | Does NOT fetch from Git, does NOT build images | Argo CD (accept changes), Kubelet (instruct), Envoy Gateway (route) |
| **Envoy Gateway** | Route external traffic to services, terminate TLS, HTTP routing | Does NOT deploy apps, does NOT manage pods | Kubernetes services (route to), External clients (receive from) |
| **GKE Node Pool** | Run containers, pull images from GCR, execute workloads | Does NOT decide what to run | Kubernetes API (receive instructions), GCR (pull images) |

### Critical Separation: CI vs CD

**CI Boundary (GitHub Actions):**
- Builds artifacts (container images)
- Runs tests
- Publishes artifacts to registries
- **Updates the desired state** (k8s manifests in Git)
- Has GCR credentials only
- Triggered by code push
- Short-lived (minutes)

**CD Boundary (Argo CD):**
- **Enforces the desired state** (applies manifests to cluster)
- Continuously monitors for drift
- Has cluster credentials (RBAC)
- Triggered by Git changes (polling or webhook)
- Long-lived (always running)
- No build capabilities

**Why This Matters:**
- GitHub Actions **never** touches the cluster directly
- Argo CD **never** builds images
- All deployments are auditable via Git history
- Rollback = `git revert` + wait for Argo CD sync
- Cluster credentials never leave the cluster

## Argo CD Architecture Deep Dive

### Core Components (Running in client-cluster)

#### 1. Application Controller
**Purpose:** Heart of GitOps reconciliation loop

**Responsibilities:**
- Poll Git repository for manifest changes (default 3-minute interval)
- Compare desired state (Git manifests) with actual state (cluster resources)
- Generate sync operations when drift detected
- Execute kubectl apply/delete operations
- Monitor resource health (pods, deployments, services)
- Report sync status and health status
- Handle sync waves and hooks for ordered deployments

**Configuration:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: firecrawl
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/[org]/firecrawl
    targetRevision: main
    path: k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: firecrawl
  syncPolicy:
    automated:
      prune: true      # Delete resources not in Git
      selfHeal: true   # Correct drift automatically
```

#### 2. Repo Server
**Purpose:** Git repository interface and manifest rendering

**Responsibilities:**
- Clone Git repositories and cache them
- Render Kubernetes manifests from various sources (plain YAML, Kustomize, Helm)
- Maintain repo credentials
- Serve rendered manifests to Application Controller
- Cache rendered manifests for performance

**For Firecrawl:**
- Reads from `k8s/*.yaml` path
- No Helm/Kustomize rendering needed (plain YAML)
- Caches manifest tree for fast reconciliation

#### 3. API Server
**Purpose:** User interface and external API

**Responsibilities:**
- Serve Web UI for deployment visualization
- Expose REST/gRPC API for CLI and integrations
- Handle authentication and RBAC
- Provide deployment history and logs
- Manual sync triggers
- Application management (create/update/delete)

**Access:**
```bash
# Port-forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Or expose via Ingress/LoadBalancer
# Dashboard shows:
# - Sync status (Synced/OutOfSync)
# - Health status (Healthy/Progressing/Degraded)
# - Resource tree (pods, services, deployments)
# - Sync history with commit links
```

#### 4. Redis
**Purpose:** Caching and temporary storage

**Responsibilities:**
- Cache Git repository state
- Store application state during reconciliation
- Rate limiting and locking for concurrent operations

### Argo CD Sync Mechanisms

#### Polling (Default)
```yaml
# In argocd-cm ConfigMap
data:
  timeout.reconciliation: 180s  # 3 minutes default
```
- Argo CD polls Git repository every 3 minutes
- Detects new commits by comparing HEAD SHA
- Initiates sync if manifest changes detected
- **Trade-off:** Deployment lag up to 3 minutes

#### Webhook (Recommended for Production)
```yaml
# GitHub webhook configuration
URL: https://argocd.example.com/api/webhook
Content-Type: application/json
Events: Push
```
- GitHub notifies Argo CD immediately on push
- Sub-second deployment initiation
- Requires Argo CD API server accessible from internet
- **Trade-off:** Additional security surface, needs webhook secret

#### Manual Sync
```bash
argocd app sync firecrawl
# Or via UI: Click "Sync" button
```

### Argo CD Health Assessment

Argo CD understands Kubernetes resource types and checks:

| Resource Type | Health Check |
|--------------|--------------|
| Deployment | `.status.conditions` (Available, Progressing) |
| StatefulSet | `.status.readyReplicas == .spec.replicas` |
| Pod | `.status.phase == Running` and readiness probes |
| Service | Always healthy unless missing endpoints |
| PersistentVolumeClaim | `.status.phase == Bound` |

**Health Statuses:**
- **Healthy** — Resource running as expected
- **Progressing** — Resource starting/updating
- **Degraded** — Resource failing (CrashLoopBackOff, ImagePullError)
- **Suspended** — Resource intentionally paused
- **Missing** — Resource in Git but not in cluster
- **Unknown** — Health check not applicable

## GitHub Actions Architecture

### Workflow Structure

#### Job 1: Build and Push Images
**Responsibilities:**
- Checkout code from repository
- Authenticate to GCR using Workload Identity or service account key
- Build Docker images for `apps/api` and `apps/ingestion-ui`
- Tag images with commit SHA (e.g., `gcr.io/prometheus-461323/firecrawl-api:abc123f`)
- Push images to GCR
- Output image tags for next job

**Key Considerations:**
- Use Docker layer caching for faster builds
- Multi-stage builds to minimize image size
- Security scanning before push (optional)
- Parallel builds for multiple images

**Example Structure:**
```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      api-tag: ${{ steps.meta.outputs.api-tag }}
      ui-tag: ${{ steps.meta.outputs.ui-tag }}
    steps:
      - uses: actions/checkout@v4
      - name: Set up Docker Buildx
      - name: Authenticate to GCR
      - name: Build and push API
      - name: Build and push UI
```

#### Job 2: Update Kubernetes Manifests
**Responsibilities:**
- Receive image tags from previous job
- Clone repository (or use existing checkout)
- Update `k8s/api-deployment.yaml` with new API image tag
- Update `k8s/ingestion-ui-deployment.yaml` with new UI image tag
- Commit changes to Git
- Push commit to `main` branch

**Manifest Update Strategies:**

**Strategy 1: sed replacement (simple)**
```bash
sed -i "s|image: gcr.io/prometheus-461323/firecrawl-api:.*|image: gcr.io/prometheus-461323/firecrawl-api:${NEW_TAG}|" k8s/api-deployment.yaml
```
- Pros: Simple, no dependencies
- Cons: Fragile, regex-based, error-prone

**Strategy 2: yq (YAML processor)**
```bash
yq eval -i '.spec.template.spec.containers[0].image = "gcr.io/prometheus-461323/firecrawl-api:'${NEW_TAG}'"' k8s/api-deployment.yaml
```
- Pros: YAML-aware, precise targeting
- Cons: Requires yq installation

**Strategy 3: Kustomize (recommended for scale)**
```bash
cd k8s && kustomize edit set image gcr.io/prometheus-461323/firecrawl-api:${NEW_TAG}
```
- Pros: Standard tool, handles multiple images, supports overlays
- Cons: Requires Kustomize structure

**For Firecrawl (monorepo, simple setup):** Strategy 2 (yq) recommended for balance of simplicity and reliability.

#### Credentials Management

**GitHub Actions needs:**
- **GCR Push Permission** — Service account with `roles/storage.admin` on GCR bucket
- **Git Push Permission** — Handled by `GITHUB_TOKEN` (automatic)

**Options for GCR Authentication:**

| Method | Setup | Security | Recommended |
|--------|-------|----------|-------------|
| Service Account Key | Upload JSON key to GitHub Secrets | Lower (long-lived credential) | ✓ For simplicity |
| Workload Identity Federation | Configure OIDC between GitHub and GCP | Higher (short-lived tokens) | ✓ For production |
| GCP GitHub Actions | Use Google-provided actions | Higher (managed) | ✓ For production |

**For Firecrawl:** Service account key sufficient for initial setup, migrate to Workload Identity for production hardening.

### Git Commit Strategy

**Automated Commit Pattern:**
```bash
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git add k8s/*.yaml
git commit -m "chore: update images to ${SHORT_SHA}"
git push origin main
```

**Considerations:**
- Use `[skip ci]` in commit message to prevent infinite loops (GitHub Actions triggering itself)
- Or use `paths-ignore` filter in workflow to ignore `k8s/**` changes
- Commit should be atomic (all manifests updated together)
- Include commit SHA in message for traceability

**Potential Issue:** Push can fail if `main` branch updated between checkout and push
**Solution:** Retry with pull-rebase, or use branch + auto-merge PR pattern

## GKE Architecture Integration

### Cluster Networking

#### In-Cluster Service Discovery
```yaml
# Postgres service
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: firecrawl
spec:
  selector:
    app: postgres
  ports:
    - port: 5432
---
# API connects via DNS
DATABASE_URL=postgresql://user:pass@postgres.firecrawl.svc.cluster.local:5432/dbname
```

**DNS Pattern:** `<service>.<namespace>.svc.cluster.local`
- Services in same namespace: Use short name `postgres`
- Services in other namespace: Use FQDN `postgres.firecrawl.svc.cluster.local`

#### Envoy Gateway Integration

**Architecture:**
```
Internet → Cloud Load Balancer → Envoy Gateway Pods → HTTPRoute → Service → Pods
```

**HTTPRoute Structure:**
```yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: firecrawl-api
  namespace: firecrawl
spec:
  parentRefs:
    - name: shared-gateway  # Existing gateway in cluster
      namespace: envoy-gateway-system
  hostnames:
    - firecrawl-api.prometheusags.ai
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: firecrawl-api
          port: 3002
```

**TLS Termination:**
```yaml
# Gateway handles TLS (not HTTPRoute)
apiVersion: gateway.networking.k8s.io/v1beta1
kind: Gateway
metadata:
  name: shared-gateway
spec:
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
      tls:
        mode: Terminate
        certificateRefs:
          - name: candle-vllm  # Existing cert secret
            namespace: cert-namespace
```

**Certificate Cloning (if needed):**
```bash
# Copy TLS secret to firecrawl namespace
kubectl get secret candle-vllm -n original-namespace -o yaml | \
  sed 's/namespace: original-namespace/namespace: firecrawl/' | \
  kubectl apply -f -
```

### Storage Architecture

#### Postgres StatefulSet + PVC
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  volumeClaimTemplates:
    - metadata:
        name: postgres-data
      spec:
        accessModes: [ "ReadWriteOnce" ]
        storageClassName: immediate-binding  # Critical: immediate binding
        resources:
          requests:
            storage: 10Gi
```

**Why StatefulSet (not Deployment):**
- Stable network identity (postgres-0)
- Ordered deployment and scaling
- Stable persistent storage (PVC follows pod)
- Graceful rolling updates

**Storage Class: immediate-binding**
- PVC bound immediately when created (not when pod scheduled)
- Prevents pod stuck in Pending due to volume zone mismatch
- GKE creates PD in same zone as cluster

**Backup Considerations:**
- No automated backup in v1 (per constraints)
- Manual: `kubectl exec` → `pg_dump` → store externally
- Future: VolumeSnapshots or external backup tools

#### Redis StatefulSet + PVC
Similar pattern to Postgres, but:
- Smaller volume (1Gi sufficient for cache/queues)
- RDB persistence enabled for queue durability
- Could use ephemeral storage if acceptable data loss on restart

### Workload Types

| Service | Type | Replicas | Why |
|---------|------|----------|-----|
| API | Deployment | 2-3 | Stateless, horizontal scale, rolling updates |
| Worker | Deployment | 3-5 | Stateless, process jobs, scale with queue depth |
| Ingestion UI | Deployment | 2 | Stateless, static frontend |
| Postgres | StatefulSet | 1 | Stateful, single primary (no HA in v1) |
| Redis | StatefulSet | 1 | Stateful, single instance (no HA in v1) |
| Playwright | Deployment | 2 | Stateless, browser automation, isolate failures |

## Data Flow: Code to Cluster

### Deployment Sequence (Happy Path)

```
T+0:00  Developer pushes commit to main
        ├─ GitHub receives push
        └─ Triggers GitHub Actions workflow

T+0:05  GitHub Actions: Build job starts
        ├─ Checkout code
        ├─ Build API Docker image (3-5 minutes)
        ├─ Build UI Docker image (2-3 minutes)
        ├─ Push to GCR (1 minute)
        └─ Output image tags

T+0:10  GitHub Actions: Update manifests job starts
        ├─ Update k8s/api-deployment.yaml
        ├─ Update k8s/ingestion-ui-deployment.yaml
        ├─ Git commit
        └─ Git push to main

T+0:11  Argo CD: Detects Git change
        ├─ Repo server clones/pulls repo
        ├─ Detects manifest diff
        └─ Triggers sync (if auto-sync enabled)

T+0:12  Argo CD: Sync operation starts
        ├─ Application controller renders manifests
        ├─ Compares with cluster state
        ├─ Generates kubectl apply operations
        └─ Applies to Kubernetes API

T+0:13  Kubernetes: Rolling update
        ├─ Creates new ReplicaSet with new image
        ├─ Starts new pods
        ├─ Waits for readiness probes (30s)
        ├─ Scales down old ReplicaSet
        └─ Terminates old pods

T+0:15  Argo CD: Health check
        ├─ Monitors pod status
        ├─ Waits for all pods Running
        ├─ Checks readiness
        └─ Reports sync complete + healthy

T+0:16  Deployment complete (total ~16 minutes)
```

### Rollback Sequence

```
T+0:00  Issue detected (manual or automated)
        └─ Developer runs: git revert <commit>

T+0:01  Git revert pushed to main
        └─ Manifest reverted to previous image tags

T+0:04  Argo CD detects revert (3-min poll or webhook)
        ├─ Recognizes manifest change
        └─ Initiates sync

T+0:05  Kubernetes rolls back
        ├─ Creates ReplicaSet with old image
        ├─ Starts pods (faster: image cached)
        ├─ Scales down new ReplicaSet
        └─ Service restored

T+0:07  Rollback complete (total ~7 minutes)
```

**Why Fast:** Old images already pulled on nodes, no build phase needed.

### Error Scenarios and Handling

#### Scenario 1: Image Build Fails
- **Detection:** GitHub Actions job fails
- **Impact:** No manifest update, no deployment triggered
- **Cluster State:** Unchanged (still running previous version)
- **Recovery:** Fix code, push again

#### Scenario 2: Image Push Fails
- **Detection:** GitHub Actions job fails at GCR push
- **Impact:** New image tag in manifests, but image doesn't exist
- **Cluster State:** Deployment fails with `ImagePullBackOff`
- **Argo CD View:** Degraded health status
- **Recovery:** Re-run workflow or rollback manifests

#### Scenario 3: Manifest Update Fails
- **Detection:** GitHub Actions can't push to Git
- **Impact:** New images in GCR, but manifests not updated
- **Cluster State:** Unchanged (no Argo CD trigger)
- **Recovery:** Manual manifest update or re-run workflow

#### Scenario 4: Argo CD Sync Fails
- **Detection:** Argo CD reports sync error
- **Possible Causes:**
  - Invalid YAML syntax
  - Resource quota exceeded
  - RBAC permission denied
  - Namespace doesn't exist
- **Impact:** Cluster state unchanged or partially updated
- **Argo CD View:** OutOfSync + Degraded
- **Recovery:** Fix manifest issue, Argo CD auto-retries

#### Scenario 5: Pods Crash After Deployment
- **Detection:** Argo CD reports Degraded health
- **Impact:** New pods in CrashLoopBackOff, old pods terminated
- **Cluster State:** Service degraded or down
- **Recovery:** Git revert (rollback) or manual intervention

#### Scenario 6: StatefulSet Update Blocks
- **Detection:** Postgres/Redis stuck in Pending
- **Possible Causes:**
  - PVC can't bind (storage class issue)
  - Volume in different zone than node
- **Impact:** Database unavailable, app degraded
- **Recovery:** Fix storage class, delete PVC and pod to recreate

## Build Order and Dependency Management

### Phase 1: Foundation (No Dependencies)
**Components:**
- Namespace creation
- RBAC (ServiceAccounts, Roles, RoleBindings)
- ConfigMaps for configuration
- Secrets for credentials

**Why First:**
- Required by all other resources
- No runtime dependencies
- Can be applied in any order

**Argo CD Handling:**
Automatically applies in correct order based on Kubernetes resource types.

### Phase 2: Storage (Depends on Namespace)
**Components:**
- PersistentVolumeClaims for Postgres
- PersistentVolumeClaims for Redis

**Why Second:**
- StatefulSets block until PVC bound
- Immediate-binding storage class binds PVC before pod created
- Prevents pod scheduling delays

**Argo CD Handling:**
Waits for PVC to reach `Bound` state before marking healthy.

### Phase 3: Stateful Services (Depends on Storage)
**Components:**
- Postgres StatefulSet + Service
- Redis StatefulSet + Service

**Why Third:**
- Application pods depend on these services being ready
- StatefulSets need PVCs bound first
- Services need to be discoverable via DNS

**Argo CD Handling:**
Monitors StatefulSet rollout, waits for `.status.readyReplicas == .spec.replicas`.

**Critical:** Add readiness probes to ensure pods actually accepting connections:
```yaml
readinessProbe:
  tcpSocket:
    port: 5432
  initialDelaySeconds: 10
  periodSeconds: 5
```

### Phase 4: Supporting Services (Depends on Phase 3)
**Components:**
- Playwright Deployment + Service

**Why Fourth:**
- Workers depend on Playwright for browser automation
- Should be ready before workers start

### Phase 5: Application Services (Depends on Phase 3-4)
**Components:**
- API Deployment + Service
- Worker Deployment
- Ingestion UI Deployment + Service

**Why Fifth:**
- Depends on Postgres, Redis, Playwright being healthy
- Use `initContainers` to wait for database readiness:
```yaml
initContainers:
  - name: wait-for-postgres
    image: busybox
    command: ['sh', '-c', 'until nc -z postgres 5432; do sleep 2; done']
```

### Phase 6: Ingress (Depends on Phase 5)
**Components:**
- HTTPRoute for API
- HTTPRoute for Ingestion UI

**Why Last:**
- Depends on Services being created
- Envoy Gateway validates backend references exist
- Prevents external traffic before app ready

**Argo CD Handling:**
HTTPRoute marked healthy if Gateway accepts it (valid backend references).

### Argo CD Sync Waves (Optional Ordering)

For strict ordering, use sync waves:
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"  # Lower number = earlier deployment
```

**Recommended Waves for Firecrawl:**
```yaml
# Wave 0: Namespace, RBAC, ConfigMaps, Secrets
argocd.argoproj.io/sync-wave: "0"

# Wave 1: PVCs
argocd.argoproj.io/sync-wave: "1"

# Wave 2: Postgres, Redis
argocd.argoproj.io/sync-wave: "2"

# Wave 3: Playwright
argocd.argoproj.io/sync-wave: "3"

# Wave 4: API, Workers, UI
argocd.argoproj.io/sync-wave: "4"

# Wave 5: HTTPRoutes
argocd.argoproj.io/sync-wave: "5"
```

**Trade-off:** Slower deployments (waits for each wave to be healthy) vs guaranteed order.

### Dependency Visualization

```
Namespace
   ├─── RBAC
   ├─── Secrets
   ├─── ConfigMaps
   └─── PVCs
          ├─── Postgres StatefulSet ─┐
          └─── Redis StatefulSet ────┤
                                      ├─── Playwright Deployment ─┐
                                      │                            │
                                      ├─── API Deployment ─────────┤
                                      ├─── Worker Deployment ──────┤
                                      └─── UI Deployment ──────────┤
                                                                   │
                    HTTPRoute (API) ←──────────────────────────────┤
                    HTTPRoute (UI)  ←───────────────────────────────┘
```

## Observability and Monitoring

### Argo CD Observability

**Built-in Dashboards:**
- Application list (sync/health status)
- Resource tree (hierarchical view of all resources)
- Event logs (Git commits, sync operations, errors)
- Resource diff viewer (Git vs cluster state)

**CLI Access:**
```bash
# Install Argo CD CLI
brew install argocd  # or download binary

# Login
argocd login argocd.example.com

# Watch deployment
argocd app get firecrawl --watch

# View sync history
argocd app history firecrawl

# Manual sync
argocd app sync firecrawl
```

**Metrics (Prometheus):**
Argo CD exposes metrics at `/metrics` endpoint:
- `argocd_app_sync_total` — Sync attempts
- `argocd_app_reconcile_count` — Reconciliation loops
- `argocd_app_info` — Application metadata
- `argocd_git_request_duration_seconds` — Git operation latency

### GitHub Actions Observability

**Built-in:**
- Workflow run history in GitHub UI
- Step-by-step logs
- Artifacts (test results, build logs)
- Status checks on commits/PRs

**Notifications:**
```yaml
# In workflow
- name: Notify on failure
  if: failure()
  uses: actions/github-script@v6
  with:
    script: |
      github.rest.issues.createComment({
        issue_number: context.issue.number,
        owner: context.repo.owner,
        repo: context.repo.repo,
        body: '🚨 Deployment failed!'
      })
```

### Kubernetes Observability

**GKE Built-in:**
- GKE Dashboard (Workloads, Services, Ingress)
- Cloud Logging (pod logs, cluster events)
- Cloud Monitoring (resource usage, SLOs)

**kubectl Access:**
```bash
# Watch deployment rollout
kubectl rollout status deployment/firecrawl-api -n firecrawl

# View pod logs
kubectl logs -f deployment/firecrawl-api -n firecrawl

# Describe resources
kubectl describe pod <pod-name> -n firecrawl

# View events
kubectl get events -n firecrawl --sort-by='.lastTimestamp'
```

**Existing Sentry Integration:**
Firecrawl already uses Sentry for error tracking (per PROJECT.md), continue using for application-level observability.

## Security Considerations

### Principle of Least Privilege

| Component | Required Permissions | Should NOT Have |
|-----------|---------------------|-----------------|
| GitHub Actions | GCR push, Git push | Kubernetes API access, cluster credentials |
| Argo CD Application Controller | Full access to `firecrawl` namespace | Access to other namespaces, cluster-admin |
| API Pods | Access to ConfigMaps/Secrets in `firecrawl` namespace | Node access, other namespace access |
| Postgres Pods | Storage read/write | Network policies allow only API/Worker connections |

### Secret Management

**Secrets in GitHub:**
- GCR service account key stored as GitHub Secret
- Never commit to repository
- Rotate periodically

**Secrets in Kubernetes:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: firecrawl-secrets
  namespace: firecrawl
type: Opaque
stringData:
  DATABASE_URL: postgresql://...
  REDIS_URL: redis://...
  OPENAI_API_KEY: sk-...
```

**Argo CD Secret Handling:**
- Argo CD does NOT modify secrets by default
- Use `kubectl create secret` or external tools (not tracked in Git)
- OR use sealed-secrets/external-secrets (out of scope for v1)

### Network Policies (Recommended)

```yaml
# Only allow API/Worker to access Postgres
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: postgres-access
  namespace: firecrawl
spec:
  podSelector:
    matchLabels:
      app: postgres
  ingress:
    - from:
      - podSelector:
          matchLabels:
            app: firecrawl-api
      - podSelector:
          matchLabels:
            app: firecrawl-worker
      ports:
      - port: 5432
```

### Image Security

**Recommendations:**
- Use minimal base images (alpine, distroless)
- Scan images for vulnerabilities (Trivy, Snyk)
- Pin image digests in production (not just tags)
- Use private GCR (not public)

```yaml
# Pin by digest for immutability
image: gcr.io/prometheus-461323/firecrawl-api@sha256:abc123...
# Instead of:
image: gcr.io/prometheus-461323/firecrawl-api:latest
```

## Scalability Patterns

### Horizontal Scaling (Future)

**API/Worker Scaling:**
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: firecrawl-api
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: firecrawl-api
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

**Considerations:**
- Out of scope for v1 (per PROJECT.md)
- Workers should scale based on queue depth (custom metric)
- API scales based on CPU/memory or request rate

### Database Scaling (Future)

**Postgres:**
- Current: Single StatefulSet (no HA)
- Future: CloudSQL Postgres (managed HA, backups, replicas)
- OR: Patroni/Stolon (HA Postgres on K8s, complex)

**Redis:**
- Current: Single StatefulSet
- Future: Redis Sentinel (HA) or Redis Cluster (sharding)
- OR: Cloud Memorystore (managed)

### GitOps Scaling

**Multi-Environment:**
```
k8s/
  base/          # Common manifests
  overlays/
    dev/         # Dev overrides
    staging/     # Staging overrides
    production/  # Prod overrides
```

**Multiple Applications:**
- App-of-apps pattern (Argo CD manages multiple apps)
- ApplicationSet for templated deployments
- Separate repos per app (mono-repo vs poly-repo)

## Operational Patterns

### Deployment Strategies

**Rolling Update (Default):**
```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0    # No downtime
      maxSurge: 1          # One extra pod during rollout
```
- Gradual replacement of pods
- No downtime if readiness probes correct
- Default for Deployments

**Recreate (Stateful apps):**
```yaml
spec:
  strategy:
    type: Recreate
```
- Terminate all old pods before creating new
- Downtime acceptable (Postgres, Redis)
- Simpler than rolling for StatefulSets

**Blue-Green (Future):**
- Two complete environments
- Switch traffic via Service selector change
- Requires 2x resources
- Out of scope for v1

**Canary (Future):**
- Gradual traffic shift to new version
- Requires service mesh (Istio) or Flagger
- Out of scope for v1

### Health Checks

**Liveness Probe:**
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 3002
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 3
```
- Determines if container should be restarted
- Should check critical dependencies (DB connection)
- Failure → pod restarted

**Readiness Probe:**
```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: 3002
  initialDelaySeconds: 10
  periodSeconds: 5
  failureThreshold: 3
```
- Determines if pod should receive traffic
- Should be faster check than liveness
- Failure → pod removed from Service endpoints

**Startup Probe (Slow starts):**
```yaml
startupProbe:
  httpGet:
    path: /health
    port: 3002
  initialDelaySeconds: 0
  periodSeconds: 5
  failureThreshold: 30  # 30*5 = 150s max startup time
```
- For apps with slow initialization
- Prevents liveness probe from killing during startup

### Resource Management

**Requests and Limits:**
```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "250m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

**Best Practices:**
- Always set requests (affects scheduling)
- Set limits to prevent resource hogging
- Requests = minimum needed, Limits = maximum allowed
- Monitor actual usage, adjust accordingly

**Quality of Service:**
- **Guaranteed** (requests == limits) — highest priority
- **Burstable** (requests < limits) — medium priority
- **BestEffort** (no requests/limits) — lowest priority, evicted first

### Disaster Recovery

**Backup Strategy:**
```bash
# Manual Postgres backup
kubectl exec postgres-0 -n firecrawl -- pg_dump -U postgres firecrawl > backup.sql

# Restore
kubectl exec -i postgres-0 -n firecrawl -- psql -U postgres firecrawl < backup.sql
```

**Git as Source of Truth:**
- All manifests in Git → infrastructure as code
- Cluster destroyed → `argocd app sync` rebuilds everything
- Data loss requires backups (Postgres/Redis)

**Recovery Time:**
- Manifest rollback: ~5-10 minutes (Git revert + Argo CD sync)
- Full cluster rebuild: ~30 minutes (provision + Argo CD sync)
- Data restore: Depends on backup size

## Anti-Patterns to Avoid

### Anti-Pattern 1: kubectl apply from CI
**What:** GitHub Actions runs `kubectl apply -f k8s/` directly

**Why Bad:**
- CI needs cluster credentials (security risk)
- No deployment audit trail
- No drift detection
- Harder rollbacks (need to re-run CI)
- Violates GitOps principles

**Instead:** Use Argo CD (pull-based deployment)

### Anti-Pattern 2: Manual kubectl Changes
**What:** Operator runs `kubectl edit deployment/firecrawl-api` to hotfix

**Why Bad:**
- Change not in Git (state drift)
- Next Argo CD sync reverts change
- No audit trail
- Can't reproduce in other environments

**Instead:** Change manifest in Git, let Argo CD sync

**Exception:** Debugging/testing only, never for production changes

### Anti-Pattern 3: Latest Tag in Production
**What:** `image: gcr.io/prometheus-461323/firecrawl-api:latest`

**Why Bad:**
- Not immutable (different pulls = different images)
- Can't rollback (latest changed)
- Cache issues (kubelet thinks image unchanged)
- Not auditable (which code is running?)

**Instead:** Use SHA-based tags: `firecrawl-api:abc123f`

### Anti-Pattern 4: Shared Namespace
**What:** Deploy Firecrawl to `default` namespace with other apps

**Why Bad:**
- RBAC hard to scope (all-or-nothing access)
- Resource quotas affect all apps
- Naming conflicts
- Blast radius of mistakes

**Instead:** Dedicated `firecrawl` namespace

### Anti-Pattern 5: No Resource Limits
**What:** Deployments without `resources.limits`

**Why Bad:**
- Single pod can consume all node resources
- OOM kills other pods
- Node instability
- Unpredictable performance

**Instead:** Set appropriate limits based on profiling

### Anti-Pattern 6: Secrets in Git
**What:** Commit `secret.yaml` with base64-encoded credentials

**Why Bad:**
- Base64 is encoding, not encryption (trivial to decode)
- Git history retains forever
- Exposed in Argo CD UI
- Violates security best practices

**Instead:**
- Create secrets manually via `kubectl create secret`
- OR use sealed-secrets/external-secrets (out of scope for v1)
- Never commit secrets to Git

### Anti-Pattern 7: No Health Checks
**What:** Deployments without readiness/liveness probes

**Why Bad:**
- Kubernetes doesn't know when pod is ready
- Traffic sent to crashed pods
- Failed deployments not detected
- Manual intervention required

**Instead:** Always define probes for Deployments

### Anti-Pattern 8: Ignoring Argo CD Sync Status
**What:** Push to Git and assume deployment succeeded

**Why Bad:**
- Sync might fail (invalid YAML, quota exceeded)
- Pods might crash (CrashLoopBackOff)
- Service might be degraded
- No notification of failure

**Instead:** Monitor Argo CD dashboard or set up notifications

## Summary: Component Interactions

### Single Deployment Flow

```
1. Developer: git push to main
   ↓
2. GitHub Actions: Builds images (5-10 min)
   ↓
3. GCR: Stores images
   ↓
4. GitHub Actions: Updates k8s/*.yaml with new tags
   ↓
5. GitHub Actions: git commit + push manifest changes
   ↓
6. Argo CD: Detects Git change (poll/webhook)
   ↓
7. Argo CD Repo Server: Clones repo, renders manifests
   ↓
8. Argo CD Application Controller: Compares Git vs cluster state
   ↓
9. Argo CD: Executes kubectl apply
   ↓
10. Kubernetes API: Accepts manifests
    ↓
11. Kubernetes Scheduler: Schedules new pods on nodes
    ↓
12. Kubelet: Pulls images from GCR
    ↓
13. Container Runtime: Starts containers
    ↓
14. Pods: Execute app code, health checks pass
    ↓
15. Service: Routes traffic to new pods
    ↓
16. Envoy Gateway: Routes external traffic to Service
    ↓
17. Argo CD: Monitors health, reports status
    ↓
18. Deployment Complete ✓
```

### Continuous Reconciliation

**While System Running:**
- **Argo CD polls Git every 3 minutes** (or webhook triggers immediately)
- **Compares desired state (Git) vs actual state (cluster)**
- **Auto-heals drift** if `selfHeal: true` enabled
- **Reports health status** based on pod conditions

**If Manual Change Made:**
```
kubectl scale deployment/firecrawl-api --replicas=5
  ↓ (within 3 minutes)
Argo CD detects replicas: 5 (cluster) vs replicas: 3 (Git)
  ↓
Argo CD scales back to 3 (self-heal)
  ↓
Cluster matches Git again
```

## Confidence Assessment

**Overall Confidence: MEDIUM**

This architecture is based on established GitOps patterns and standard practices for GitHub Actions + Argo CD + GKE integrations. The patterns described are well-documented in official Argo CD documentation and widely used in production environments.

**HIGH Confidence Areas:**
- Argo CD core architecture (official docs)
- Kubernetes resource types and dependencies
- GitOps pull-based deployment model
- Component boundary separation (CI vs CD)

**MEDIUM Confidence Areas:**
- GitHub Actions specific implementation details (varies by project)
- Envoy Gateway HTTPRoute integration (newer API, less documentation)
- GKE-specific networking nuances
- Optimal sync wave configuration for this specific workload

**LOW Confidence Areas:**
- Specific quirks of prometheus-461323 GKE cluster setup
- Existing Envoy Gateway configuration details
- Exact TLS certificate structure in candle-vllm secret

## Sources

**Architecture patterns based on:**
- Argo CD official documentation (argocd.readthedocs.io)
- Kubernetes official documentation (kubernetes.io)
- Google Cloud GKE documentation (cloud.google.com)
- GitOps principles from Weaveworks/CNCF
- Standard industry practices for CI/CD pipelines

**Note:** This document describes architectural patterns and best practices. Actual implementation will require verification against the specific client-cluster configuration and may need adjustments based on cluster-specific settings (RBAC, network policies, existing Envoy Gateway configuration, etc.).

## Recommended Build Order

Based on dependencies analysis above:

**Phase 1: Foundation Setup**
1. Namespace, RBAC, ConfigMaps (no dependencies)
2. Can be applied in parallel

**Phase 2: CI Pipeline**
1. GitHub Actions workflow (depends on GCR credentials)
2. Can test with dummy image push

**Phase 3: Storage Layer**
1. PVCs for Postgres and Redis (depends on namespace)
2. Verify immediate-binding storage class available

**Phase 4: Data Layer**
1. Postgres StatefulSet (depends on PVC)
2. Redis StatefulSet (depends on PVC)
3. Can deploy in parallel
4. **Critical:** Wait for both healthy before proceeding

**Phase 5: Support Services**
1. Playwright Deployment (depends on namespace)
2. Can start while data layer stabilizing

**Phase 6: Application Layer**
1. API Deployment (depends on Postgres, Redis, Playwright)
2. Worker Deployment (depends on Postgres, Redis, Playwright)
3. Ingestion UI Deployment (depends on API)
4. Use initContainers to wait for dependencies

**Phase 7: External Access**
1. HTTPRoutes (depends on Services existing)
2. Verify TLS certificate available
3. Test external connectivity

**Phase 8: Argo CD Integration**
1. Argo CD Application manifest
2. Configure auto-sync
3. Verify reconciliation loop working

**Total Estimated Time:**
- Phase 1-3: ~10 minutes (setup)
- Phase 4: ~5 minutes (StatefulSet rollout)
- Phase 5-6: ~10 minutes (application rollout)
- Phase 7-8: ~5 minutes (routing + Argo CD)
- **Total: ~30 minutes for initial deployment**

**Subsequent Deployments:** ~15 minutes (only phases 6-7, reusing existing storage/data layer)
