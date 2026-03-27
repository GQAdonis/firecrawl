---
phase: 05-data-layer
plan: 01
subsystem: data-infrastructure
tags: [postgres, redis, statefulset, health-probes, validation]
status: complete
completed_at: "2026-03-27T21:02:43Z"

requirements_addressed:
  - DATA-01  # Postgres StatefulSet with PVC mount
  - DATA-02  # Postgres resource limits
  - DATA-03  # Postgres health probes
  - DATA-04  # Redis StatefulSet with PVC mount
  - DATA-05  # Redis resource limits
  - DATA-06  # Redis health probes
  - DATA-07  # ClusterIP Services

dependency_graph:
  requires:
    - storage-class-immediate (Phase 04)
    - pvc-postgres (Phase 04)
    - pvc-redis (Phase 04)
    - configmap-database (Phase 03)
    - configmap-redis (Phase 03)
  provides:
    - postgres-statefulset
    - postgres-service
    - redis-statefulset
    - redis-service
    - validate-data-layer.sh
  affects:
    - Phase 06 (application layer depends on data services)

tech_stack:
  added:
    - postgres:15-alpine
    - redis:7-alpine
  patterns:
    - StatefulSet with persistent storage
    - Health probes (readiness/liveness)
    - AOF persistence for Redis
    - ClusterIP Services for internal DNS

key_files:
  created:
    - k8s/base/postgres-statefulset.yaml
    - k8s/base/postgres-service.yaml
    - k8s/base/redis-statefulset.yaml
    - k8s/base/redis-service.yaml
    - .planning/phases/05-data-layer/validate-data-layer.sh
  modified:
    - k8s/base/kustomization.yaml

decisions:
  - decision: "Use default ServiceAccount for Postgres and Redis"
    rationale: "Database pods do not need Kubernetes API access"
    alternatives: ["Create dedicated ServiceAccounts"]
    chosen_because: "Simplicity - no K8s API interaction required"

  - decision: "PGDATA subdirectory /var/lib/postgresql/data/pgdata"
    rationale: "Avoids ext4 lost+found directory conflict on empty PVC mount"
    alternatives: ["Use root mount path /var/lib/postgresql/data"]
    chosen_because: "Prevents Postgres initialization failure (Pitfall 5 from research)"

  - decision: "fsGroup: 999 for both StatefulSets"
    rationale: "Matches postgres and redis user UIDs in official Alpine images"
    alternatives: ["Let containers run with default fsGroup"]
    chosen_because: "Ensures PVC write permissions without container modifications"

  - decision: "Conservative resource limits (Postgres 2/4Gi, Redis 1/2Gi)"
    rationale: "Prevents OOMKilled, allows tuning based on actual usage"
    alternatives: ["Match LimitRange defaults", "Use higher limits"]
    chosen_because: "Phase 6 can increase limits after load testing (Pitfall 4 mitigation)"

  - decision: "Readiness probe delays shorter than liveness (30s vs 60s for Postgres)"
    rationale: "Delay pod routing until ready, but prevent premature restarts during cold start"
    alternatives: ["Same delays for both probes"]
    chosen_because: "Standard Kubernetes best practice (Pitfall 1 mitigation)"

  - decision: "Redis AOF persistence with everysec fsync"
    rationale: "Balance between durability and performance"
    alternatives: ["RDB snapshots only", "always fsync"]
    chosen_because: "Tolerates 1 second data loss on crash, minimal performance impact (Pitfall 2 mitigation)"

metrics:
  duration_seconds: 240
  tasks_completed: 3
  files_created: 5
  files_modified: 1
  commits: 4
  deviations: 1
---

# Phase 05 Plan 01: Data Layer StatefulSets and Services Summary

**One-liner:** Created Postgres and Redis StatefulSets with persistent storage, health probes, and ClusterIP Services for internal DNS resolution

## What Was Built

Created the data layer foundation for Firecrawl deployment:

1. **Postgres StatefulSet** (postgres:15-alpine)
   - PVC mount to postgres-data (10Gi from Phase 04)
   - Resource limits: 500m/1Gi requests, 2/4Gi limits
   - Health probes: pg_isready with 30s/60s initial delays
   - PGDATA subdirectory to avoid lost+found conflict
   - fsGroup 999 for PVC write permissions

2. **Redis StatefulSet** (redis:7-alpine)
   - PVC mount to redis-data (1Gi from Phase 04)
   - AOF persistence enabled (appendonly yes, appendfsync everysec)
   - Resource limits: 200m/512Mi requests, 1/2Gi limits
   - Health probes: redis-cli ping with 5s/10s initial delays
   - fsGroup 999 for PVC write permissions

3. **ClusterIP Services**
   - postgres-service: port 5432 (matches configmap-database.yaml DNS)
   - redis-service: port 6379 (matches configmap-redis.yaml DNS)

4. **Phase-Gate Validation Script**
   - Validates DATA-01 through DATA-08 requirements
   - Manifest-based checks (works without live cluster)
   - Optional live cluster validation

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed validation script arithmetic expansion with set -e**
- **Found during:** Task 0 verification
- **Issue:** The validation script used `((VAR++))` which returns exit code 1 when VAR=0, causing `set -euo pipefail` to exit immediately after the first PASS
- **Fix:** Changed all arithmetic expansions from `((VAR++))` to `VAR=$((VAR + 1))` to ensure consistent exit code 0
- **Files modified:** .planning/phases/05-data-layer/validate-data-layer.sh
- **Commit:** 6c3c3833

This was a bash quirk where postfix increment on value 0 returns false (exit code 1), failing the `set -e` error detection. The fix ensures the script runs all checks correctly.

## Implementation Notes

### Key Design Decisions

1. **serviceName field in StatefulSets:** Both StatefulSets reference their corresponding Services (postgres-service, redis-service) to enable stable DNS names for pod ordinals

2. **Resource ordering in kustomization.yaml:** StatefulSets and Services positioned after PVCs (which they depend on) and before Deployments (which depend on them)

3. **Probe configuration:** Liveness probes have longer initial delays and higher failure thresholds than readiness probes to prevent restart loops during initialization

4. **Image pull policy:** Set to IfNotPresent to reduce registry load while allowing version updates when tags change

### Verification

All DATA-01 through DATA-07 manifest checks pass:
- 16 manifest checks: PASS
- 3 DATA-08 checks: SKIP (expected - Plan 02 will create backup resources)
- 5 live cluster checks: FAIL (expected - resources not yet deployed)

Phase-gate validation command:
```bash
bash .planning/phases/05-data-layer/validate-data-layer.sh
```

### Dependencies Satisfied

From Phase 03:
- configmap-database.yaml provides POSTGRES_HOST, POSTGRES_PORT, POSTGRES_DB
- configmap-redis.yaml provides REDIS_URL pointing to redis-service DNS

From Phase 04:
- pvc-postgres.yaml provides postgres-data PVC (10Gi)
- pvc-redis.yaml provides redis-data PVC (1Gi)
- storage-class-immediate.yaml ensures immediate volume binding

### Phase 06 Integration

Application deployments (Phase 06) will:
- Use postgres-service.firecrawl.svc.cluster.local:5432 for database connections
- Use redis-service.firecrawl.svc.cluster.local:6379 for cache and BullMQ queues
- Reference firecrawl-database-secret for POSTGRES_USER and POSTGRES_PASSWORD credentials

## Task Commits

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 0 | Create phase-gate validation script | 70387918 | validate-data-layer.sh |
| 1 | Create Postgres StatefulSet and Service | 0e55acac | postgres-statefulset.yaml, postgres-service.yaml |
| 2 | Create Redis StatefulSet and Service, update kustomization | 1ee0a8f7 | redis-statefulset.yaml, redis-service.yaml, kustomization.yaml |
| - | Fix validation script arithmetic bug | 6c3c3833 | validate-data-layer.sh |

## Next Steps

Proceed to Phase 05 Plan 02: Postgres Backup CronJob with Cloud Storage Integration

Plan 02 will:
- Create backup-serviceaccount.yaml with Workload Identity annotation
- Create backup-cronjob.yaml with 6-hour schedule
- Use pg_dump to backup to GCS bucket
- Complete DATA-08 requirement validation

## Self-Check: PASSED

Verified all claimed artifacts exist:
```
FOUND: .planning/phases/05-data-layer/validate-data-layer.sh
FOUND: k8s/base/postgres-statefulset.yaml
FOUND: k8s/base/postgres-service.yaml
FOUND: k8s/base/redis-statefulset.yaml
FOUND: k8s/base/redis-service.yaml
```

Verified all commits exist:
```
FOUND: 70387918 (Task 0)
FOUND: 0e55acac (Task 1)
FOUND: 1ee0a8f7 (Task 2)
FOUND: 6c3c3833 (Deviation fix)
```

All must-have artifacts from PLAN.md frontmatter are present and contain required patterns.
