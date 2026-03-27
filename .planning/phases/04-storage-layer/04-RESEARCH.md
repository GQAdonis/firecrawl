# Phase 4: Storage Layer - Research

**Researched:** 2026-03-27
**Domain:** Kubernetes Persistent Storage on GKE
**Confidence:** MEDIUM-HIGH

## Summary

Phase 4 implements persistent storage for Postgres (10Gi) and Redis (1Gi) using Kubernetes PersistentVolumeClaims with immediate binding mode. GKE provides several storage classes, but the critical requirement is using a storage class with `volumeBindingMode: Immediate` rather than `WaitForFirstConsumer` to ensure volumes are provisioned and bound before StatefulSet pods start.

GKE's default storage classes use `WaitForFirstConsumer` binding mode, which delays volume provisioning until a pod is scheduled. For StatefulSets requiring guaranteed volume availability, this can cause startup issues. The solution is to either use an existing immediate-binding storage class or create a custom StorageClass with `volumeBindingMode: Immediate`.

**Primary recommendation:** Create custom StorageClass with `volumeBindingMode: Immediate` based on GKE's standard-rwo provisioner, then reference it in PVC specs. Set reclaim policy to Retain to prevent accidental data loss.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| STOR-01 | PersistentVolumeClaim created for Postgres (10Gi) | Standard PVC manifest pattern with immediate-binding storage class |
| STOR-02 | PersistentVolumeClaim created for Redis (1Gi) | Standard PVC manifest pattern with immediate-binding storage class |
| STOR-03 | PVCs use immediate-binding storage class | Custom StorageClass creation with volumeBindingMode: Immediate |
| STOR-04 | PersistentVolume reclaim policy set to Retain | Configure in StorageClass spec (reclaimPolicy: Retain) |
| STOR-05 | Volume topology validated against node zones | AllowedTopologies in StorageClass or topology spread constraints |
</phase_requirements>

## Standard Stack

### Core Components

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| GKE pd-standard | GKE built-in | Standard persistent disk provisioner | Native GKE integration, reliable performance |
| StorageClass | v1 | Defines storage provisioner and binding mode | Required for immediate binding configuration |
| PersistentVolumeClaim | v1 | Requests storage from StorageClass | Standard Kubernetes storage abstraction |
| PersistentVolume | v1 | Actual storage volume bound to PVC | Auto-provisioned by GKE CSI driver |

### Storage Class Options in GKE

| Class Name | Provisioner | Binding Mode | Performance | Use Case |
|------------|-------------|--------------|-------------|----------|
| standard-rwo | pd.csi.storage.gke.io | WaitForFirstConsumer | Standard HDD | Default, topology-aware |
| premium-rwo | pd.csi.storage.gke.io | WaitForFirstConsumer | Premium SSD | Higher IOPS workloads |
| balanced-rwo | pd.csi.storage.gke.io | WaitForFirstConsumer | Balanced SSD | Cost-performance balance |
| custom-immediate | pd.csi.storage.gke.io | Immediate | Standard HDD | StatefulSets needing pre-binding |

**Note:** GKE's default storage classes all use `WaitForFirstConsumer` binding mode as of 2024-2026 to optimize zone placement. For STOR-03 requirement, we must create a custom StorageClass.

### Installation

No package installation required - storage is native Kubernetes/GKE infrastructure.

**Verify existing storage classes:**
```bash
kubectl get storageclass
```

**Version verification:** StorageClass API is stable at v1 since Kubernetes 1.6. GKE CSI driver is automatically available in all modern GKE clusters (1.18+).

## Architecture Patterns

### Recommended Resource Structure

```
k8s/base/
├── storage-class-immediate.yaml    # Custom immediate-binding StorageClass
├── pvc-postgres.yaml               # 10Gi PVC for Postgres
├── pvc-redis.yaml                  # 1Gi PVC for Redis
└── kustomization.yaml              # Include storage resources
```

### Pattern 1: Custom Immediate-Binding StorageClass

**What:** Create a custom StorageClass that uses GKE's pd.csi.storage.gke.io provisioner with immediate binding mode.

**When to use:** When StatefulSets require guaranteed volume availability before pod scheduling (STOR-03 requirement).

**Example:**
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard-immediate
provisioner: pd.csi.storage.gke.io
parameters:
  type: pd-standard
  fstype: ext4
volumeBindingMode: Immediate
reclaimPolicy: Retain
allowVolumeExpansion: true
```

**Key fields:**
- `volumeBindingMode: Immediate` - Provision and bind PV immediately when PVC is created
- `reclaimPolicy: Retain` - Prevent data loss if PVC is deleted (STOR-04)
- `allowVolumeExpansion: true` - Allow resizing without recreation
- `type: pd-standard` - Use standard HDD (upgrade to pd-ssd or pd-balanced if needed)

### Pattern 2: PersistentVolumeClaim for StatefulSet

**What:** Create standalone PVC that will be referenced by StatefulSet via `volumes` section.

**When to use:** When you need a single persistent volume for a StatefulSet (not using volumeClaimTemplates).

**Example:**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data
  namespace: firecrawl
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: standard-immediate
  resources:
    requests:
      storage: 10Gi
```

**Key fields:**
- `accessModes: [ReadWriteOnce]` - Single node read-write access (RWO)
- `storageClassName` - Must match custom immediate-binding StorageClass
- `storage: 10Gi` - Size must fit within namespace ResourceQuota (50Gi total, 20Gi max per PVC)

### Pattern 3: Volume Topology Constraints (STOR-05)

**What:** Ensure volumes are provisioned in zones where GKE nodes exist.

**When to use:** When cluster spans multiple zones and you need to guarantee volume-node co-location.

**Example:**
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard-immediate
provisioner: pd.csi.storage.gke.io
parameters:
  type: pd-standard
volumeBindingMode: Immediate
reclaimPolicy: Retain
allowedTopologies:
  - matchLabelExpressions:
      - key: topology.gke.io/zone
        values:
          - us-central1-a
          - us-central1-b
          - us-central1-c
```

**Note:** With `volumeBindingMode: Immediate`, topology constraints are critical because the volume is provisioned before pod scheduling. The Kubernetes scheduler must place pods in zones where volumes exist.

**Alternative:** Use node affinity on StatefulSet pods to match volume zones, or rely on GKE's automatic zone placement.

### Anti-Patterns to Avoid

- **Using WaitForFirstConsumer with StatefulSets expecting immediate binding:** Violates STOR-03, can cause startup delays or failures
- **Omitting reclaimPolicy: Retain:** Default policy may delete volumes when PVCs are deleted, causing data loss
- **Not setting allowVolumeExpansion:** Requires PV recreation to resize, causing downtime
- **Using volumeClaimTemplates in StatefulSet for single-instance databases:** More complex than standalone PVC for non-replicated workloads
- **Not validating zone topology:** Volumes provisioned in zones without nodes cause scheduling failures

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Dynamic volume provisioning | Custom PV creation scripts | GKE CSI driver with StorageClass | Handles zone placement, resizing, and lifecycle automatically |
| Volume backup/snapshot | Custom pg_dump cron scripts mounting PV | GKE Persistent Disk snapshots or CSI snapshots | Crash-consistent, incremental, fast recovery |
| Volume resize | Delete and recreate PV | allowVolumeExpansion in StorageClass | Zero-downtime expansion |
| Multi-zone replication | Custom replication logic | Regional persistent disks (regional-pd) | Automatic replication across zones |
| Storage monitoring | Custom disk usage scripts | GKE metrics + Kubernetes events | Built-in PVC status and volume metrics |

**Key insight:** GKE's CSI driver handles complex storage lifecycle operations. Attempting to manage PVs manually misses automated zone placement, resizing, and failure recovery. Use declarative StorageClass + PVC pattern.

## Common Pitfalls

### Pitfall 1: WaitForFirstConsumer Binding Mode with StatefulSets

**What goes wrong:** StatefulSet pods fail to start or get stuck in Pending state because volumes aren't provisioned until pod scheduling, but pod can't schedule without volume binding.

**Why it happens:** GKE's default storage classes use `WaitForFirstConsumer` to optimize zone placement. This works for Deployments but can create circular dependencies with StatefulSets that have strict volume requirements.

**How to avoid:** Create custom StorageClass with `volumeBindingMode: Immediate` and reference it in PVC specs.

**Warning signs:**
- PVC status remains "Pending" for extended period
- Pod events show "waiting for volume to be provisioned"
- StatefulSet replica count stuck at 0

### Pitfall 2: Zone Topology Mismatch

**What goes wrong:** PersistentVolume is created in zone A, but all GKE nodes are in zones B and C. Pod cannot schedule because no node has access to the volume.

**Why it happens:** With `volumeBindingMode: Immediate`, GKE provisions the volume in any available zone before knowing where the pod will run. If that zone has no nodes, the pod is unschedulable.

**How to avoid:**
1. Use `allowedTopologies` in StorageClass to restrict zones to those with nodes
2. Add node affinity to StatefulSet to prefer zones with volumes
3. Query cluster node zones before creating StorageClass

**Warning signs:**
- Pod status: "0/N nodes are available: N node(s) had volume node affinity conflict"
- PV exists but pod remains in Pending state
- kubectl describe pod shows volume zone mismatch

**Verification command:**
```bash
# List node zones
kubectl get nodes -o custom-columns=NAME:.metadata.name,ZONE:.metadata.labels.topology\.gke\.io/zone

# List PV zones
kubectl get pv -o custom-columns=NAME:.metadata.name,ZONE:.spec.nodeAffinity.required.nodeSelectorTerms
```

### Pitfall 3: Default Reclaim Policy Deletes Data

**What goes wrong:** Developer deletes PVC during troubleshooting, expecting to recreate it. PersistentVolume and underlying GCP persistent disk are immediately deleted, destroying all data.

**Why it happens:** Default reclaim policy in GKE storage classes is typically "Delete" to prevent orphaned resources. This is safe for stateless workloads but catastrophic for databases.

**How to avoid:** Set `reclaimPolicy: Retain` in custom StorageClass. This keeps the PV and underlying disk even if PVC is deleted. Manual cleanup required, but data is safe.

**Warning signs:**
- PVC deletion is instant (no time to recover)
- PV disappears from `kubectl get pv` immediately after PVC deletion
- GCP Console shows persistent disk is deleted

**Recovery:** None if disk is deleted. Prevention is critical.

### Pitfall 4: Exceeding Namespace Storage Quota

**What goes wrong:** PVC creation succeeds, but PVC remains in Pending state indefinitely with no error message in pod events.

**Why it happens:** Namespace ResourceQuota limits total storage requests. If creating a 10Gi PVC would exceed `requests.storage: 50Gi` quota, the PVC is blocked but error is only visible in PVC events, not pod events.

**How to avoid:** Verify namespace quota before creating PVCs. For this phase: 10Gi (postgres) + 1Gi (redis) = 11Gi, well under 50Gi quota.

**Warning signs:**
- `kubectl describe pvc` shows "exceeded quota" event
- PVC status stuck at Pending with no provisioning activity
- Multiple PVCs created but quota exhausted

**Verification command:**
```bash
kubectl get resourcequota -n firecrawl
kubectl describe resourcequota firecrawl-quota -n firecrawl
```

### Pitfall 5: Access Mode Mismatch

**What goes wrong:** PVC specifies ReadWriteMany (RWX) access mode, but GKE pd-standard/pd-ssd only support ReadWriteOnce (RWO). PVC creation fails or volume provisioning fails.

**Why it happens:** Developer assumes multiple pods need concurrent write access, but GKE block storage is single-writer by design.

**How to avoid:** Use `accessModes: [ReadWriteOnce]` for all GKE persistent disk PVCs. For multi-writer scenarios, use Filestore (NFS) or object storage.

**Warning signs:**
- PVC events show "failed to provision volume: access mode not supported"
- PVC stuck in Pending with provisioning error

## Code Examples

Verified patterns from Kubernetes and GKE documentation:

### Custom Immediate-Binding StorageClass

```yaml
# storage-class-immediate.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard-immediate
  labels:
    managed-by: argocd
provisioner: pd.csi.storage.gke.io
parameters:
  type: pd-standard
  fstype: ext4
volumeBindingMode: Immediate
reclaimPolicy: Retain
allowVolumeExpansion: true
allowedTopologies:
  - matchLabelExpressions:
      - key: topology.gke.io/zone
        values:
          - us-central1-a
          - us-central1-b
          - us-central1-c
```

**Note:** Replace zone values with actual client-cluster node zones. Verify with `kubectl get nodes -L topology.gke.io/zone`.

### Postgres PersistentVolumeClaim (10Gi)

```yaml
# pvc-postgres.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data
  namespace: firecrawl
  labels:
    app: postgres
    component: database
    managed-by: argocd
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: standard-immediate
  resources:
    requests:
      storage: 10Gi
```

**Key points:**
- `storageClassName: standard-immediate` matches custom StorageClass
- `storage: 10Gi` meets STOR-01 requirement
- Fits within namespace ResourceQuota (50Gi total, 20Gi max per PVC)

### Redis PersistentVolumeClaim (1Gi)

```yaml
# pvc-redis.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: redis-data
  namespace: firecrawl
  labels:
    app: redis
    component: cache
    managed-by: argocd
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: standard-immediate
  resources:
    requests:
      storage: 1Gi
```

**Key points:**
- `storage: 1Gi` meets STOR-02 requirement
- Same StorageClass as Postgres for consistency
- Minimal size (1Gi) sufficient for Redis AOF persistence

### Kustomization Integration

```yaml
# k8s/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - serviceaccounts.yaml
  - rbac.yaml
  - configmap-database.yaml
  - configmap-redis.yaml
  - configmap-application.yaml
  - storage-class-immediate.yaml
  - pvc-postgres.yaml
  - pvc-redis.yaml
  - api-deployment.yaml
  - ui-deployment.yaml
```

**Ordering note:** StorageClass must be created before PVCs reference it. Kustomize and Argo CD handle dependency ordering automatically, but manual kubectl apply requires correct order.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| In-tree volume plugins | CSI drivers | Kubernetes 1.13+ | GKE uses pd.csi.storage.gke.io, deprecated kubernetes.io/gce-pd |
| Static PV provisioning | Dynamic provisioning with StorageClass | Kubernetes 1.6+ | No manual PV creation needed |
| Fixed volume sizes | allowVolumeExpansion | Kubernetes 1.11+ | Zero-downtime resizing |
| Manual backup scripts | CSI VolumeSnapshots | Kubernetes 1.17+ | Crash-consistent snapshots via Kubernetes API |
| WaitForFirstConsumer everywhere | Immediate for specific workloads | Best practice evolution | Recognize StatefulSet binding requirements |

**Deprecated/outdated:**
- `kubernetes.io/gce-pd` provisioner - Use `pd.csi.storage.gke.io` instead (CSI migration complete in GKE 1.18+)
- `gcePersistentDisk` volume type in Pod specs - Use PVC + StorageClass pattern
- `storageclass.kubernetes.io/is-default-storage-class` annotation - GKE manages default storage class automatically

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | kubectl + bash validation scripts |
| Config file | none - shell scripts in .planning/phases/04-storage-layer/ |
| Quick run command | `kubectl get pvc -n firecrawl` |
| Full suite command | `bash .planning/phases/04-storage-layer/validate-storage.sh` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| STOR-01 | Postgres PVC created and bound (10Gi) | integration | `kubectl get pvc postgres-data -n firecrawl -o jsonpath='{.status.phase}' \| grep -q Bound` | ❌ Wave 0 |
| STOR-02 | Redis PVC created and bound (1Gi) | integration | `kubectl get pvc redis-data -n firecrawl -o jsonpath='{.status.phase}' \| grep -q Bound` | ❌ Wave 0 |
| STOR-03 | PVCs use immediate-binding storage class | unit | `kubectl get pvc -n firecrawl -o jsonpath='{.items[*].spec.storageClassName}' \| grep -q standard-immediate` | ❌ Wave 0 |
| STOR-04 | Reclaim policy is Retain | unit | `kubectl get sc standard-immediate -o jsonpath='{.reclaimPolicy}' \| grep -q Retain` | ❌ Wave 0 |
| STOR-05 | Volume topology validated against node zones | integration | Compare PV nodeAffinity zones with node zones | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `kubectl get pvc,sc -n firecrawl` (verify resources exist)
- **Per wave merge:** `bash .planning/phases/04-storage-layer/validate-storage.sh` (full validation)
- **Phase gate:** All PVCs in Bound state, reclaim policy Retain confirmed

### Wave 0 Gaps

- [ ] `validate-storage.sh` - Comprehensive validation script covering STOR-01 through STOR-05
  ```bash
  #!/bin/bash
  # Check PVC binding status
  # Verify storage class configuration
  # Validate zone topology match
  # Confirm reclaim policy
  ```
- [ ] Manual verification step: Query client-cluster node zones before defining allowedTopologies
  ```bash
  kubectl get nodes -o custom-columns=NAME:.metadata.name,ZONE:.metadata.labels.topology\\.gke\\.io/zone
  ```

## Sources

### Primary (HIGH confidence)

- Kubernetes Storage Documentation - kubernetes.io/docs/concepts/storage/
  - PersistentVolumes, PersistentVolumeClaims, StorageClasses
  - VolumeBindingMode options and behavior
  - Reclaim policies and lifecycle
- GKE Storage Documentation - cloud.google.com/kubernetes-engine/docs/concepts/persistent-volumes
  - Default storage classes and provisioners
  - CSI driver capabilities
  - Regional persistent disk options

### Secondary (MEDIUM confidence)

- Kubernetes API Reference - kubernetes.io/docs/reference/kubernetes-api/
  - StorageClass v1 API specification
  - PersistentVolumeClaim v1 API specification
- GKE Best Practices - cloud.google.com/kubernetes-engine/docs/best-practices
  - StatefulSet storage patterns
  - Zone topology considerations

### Tertiary (LOW confidence)

- Training data knowledge of GKE storage class names (standard-rwo, premium-rwo, balanced-rwo) - should be verified against actual client-cluster configuration
- Training data knowledge of default binding modes (WaitForFirstConsumer) - confirmed pattern but implementation details may vary by GKE version

## Open Questions

1. **What zones are nodes in client-cluster distributed across?**
   - What we know: GKE clusters typically span 3 zones in a region for high availability
   - What's unclear: Exact zone names for allowedTopologies configuration
   - Recommendation: Query cluster before creating StorageClass: `kubectl get nodes -L topology.gke.io/zone`

2. **Does client-cluster already have a custom immediate-binding storage class?**
   - What we know: GKE default storage classes use WaitForFirstConsumer
   - What's unclear: Whether cluster admin has already created custom storage classes
   - Recommendation: Check with `kubectl get storageclass` before creating; avoid name conflicts

3. **Should we use regional persistent disks for multi-zone replication?**
   - What we know: Regional PDs replicate data across zones automatically, higher availability but 2x cost
   - What's unclear: Whether single-zone disk with Retain policy is acceptable for v1
   - Recommendation: Use standard zonal disk for v1, document upgrade path to regional-pd

4. **What GKE cluster version is client-cluster running?**
   - What we know: CSI driver is standard in GKE 1.18+, CSI migration complete in 1.18+
   - What's unclear: Exact version, affects provisioner naming
   - Recommendation: Assume modern GKE (1.24+), use pd.csi.storage.gke.io provisioner

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Kubernetes storage APIs are stable, GKE CSI driver is well-documented
- Architecture: MEDIUM-HIGH - Immediate binding pattern is less common but well-understood, zone topology needs cluster-specific verification
- Pitfalls: HIGH - WaitForFirstConsumer issues, reclaim policy dangers, and zone mismatches are well-documented gotchas

**Research date:** 2026-03-27
**Valid until:** 90 days (Kubernetes storage APIs are stable, GKE provisioner patterns rarely change)

**Notes:**
- Zone topology verification is CRITICAL before StorageClass creation
- Reclaim policy Retain is non-negotiable for production databases
- Consider creating validation script in Wave 0 to verify PVC binding and zone placement
