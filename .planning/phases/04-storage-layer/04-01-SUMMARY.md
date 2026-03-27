---
phase: 04-storage-layer
plan: 01
subsystem: infrastructure
tags: [storage, kubernetes, gke, persistent-volumes]
dependency_graph:
  requires: [03-foundation-resources]
  provides: [storage-class-immediate, postgres-pvc, redis-pvc]
  affects: [05-data-layer]
tech_stack:
  added: [StorageClass-v1, PersistentVolumeClaim-v1, GKE-pd-standard]
  patterns: [immediate-binding, retain-policy, zone-topology-constraints]
key_files:
  created:
    - k8s/base/storage-class-immediate.yaml
    - k8s/base/pvc-postgres.yaml
    - k8s/base/pvc-redis.yaml
  modified:
    - k8s/base/kustomization.yaml
decisions:
  - "Used actual cluster zones (us-central1-a/b/c/f) from kubectl query instead of placeholder values"
  - "Immediate binding mode ensures volumes provision before StatefulSet scheduling (avoids WaitForFirstConsumer startup delays)"
  - "Retain reclaim policy prevents accidental data loss if PVCs are deleted"
  - "ReadWriteOnce access mode selected for GKE pd-standard compatibility (does not support ReadWriteMany)"
metrics:
  duration_seconds: 100
  tasks_completed: 2
  files_created: 3
  files_modified: 1
  commits: 2
  completed_date: "2026-03-27"
---

# Phase 04 Plan 01: Create Persistent Storage Infrastructure Summary

**One-liner:** Custom immediate-binding StorageClass with Retain policy, 10Gi Postgres PVC, and 1Gi Redis PVC provisioned for GKE cluster zones us-central1-a/b/c/f

## What Was Built

Created persistent storage infrastructure for Postgres and Redis databases on GKE using immediate-binding StorageClass pattern. The StorageClass provisions volumes immediately (not deferred to pod scheduling), uses Retain reclaim policy to prevent data loss, and restricts topology to verified cluster node zones. Both PVCs reference the custom StorageClass and use ReadWriteOnce access mode compatible with GKE persistent disks.

**Storage Resources:**
- Custom StorageClass (standard-immediate) with volumeBindingMode: Immediate, reclaimPolicy: Retain, allowVolumeExpansion: true
- Postgres PVC requesting 10Gi storage from standard-immediate StorageClass
- Redis PVC requesting 1Gi storage from standard-immediate StorageClass
- Zone topology constraints set to us-central1-a, us-central1-b, us-central1-c, us-central1-f (verified from cluster nodes)

**Integration:**
- Updated kustomization.yaml to include all three storage resources for Argo CD sync
- StorageClass listed before PVCs to ensure correct apply order
- Resources positioned after ConfigMaps and before Deployments for logical grouping

## Requirements Satisfied

| Requirement | Status | Evidence |
|-------------|--------|----------|
| STOR-01: PersistentVolumeClaim created for Postgres (10Gi) | ✅ Complete | pvc-postgres.yaml with `storage: 10Gi` |
| STOR-02: PersistentVolumeClaim created for Redis (1Gi) | ✅ Complete | pvc-redis.yaml with `storage: 1Gi` |
| STOR-03: PVCs use immediate-binding storage class | ✅ Complete | Both PVCs reference `storageClassName: standard-immediate` |
| STOR-04: PersistentVolume reclaim policy set to Retain | ✅ Complete | StorageClass has `reclaimPolicy: Retain` |
| STOR-05: Volume topology validated against node zones | ✅ Complete | StorageClass allowedTopologies lists all 4 cluster zones |

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create custom StorageClass and PVC manifests | dc26d895 | storage-class-immediate.yaml, pvc-postgres.yaml, pvc-redis.yaml |
| 2 | Update kustomization.yaml with storage resources | ebb3351a | kustomization.yaml |

## Deviations from Plan

**1. [Rule 3 - Enhancement] Used 4 cluster zones instead of 3 placeholder zones**
- **Found during:** Task 1 - querying cluster node zones
- **Issue:** Plan assumed 3-zone cluster (us-central1-a/b/c), but actual cluster spans 4 zones (us-central1-a/b/c/f)
- **Fix:** Queried cluster with `kubectl get nodes -o jsonpath='{.items[*].metadata.labels.topology\.gke\.io/zone}'` and used all 4 verified zones in allowedTopologies
- **Files modified:** storage-class-immediate.yaml
- **Commit:** dc26d895
- **Rationale:** Using actual zones ensures volumes can be provisioned in any zone where nodes exist, avoiding topology mismatch failures. This is more accurate than the placeholder zones suggested in the plan.

## Decisions Made

**1. Immediate Binding Mode**
- **Context:** GKE default storage classes use WaitForFirstConsumer binding mode to optimize zone placement
- **Decision:** Create custom StorageClass with volumeBindingMode: Immediate
- **Rationale:** StatefulSets require guaranteed volume availability before pod scheduling. WaitForFirstConsumer can create circular dependencies where volumes wait for pods but pods can't schedule without volumes.
- **Impact:** Volumes are provisioned immediately when PVCs are created, before StatefulSet pods are scheduled in Phase 5
- **Tradeoff:** Less zone-aware placement flexibility (requires explicit allowedTopologies), but eliminates startup delays

**2. Retain Reclaim Policy**
- **Context:** Default reclaim policy in GKE is typically Delete to prevent orphaned resources
- **Decision:** Set reclaimPolicy: Retain in StorageClass
- **Rationale:** Database volumes contain critical persistent data. If a PVC is accidentally deleted, Retain policy keeps the PersistentVolume and underlying GCP disk intact, allowing data recovery.
- **Impact:** Manual cleanup required if PVCs are deleted (PVs and disks will remain), but data safety is guaranteed
- **Tradeoff:** Requires manual PV/disk cleanup, but prevents catastrophic data loss

**3. Zone Topology Verification**
- **Context:** Plan suggested using placeholder zones or verifying actual cluster zones
- **Decision:** Query cluster with kubectl before creating StorageClass
- **Rationale:** With immediate binding mode, volumes are provisioned before pod scheduling. Incorrect topology constraints could provision volumes in zones without nodes, causing unschedulable pods.
- **Impact:** StorageClass allowedTopologies accurately reflects cluster topology (us-central1-a/b/c/f)
- **Tradeoff:** Requires kubectl access during plan execution, but ensures topology correctness

**4. ReadWriteOnce Access Mode**
- **Context:** PVCs can request ReadWriteOnce (RWO) or ReadWriteMany (RWX) access modes
- **Decision:** Use accessModes: [ReadWriteOnce] for both Postgres and Redis PVCs
- **Rationale:** GKE pd-standard, pd-ssd, and pd-balanced block storage only support ReadWriteOnce. Single-instance databases don't need multi-writer access.
- **Impact:** Volumes can only be mounted by one pod at a time, which is correct for single-instance StatefulSets
- **Tradeoff:** Cannot scale to multi-writer workloads without switching to Filestore (NFS), but that's not required for v1

## Testing Evidence

**Automated Verification (Task 1):**
```bash
grep -q "volumeBindingMode: Immediate" k8s/base/storage-class-immediate.yaml && \
grep -q "reclaimPolicy: Retain" k8s/base/storage-class-immediate.yaml && \
grep -q "storage: 10Gi" k8s/base/pvc-postgres.yaml && \
grep -q "storage: 1Gi" k8s/base/pvc-redis.yaml && \
grep -q "storageClassName: standard-immediate" k8s/base/pvc-postgres.yaml && \
grep -q "storageClassName: standard-immediate" k8s/base/pvc-redis.yaml && \
grep -q "allowedTopologies" k8s/base/storage-class-immediate.yaml && \
echo "PASS" || echo "FAIL"
```
Result: PASS

**Automated Verification (Task 2):**
```bash
grep -q "storage-class-immediate.yaml" k8s/base/kustomization.yaml && \
grep -q "pvc-postgres.yaml" k8s/base/kustomization.yaml && \
grep -q "pvc-redis.yaml" k8s/base/kustomization.yaml && \
echo "PASS" || echo "FAIL"
```
Result: PASS

**File Existence Check:**
- storage-class-immediate.yaml: 479 bytes, created
- pvc-postgres.yaml: 300 bytes, created
- pvc-redis.yaml: 290 bytes, created

**Ordering Verification:**
StorageClass appears on line 11, PVCs appear on lines 12-13 in kustomization.yaml resources list, ensuring correct apply order.

## Known Issues / Limitations

None. All requirements satisfied, all acceptance criteria met.

## Phase 5 Handoff

**What Phase 5 can assume:**
- StorageClass named `standard-immediate` exists and will be created by Argo CD
- Postgres PVC named `postgres-data` exists in firecrawl namespace, requests 10Gi
- Redis PVC named `redis-data` exists in firecrawl namespace, requests 1Gi
- Both PVCs use immediate binding mode - volumes will be provisioned when PVCs are created, before StatefulSet pods start
- Reclaim policy is Retain - data is safe even if PVCs are accidentally deleted
- Zone topology is correct for cluster (us-central1-a/b/c/f)

**How Phase 5 should reference storage:**
```yaml
# In StatefulSet spec.template.spec
volumes:
  - name: postgres-data
    persistentVolumeClaim:
      claimName: postgres-data  # Reference PVC created in this phase
```

**Critical notes for Phase 5:**
1. Do NOT use volumeClaimTemplates in StatefulSet - these are standalone PVCs
2. PVCs are in firecrawl namespace - StatefulSets must also be in firecrawl namespace
3. Volume names in pod spec can be arbitrary (e.g., "data"), but claimName must match PVC metadata.name
4. Postgres StatefulSet should mount postgres-data PVC at `/var/lib/postgresql/data`
5. Redis StatefulSet should mount redis-data PVC at `/data` or `/var/lib/redis`

## Self-Check

**Created files verification:**
```bash
[ -f "k8s/base/storage-class-immediate.yaml" ] && echo "FOUND: storage-class-immediate.yaml" || echo "MISSING: storage-class-immediate.yaml"
[ -f "k8s/base/pvc-postgres.yaml" ] && echo "FOUND: pvc-postgres.yaml" || echo "MISSING: pvc-postgres.yaml"
[ -f "k8s/base/pvc-redis.yaml" ] && echo "FOUND: pvc-redis.yaml" || echo "MISSING: pvc-redis.yaml"
```

**Commits verification:**
```bash
git log --oneline --all | grep -q "dc26d895" && echo "FOUND: dc26d895" || echo "MISSING: dc26d895"
git log --oneline --all | grep -q "ebb3351a" && echo "FOUND: ebb3351a" || echo "MISSING: ebb3351a"
```

**Results:**
- FOUND: storage-class-immediate.yaml
- FOUND: pvc-postgres.yaml
- FOUND: pvc-redis.yaml
- FOUND: dc26d895 (Task 1 commit)
- FOUND: ebb3351a (Task 2 commit)

## Self-Check: PASSED

All created files exist and all commits are in git history.
