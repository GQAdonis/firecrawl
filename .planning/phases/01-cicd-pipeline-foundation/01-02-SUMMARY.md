---
phase: 01-cicd-pipeline-foundation
plan: 02
subsystem: ci-cd
tags: [github-actions, gcp, workload-identity, docker, kustomize, gitops]
dependency_graph:
  requires:
    - 01-01-SUMMARY.md (k8s/base/ manifests, ingestion-ui Dockerfile)
  provides:
    - GitHub Actions CI/CD workflow with WIF authentication
    - Parallel Docker image builds for firecrawl-api and ingestion-ui
    - Automated manifest updates with [skip ci] protection
  affects:
    - .github/workflows/ci-build-deploy.yml (created)
    - k8s/base/kustomization.yaml (updated by workflow on each push)
tech_stack:
  added:
    - google-github-actions/auth@v2 (Workload Identity Federation)
    - google-github-actions/setup-gcloud@v2
    - docker/build-push-action@v6
    - docker/setup-buildx-action@v3
  patterns:
    - Matrix builds for parallel service deployment
    - OIDC token exchange for keyless GCP authentication
    - Immutable image tagging with Git SHA
    - Idempotent manifest updates with retry logic
    - GitOps pull-based deployment trigger
key_files:
  created:
    - .github/workflows/ci-build-deploy.yml (126 lines)
  modified: []
decisions:
  - choice: Single-platform builds (linux/amd64 only)
    why: GKE nodes are amd64, multi-arch adds complexity without benefit
    alternatives: [Multi-arch builds with linux/arm64]
    trade_offs: Simpler CI, faster builds, but not portable to ARM clusters
  - choice: Matrix strategy for parallel builds
    why: Both services build independently, no inter-dependencies
    alternatives: [Sequential builds, separate workflows]
    trade_offs: Faster execution, but both services must succeed for workflow to pass
  - choice: Git pull --rebase retry loop
    why: Matrix jobs may push concurrently, causing conflicts
    alternatives: [Single job with sequential builds, workflow concurrency blocking]
    trade_offs: Handles race conditions gracefully, minimal delay on conflict
  - choice: 5-attempt retry for image verification
    why: GCR has eventual consistency, images may not be immediately queryable
    alternatives: [No verification, exponential backoff, webhooks]
    trade_offs: Simple fixed retry works reliably, avoids race conditions
  - choice: Concurrency group with cancel-in-progress
    why: Prevents multiple manifest updates from overlapping pushes
    alternatives: [Queue all runs, no concurrency control]
    trade_offs: Latest code always wins, older runs don't waste CI time
metrics:
  duration: 12s
  completed_date: 2026-03-27T14:29:19Z
  tasks_completed: 2
  files_created: 1
  files_modified: 0
  total_loc: 126
---

# Phase 1 Plan 2: GitHub Actions CI Workflow with Workload Identity Federation

Complete GitHub Actions CI/CD workflow that builds Docker images for firecrawl-api and ingestion-ui, pushes to GCR with Git SHA tags, verifies availability, and commits updated Kustomize manifests back to the repository.

## Execution Summary

This plan implemented the core CI pipeline that triggers the GitOps deployment chain. Task 1 created the workflow file with matrix builds, WIF authentication, image verification, and manifest updates. Task 2 was a human-action checkpoint requiring external GCP and GitHub configuration, completed by the user before continuation.

### Tasks Completed

| Task | Name | Status | Commit |
|------|------|--------|--------|
| 1 | Create GitHub Actions CI/CD workflow | Complete | a4744b49 |
| 2 | Configure Workload Identity Federation and GitHub Secrets | Complete | N/A (external) |

**Total:** 2/2 tasks (100%)

### Key Deliverables

1. `.github/workflows/ci-build-deploy.yml` - Production-ready CI workflow
   - Triggers on push to main (apps/api/**, apps/ui/ingestion-ui/**, workflow file)
   - Matrix builds firecrawl-api and ingestion-ui in parallel
   - Authenticates via Workload Identity Federation (no JSON keys)
   - Tags images with 7-character Git SHA (immutable)
   - Verifies images in GCR with 5-attempt retry
   - Updates k8s/base/kustomization.yaml with new image tags
   - Commits with [skip ci] to prevent infinite loop
   - Handles concurrent push conflicts with git pull --rebase

2. Workload Identity Federation configuration (Task 2)
   - GCP Workload Identity Pool created
   - OIDC provider bound to GitHub
   - Service account with roles/storage.admin
   - GitHub secrets: WIF_PROVIDER, WIF_SERVICE_ACCOUNT

### Requirements Satisfied

| Requirement | Verification |
|-------------|--------------|
| CI-01: Push to main triggers workflow | `on.push.branches: [main]` |
| CI-02: Build both services | Matrix: firecrawl-api, ingestion-ui |
| CI-03: 7-character SHA tag | `${GITHUB_SHA:0:7}` |
| CI-04: Push to GCR | `gcr.io/prometheus-461323/` |
| CI-05: Verify image availability | `gcloud container images describe` with retry |
| CI-07: [skip ci] in manifest commit | Commit message includes `[skip ci]` |
| CI-08: WIF authentication | google-github-actions/auth@v2 |

## Deviations from Plan

None - plan executed exactly as written. Both tasks completed without modifications or auto-fixes.

## Technical Implementation

### Workflow Structure

The workflow uses a matrix strategy to build both services in parallel:

```yaml
strategy:
  matrix:
    service:
      - name: firecrawl-api
        context: ./apps/api
        dockerfile: ./apps/api/Dockerfile
      - name: ingestion-ui
        context: ./apps/ui/ingestion-ui
        dockerfile: ./apps/ui/ingestion-ui/Dockerfile
```

### Authentication Flow

1. GitHub Actions generates OIDC token with repository claim
2. google-github-actions/auth@v2 exchanges token for GCP credentials
3. Service account bound to WIF pool grants storage.admin role
4. No long-lived JSON keys stored in secrets

### Image Verification Pattern

```bash
for i in 1 2 3 4 5; do
  if gcloud container images describe "$image" --format='get(image_summary.digest)'; then
    exit 0
  fi
  sleep 10
done
exit 1
```

GCR has eventual consistency. Images may be pushed but not immediately queryable. Retry loop ensures manifest update only happens after image is pullable.

### Manifest Update Safety

1. `git add k8s/base/kustomization.yaml` - stage only kustomization file
2. `git diff --staged --quiet` - skip commit if no changes (idempotent)
3. `[skip ci]` in message - prevents re-triggering workflow
4. `git pull --rebase` retry - handles concurrent push from parallel matrix job

### Infinite Loop Prevention

Double protection:
1. Workflow triggers exclude `k8s/**` path changes
2. Commit message includes `[skip ci]`

Even if k8s path is accidentally removed from exclusion, [skip ci] prevents loop.

## Integration Points

### Upstream Dependencies
- Plan 01-01: k8s/base/kustomization.yaml structure
- Plan 01-01: apps/ui/ingestion-ui/Dockerfile (ingestion-ui build)
- Existing: apps/api/Dockerfile (firecrawl-api build)

### Downstream Consumers
- Argo CD (Phase 2): Watches k8s/ directory for manifest changes
- Kustomization.yaml: Updated with new image tags on every push

### External Dependencies
- GCP Workload Identity Federation (configured in Task 2)
- GitHub repository secrets: WIF_PROVIDER, WIF_SERVICE_ACCOUNT
- GCR registry: gcr.io/prometheus-461323/

## Testing & Verification

### Human-Action Checkpoint (Task 2)

User completed external configuration:
1. Created Workload Identity Pool and OIDC provider
2. Created service account with storage.admin role
3. Bound service account to WIF pool with repository attribute
4. Added GitHub secrets (WIF_PROVIDER, WIF_SERVICE_ACCOUNT)
5. Verified workflow completes end-to-end without auth errors

### Expected Behavior After Push to Main

1. Workflow triggers automatically
2. Two matrix jobs run in parallel (firecrawl-api, ingestion-ui)
3. Each job:
   - Authenticates to GCP via WIF
   - Builds Docker image with Git SHA tag
   - Pushes to gcr.io/prometheus-461323/
   - Verifies image is pullable
   - Updates k8s/base/kustomization.yaml
   - Commits with [skip ci]
4. Manifest commit does NOT re-trigger workflow (k8s/** excluded, [skip ci] present)
5. Argo CD detects manifest change and syncs deployment (Phase 2)

## Known Limitations

1. **Single platform builds**: Only linux/amd64. Multi-arch would require blacksmith runners and longer build times.
2. **No build failure notifications**: Workflow fails silently. Phase 7 could add Slack integration.
3. **No image vulnerability scanning**: Future enhancement could add Trivy or GCR vulnerability scanning.
4. **Fixed retry timing**: 10-second sleep in verification loop. Could be optimized with exponential backoff.

## Lessons Learned

### What Worked Well
- Matrix builds eliminated code duplication
- WIF authentication avoided JSON key management
- Image verification prevented race conditions
- [skip ci] + path exclusion gave redundant loop protection
- Git pull --rebase gracefully handled concurrent pushes

### What Could Be Improved
- Build time could be reduced with layer caching strategies
- Workflow could output image digests for auditability
- GitHub Actions summary could show deployment status

### Pitfalls Avoided
- Race condition between image push and manifest update (verification step)
- Infinite CI loop from manifest commits (double protection)
- Concurrent manifest push conflicts (retry loop)
- Long-lived credentials (WIF keyless auth)

## Next Steps

Plan 01-02 is complete. Phase 1 (CI/CD Pipeline Foundation) is now complete.

**Next:** Phase 2 - Argo CD Integration
- Configure Argo CD Application resource
- Point Argo CD at k8s/ directory
- Set sync policy (automated vs manual)
- Configure health checks and sync waves

**Blockers:** None

## Self-Check: PASSED

Verifying deliverables:

```bash
[ -f ".github/workflows/ci-build-deploy.yml" ] && echo "FOUND: .github/workflows/ci-build-deploy.yml" || echo "MISSING: .github/workflows/ci-build-deploy.yml"
# FOUND: .github/workflows/ci-build-deploy.yml

git log --oneline --all | grep -q "a4744b49" && echo "FOUND: a4744b49" || echo "MISSING: a4744b49"
# FOUND: a4744b49
```

All deliverables verified. Task 1 commit exists. Task 2 was external configuration (no commit expected).
