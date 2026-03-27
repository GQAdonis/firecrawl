---
phase: 03-foundation-resources
plan: 01
subsystem: kubernetes-foundation
tags: [namespace, rbac, resource-governance, serviceaccounts]
dependency_graph:
  requires: [02-01]
  provides: [firecrawl-namespace, resource-quotas, serviceaccounts, rbac-roles]
  affects: [03-02, 04-01, 05-01, 06-01]
tech_stack:
  added: []
  patterns: [namespace-isolation, least-privilege-rbac, resource-governance]
key_files:
  created:
    - k8s/base/namespace.yaml
    - k8s/base/serviceaccounts.yaml
    - k8s/base/rbac.yaml
  modified:
    - k8s/base/kustomization.yaml
decisions:
  - "ResourceQuota limits: 10 CPU requests, 20Gi memory requests, 40Gi memory limits, 50 pods"
  - "LimitRange defaults: 1 CPU, 2Gi memory per container; max 4 CPU, 8Gi per container"
  - "ServiceAccount token automount: true for api and worker (ConfigMap access), false for ui and playwright (no K8s API needed)"
  - "RBAC: Single Role with read-only ConfigMap permissions, bound only to api and worker ServiceAccounts"
metrics:
  duration_seconds: 89
  tasks_completed: 2
  files_created: 3
  files_modified: 1
  commits: 2
  completed_at: "2026-03-27T19:48:21Z"
---

# Phase 03 Plan 01: Foundation Resources Summary

**Firecrawl namespace with resource governance, ServiceAccounts, and least-privilege RBAC established**

## Overview

Created the `firecrawl` namespace with ResourceQuota and LimitRange for resource governance, four ServiceAccounts for workload identity (api, worker, ui, playwright), and RBAC roles with least-privilege permissions (read-only ConfigMap access for api and worker only).

## What Was Built

### Namespace with Resource Governance
- **Namespace**: `firecrawl` with labels `managed-by: argocd` and `environment: production`
- **ResourceQuota**: Limits namespace-level resource consumption
  - CPU: 10 requests, 20 limits
  - Memory: 20Gi requests, 40Gi limits
  - Storage: 50Gi total, 5 PVCs max
  - Objects: 50 pods, 10 services, 20 configmaps, 20 secrets
- **LimitRange**: Provides pod-level defaults and constraints
  - Container defaults: 1 CPU, 2Gi memory
  - Container requests: 100m CPU, 256Mi memory
  - Container max: 4 CPU, 8Gi memory
  - Pod max: 8 CPU, 16Gi memory
  - PVC range: 1Gi min, 20Gi max

### ServiceAccounts for Workload Identity
Created 4 ServiceAccounts with appropriate token mount settings:
- **firecrawl-api**: `automountServiceAccountToken: true` (needs ConfigMap access)
- **firecrawl-worker**: `automountServiceAccountToken: true` (needs ConfigMap access)
- **firecrawl-ui**: `automountServiceAccountToken: false` (frontend, no K8s API access)
- **firecrawl-playwright**: `automountServiceAccountToken: false` (browser service, no K8s API access)

### RBAC with Least-Privilege Permissions
- **Role**: `firecrawl-configmap-reader` - read-only access to ConfigMaps (get, list, watch verbs)
- **RoleBindings**: Bound only to `firecrawl-api` and `firecrawl-worker` ServiceAccounts
- **Security posture**: UI and playwright have no K8s API permissions (secure default)

### Kustomize Integration
Updated `k8s/base/kustomization.yaml` to include:
1. namespace.yaml (first - must exist before other resources)
2. serviceaccounts.yaml
3. rbac.yaml
4. api-deployment.yaml (existing)
5. ui-deployment.yaml (existing)

Kustomize validation passes: `kubectl kustomize k8s/base/` produces valid output with all resources.

## Tasks Completed

| Task | Status | Commit | Files |
|------|--------|--------|-------|
| Task 1: Create namespace with ResourceQuota and LimitRange | ✅ Complete | eddfc78e | k8s/base/namespace.yaml |
| Task 2: Create ServiceAccounts, RBAC, and update kustomization.yaml | ✅ Complete | 99dbf0d2 | k8s/base/serviceaccounts.yaml, k8s/base/rbac.yaml, k8s/base/kustomization.yaml |

## Deviations from Plan

None - plan executed exactly as written.

## Key Decisions Made

1. **Resource limits sized with 2x headroom**: ResourceQuota limits account for rolling updates (old and new pods running simultaneously) and provide buffer for temporary spikes. Can be tuned after observing actual usage in Phase 6.

2. **Least-privilege RBAC**: Only api and worker get ConfigMap read access. UI and playwright have no K8s permissions, following secure-by-default principle. This reduces blast radius if pod is compromised.

3. **automountServiceAccountToken differentiation**: Set `true` for api/worker (may need ConfigMap access), `false` for ui/playwright (no K8s API access needed). Reduces unnecessary attack surface.

4. **Namespace-first ordering in kustomization**: Listed namespace.yaml first in resources to ensure namespace exists before ServiceAccounts and RBAC resources that reference it.

## Integration Points

### Upstream Dependencies (Complete)
- Phase 02-01: Argo CD Application manifest points to k8s/base/ directory

### Downstream Consumers (Unblocked)
- Phase 03-02: ConfigMaps and Secrets will be created in firecrawl namespace
- Phase 04-01: StorageClass will be available for PVCs within ResourceQuota limits
- Phase 05-01: PostgreSQL and Redis StatefulSets will use firecrawl namespace and ServiceAccounts
- Phase 06-01: Application Deployments will reference ServiceAccounts and run within LimitRange constraints
- Phase 07-01: HTTPRoutes will route to Services in firecrawl namespace

## Technical Artifacts

### Files Created
```
k8s/base/namespace.yaml (56 lines)
  - Namespace: firecrawl
  - ResourceQuota: firecrawl-quota (CPU/memory/storage/object count limits)
  - LimitRange: firecrawl-limits (container/pod/PVC constraints)

k8s/base/serviceaccounts.yaml (42 lines)
  - ServiceAccount: firecrawl-api (automountServiceAccountToken: true)
  - ServiceAccount: firecrawl-worker (automountServiceAccountToken: true)
  - ServiceAccount: firecrawl-ui (automountServiceAccountToken: false)
  - ServiceAccount: firecrawl-playwright (automountServiceAccountToken: false)

k8s/base/rbac.yaml (34 lines)
  - Role: firecrawl-configmap-reader (read-only ConfigMap access)
  - RoleBinding: firecrawl-api-configmap-binding
  - RoleBinding: firecrawl-worker-configmap-binding
```

### Files Modified
```
k8s/base/kustomization.yaml
  - Added namespace.yaml to resources (first position)
  - Added serviceaccounts.yaml to resources
  - Added rbac.yaml to resources
  - Retained existing api-deployment.yaml and ui-deployment.yaml
  - Retained existing images section
```

## Verification Results

### Task 1 Verification (PASSED)
```bash
grep -c "kind:" k8s/base/namespace.yaml | grep -q "3"  # 3 resources
grep "name: firecrawl" k8s/base/namespace.yaml        # Namespace name
grep "requests.cpu" k8s/base/namespace.yaml           # ResourceQuota
grep "type: Container" k8s/base/namespace.yaml        # LimitRange
```

### Task 2 Verification (PASSED)
```bash
grep -c "kind: ServiceAccount" k8s/base/serviceaccounts.yaml | grep -q "4"  # 4 ServiceAccounts
grep "firecrawl-api" k8s/base/serviceaccounts.yaml                          # API ServiceAccount
grep "kind: Role" k8s/base/rbac.yaml                                        # Role exists
grep "firecrawl-configmap-reader" k8s/base/rbac.yaml                        # Role name
grep "namespace.yaml" k8s/base/kustomization.yaml                           # Added to resources
grep "rbac.yaml" k8s/base/kustomization.yaml                                # Added to resources
```

### Overall Verification (PASSED)
```bash
kubectl kustomize k8s/base/  # Produces valid YAML with all resources (Namespace, ResourceQuota, LimitRange, ServiceAccounts, Role, RoleBindings, Deployments)
```

All acceptance criteria met:
- ✅ namespace.yaml contains exactly 3 `kind:` entries
- ✅ Namespace has `name: firecrawl` and `managed-by: argocd` label
- ✅ ResourceQuota contains CPU (10/20), memory (20Gi/40Gi), storage (50Gi), pods (50)
- ✅ LimitRange contains Container defaults (1 CPU, 2Gi memory) and max (4 CPU, 8Gi memory)
- ✅ LimitRange contains PersistentVolumeClaim max (20Gi)
- ✅ serviceaccounts.yaml contains exactly 4 ServiceAccounts
- ✅ ServiceAccounts named: firecrawl-api, firecrawl-worker, firecrawl-ui, firecrawl-playwright
- ✅ automountServiceAccountToken: false for ui and playwright
- ✅ automountServiceAccountToken: true for api and worker
- ✅ rbac.yaml contains Role `firecrawl-configmap-reader`
- ✅ Role has verbs ["get", "list", "watch"] and resources ["configmaps"]
- ✅ rbac.yaml contains 2 RoleBindings for api and worker
- ✅ kustomization.yaml includes namespace.yaml, serviceaccounts.yaml, rbac.yaml
- ✅ kustomization.yaml retains api-deployment.yaml and ui-deployment.yaml
- ✅ kustomization.yaml retains images section

## Success Criteria Met

All Phase 03 Plan 01 requirements satisfied:

- ✅ **FOUND-01**: firecrawl namespace created with ResourceQuota (10 CPU requests, 20Gi memory requests, 40Gi memory limits, 50 pods) and LimitRange (1 CPU, 2Gi memory container defaults; 4 CPU, 8Gi memory container max)
- ✅ **FOUND-02**: ServiceAccounts created for all workload types (api, worker, ui, playwright) with appropriate token mount settings
- ✅ **FOUND-03**: RBAC roles configured following least-privilege (read-only ConfigMap access, only for api and worker ServiceAccounts)

## Next Steps

1. **Phase 03 Plan 02** (if exists): Create ConfigMaps for database, redis, and application configuration
2. **Manual Secret Creation**: Follow runbook in `.planning/phases/03-foundation-resources/03-RESEARCH.md` (Pattern 5) to manually create secrets via kubectl before deploying applications
3. **Argo CD Sync**: After Phase 03 completes, Argo CD will sync namespace, ServiceAccounts, and RBAC to cluster (Application should move from OutOfSync to Synced status)

## Commits

- `eddfc78e`: feat(03-foundation-resources-01): create firecrawl namespace with resource governance
- `99dbf0d2`: feat(03-foundation-resources-01): create ServiceAccounts and RBAC with least-privilege

## Self-Check: PASSED

### Created Files Verification
```bash
[ -f "k8s/base/namespace.yaml" ] && echo "FOUND: k8s/base/namespace.yaml" || echo "MISSING: k8s/base/namespace.yaml"
[ -f "k8s/base/serviceaccounts.yaml" ] && echo "FOUND: k8s/base/serviceaccounts.yaml" || echo "MISSING: k8s/base/serviceaccounts.yaml"
[ -f "k8s/base/rbac.yaml" ] && echo "FOUND: k8s/base/rbac.yaml" || echo "MISSING: k8s/base/rbac.yaml"
```

Result:
- ✅ FOUND: k8s/base/namespace.yaml
- ✅ FOUND: k8s/base/serviceaccounts.yaml
- ✅ FOUND: k8s/base/rbac.yaml

### Commit Hash Verification
```bash
git log --oneline --all | grep -q "eddfc78e" && echo "FOUND: eddfc78e" || echo "MISSING: eddfc78e"
git log --oneline --all | grep -q "99dbf0d2" && echo "FOUND: 99dbf0d2" || echo "MISSING: 99dbf0d2"
```

Result:
- ✅ FOUND: eddfc78e
- ✅ FOUND: 99dbf0d2

All artifacts verified. Plan execution complete.
