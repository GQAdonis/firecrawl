# Phase 01 Plan 01: CI/CD Prerequisites Summary

**Created:** 2026-03-27T14:06:26Z
**Phase:** 01-cicd-pipeline-foundation
**Plan:** 01
**Status:** Complete

## One-Liner

Created production Dockerfile for ingestion-ui and k8s/base/ Kustomize manifests with image transformer configuration ready for CI workflow updates.

## Overview

This plan created the prerequisite files required for the CI/CD pipeline: a multi-stage production Dockerfile for the ingestion-ui React/Vite app, and the k8s/base/ directory structure with Kustomize configuration and stub deployment manifests. These files enable Plan 02's GitHub Actions workflow to build images and update manifests.

**Subsystem:** Infrastructure / Build Configuration
**Wave:** 1

## What Changed

### Files Created

- `apps/ui/ingestion-ui/Dockerfile` - Multi-stage Docker build (node:22-slim builder + nginx:alpine runtime) for Vite React app with SPA routing
- `apps/ui/ingestion-ui/.dockerignore` - Docker build exclusions (node_modules, dist, .git)
- `k8s/base/kustomization.yaml` - Kustomize configuration with image entries for firecrawl-api and ingestion-ui
- `k8s/base/api-deployment.yaml` - Stub Deployment manifest for firecrawl-api service
- `k8s/base/ui-deployment.yaml` - Stub Deployment manifest for ingestion-ui service

### Files Modified

None (all new files)

### Files Deleted

None

## Technical Details

### Ingestion-UI Dockerfile Architecture

**Build Stage (node:22-slim):**
- Uses pnpm with corepack for package management
- Installs dependencies with frozen lockfile and cache mount
- Builds Vite app using `tsc -b && vite build`
- Output: `dist/` directory with static assets

**Production Stage (nginx:alpine):**
- Copies built static files to `/usr/share/nginx/html`
- Custom nginx configuration for SPA routing (try_files fallback to index.html)
- Exposes port 80 for HTTP traffic
- Minimal runtime footprint (~25MB alpine base)

### Kustomize Configuration Structure

**kustomization.yaml images section:**
```yaml
images:
  - name: firecrawl-api
    newName: gcr.io/prometheus-461323/firecrawl-api
    newTag: "initial"
  - name: ingestion-ui
    newName: gcr.io/prometheus-461323/ingestion-ui
    newTag: "initial"
```

**Key design decisions:**
- Bare image names in deployment manifests (e.g., `image: firecrawl-api`) allow Kustomize image transformer to replace with full registry path and tag
- Image names in kustomization.yaml match container image references in deployments
- Initial tags set to "initial" as placeholders - CI workflow will update with Git SHA
- Resources list references both deployment manifests for atomic updates

### Integration Points

**For CI workflow (Plan 02):**
- Dockerfile build context: `./apps/ui/ingestion-ui`
- Kustomize edit command: `kustomize edit set image firecrawl-api=gcr.io/prometheus-461323/firecrawl-api:SHA`
- Manifest update location: `k8s/base/kustomization.yaml`

**For Argo CD (Phase 2):**
- Application path: `k8s/base/`
- Kustomize build command: `kustomize build k8s/base/`
- Namespace: `firecrawl` (specified in deployment manifests)

## Deviations from Plan

None - plan executed exactly as written. All acceptance criteria met without modifications.

## Decisions Made

| Decision | Rationale | Alternatives Considered |
|----------|-----------|-------------------------|
| Use ingestion-ui's local pnpm-lock.yaml | Directory has its own lock file, simpler build context | Copy workspace root lock file (more complex COPY paths) |
| RUN echo for nginx config | Inline configuration avoids separate config file | COPY external nginx.conf (requires additional file) |
| Initial tag value "initial" | Clear placeholder for first CI run | Empty string or "placeholder" (less semantic) |
| Bare image names in deployments | Enables Kustomize image transformer | Full registry paths (breaks transformer pattern) |
| Stub manifests without resource limits | Phase 6 will add production resource configuration | Include limits now (premature optimization) |

## Requirements Satisfied

- **CI-02:** Workflow can build Docker images for firecrawl-api and ingestion-ui (Dockerfile exists)
- **CI-06:** Workflow can update k8s/ manifests with new image tags (kustomization.yaml has images section)

## Dependencies

### Requires

- Node.js 22 runtime (for Dockerfile builder stage)
- pnpm package manager (via corepack)
- nginx:alpine base image
- Vite build tooling (from package.json)

### Provides

- `apps/ui/ingestion-ui/Dockerfile` - Production Docker build for React UI
- `k8s/base/kustomization.yaml` - Kustomize configuration with image transformer setup
- `k8s/base/*-deployment.yaml` - Stub Deployment manifests for API and UI

### Affects

- Plan 02 (GitHub Actions CI workflow) - depends on these files to build and update manifests
- Phase 2 (Argo CD configuration) - will reference k8s/base/ as application path
- Phase 6 (Application Layer) - will enhance deployment manifests with resource limits and probes

## Testing & Verification

### Automated Checks Performed

**Task 1 verification:**
```bash
test -f apps/ui/ingestion-ui/Dockerfile && \
grep -q "FROM nginx" apps/ui/ingestion-ui/Dockerfile && \
grep -q "FROM node:22-slim" apps/ui/ingestion-ui/Dockerfile && \
grep -q "pnpm" apps/ui/ingestion-ui/Dockerfile && \
grep -q "try_files" apps/ui/ingestion-ui/Dockerfile
# Result: PASS
```

**Task 2 verification:**
```bash
test -d k8s/base && \
test -f k8s/base/kustomization.yaml && \
test -f k8s/base/api-deployment.yaml && \
test -f k8s/base/ui-deployment.yaml && \
grep -q "images:" k8s/base/kustomization.yaml && \
grep -q "gcr.io/prometheus-461323/firecrawl-api" k8s/base/kustomization.yaml && \
grep -q "gcr.io/prometheus-461323/ingestion-ui" k8s/base/kustomization.yaml && \
grep -q "image: firecrawl-api" k8s/base/api-deployment.yaml && \
grep -q "image: ingestion-ui" k8s/base/ui-deployment.yaml
# Result: PASS
```

### Manual Verification

Visual inspection confirmed:
- k8s/base/ directory contains all three expected files
- Dockerfile contains multi-stage build with nginx production stage
- kustomization.yaml images section has entries for both services
- Deployment manifests use bare image names matching kustomization.yaml

### Integration Test Plan

**For Plan 02 (CI workflow implementation):**
1. Test Docker build: `docker build -t test-ui apps/ui/ingestion-ui/`
2. Test nginx serves correctly: `docker run -p 8080:80 test-ui` and access localhost:8080
3. Test kustomize build: `cd k8s/base && kustomize build .`
4. Test kustomize edit: `kustomize edit set image firecrawl-api=gcr.io/prometheus-461323/firecrawl-api:test123`
5. Verify image name replacement works correctly

## Metrics

**Execution:**
- Duration: 103 seconds (1m 43s)
- Tasks completed: 2/2 (100%)
- Files created: 5
- Files modified: 0
- Deviations: 0

**Code Changes:**
- Lines added: 100
- Lines removed: 0
- Commits: 2

**Testing:**
- Automated checks: 2/2 passed
- Manual verification: Complete
- Integration tests: Deferred to Plan 02

## Follow-Up Items

**For Plan 02 (GitHub Actions workflow):**
- Verify Dockerfile builds successfully in CI environment
- Confirm pnpm cache mount works with GitHub Actions cache
- Test nginx configuration serves app correctly after build
- Validate kustomize edit commands update tags correctly

**For Phase 6 (Production hardening):**
- Add resource limits to deployment manifests
- Add liveness/readiness probes
- Add environment variables for API configuration
- Add init containers if needed for DB migrations

**For Future Optimization:**
- Consider multi-arch builds if ARM64 nodes added to cluster
- Evaluate nginx caching headers for static assets
- Consider adding security context to deployment manifests
- Evaluate separate nginx.conf file vs inline for maintainability

## Commits

| Hash | Message | Files |
|------|---------|-------|
| 7a8b8867 | feat(01-cicd): add production Dockerfile for ingestion-ui | apps/ui/ingestion-ui/Dockerfile, apps/ui/ingestion-ui/.dockerignore |
| 1cac2911 | feat(01-cicd): add k8s/base manifests with Kustomize configuration | k8s/base/kustomization.yaml, k8s/base/api-deployment.yaml, k8s/base/ui-deployment.yaml |

## Self-Check

**Files created verification:**
```bash
[ -f "apps/ui/ingestion-ui/Dockerfile" ] # FOUND
[ -f "apps/ui/ingestion-ui/.dockerignore" ] # FOUND
[ -f "k8s/base/kustomization.yaml" ] # FOUND
[ -f "k8s/base/api-deployment.yaml" ] # FOUND
[ -f "k8s/base/ui-deployment.yaml" ] # FOUND
```

**Commits verification:**
```bash
git log --oneline --all | grep "7a8b8867" # FOUND
git log --oneline --all | grep "1cac2911" # FOUND
```

## Self-Check: PASSED

All created files exist at expected locations. Both commit hashes found in git history. Plan execution complete and verified.
