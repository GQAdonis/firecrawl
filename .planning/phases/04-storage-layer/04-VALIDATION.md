---
phase: 4
slug: storage-layer
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-27
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | kubectl + bash validation scripts |
| **Config file** | none — shell scripts in phase directory |
| **Quick run command** | `kubectl get pvc -n firecrawl` |
| **Full suite command** | `bash .planning/phases/04-storage-layer/validate-storage.sh` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `kubectl get pvc,sc -n firecrawl` (verify resources exist)
- **After every plan wave:** Run `bash .planning/phases/04-storage-layer/validate-storage.sh` (full validation)
- **Before `/gsd:verify-work`:** All PVCs in Bound state, reclaim policy Retain confirmed
- **Max feedback latency:** 15 seconds

**Phase gate full validation:**
1. Run `bash .planning/phases/04-storage-layer/validate-storage.sh`
2. Verify all PVCs show status=Bound
3. Verify storage class has volumeBindingMode=Immediate and reclaimPolicy=Retain
4. Verify PV nodeAffinity zones match cluster node zones

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 4-01-01 | 01 | 0 | N/A | manual-only | Query client-cluster node zones: `kubectl get nodes -o custom-columns=NAME:.metadata.name,ZONE:.metadata.labels.topology\\.gke\\.io/zone` | N/A | ⬜ pending |
| 4-01-02 | 01 | 1 | STOR-03, STOR-04 | unit | `kubectl get sc standard-immediate -o jsonpath='{.reclaimPolicy}' \| grep -q Retain && kubectl get sc standard-immediate -o jsonpath='{.volumeBindingMode}' \| grep -q Immediate` | ❌ W0 | ⬜ pending |
| 4-01-03 | 01 | 1 | STOR-01 | integration | `kubectl get pvc postgres-data -n firecrawl -o jsonpath='{.status.phase}' \| grep -q Bound` | ❌ W0 | ⬜ pending |
| 4-01-04 | 01 | 1 | STOR-02 | integration | `kubectl get pvc redis-data -n firecrawl -o jsonpath='{.status.phase}' \| grep -q Bound` | ❌ W0 | ⬜ pending |
| 4-01-05 | 01 | 1 | STOR-05 | integration | Compare PV nodeAffinity zones with node zones (in validate-storage.sh) | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Query client-cluster node zones before StorageClass creation: `kubectl get nodes -o custom-columns=NAME:.metadata.name,ZONE:.metadata.labels.topology\\.gke\\.io/zone`
- [ ] `validate-storage.sh` — comprehensive validation script covering STOR-01 through STOR-05
- [ ] Validation script must check:
  - PVC binding status (Bound state)
  - Storage class configuration (volumeBindingMode, reclaimPolicy)
  - Zone topology match (PV nodeAffinity vs node zones)

*Note: Task 4-01-01 is a Wave 0 manual prerequisite that must be completed before creating the StorageClass. The node zones discovered will populate the `allowedTopologies` field in the StorageClass manifest.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Query cluster node zones | STOR-05 (indirectly) | Requires kubectl access to cluster before manifest creation | Run `kubectl get nodes -o custom-columns=NAME:.metadata.name,ZONE:.metadata.labels.topology\\.gke\\.io/zone` and note zones for StorageClass allowedTopologies |
| Verify PVCs bind immediately | STOR-03 | Runtime behavior verification requires observing PVC creation timing | Create PVC, observe status changes to Bound within seconds (not waiting for pod scheduling) |
| Confirm data persists across pod restarts | STOR-04 (indirectly) | Requires functional StatefulSet from Phase 5 | After Phase 5: write data, delete pod, verify data remains after pod recreates |

*Note: PersistentVolumeClaim resources are storage provisioning requests. Validation happens via kubectl commands checking cluster state, not traditional unit tests.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify (N/A - single plan expected)
- [ ] Wave 0 covers all MISSING references (node zone query, validation script)
- [ ] No watch-mode flags (N/A - kubectl commands are one-shot)
- [ ] Feedback latency < 15s (kubectl validation)
- [ ] `nyquist_compliant: true` set in frontmatter (pending Wave 0 completion)

**Approval:** pending (will be approved after Wave 0 completion and first successful validation run)
