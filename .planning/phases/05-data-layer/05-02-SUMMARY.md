---
phase: 05-data-layer
plan: 02
subsystem: infra
tags: [postgres, backup, gcs, cronjob, kubernetes, workload-identity]

# Dependency graph
requires:
  - phase: 05-01
    provides: Postgres StatefulSet with postgres-service DNS endpoint
provides:
  - Postgres backup CronJob running every 6 hours with pg_dump to GCS
  - ServiceAccount with Workload Identity annotation for GCS authentication
  - Comprehensive restoration runbook with step-by-step recovery procedure
affects: [operations, disaster-recovery]

# Tech tracking
tech-stack:
  added: [google/cloud-sdk:alpine, postgresql15-client, gsutil]
  patterns: [Workload Identity for GCS access, CronJob for scheduled backups, automated cleanup retention policy]

key-files:
  created:
    - k8s/base/backup-serviceaccount.yaml
    - k8s/base/backup-cronjob.yaml
    - .planning/phases/05-data-layer/backup-restore-runbook.md
  modified:
    - k8s/base/kustomization.yaml

key-decisions:
  - "6-hour backup schedule (00:00, 06:00, 12:00, 18:00 UTC) balances RPO with storage costs"
  - "Workload Identity eliminates long-lived service account keys for GCS authentication"
  - "30-day retention policy (120 backups) via automated cleanup script in CronJob"
  - "gzip compression reduces storage costs while maintaining quick restoration"
  - "pg_dump with --clean --if-exists --create flags for complete database recreation on restore"

patterns-established:
  - "Workload Identity: ServiceAccount annotation binds K8s SA to GCP SA for keyless authentication"
  - "CronJob cleanup: Inline script deletes backups older than cutoff date"
  - "Backup naming: postgres-backup-YYYYMMDD-HHMMSS.sql.gz for chronological sorting"

requirements-completed: [DATA-08, DATA-09]

# Metrics
duration: 18min
completed: 2026-03-27
---

# Phase 05 Plan 02: Postgres Backup and Recovery Summary

**Automated Postgres backups every 6 hours to GCS with Workload Identity authentication and documented restoration runbook**

## Performance

- **Duration:** 18 min
- **Started:** 2026-03-27T21:04:26Z
- **Completed:** 2026-03-27T21:22:00Z (estimated)
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Postgres backup CronJob with 6-hour schedule exports pg_dump to GCS bucket
- Workload Identity ServiceAccount enables keyless GCS authentication
- Comprehensive restoration runbook documents recovery procedure with 8 steps
- Automated cleanup retains 30 days of backups (120 at 6-hour intervals)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create backup ServiceAccount, CronJob, and update kustomization** - `cc8f2a56` (feat)
2. **Task 2: Verify backup restoration runbook and GCS prerequisites** - `ead4dd6f` (docs)

## Files Created/Modified
- `k8s/base/backup-serviceaccount.yaml` - ServiceAccount with Workload Identity annotation for firecrawl-backup@prometheus-461323.iam.gserviceaccount.com
- `k8s/base/backup-cronjob.yaml` - CronJob running every 6 hours with pg_dump, gzip compression, gsutil upload to gs://firecrawl-backups/postgres/, and 30-day cleanup
- `k8s/base/kustomization.yaml` - Added backup-serviceaccount.yaml and backup-cronjob.yaml to resources list
- `.planning/phases/05-data-layer/backup-restore-runbook.md` - Step-by-step restoration procedure, manual backup trigger, quarterly testing, troubleshooting

## Decisions Made

**6-hour backup schedule:** Balances Recovery Point Objective (max 6 hours data loss) with storage costs and compute overhead. Runs at 00:00, 06:00, 12:00, 18:00 UTC.

**Workload Identity authentication:** Eliminates need for long-lived service account keys stored as Kubernetes secrets. The annotation `iam.gke.io/gcp-service-account` binds K8s ServiceAccount to GCP service account with IAM policy binding.

**30-day retention policy:** Keeps 120 backups (30 days * 4 backups/day). Automated cleanup script in CronJob deletes backups older than cutoff date via gsutil ls + rm.

**gzip compression:** Reduces storage costs significantly while maintaining fast restoration (gunzip is fast). Trade-off: slightly higher CPU during backup, but negligible for 6-hour schedule.

**pg_dump flags:** `--clean --if-exists --create` ensures complete database recreation on restore, dropping existing objects safely before recreating from backup.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None - backup CronJob manifest and restoration runbook created as specified.

## User Setup Required

**External services require manual configuration.** The user must complete GCS setup before the CronJob can run successfully:

**Prerequisites (documented in plan frontmatter user_setup):**
1. Create GCS bucket `gs://firecrawl-backups` in us-central1
   ```bash
   gsutil mb -p prometheus-461323 -l us-central1 gs://firecrawl-backups
   ```

2. Create GCP service account `firecrawl-backup@prometheus-461323.iam.gserviceaccount.com`
   ```bash
   gcloud iam service-accounts create firecrawl-backup --project=prometheus-461323
   ```

3. Grant GCS objectAdmin role to service account on bucket
   ```bash
   gcloud projects add-iam-policy-binding prometheus-461323 \
     --member=serviceAccount:firecrawl-backup@prometheus-461323.iam.gserviceaccount.com \
     --role=roles/storage.objectAdmin
   ```

4. Bind Workload Identity between K8s ServiceAccount and GCP ServiceAccount
   ```bash
   gcloud iam service-accounts add-iam-policy-binding \
     firecrawl-backup@prometheus-461323.iam.gserviceaccount.com \
     --project=prometheus-461323 \
     --role=roles/iam.workloadIdentityUser \
     --member=serviceAccount:prometheus-461323.svc.id.goog[firecrawl/postgres-backup-sa]
   ```

**Verification:** After completing setup, trigger manual backup and check logs:
```bash
kubectl create job --from=cronjob/postgres-backup manual-backup-test -n firecrawl
kubectl logs -n firecrawl job/manual-backup-test -f
```

## Next Phase Readiness

- Backup and recovery infrastructure complete
- Phase 05 Data Layer complete (2/2 plans done)
- Ready to proceed to Phase 06 (Application Layer) - API and worker deployments
- Postgres and Redis StatefulSets from Plan 01 provide database endpoints
- Backup CronJob provides data protection from day one

**Blocker:** User must complete GCS setup (bucket, service account, IAM bindings) before backups can run. This is a prerequisite, not a blocker for Phase 06 development.

---
*Phase: 05-data-layer*
*Completed: 2026-03-27*
