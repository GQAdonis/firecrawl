# Roadmap: Firecrawl GKE Deployment Automation

**Project:** Firecrawl GKE Deployment Automation
**Core Value:** Deployments are automated, auditable, and easy to rollback
**Created:** 2026-03-27
**Status:** Planning

## Overview

This roadmap delivers a production-ready GitOps deployment pipeline for Firecrawl on Google Kubernetes Engine. The architecture follows a pull-based model where GitHub Actions builds and publishes container images, then commits updated manifests to Git. Argo CD continuously monitors the repository and automatically syncs changes to the cluster. All services deploy to a dedicated firecrawl namespace with external access via Envoy Gateway HTTPRoutes.

**Phases:** 7
**Granularity:** Standard
**Coverage:** 61/61 v1 requirements mapped

## Phases

- [x] **Phase 1: CI/CD Pipeline Foundation** - Automated image builds and manifest updates (completed 2026-03-27)
- [x] **Phase 2: Argo CD Integration** - GitOps continuous deployment setup (completed 2026-03-27)
- [ ] **Phase 3: Foundation Resources** - Namespace, RBAC, ConfigMaps, Secrets
- [ ] **Phase 4: Storage Layer** - Persistent volumes for stateful services
- [ ] **Phase 5: Data Layer** - Postgres and Redis StatefulSets with backups
- [ ] **Phase 6: Application Layer** - API, Workers, UI, and Playwright deployments
- [ ] **Phase 7: External Access** - HTTPRoutes with TLS termination

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. CI/CD Pipeline Foundation | 2/2 | Complete    | 2026-03-27 |
| 2. Argo CD Integration | 1/1 | Complete    | 2026-03-27 |
| 3. Foundation Resources | 0/? | Not started | - |
| 4. Storage Layer | 0/? | Not started | - |
| 5. Data Layer | 0/? | Not started | - |
| 6. Application Layer | 0/? | Not started | - |
| 7. External Access | 0/? | Not started | - |

## Phase Details

### Phase 1: CI/CD Pipeline Foundation

**Goal:** Automated image builds with immutable tags and manifest updates committed to Git

**Depends on:** Nothing (first phase)

**Requirements:** CI-01, CI-02, CI-03, CI-04, CI-05, CI-06, CI-07, CI-08

**Success Criteria** (what must be TRUE):
1. Push to main branch triggers GitHub Actions workflow automatically
2. Workflow builds Docker images for firecrawl-api and ingestion-ui successfully
3. Images are tagged with 7-character Git SHA (immutable, auditable)
4. Images are pushed to Google Container Registry in prometheus-461323 project
5. Workflow verifies image availability in GCR before updating manifests
6. Workflow updates k8s/ manifests with new image tags automatically
7. Manifest changes are committed back to main with [skip ci] to prevent loops
8. Workflow authenticates to GCP using Workload Identity Federation (no long-lived keys)

**Plans:** 2/2 plans complete

Plans:
- [ ] 01-01-PLAN.md -- Foundation files: ingestion-ui Dockerfile + k8s/base Kustomize structure
- [ ] 01-02-PLAN.md -- GitHub Actions CI workflow with WIF auth and manifest updates

**Research Note:** Standard patterns, skip phase research. GitHub Actions + GCR integration is well-documented.

---

### Phase 2: Argo CD Integration

**Goal:** GitOps continuous deployment that automatically syncs manifest changes to cluster

**Depends on:** Phase 1 (manifests must exist and be updated automatically)

**Requirements:** GITOPS-01, GITOPS-02, GITOPS-03, GITOPS-04, GITOPS-05, GITOPS-06, GITOPS-07

**Success Criteria** (what must be TRUE):
1. Argo CD Application manifest exists and points to firecrawl k8s/ directory
2. Argo CD automatically syncs manifest changes to cluster within 3 minutes
3. Argo CD prunes deleted resources automatically
4. Argo CD self-heals manual cluster changes back to Git state
5. Argo CD monitors health of all deployed resources
6. Deployment status is visible in Argo CD dashboard
7. Rollback is possible via git revert + Argo CD sync

**Plans:** 1/1 plans complete

Plans:
- [ ] 02-01-PLAN.md -- Argo CD Application manifest with automated sync, prune, and self-heal

**Research Note:** Standard patterns, skip phase research. Argo CD Application spec is straightforward.

---

### Phase 3: Foundation Resources

**Goal:** Configuration foundation with namespace isolation, RBAC, and secure secrets management

**Depends on:** Phase 2 (Argo CD must be configured to deploy resources)

**Requirements:** FOUND-01, FOUND-02, FOUND-03, FOUND-04, FOUND-05, FOUND-06

**Success Criteria** (what must be TRUE):
1. firecrawl namespace exists with resource quotas configured
2. ServiceAccounts are created for application pods
3. RBAC roles are configured for service accounts
4. ConfigMaps contain externalized application configuration
5. Secrets are created manually via kubectl (not committed to Git)
6. All required secrets exist including database passwords and API keys

**Plans:** TBD

**Research Note:** Standard patterns, skip phase research. Basic Kubernetes resources.

---

### Phase 4: Storage Layer

**Goal:** Persistent storage provisioned and bound for stateful services

**Depends on:** Phase 3 (namespace must exist for PVC creation)

**Requirements:** STOR-01, STOR-02, STOR-03, STOR-04, STOR-05

**Success Criteria** (what must be TRUE):
1. PersistentVolumeClaim for Postgres (10Gi) is created and bound
2. PersistentVolumeClaim for Redis (1Gi) is created and bound
3. PVCs use immediate-binding storage class
4. PersistentVolume reclaim policy is set to Retain
5. Volume topology is validated against node zones

**Plans:** TBD

**Research Note:** Needs validation. GKE-specific storage class configuration requires verification against client-cluster setup.

---

### Phase 5: Data Layer

**Goal:** Postgres and Redis are running, healthy, and accepting connections with backup strategy

**Depends on:** Phase 4 (PVCs must be bound before StatefulSets deploy)

**Requirements:** DATA-01, DATA-02, DATA-03, DATA-04, DATA-05, DATA-06, DATA-07, DATA-08, DATA-09

**Success Criteria** (what must be TRUE):
1. Postgres StatefulSet is deployed with PVC mount and resource limits
2. Postgres has readiness and liveness probes configured and passing
3. Redis StatefulSet is deployed with PVC mount and resource limits
4. Redis has readiness and liveness probes configured and passing
5. Kubernetes Services exist for Postgres and Redis with internal DNS resolution
6. CronJob is created for Postgres pg_dump backups to GCS (every 6 hours)
7. Backup restoration procedure is documented
8. Application pods can connect to Postgres and Redis using service DNS names

**Plans:** TBD

**Research Note:** Standard patterns, skip phase research. StatefulSet + Service configuration is well-documented.

---

### Phase 6: Application Layer

**Goal:** All application services (API, workers, UI, Playwright) are running and healthy

**Depends on:** Phase 5 (Postgres and Redis must be healthy before application starts)

**Requirements:** APP-01, APP-02, APP-03, APP-04, APP-05, APP-06, APP-07, APP-08, APP-09, APP-10, APP-11, APP-12, APP-13, APP-14, APP-15, APP-16

**Success Criteria** (what must be TRUE):
1. Firecrawl API Deployment is running with resource limits and health probes
2. API has Node.js --max-old-space-size set to 85% of memory limit
3. API has init container that waits for Postgres/Redis readiness before starting
4. Worker Deployments (extract, nuq, prefetch) are running with resource limits
5. Workers have Node.js --max-old-space-size configured properly
6. Workers have init containers that wait for dependencies
7. Ingestion UI Deployment is running with resource limits and health probes
8. Playwright Deployment is running with resource limits for browser automation
9. Kubernetes Services exist for all application components
10. Application pods can process requests without crashing

**Plans:** TBD

**Research Note:** Needs validation. BullMQ worker configuration, Redis connection pool sizing, and resource limit tuning require load testing.

---

### Phase 7: External Access

**Goal:** External traffic reaches application via HTTPS with TLS termination at Envoy Gateway

**Depends on:** Phase 6 (Services must exist and be healthy before HTTPRoutes)

**Requirements:** ROUTE-01, ROUTE-02, ROUTE-03, ROUTE-04, ROUTE-05, ROUTE-06, ROUTE-07, ROUTE-08

**Success Criteria** (what must be TRUE):
1. HTTPRoute exists for API at firecrawl-api.prometheusags.ai
2. HTTPRoute exists for UI at firecrawl.prometheusags.ai
3. HTTPRoutes use existing Envoy Gateway installation
4. TLS certificate is cloned from candle-vllm secret
5. HTTPRoutes are configured with TLS termination
6. HTTPRoutes are configured with HTTP to HTTPS redirect
7. Backend services use HTTP internally (TLS terminates at Gateway)
8. External connectivity is validated from internet to both domains

**Plans:** TBD

**Research Note:** Needs validation. Envoy Gateway HTTPRoute configuration specific to client-cluster requires verification.

---

## Dependencies

```
Phase 1 (CI/CD Pipeline Foundation)
  |
Phase 2 (Argo CD Integration)
  |
Phase 3 (Foundation Resources)
  |
Phase 4 (Storage Layer)
  |
Phase 5 (Data Layer)
  |
Phase 6 (Application Layer)
  |
Phase 7 (External Access)
```

## Notes

**Critical Path:** This is a strictly sequential roadmap. Each phase depends on successful completion of the previous phase. StatefulSets must be healthy before Deployments start. Storage must bind before StatefulSets deploy. The CI pipeline must be correct from day one because mutable tags create silent failures.

**Research Flags:** Phases 4, 6, and 7 have "needs validation" flags for cluster-specific configuration details that should be investigated during planning.

**Anti-Patterns Avoided:**
- No mutable image tags (latest, main) - using Git SHA for immutability
- No secrets in Git - manual kubectl creation only
- No horizontal layers - each phase delivers complete capability
- No cluster access from CI - GitOps pull model only

---

*Last updated: 2026-03-27*
