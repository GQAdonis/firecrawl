# Phase 1: CI/CD Pipeline Foundation - Research

**Researched:** 2026-03-27
**Domain:** GitHub Actions, Docker image builds, GCR authentication, Kustomize manifest updates
**Confidence:** MEDIUM

## Summary

Phase 1 establishes the CI component of the GitOps pipeline. GitHub Actions will build Docker images for firecrawl-api and ingestion-ui on every push to main, tag them with 7-character Git SHA for immutability, push to Google Container Registry (GCR), and commit updated Kustomize manifests back to the repository. The critical challenge is preventing infinite CI loops via `[skip ci]` commit messages and using Workload Identity Federation for secure GCP authentication without long-lived credentials.

The project already has a working Docker build workflow (`.github/workflows/deploy-image.yml`) that builds multi-arch images for firecrawl-api and pushes to GitHub Container Registry. This workflow can serve as a template, but needs modification for GCR destination, SHA-based tagging, and manifest updates. A new Dockerfile is required for ingestion-ui (React/Vite app at `apps/ui/ingestion-ui/`).

**Primary recommendation:** Build on existing `docker/build-push-action` patterns, use Google's official `auth` and `setup-gcloud` actions for Workload Identity Federation, verify image availability with `gcloud container images describe`, and use `kustomize edit set image` for atomic manifest updates.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CI-01 | GitHub Actions workflow triggers on push to main branch | Standard GitHub Actions trigger configuration (`on.push.branches`) |
| CI-02 | Workflow builds Docker images for firecrawl-api and ingestion-ui | `docker/build-push-action@v6` with multi-service matrix strategy |
| CI-03 | Images tagged with 7-character Git SHA (immutable tags) | `github.sha` context variable, substring extraction via `${GITHUB_SHA:0:7}` |
| CI-04 | Images pushed to Google Container Registry in prometheus-461323 project | GCR format: `gcr.io/prometheus-461323/firecrawl-api:SHA`, `gcr.io/prometheus-461323/ingestion-ui:SHA` |
| CI-05 | Workflow verifies image availability in GCR before manifest updates | `gcloud container images describe` with retry logic for registry propagation delay |
| CI-06 | Workflow updates k8s/ manifests with new image tags | `kustomize edit set image` command for atomic updates to kustomization.yaml |
| CI-07 | Workflow commits manifest changes with [skip ci] to prevent loops | Git operations with commit message containing `[skip ci]` or `[ci skip]` marker |
| CI-08 | Workflow uses Workload Identity Federation for GCP authentication | `google-github-actions/auth@v2` with Workload Identity Provider and Service Account |
</phase_requirements>

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| docker/build-push-action | v6 | Docker image build and push | Official Docker GitHub Action, supports BuildKit, multi-platform builds, layer caching |
| google-github-actions/auth | v2 | GCP authentication via Workload Identity Federation | Official Google action, eliminates service account keys, uses OIDC federation |
| google-github-actions/setup-gcloud | v2 | Install and configure gcloud CLI | Official Google action, required for GCR verification commands |
| actions/checkout | v4 | Repository checkout with write access | Standard GitHub action, fetch-depth: 0 for full history |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| docker/setup-buildx-action | v3 | Enable BuildKit and advanced features | Used before build-push-action for caching, multi-platform |
| docker/login-action | v3 | Authenticate to container registries | Not needed - auth action handles GCR token |
| kustomize | 5.x (CLI) | Update Kubernetes manifests | Installed in runner, used via shell commands |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Workload Identity Federation | Service Account JSON keys | Keys are security risk, require rotation, can leak in logs. WIF uses short-lived OIDC tokens. |
| kustomize edit | yq/sed for YAML manipulation | Kustomize is purpose-built for K8s, handles escaping/validation correctly |
| GCR (gcr.io) | Artifact Registry (pkg.dev) | AR is newer but requires different authentication setup. GCR still supported in 2026. |
| 7-char SHA | Full 40-char SHA or semantic version | 7-char standard for Docker, balances uniqueness with readability |

**Installation:**

```bash
# GitHub Actions runners come with Docker pre-installed
# Kustomize installation in workflow:
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
sudo mv kustomize /usr/local/bin/
```

**Version verification:**

As of my training (January 2025), these are the recommended versions. Package versions should be verified at implementation time:

- `docker/build-push-action@v6` - current as of late 2024
- `google-github-actions/auth@v2` - current WIF-enabled version
- `actions/checkout@v4` - current major version

Note: GitHub Actions use major version tags (v6, v4) that auto-update to latest minor/patch within that major version.

## Architecture Patterns

### Recommended Project Structure

```
.github/workflows/
├── ci-build-deploy.yml          # Main CI workflow
└── (existing workflows...)

k8s/
├── base/
│   ├── kustomization.yaml       # Base configuration with image refs
│   ├── api-deployment.yaml      # API Deployment manifest
│   ├── ui-deployment.yaml       # UI Deployment manifest
│   └── ...                      # Other K8s resources
└── overlays/                    # (Future: dev/staging/prod)
```

### Pattern 1: Multi-Service Docker Build with Matrix Strategy

**What:** Build multiple services in parallel with shared authentication and tag strategy

**When to use:** When multiple services need building with same configuration (registry, tagging, auth)

**Example:**

```yaml
# .github/workflows/ci-build-deploy.yml
name: CI Build and Deploy

on:
  push:
    branches:
      - main
    paths:
      - 'apps/api/**'
      - 'apps/ui/ingestion-ui/**'
      - '.github/workflows/ci-build-deploy.yml'

env:
  GCP_PROJECT_ID: prometheus-461323
  GCR_REGISTRY: gcr.io

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions:
      contents: write      # For pushing manifest updates
      id-token: write      # For Workload Identity Federation

    strategy:
      matrix:
        service:
          - name: firecrawl-api
            context: ./apps/api
            dockerfile: ./apps/api/Dockerfile
          - name: ingestion-ui
            context: ./apps/ui/ingestion-ui
            dockerfile: ./apps/ui/ingestion-ui/Dockerfile

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Full history for git operations
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract short SHA
        run: echo "SHORT_SHA=${GITHUB_SHA:0:7}" >> $GITHUB_ENV

      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.WIF_PROVIDER }}
          service_account: ${{ secrets.WIF_SERVICE_ACCOUNT }}

      - name: Set up Cloud SDK
        uses: google-github-actions/setup-gcloud@v2

      - name: Configure Docker for GCR
        run: gcloud auth configure-docker gcr.io

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build and push image
        uses: docker/build-push-action@v6
        with:
          context: ${{ matrix.service.context }}
          file: ${{ matrix.service.dockerfile }}
          push: true
          tags: ${{ env.GCR_REGISTRY }}/${{ env.GCP_PROJECT_ID }}/${{ matrix.service.name }}:${{ env.SHORT_SHA }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

### Pattern 2: Image Availability Verification with Retry

**What:** Verify image is pullable from GCR before committing manifest updates

**When to use:** Always - prevents race condition where Argo CD tries to pull image before registry indexing completes

**Example:**

```yaml
- name: Verify image in GCR
  run: |
    max_attempts=5
    attempt=1
    image="${GCR_REGISTRY}/${GCP_PROJECT_ID}/${{ matrix.service.name }}:${SHORT_SHA}"

    while [ $attempt -le $max_attempts ]; do
      echo "Verification attempt $attempt of $max_attempts"
      if gcloud container images describe "$image" --format='get(image_summary.digest)'; then
        echo "Image verified: $image"
        exit 0
      fi

      echo "Image not yet available, waiting 10 seconds..."
      sleep 10
      attempt=$((attempt + 1))
    done

    echo "Failed to verify image after $max_attempts attempts"
    exit 1
```

### Pattern 3: Atomic Kustomize Manifest Update

**What:** Use `kustomize edit set image` to update image references in kustomization.yaml atomically

**When to use:** Always for Kustomize manifest updates - safer than YAML manipulation with sed/yq

**Example:**

```yaml
- name: Install kustomize
  run: |
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    sudo mv kustomize /usr/local/bin/
    kustomize version

- name: Update kustomization with new image
  run: |
    cd k8s/base

    # Update image reference atomically
    kustomize edit set image \
      ${{ matrix.service.name }}=${GCR_REGISTRY}/${GCP_PROJECT_ID}/${{ matrix.service.name }}:${SHORT_SHA}

    # Show changes
    git diff kustomization.yaml
```

**Note:** This requires kustomization.yaml to have an `images` section with entries matching service names:

```yaml
# k8s/base/kustomization.yaml
images:
- name: firecrawl-api
  newName: gcr.io/prometheus-461323/firecrawl-api
  newTag: placeholder
- name: ingestion-ui
  newName: gcr.io/prometheus-461323/ingestion-ui
  newTag: placeholder
```

### Pattern 4: Loop-Safe Git Commit

**What:** Commit manifest changes with `[skip ci]` marker to prevent workflow re-triggering

**When to use:** Always when workflow commits back to repository

**Example:**

```yaml
- name: Commit and push manifest updates
  run: |
    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"

    # Stage only kustomization.yaml changes
    git add k8s/base/kustomization.yaml

    # Check if there are changes to commit
    if git diff --staged --quiet; then
      echo "No changes to commit"
      exit 0
    fi

    # Commit with [skip ci] to prevent loop
    git commit -m "ci: update ${{ matrix.service.name }} image to ${SHORT_SHA} [skip ci]"

    # Push with retry logic
    max_attempts=3
    attempt=1
    while [ $attempt -le $max_attempts ]; do
      if git push origin main; then
        echo "Successfully pushed changes"
        exit 0
      fi
      echo "Push failed, pulling and retrying..."
      git pull --rebase origin main
      attempt=$((attempt + 1))
    done

    echo "Failed to push after $max_attempts attempts"
    exit 1
```

### Anti-Patterns to Avoid

- **Building services sequentially instead of parallel:** Use matrix strategy to build both services simultaneously, reduces CI time significantly
- **Using mutable tags like `latest`:** Breaks GitOps auditability, can't determine what's actually deployed by looking at manifest
- **Committing without `[skip ci]`:** Creates infinite loop where commit triggers CI which commits which triggers CI
- **Pushing before verifying image availability:** Argo CD will fail to sync if image isn't pullable yet
- **Service account JSON keys in secrets:** Security risk, use Workload Identity Federation instead
- **Manipulating YAML with sed/awk:** Easy to break YAML syntax, use `kustomize edit` commands

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| GCP authentication | Custom OIDC token exchange logic | `google-github-actions/auth@v2` | Handles token lifecycle, refresh, project configuration, error cases |
| Docker build optimization | Custom layer caching, build scripts | `docker/build-push-action@v6` | BuildKit integration, GitHub Actions cache backend, multi-platform support |
| YAML manifest updates | sed/awk/yq for kustomization.yaml edits | `kustomize edit set image` | Validates YAML structure, handles escaping, atomic updates |
| Image verification | Polling Docker registry API | `gcloud container images describe` | Handles authentication, retries, proper error codes |
| Git conflict resolution | Manual merge logic | `git pull --rebase` with retry | Handles common conflict patterns automatically |

**Key insight:** GitHub Actions and Google Cloud have mature, well-tested actions for these workflows. Custom scripts are harder to maintain, miss edge cases (token expiration, concurrent pushes, network failures), and lack the GitHub Actions cache integration that significantly speeds up builds.

## Common Pitfalls

### Pitfall 1: Infinite CI Loop from Manifest Commits

**What goes wrong:** Workflow commits manifest updates, which triggers workflow again, creating infinite loop

**Why it happens:** GitHub Actions triggers on push to main by default, workflow commits are pushes to main

**How to avoid:**
1. Include `[skip ci]` or `[ci skip]` in commit message (GitHub honors this)
2. Alternative: Use workflow path filters to exclude k8s/ directory changes
3. Test by examining workflow runs - should see only 1 run per actual code change

**Warning signs:**
- Multiple workflow runs for single code change
- Workflow runs with only kustomization.yaml changes
- Empty commits with "update image" messages

**Example of safe commit:**
```bash
git commit -m "ci: update firecrawl-api image to 1a2b3c4 [skip ci]"
```

### Pitfall 2: Registry Propagation Delay

**What goes wrong:** Manifest is committed before image is pullable from GCR, Argo CD sync fails with ImagePullBackOff

**Why it happens:** Image push is asynchronous, GCR needs time to index and make image pullable (typically 5-30 seconds)

**How to avoid:**
1. Always verify image availability with `gcloud container images describe` before committing manifests
2. Implement retry logic with exponential backoff (5-10 second intervals, 5 attempts max)
3. Use `--format='get(image_summary.digest)'` to confirm full metadata is available

**Warning signs:**
- ImagePullBackOff in Argo CD immediately after sync
- "manifest unknown" errors in pod events
- Sporadic deployment failures that resolve on retry

### Pitfall 3: Concurrent Workflow Runs Conflict

**What goes wrong:** Two pushes to main happen close together, both workflows try to commit manifest updates, one fails with push rejection

**Why it happens:** Git requires linear history, second workflow's base commit is outdated after first workflow pushes

**How to avoid:**
1. Use `git pull --rebase` before push in retry loop
2. Limit concurrency with `concurrency` key in workflow (cancel in-progress runs)
3. Accept that some runs may fail - they'll succeed on next trigger

**Warning signs:**
- "Updates were rejected because the remote contains work" errors
- Workflow failures only on rapid successive pushes
- Success on workflow re-run without code changes

**Example concurrency configuration:**
```yaml
concurrency:
  group: deploy-${{ github.ref }}
  cancel-in-progress: true  # Cancel old runs when new push happens
```

### Pitfall 4: Workload Identity Federation Misconfiguration

**What goes wrong:** Workflow fails with "Permission denied" or "Invalid authentication credentials" when pushing to GCR

**Why it happens:** WIF requires precise configuration of provider, service account, attribute mapping, and IAM bindings

**How to avoid:**
1. Verify service account has `roles/storage.admin` for GCS buckets backing GCR
2. Confirm attribute mapping includes `attribute.repository` = `firecrawl/firecrawl` (or your repo)
3. Test authentication with `gcloud auth list` step before Docker operations
4. Use `google-github-actions/auth` action's built-in token source configuration

**Warning signs:**
- "Failed to get credentials" errors
- "Access denied" when running gcloud commands
- Successful authentication but failed Docker push

**Debug step:**
```yaml
- name: Verify authentication
  run: |
    gcloud auth list
    gcloud config get-value project
    gcloud container images list --repository=gcr.io/${{ env.GCP_PROJECT_ID }}
```

### Pitfall 5: Missing Dockerfile for Ingestion-UI

**What goes wrong:** Workflow fails when trying to build ingestion-ui because no Dockerfile exists in `apps/ui/ingestion-ui/`

**Why it happens:** Existing codebase has Dockerfile for API but not for UI (React/Vite app)

**How to avoid:**
1. Create production-ready Dockerfile for Vite app BEFORE workflow implementation
2. Use multi-stage build: Node build stage + nginx serve stage
3. Test Docker build locally before adding to workflow
4. Validate that built image actually serves the UI correctly

**Warning signs:**
- "unable to prepare context: unable to evaluate symlinks in Dockerfile path" error
- Workflow fails at build step for ingestion-ui service
- CI passes but no ingestion-ui image appears in GCR

**Note:** This is a known gap that must be addressed in Phase 1 planning.

### Pitfall 6: Incorrect Kustomization.yaml Structure

**What goes wrong:** `kustomize edit set image` fails with "no matches for Id" error

**Why it happens:** kustomization.yaml must have `images` section with placeholder entries matching service names

**How to avoid:**
1. Initialize kustomization.yaml with image entries before workflow runs
2. Use service name (e.g., `firecrawl-api`) as image name in kustomization
3. Set placeholder values for newName and newTag - they'll be replaced by `kustomize edit`

**Warning signs:**
- "no matches for Id firecrawl-api" errors
- Kustomize command succeeds but kustomization.yaml unchanged
- Manual `kustomize build` works but automated update fails

**Example initialization:**
```yaml
# k8s/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- api-deployment.yaml
- ui-deployment.yaml

images:
- name: firecrawl-api
  newName: gcr.io/prometheus-461323/firecrawl-api
  newTag: "initial"
- name: ingestion-ui
  newName: gcr.io/prometheus-461323/ingestion-ui
  newTag: "initial"
```

## Code Examples

Verified patterns based on GitHub Actions and Google Cloud documentation:

### Complete Workload Identity Federation Authentication

```yaml
# Prerequisite: Create WIF provider and service account in GCP
# gcloud iam workload-identity-pools create github-actions-pool \
#   --location=global \
#   --display-name="GitHub Actions Pool"
#
# gcloud iam workload-identity-pools providers create-oidc github-provider \
#   --location=global \
#   --workload-identity-pool=github-actions-pool \
#   --issuer-uri=https://token.actions.githubusercontent.com \
#   --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository"

- name: Authenticate to Google Cloud
  uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: 'projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions-pool/providers/github-provider'
    service_account: 'github-actions@prometheus-461323.iam.gserviceaccount.com'
    token_format: 'access_token'
    access_token_lifetime: '3600s'

- name: Set up Cloud SDK
  uses: google-github-actions/setup-gcloud@v2

- name: Configure Docker authentication
  run: gcloud auth configure-docker gcr.io

# Service account must have these IAM roles:
# - roles/storage.admin (for GCS buckets backing GCR)
# - roles/iam.workloadIdentityUser (for WIF binding)
```

### Multi-Arch Docker Build (Optional Enhancement)

```yaml
# If multi-architecture support needed (existing workflow has this for amd64/arm64)
- name: Set up QEMU
  uses: docker/setup-qemu-action@v3

- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v3

- name: Build and push multi-arch image
  uses: docker/build-push-action@v6
  with:
    context: ./apps/api
    platforms: linux/amd64,linux/arm64
    push: true
    tags: gcr.io/prometheus-461323/firecrawl-api:${{ env.SHORT_SHA }}
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

Note: Multi-arch build is an enhancement. Start with single platform (linux/amd64) for simplicity unless GKE cluster has ARM nodes.

### Ingestion-UI Dockerfile Template

```dockerfile
# apps/ui/ingestion-ui/Dockerfile
# Production-ready Vite React app

# Build stage
FROM node:22-slim AS builder

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable

WORKDIR /app

# Copy workspace configuration
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY apps/ui/ingestion-ui/package.json ./apps/ui/ingestion-ui/

# Install dependencies
RUN --mount=type=cache,id=pnpm,target=/pnpm/store \
    pnpm install --frozen-lockfile

# Copy source and build
COPY apps/ui/ingestion-ui ./apps/ui/ingestion-ui
RUN cd apps/ui/ingestion-ui && pnpm run build

# Production stage - nginx to serve static files
FROM nginx:alpine

# Copy built assets
COPY --from=builder /app/apps/ui/ingestion-ui/dist /usr/share/nginx/html

# Custom nginx config for SPA routing
RUN echo 'server { \
    listen 80; \
    root /usr/share/nginx/html; \
    index index.html; \
    location / { \
        try_files $uri $uri/ /index.html; \
    } \
}' > /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

### Full Workflow Integration

```yaml
name: CI Build and Deploy

on:
  push:
    branches:
      - main
    paths:
      - 'apps/api/**'
      - 'apps/ui/ingestion-ui/**'
      - 'k8s/**'
      - '.github/workflows/ci-build-deploy.yml'
  workflow_dispatch:  # Allow manual trigger

concurrency:
  group: deploy-${{ github.ref }}
  cancel-in-progress: true

env:
  GCP_PROJECT_ID: prometheus-461323
  GCR_REGISTRY: gcr.io

jobs:
  build-push-update:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      id-token: write

    strategy:
      matrix:
        service:
          - name: firecrawl-api
            context: ./apps/api
            dockerfile: ./apps/api/Dockerfile
          - name: ingestion-ui
            context: ./apps/ui/ingestion-ui
            dockerfile: ./apps/ui/ingestion-ui/Dockerfile

    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Extract short SHA
        run: echo "SHORT_SHA=${GITHUB_SHA:0:7}" >> $GITHUB_ENV

      - name: Authenticate to GCP
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.WIF_PROVIDER }}
          service_account: ${{ secrets.WIF_SERVICE_ACCOUNT }}

      - name: Setup gcloud
        uses: google-github-actions/setup-gcloud@v2

      - name: Configure Docker
        run: gcloud auth configure-docker gcr.io

      - name: Setup Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: ${{ matrix.service.context }}
          file: ${{ matrix.service.dockerfile }}
          push: true
          tags: ${{ env.GCR_REGISTRY }}/${{ env.GCP_PROJECT_ID }}/${{ matrix.service.name }}:${{ env.SHORT_SHA }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Verify image
        run: |
          image="${GCR_REGISTRY}/${GCP_PROJECT_ID}/${{ matrix.service.name }}:${SHORT_SHA}"
          for i in {1..5}; do
            if gcloud container images describe "$image" --format='get(image_summary.digest)'; then
              echo "Image verified"
              exit 0
            fi
            echo "Waiting for image availability (attempt $i/5)..."
            sleep 10
          done
          echo "Image verification failed"
          exit 1

      - name: Install kustomize
        run: |
          curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
          sudo mv kustomize /usr/local/bin/

      - name: Update kustomization
        run: |
          cd k8s/base
          kustomize edit set image \
            ${{ matrix.service.name }}=${GCR_REGISTRY}/${GCP_PROJECT_ID}/${{ matrix.service.name }}:${SHORT_SHA}
          git diff kustomization.yaml

      - name: Commit and push
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add k8s/base/kustomization.yaml

          if git diff --staged --quiet; then
            echo "No changes"
            exit 0
          fi

          git commit -m "ci: update ${{ matrix.service.name }} to ${SHORT_SHA} [skip ci]"

          for i in {1..3}; do
            if git push origin main; then
              echo "Pushed successfully"
              exit 0
            fi
            git pull --rebase origin main
          done

          echo "Push failed after retries"
          exit 1
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Service account JSON keys | Workload Identity Federation | 2021-2022 | Eliminates long-lived credentials, improves security posture |
| Docker Buildkit disabled | BuildKit enabled by default | Docker 23+ (2023) | Faster builds, better caching, parallel stage execution |
| GCR (gcr.io) primary | Artifact Registry (pkg.dev) preferred | 2023-2024 | AR offers vulnerability scanning, regional redundancy, but GCR still fully supported |
| sed/yq for YAML edits | `kustomize edit` commands | Kustomize 3+ (2019) | Type-safe manifest updates, prevents YAML syntax errors |
| Single-platform images | Multi-platform manifests | Docker 2020+ | Support for ARM64 nodes, Apple Silicon development |

**Deprecated/outdated:**
- `docker/build-push-action@v4` and earlier: Use v6 for latest BuildKit features
- `google-github-actions/setup-gcloud@v1`: Use v2 for improved WIF support
- `actions/checkout@v3` and earlier: Use v4 for better performance and Git LFS support
- Artifact Registry v1beta1 API: Use v1 stable API for production

**Current as of 2026:**
- GCR is still fully supported and simpler than Artifact Registry for basic use cases
- GitHub Actions recommends major version pinning (v6, v4) rather than specific commits
- Kustomize standalone CLI (5.x) is recommended over kubectl's built-in kustomize (often outdated)

## Open Questions

1. **Workload Identity Federation provider already configured?**
   - What we know: GCP project prometheus-461323 exists, WIF requires provider setup
   - What's unclear: Whether WIF provider and service account already exist, or need creation
   - Recommendation: Check with `gcloud iam workload-identity-pools list` before planning, include setup tasks if needed. Document provider ID and service account email as secrets.

2. **Multi-arch build requirement?**
   - What we know: Existing workflow builds amd64 and arm64 images, GKE typically uses amd64
   - What's unclear: Whether client-cluster has ARM nodes requiring arm64 images
   - Recommendation: Start with single platform (linux/amd64) for simplicity. Add multi-arch as enhancement if needed. Low risk - can add platforms later without breaking existing deployments.

3. **Kustomize overlay structure needed now?**
   - What we know: PROJECT.md specifies single production environment, no dev/staging
   - What's unclear: Whether to structure k8s/ with base/overlays from start or add later
   - Recommendation: Use flat k8s/base/ structure initially, simplifies workflow. Overlays are easy to add in future phases without breaking GitOps flow.

4. **GitHub Actions runner constraints?**
   - What we know: Existing workflow uses Blacksmith runners (custom infrastructure)
   - What's unclear: Whether CI/CD workflow should use Blacksmith runners or standard GitHub-hosted
   - Recommendation: Use standard ubuntu-latest runners for CI workflow unless Blacksmith is required. Standard runners have GCP tooling pre-installed, reducing setup time.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Bash + GitHub Actions (workflow validation) |
| Config file | .github/workflows/ci-build-deploy.yml |
| Quick run command | N/A (CI only) |
| Full suite command | `act push -j build-push-update` (local testing with nektos/act) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CI-01 | Workflow triggers on main push | integration | Push test commit, verify workflow run via `gh run list` | ❌ Wave 0 |
| CI-02 | Builds firecrawl-api and ingestion-ui images | integration | `act push -j build-push-update` (requires act tool) | ❌ Wave 0 |
| CI-03 | Images tagged with 7-char SHA | integration | Inspect image tags via `gcloud container images list-tags` | ❌ Wave 0 |
| CI-04 | Images pushed to GCR prometheus-461323 | integration | `gcloud container images list --repository=gcr.io/prometheus-461323` | ❌ Wave 0 |
| CI-05 | Verifies image availability before manifest update | integration | Check workflow logs for verification step success | ❌ Wave 0 |
| CI-06 | Updates k8s/ manifests with new tags | integration | Inspect git diff after workflow run | ❌ Wave 0 |
| CI-07 | Commits with [skip ci] marker | integration | Check commit message via `git log`, verify no re-trigger | ❌ Wave 0 |
| CI-08 | Uses Workload Identity Federation | integration | Check workflow logs for WIF authentication step | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** N/A (workflow is the deliverable, not code with tests)
- **Per wave merge:** Manual validation - trigger workflow, verify all 8 requirements pass
- **Phase gate:** Full integration test:
  1. Push test change to apps/api/
  2. Verify workflow completes successfully
  3. Verify both images appear in GCR with correct SHA tags
  4. Verify kustomization.yaml updated and committed
  5. Verify only 1 workflow run (no loop)

### Wave 0 Gaps

- [ ] Workload Identity Federation provider and service account setup in GCP
- [ ] Repository secrets configuration: WIF_PROVIDER, WIF_SERVICE_ACCOUNT
- [ ] k8s/base/ directory structure with initial kustomization.yaml
- [ ] apps/ui/ingestion-ui/Dockerfile creation (doesn't exist yet)
- [ ] Local testing capability via nektos/act (optional but recommended)

**Note:** CI/CD workflows are inherently integration tests. Unit testing is not applicable. Validation happens by executing the workflow and verifying outcomes (images in GCR, manifests updated, no loops).

## Sources

### Primary (HIGH confidence)

- Existing workflow `.github/workflows/deploy-image.yml` - demonstrates working Docker build pattern with multi-platform support
- GitHub Actions documentation for `docker/build-push-action`, `google-github-actions/auth`, and core actions (actions/checkout) - standard reference
- Kustomize CLI documentation for `edit set image` command - official reference for manifest updates

### Secondary (MEDIUM confidence)

- Google Cloud documentation for Workload Identity Federation setup - based on training knowledge from 2024-2025
- GCR authentication patterns via `gcloud auth configure-docker` - standard GCP practice
- GitHub Actions concurrency and loop prevention patterns - established best practices

### Tertiary (LOW confidence)

- Action version numbers (v6, v4, v2) - based on training data from January 2025, should verify current versions at implementation time
- GCR vs Artifact Registry state in 2026 - GCR was fully supported through 2024, but AR is newer standard. Both should work, GCR is simpler.
- Multi-arch build necessity - depends on cluster node architecture, should validate

## Metadata

**Confidence breakdown:**
- Standard stack: MEDIUM - versions based on training knowledge, should verify at implementation time
- Architecture: HIGH - patterns are standard GitHub Actions best practices, existing workflow provides template
- Pitfalls: HIGH - based on common CI/CD issues and specific GitHub Actions/GCR integration gotchas
- Validation: HIGH - integration testing approach is correct for CI/CD workflows

**Research date:** 2026-03-27
**Valid until:** 60 days (standard GitHub Actions patterns), 30 days (specific action versions)

**Known gaps requiring validation during planning:**
1. Workload Identity Federation provider existence and configuration
2. Current versions of GitHub Actions (v6, v4, v2 references)
3. Cluster architecture (amd64 vs arm64 requirements)
4. Blacksmith runner requirements vs standard GitHub-hosted runners
