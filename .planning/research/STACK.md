# Technology Stack - Kubernetes GitOps Deployment

**Project:** Firecrawl GKE Deployment Automation
**Researched:** 2026-03-27
**Confidence:** MEDIUM (based on training data through January 2025, unable to verify current versions)

## Executive Summary

This stack focuses on the deployment automation layer for Firecrawl on GKE. The application stack (Node.js/TypeScript, BullMQ, Playwright) already exists. This research covers the GitOps tooling needed to deploy and manage the application on Kubernetes.

**Key principle:** Use native Kubernetes tooling and Google-provided GitHub Actions wherever possible to minimize external dependencies and maintenance burden.

## Recommended Stack

### CI/CD Pipeline

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| GitHub Actions | N/A (SaaS) | CI orchestration | Native GitHub integration, no separate CI server to manage |
| Docker Buildx | v0.12+ | Multi-platform image builds | Standard for building optimized container images with layer caching |
| google-github-actions/auth | v2+ | GCP authentication | Official Google action for Workload Identity Federation (keyless auth) |
| google-github-actions/setup-gcloud | v2+ | gcloud CLI setup | Official Google action for CLI tooling |

**Rationale:** GitHub Actions provides the CI layer (build and push images) without requiring a separate CI server. Google's official actions handle authentication securely via Workload Identity Federation instead of long-lived service account keys.

**Confidence:** HIGH for GitHub Actions and Docker Buildx (industry standard), MEDIUM for specific Google action versions (unable to verify latest)

### GitOps & Deployment

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Argo CD | v2.10+ | GitOps continuous deployment | Already installed in cluster, declarative sync from git to cluster |
| Kustomize | v5.3+ (built into kubectl) | Manifest templating | Native Kubernetes tooling, no Helm chart maintenance, works seamlessly with Argo CD |
| kubectl | v1.29+ | Kubernetes CLI | Standard K8s management tool, matches GKE cluster version |

**Rationale:** Argo CD is already installed and is the de facto standard for Kubernetes GitOps. Kustomize is simpler than Helm for this use case (no need for community charts, full control over manifests) and integrates natively with kubectl and Argo CD.

**Confidence:** HIGH for Argo CD as the GitOps tool, MEDIUM for specific versions (unable to verify current releases)

### Container Registry

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Google Container Registry (GCR) | N/A (managed) | Container image storage | Native GCP integration, already using prometheus-461323 project |
| Artifact Registry | N/A (managed) | Future-proof alternative | GCR successor, consider migrating for improved features and regional replication |

**Rationale:** GCR is the path of least resistance for GCP projects. Artifact Registry is Google's recommended upgrade path with better performance and features, but GCR is simpler for initial setup.

**Recommendation:** Start with GCR (`gcr.io/prometheus-461323`), migrate to Artifact Registry when regional replication or vulnerability scanning becomes important.

**Confidence:** HIGH (Google's official offerings)

### Kubernetes Resources

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Envoy Gateway | Already installed | Ingress/routing | Kubernetes Gateway API implementation, already present in cluster |
| Gateway API (HTTPRoute) | v1 | Traffic routing | Modern successor to Ingress, better routing capabilities |
| Kubernetes Secrets | v1 | Configuration storage | Native secret management, sufficient for initial deployment |
| StatefulSets | v1 | Postgres/Redis | Stable network identities and persistent storage for stateful services |
| PersistentVolumeClaims | v1 | Data persistence | Storage abstraction with immediate-binding for postgres |

**Rationale:** Use what's already installed (Envoy Gateway) and native Kubernetes primitives. Gateway API HTTPRoutes are more powerful than traditional Ingress resources and match the project requirements.

**Confidence:** HIGH (Kubernetes stable APIs and existing cluster infrastructure)

### Image Tagging Strategy

| Strategy | Format | When to Use | Why |
|----------|--------|-------------|-----|
| Git SHA (short) | `api:abc1234` | Every build | Immutable, traceable to exact code version |
| Git SHA + timestamp | `api:abc1234-20260327-1430` | Optional enhancement | Adds human-readable ordering |
| Semantic version | `api:v1.2.3` | Releases only | Clean rollback targets, not for continuous deployment |

**Recommendation:** Use short git SHA (7 characters) as primary tag for all builds. This provides immutability and traceability without requiring version bumps in every commit.

**Workflow:**
1. GitHub Actions builds on main branch push
2. Tag image with `${GITHUB_SHA:0:7}`
3. Update kustomization.yaml with new tag
4. Commit and push manifest change
5. Argo CD detects change and syncs

**Confidence:** HIGH (established GitOps pattern)

### Supporting Tools

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| kustomize CLI | v5.3+ | Local manifest validation | Before committing manifest changes |
| kubeval or kubeconform | Latest | Manifest schema validation | In GitHub Actions pre-commit checks |
| trivy | v0.50+ | Container vulnerability scanning | Optional in GitHub Actions, scan built images |
| gke-gcloud-auth-plugin | Latest | GKE authentication | Local kubectl access to cluster |

**Confidence:** MEDIUM (tool names are standard, versions may be outdated)

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| GitOps tool | Argo CD | Flux CD | Argo CD already installed, no reason to add second tool |
| Manifest tool | Kustomize | Helm | No need for templating complexity, not using community charts |
| CI platform | GitHub Actions | Cloud Build | GitHub-native workflow simpler, no GCP billing for CI |
| Registry | GCR | Docker Hub | Native GCP integration, private images without subscription |
| Secret mgmt | K8s Secrets | Sealed Secrets / Vault | Out of scope per PROJECT.md, native secrets sufficient initially |
| Image tag | Git SHA | latest / main | Immutable tags prevent accidental rollbacks, enable auditability |

## Installation & Configuration

### GitHub Actions Setup

```yaml
# .github/workflows/deploy.yml (minimal example)
name: Deploy to GKE

on:
  push:
    branches: [main]

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      id-token: write

    steps:
      - uses: actions/checkout@v4

      - uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.WIF_PROVIDER }}
          service_account: ${{ secrets.WIF_SERVICE_ACCOUNT }}

      - uses: google-github-actions/setup-gcloud@v2

      - name: Configure Docker for GCR
        run: gcloud auth configure-docker gcr.io

      - name: Build and push images
        run: |
          docker buildx build --push \
            -t gcr.io/prometheus-461323/firecrawl-api:${GITHUB_SHA:0:7} \
            -f apps/api/Dockerfile .

      - name: Update manifests
        run: |
          cd k8s
          kustomize edit set image \
            gcr.io/prometheus-461323/firecrawl-api:${GITHUB_SHA:0:7}

      - name: Commit manifest changes
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add k8s/
          git commit -m "Deploy ${GITHUB_SHA:0:7}"
          git push
```

### Kustomize Directory Structure

```
k8s/
├── base/
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── api-deployment.yaml
│   ├── worker-deployment.yaml
│   ├── postgres-statefulset.yaml
│   ├── redis-statefulset.yaml
│   ├── playwright-deployment.yaml
│   ├── services.yaml
│   └── httproutes.yaml
└── kustomization.yaml  # Root kustomization
```

**Rationale:** Flat structure (no overlays) since there's only one environment (production). Base directory provides organization without overlay complexity.

### Argo CD Application Configuration

```yaml
# argocd-application.yaml (apply once to Argo CD)
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
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**Key settings:**
- `automated.prune: true` - Remove resources deleted from git
- `automated.selfHeal: true` - Revert manual kubectl changes
- `CreateNamespace=true` - Create firecrawl namespace automatically

## Deployment Workflow

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐     ┌──────────────┐
│  Developer  │────▶│    GitHub    │────▶│   GitHub    │────▶│   Argo CD    │
│   git push  │     │  main branch │     │   Actions   │     │  Auto-sync   │
└─────────────┘     └──────────────┘     └─────────────┘     └──────────────┘
                                                │                      │
                                                ▼                      ▼
                                         ┌─────────────┐        ┌──────────┐
                                         │  Build &    │        │   GKE    │
                                         │  Push Image │        │  Cluster │
                                         └─────────────┘        └──────────┘
                                                │
                                                ▼
                                         ┌─────────────┐
                                         │   Update    │
                                         │  Manifests  │
                                         │  (git SHA)  │
                                         └─────────────┘
                                                │
                                                ▼
                                         ┌─────────────┐
                                         │ Commit back │
                                         │  to main    │
                                         └─────────────┘
```

**Flow:**
1. Developer pushes code to main
2. GitHub Actions builds container image
3. Image tagged with git SHA and pushed to GCR
4. GitHub Actions updates k8s/kustomization.yaml with new image tag
5. GitHub Actions commits manifest change back to main
6. Argo CD detects git change and syncs to cluster
7. New pods roll out with updated image

## Anti-Patterns to Avoid

### Don't: Use 'latest' or mutable tags

```yaml
# BAD
image: gcr.io/prometheus-461323/firecrawl-api:latest
```

**Why:** Mutable tags break GitOps auditability. Can't rollback to previous "latest". Creates drift between git and cluster.

**Instead:** Immutable tags based on git SHA.

### Don't: Apply manifests directly in GitHub Actions

```yaml
# BAD - bypasses GitOps
- name: Deploy
  run: kubectl apply -f k8s/
```

**Why:** Breaks GitOps single source of truth. Argo CD doesn't know about changes. Can't revert via git.

**Instead:** Commit manifest changes, let Argo CD sync.

### Don't: Store secrets in git (even encrypted)

**Why:** Project explicitly excludes external secret management tools. Even Sealed Secrets or SOPS adds complexity.

**Instead:** Manually create Kubernetes secrets once, reference them in manifests. Document secret creation in ops runbook.

### Don't: Use Helm for this project

**Why:** Adds unnecessary templating complexity when full control over manifests is desired. Helm's value system is overkill for single-environment deployment.

**Instead:** Kustomize with patches for environment-specific overrides (if multi-environment is added later).

### Don't: Build images inside Kubernetes

**Why:** GitHub Actions can build faster with layer caching. Separates CI concerns from cluster.

**Instead:** Build in GitHub Actions, push to registry, deploy to cluster.

## Migration Path (Future Considerations)

| Current | Future Enhancement | When |
|---------|-------------------|------|
| GCR | Artifact Registry | Need regional replication or vuln scanning |
| K8s Secrets | External Secrets Operator + GCP Secret Manager | Need secret rotation or centralized mgmt |
| Kustomize | Helm | Need to publish charts for others to deploy |
| Fixed replicas | Horizontal Pod Autoscaler | Need dynamic scaling based on load |
| Single environment | Kustomize overlays (dev/staging/prod) | Need multiple environments |
| Immediate deployment | Progressive delivery (Argo Rollouts) | Need canary or blue-green deployments |

## Confidence Assessment

| Area | Level | Reasoning |
|------|-------|-----------|
| GitHub Actions | HIGH | Industry standard, well-documented, stable |
| Argo CD | HIGH | Already installed, established GitOps leader |
| Kustomize | HIGH | Native K8s tool, simpler than Helm for use case |
| Google Actions | MEDIUM | Could not verify latest versions (v2 likely current) |
| Specific versions | MEDIUM | Training data through Jan 2025, versions may have advanced |
| Workflow pattern | HIGH | Established GitOps pattern, widely used |

## Sources

**Note:** Unable to access external sources due to permission constraints. This stack is based on:
- Training data through January 2025
- Kubernetes documentation patterns
- Google Cloud best practices
- Argo CD documentation patterns
- Established GitOps workflows in the industry

**Recommendation:** Verify specific version numbers before implementation:
- Argo CD: Check https://github.com/argoproj/argo-cd/releases
- GitHub Actions: Check https://github.com/google-github-actions/auth and google-github-actions/setup-gcloud
- Kustomize: Check https://github.com/kubernetes-sigs/kustomize/releases

## Key Takeaways

1. **Use what's already there:** Argo CD and Envoy Gateway are installed, build around them
2. **Keep it simple:** Kustomize over Helm, native secrets over external tools
3. **Immutable tags:** Git SHA-based tags for auditability and rollback
4. **Separation of concerns:** GitHub Actions builds, Argo CD deploys
5. **GitOps principle:** Git is the single source of truth, never kubectl apply from CI
