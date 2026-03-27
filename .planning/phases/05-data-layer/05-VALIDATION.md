---
phase: 5
slug: data-layer
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-27
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | kubectl + bash validation scripts |
| **Config file** | none — shell scripts in .planning/phases/05-data-layer/ |
| **Quick run command** | `kubectl get statefulsets,svc,cronjobs -n firecrawl` |
| **Full suite command** | `bash .planning/phases/05-data-layer/validate-data-layer.sh` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `kubectl get statefulsets,pods,svc -n firecrawl` (verify resources exist and pods are ready)
- **After every plan wave:** Run `bash .planning/phases/05-data-layer/validate-data-layer.sh` (full validation including connectivity tests)
- **Before `/gsd:verify-work`:** Postgres and Redis pods in Running state with 1/1 ready, CronJob created, backup runbook documented
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 5-01-01 | 01 | 1 | DATA-01 | integration | `kubectl get statefulset postgres -n firecrawl -o jsonpath='{.spec.template.spec.volumes[?(@.name=="postgres-data")].persistentVolumeClaim.claimName}' \| grep -q postgres-data` | ❌ W0 | ⬜ pending |
| 5-01-02 | 01 | 1 | DATA-02 | unit | `kubectl get statefulset postgres -n firecrawl -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' \| grep -q 4Gi` | ❌ W0 | ⬜ pending |
| 5-01-03 | 01 | 1 | DATA-03 | unit | `kubectl get statefulset postgres -n firecrawl -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.exec.command[2]}' \| grep -q pg_isready` | ❌ W0 | ⬜ pending |
| 5-02-01 | 02 | 1 | DATA-04 | integration | `kubectl get statefulset redis -n firecrawl -o jsonpath='{.spec.template.spec.volumes[?(@.name=="redis-data")].persistentVolumeClaim.claimName}' \| grep -q redis-data` | ❌ W0 | ⬜ pending |
| 5-02-02 | 02 | 1 | DATA-05 | unit | `kubectl get statefulset redis -n firecrawl -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' \| grep -q 2Gi` | ❌ W0 | ⬜ pending |
| 5-02-03 | 02 | 1 | DATA-06 | unit | `kubectl get statefulset redis -n firecrawl -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.exec.command[1]}' \| grep -q ping` | ❌ W0 | ⬜ pending |
| 5-03-01 | 03 | 1 | DATA-07 | integration | `kubectl exec -n firecrawl postgres-0 -- sh -c 'pg_isready -h postgres-service.firecrawl.svc.cluster.local'` | ❌ W0 | ⬜ pending |
| 5-04-01 | 04 | 2 | DATA-08 | unit | `kubectl get cronjob postgres-backup -n firecrawl -o jsonpath='{.spec.schedule}' \| grep -q '0 \*/6 \* \* \*'` | ❌ W0 | ⬜ pending |
| 5-04-02 | 04 | 2 | DATA-09 | manual | Read backup-restore-runbook.md for completeness | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `validate-data-layer.sh` — Comprehensive validation script covering DATA-01 through DATA-08
  - Check StatefulSet status and replica readiness
  - Verify PVC mounts
  - Test database connectivity (pg_isready, redis-cli ping)
  - Confirm resource limits configuration
  - Validate CronJob schedule and recent job success
- [ ] `backup-restore-runbook.md` — Documented restoration procedure (DATA-09)
  - Prerequisites (kubectl access, gsutil access)
  - Restoration steps (list backups, download, scale down, restore, verify, scale up)
  - Testing restoration procedure (quarterly test in separate namespace)
- [ ] GCS bucket creation and Workload Identity configuration (prerequisite, manual setup required before CronJob execution)
  - Create gs://firecrawl-backups bucket in us-central1
  - Create GCP service account (firecrawl-backup@prometheus-461323.iam.gserviceaccount.com)
  - Bind Workload Identity between K8s SA and GCP SA

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Backup restoration procedure documented | DATA-09 | Documentation completeness requires human review of runbook quality and clarity | Read backup-restore-runbook.md and verify: prerequisites listed, all steps documented, test procedure included |
| Postgres pod can accept connections | DATA-03 | Integration test requires running pod (created after StatefulSet apply) | `kubectl exec -n firecrawl postgres-0 -- pg_isready` exits 0 |
| Redis pod can accept connections | DATA-06 | Integration test requires running pod (created after StatefulSet apply) | `kubectl exec -n firecrawl redis-0 -- redis-cli ping` returns PONG |
| CronJob successfully creates backups | DATA-08 | Requires waiting for CronJob execution (up to 6 hours) | Manually trigger job: `kubectl create job --from=cronjob/postgres-backup manual-backup-test -n firecrawl`, verify gsutil ls shows backup in GCS |
| GCS Workload Identity authentication | DATA-08 | Requires GCP IAM configuration outside Kubernetes | `kubectl exec -n firecrawl <backup-pod> -- gsutil ls gs://firecrawl-backups/` succeeds without credentials mounted |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (validate-data-layer.sh, backup-restore-runbook.md, GCS bucket setup)
- [ ] No watch-mode flags (N/A - kubectl commands are one-shot)
- [ ] Feedback latency < 30s (kubectl validation)
- [ ] `nyquist_compliant: true` set in frontmatter (pending Wave 0 completion)

**Approval:** pending (will be approved after Wave 0 completion and first successful validation run)
