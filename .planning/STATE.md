---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: planning
last_updated: "2026-03-27T20:20:42Z"
progress:
  total_phases: 7
  completed_phases: 4
  total_plans: 7
  completed_plans: 7
  percent: 100
last_completed_plan: "04-01"
---

# Project State: Firecrawl GKE Deployment Automation

**Last Updated:** 2026-03-27
**Current Status:** Roadmap created, planning not started

## Project Reference

**Core Value:**
Deployments are automated, auditable, and easy to rollback. Every deployment is a git commit that can be reverted if needed.

**Current Focus:**
Roadmap created with 7 sequential phases. Ready to begin planning Phase 1 (CI/CD Pipeline Foundation).

**Key Context:**
- GitOps pattern with GitHub Actions (CI) and Argo CD (CD)
- Pull-based deployment model - CI never touches cluster directly
- Immutable image tags (Git SHA) for auditability
- All services in dedicated firecrawl namespace
- Existing infrastructure: GKE client-cluster, Envoy Gateway, Argo CD already installed

## Current Position

**Phase:** 04-storage-layer
**Plan:** 1 of 1 complete
**Status:** Phase complete
**Progress:** [██████████] 100%

## Performance Metrics

**Phases Completed:** 4/7 (57%)
**Plans Completed:** 7 (01-01, 01-02, 02-01, 03-01, 03-02, 04-01)
**Tests Passed:** 0
**Active Blockers:** 0

## Accumulated Context

### Decisions Made

| Decision | Date | Rationale | Impact |
|----------|------|-----------|--------|
| GitOps pattern with Argo CD | 2026-03-27 | Separates CI from CD, provides auditability and easy rollbacks | Architecture: Pull-based deployment model |
| In-cluster postgres/redis | 2026-03-27 | Simpler setup than managed services, sufficient for initial deployment | Infrastructure: StatefulSets with PVCs |
| Manifests in same repo | 2026-03-27 | Simpler workflow, no separate repo permissions | Repository: k8s/ directory in firecrawl monorepo |
| Envoy Gateway HTTPRoutes | 2026-03-27 | Leverage existing installation, modern K8s native routing | External Access: HTTPRoute resources instead of Ingress |
| firecrawl namespace | 2026-03-27 | Isolates workloads, clean separation from other cluster services | Deployment: All resources in dedicated namespace |
| Immediate-binding storage | 2026-03-27 | Ensures postgres PV binds immediately, prevents startup issues | Storage: PVC binding mode configuration |
| 7 sequential phases | 2026-03-27 | Strict dependency chain requires sequential execution | Roadmap: No parallelization possible |
| Phase 01 P01 | 103 | 2 tasks | 5 files |
- [Phase 01]: Use ingestion-ui local pnpm-lock.yaml for simpler build context instead of workspace root lock file
- [Phase 01]: Bare image names in deployment manifests to enable Kustomize image transformer
| Phase 01 P02 | 12 | 2 tasks | 1 files |
- [Phase 01]: Single-platform builds (linux/amd64) for GKE amd64 nodes
- [Phase 01]: Matrix strategy for parallel firecrawl-api and ingestion-ui builds
- [Phase 01]: Git pull --rebase retry loop for concurrent manifest push conflicts
| Phase 02 P01 | 8 | 2 tasks | 1 files |
- [Phase 02]: Use GQAdonis/firecrawl fork repository URL instead of mendableai/firecrawl for Argo CD Application source
- [Phase 02]: Automated sync with prune and self-heal enabled for fully automated GitOps workflow
- [Phase 02]: CreateNamespace=false - Phase 3 will create namespace with proper RBAC and resource quotas
| Phase 03 P01 | 89 | 2 tasks | 4 files |
- [Phase 03]: ResourceQuota limits: 10 CPU requests, 20Gi memory requests, 40Gi memory limits, 50 pods
- [Phase 03]: LimitRange defaults: 1 CPU, 2Gi memory per container; max 4 CPU, 8Gi per container
- [Phase 03]: ServiceAccount token automount: true for api and worker (ConfigMap access), false for ui and playwright (no K8s API needed)
- [Phase 03]: RBAC: Single Role with read-only ConfigMap permissions, bound only to api and worker ServiceAccounts
| Phase 03 P02 | 138 | 2 tasks | 5 files |
- [Phase 03]: Structured ConfigMaps by concern (database, redis, application) instead of monolithic ConfigMap for partial updates and clearer ownership
- [Phase 03]: Manual kubectl secret creation with documented runbook instead of encrypted GitOps secrets for v1 simplicity
- [Phase 03]: Kubernetes internal DNS for service hostnames ({service}.{namespace}.svc.cluster.local) for standard K8s service discovery
| Phase 04 P01 | 100 | 2 tasks | 4 files |
- [Phase 04]: Immediate binding mode for StorageClass to ensure volumes provision before StatefulSet scheduling (avoids WaitForFirstConsumer delays)
- [Phase 04]: Retain reclaim policy prevents accidental data loss if PVCs are deleted (manual cleanup required but data is safe)
- [Phase 04]: Verified cluster zones (us-central1-a/b/c/f) from kubectl query instead of placeholder zones for accurate topology constraints
- [Phase 04]: ReadWriteOnce access mode for GKE pd-standard compatibility (does not support ReadWriteMany)

### Open Questions

| Question | Context | Needs Resolution By |
|----------|---------|---------------------|
| Which storage class exists in client-cluster? | Phase 4 requires validation of immediate-binding storage class | Phase 4 planning |
| What are optimal resource limits for API and workers? | Phase 6 requires load testing to determine memory/CPU limits | Phase 6 planning |
| How is TLS certificate structured in candle-vllm secret? | Phase 7 needs to clone certificate for HTTPRoutes | Phase 7 planning |
| Which Argo CD version is installed? | Phase 2 configuration may be version-specific | Phase 2 planning |
| What zones are nodes distributed across? | Phase 4 storage topology must match node zones | Phase 4 planning |

### Todos

- [ ] Begin Phase 1 planning with `/gsd:plan-phase 1`
- [ ] Review roadmap structure before starting planning
- [ ] Validate that all v1 requirements are covered in phases

### Blockers

*None currently*

### Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| StatefulSet volume binding failure | Medium | High | Use immediate-binding storage class, validate zones (Phase 4) |
| Missing resource limits cause OOM | Medium | High | Define limits on all containers, tune Node.js heap (Phase 6) |
| Race condition between image push and manifest update | Medium | Medium | Verify image availability before manifest commit (Phase 1) |
| TLS configuration mismatch | Low | Medium | Document TLS termination architecture, test connectivity (Phase 7) |
| Argo CD sync loop from automatic commits | Low | High | Use [skip ci] in manifest commit messages (Phase 1) |

## Phase Summary

| Phase | Status | Requirements | Success Criteria | Plans |
|-------|--------|--------------|------------------|-------|
| 1. CI/CD Pipeline Foundation | Complete | 8 | 8 | 2/2 |
| 2. Argo CD Integration | Complete | 7 | 7 | 1/1 |
| 3. Foundation Resources | Complete | 6 | 6 | 2/2 |
| 4. Storage Layer | Complete | 5 | 5 | 1/1 |
| 5. Data Layer | Not started | 9 | 8 | 0/? |
| 6. Application Layer | Not started | 16 | 10 | 0/? |
| 7. External Access | Not started | 8 | 8 | 0/? |

**Total:** 61 requirements → 52 success criteria

## Session Continuity

**What just happened:**
Completed Phase 04 Plan 01 (Persistent Storage Infrastructure). Created custom StorageClass (dc26d895): standard-immediate with volumeBindingMode: Immediate, reclaimPolicy: Retain, allowVolumeExpansion: true, and allowedTopologies restricted to cluster zones us-central1-a/b/c/f (verified from kubectl). Created Postgres PVC requesting 10Gi and Redis PVC requesting 1Gi, both referencing standard-immediate StorageClass with ReadWriteOnce access mode. Updated kustomization.yaml (ebb3351a) to include all three storage resources (StorageClass, pvc-postgres, pvc-redis) positioned after ConfigMaps and before Deployments. Phase 04 complete (1/1 plans done).

**What's next:**
Phase 04 (Storage Layer) complete. Proceed to Phase 05 (Data Layer) with `/gsd:plan-phase 5` or review phase with `/gsd:verify-work`.

**If context was lost:**
Read this STATE.md for current position. Read ROADMAP.md for phase structure. Read PROJECT.md for core value and constraints. Read REQUIREMENTS.md for detailed requirements. Start with `/gsd:plan-phase 1`.

**Critical Files:**
- `/Users/gqadonis/Projects/references/firecrawl/.planning/PROJECT.md` - Core value and constraints
- `/Users/gqadonis/Projects/references/firecrawl/.planning/REQUIREMENTS.md` - 61 v1 requirements with traceability
- `/Users/gqadonis/Projects/references/firecrawl/.planning/ROADMAP.md` - 7 phases with success criteria
- `/Users/gqadonis/Projects/references/firecrawl/.planning/research/SUMMARY.md` - Research findings and pitfalls
- `/Users/gqadonis/Projects/references/firecrawl/.planning/config.json` - Granularity and mode settings

---

*State tracking initialized: 2026-03-27*
