# Requirements: Firecrawl GKE Deployment Automation

**Defined:** 2026-03-27
**Core Value:** Deployments are automated, auditable, and easy to rollback

## v1 Requirements

Requirements for GitOps deployment automation to GKE client-cluster.

### CI Pipeline

- [x] **CI-01**: GitHub Actions workflow triggers on push to main branch
- [x] **CI-02**: Workflow builds Docker images for firecrawl-api and ingestion-ui
- [x] **CI-03**: Images tagged with 7-character Git SHA (immutable tags)
- [x] **CI-04**: Images pushed to Google Container Registry in prometheus-461323 project
- [x] **CI-05**: Workflow verifies image availability in GCR before manifest updates
- [x] **CI-06**: Workflow updates k8s/ manifests with new image tags
- [x] **CI-07**: Workflow commits manifest changes with [skip ci] to prevent loops
- [x] **CI-08**: Workflow uses Workload Identity Federation for GCP authentication

### GitOps Automation

- [ ] **GITOPS-01**: Argo CD Application manifest points to firecrawl k8s/ directory
- [ ] **GITOPS-02**: Argo CD automatically syncs manifest changes to cluster
- [ ] **GITOPS-03**: Argo CD prunes deleted resources automatically
- [ ] **GITOPS-04**: Argo CD self-heals manual cluster changes
- [ ] **GITOPS-05**: Argo CD monitors health of all deployed resources
- [ ] **GITOPS-06**: Deployment status visible in Argo CD dashboard
- [ ] **GITOPS-07**: Rollback possible via git revert + Argo CD sync

### Foundation

- [ ] **FOUND-01**: firecrawl namespace created with resource quotas
- [ ] **FOUND-02**: ServiceAccounts created for application pods
- [ ] **FOUND-03**: RBAC roles configured for service accounts
- [ ] **FOUND-04**: ConfigMaps created for application configuration
- [ ] **FOUND-05**: Secrets created manually via kubectl (not committed to Git)
- [ ] **FOUND-06**: Required secrets include database passwords and API keys

### Storage

- [ ] **STOR-01**: PersistentVolumeClaim created for Postgres (10Gi)
- [ ] **STOR-02**: PersistentVolumeClaim created for Redis (1Gi)
- [ ] **STOR-03**: PVCs use immediate-binding storage class
- [ ] **STOR-04**: PersistentVolume reclaim policy set to Retain
- [ ] **STOR-05**: Volume topology validated against node zones

### Data Layer

- [ ] **DATA-01**: Postgres StatefulSet deployed with PVC mount
- [ ] **DATA-02**: Postgres has memory and CPU resource limits configured
- [ ] **DATA-03**: Postgres has readiness and liveness probes configured
- [ ] **DATA-04**: Redis StatefulSet deployed with PVC mount
- [ ] **DATA-05**: Redis has memory and CPU resource limits configured
- [ ] **DATA-06**: Redis has readiness and liveness probes configured
- [ ] **DATA-07**: Kubernetes Services created for Postgres and Redis
- [ ] **DATA-08**: CronJob created for Postgres pg_dump backups to GCS (every 6 hours)
- [ ] **DATA-09**: Backup restoration procedure documented

### Application Layer

- [ ] **APP-01**: Firecrawl API Deployment created
- [ ] **APP-02**: API has memory and CPU resource limits configured
- [ ] **APP-03**: API has Node.js --max-old-space-size set to 85% of memory limit
- [ ] **APP-04**: API has readiness and liveness probes configured
- [ ] **APP-05**: API has init container that waits for Postgres/Redis readiness
- [ ] **APP-06**: Worker Deployments created (extract, nuq, prefetch workers)
- [ ] **APP-07**: Workers have memory and CPU resource limits configured
- [ ] **APP-08**: Workers have Node.js --max-old-space-size set to 85% of memory limit
- [ ] **APP-09**: Workers have readiness and liveness probes configured
- [ ] **APP-10**: Workers have init containers that wait for Postgres/Redis readiness
- [ ] **APP-11**: Ingestion UI Deployment created
- [ ] **APP-12**: UI has memory and CPU resource limits configured
- [ ] **APP-13**: UI has readiness and liveness probes configured
- [ ] **APP-14**: Playwright Deployment created for browser automation
- [ ] **APP-15**: Playwright has memory and CPU resource limits configured
- [ ] **APP-16**: Kubernetes Services created for all application components

### External Access

- [ ] **ROUTE-01**: HTTPRoute created for API at firecrawl-api.prometheusags.ai
- [ ] **ROUTE-02**: HTTPRoute created for UI at firecrawl.prometheusags.ai
- [ ] **ROUTE-03**: HTTPRoutes use existing Envoy Gateway installation
- [ ] **ROUTE-04**: TLS certificate cloned from candle-vllm secret
- [ ] **ROUTE-05**: HTTPRoutes configured with TLS termination
- [ ] **ROUTE-06**: HTTPRoutes configured with HTTP to HTTPS redirect
- [ ] **ROUTE-07**: Backend services use HTTP internally (TLS terminates at Gateway)
- [ ] **ROUTE-08**: External connectivity validated from internet

## v2 Requirements

Deferred to future iterations. Tracked but not in current roadmap.

### Operational Excellence

- **OPS-01**: Slack/email notifications for deployment events
- **OPS-02**: Argo CD sync wave annotations for strict ordering
- **OPS-03**: Pod disruption budgets for high availability
- **OPS-04**: Image vulnerability scanning in CI pipeline
- **OPS-05**: Horizontal pod autoscaling based on CPU/memory
- **OPS-06**: Blue-green or canary deployment strategies
- **OPS-07**: Log aggregation beyond existing Sentry integration
- **OPS-08**: Custom metrics dashboards for deployment monitoring
- **OPS-09**: Automated database backup verification testing
- **OPS-10**: Multi-environment support (dev/staging/prod)

## Out of Scope

Explicitly excluded from v1. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Multi-cluster deployment | Single production cluster initially per PROJECT.md |
| Service mesh (Istio/Linkerd) | Envoy Gateway sufficient for routing, no need for full mesh |
| External secret management (Vault) | Kubernetes Secrets sufficient for v1 |
| GitOps with separate manifest repo | Monorepo approach simpler per PROJECT.md decision |
| Helm charts | Kustomize simpler for single environment per research recommendation |
| Manual kubectl deployments | Violates GitOps principles per research anti-patterns |
| Mutable image tags (latest, main) | Non-deterministic deployments per research anti-patterns |
| Secrets committed to Git | Security risk even if base64 per research anti-patterns |
| Direct cluster access from CI | Violates GitOps separation per research architecture |
## Traceability

Which phases cover which requirements. Updated during roadmap creation.

**Coverage:**
- v1 requirements: 61 total
- Mapped to phases: 61/61 (100%)
- Unmapped: 0

| Requirement | Phase | Status |
|-------------|-------|--------|
| CI-01 | Phase 1 | Complete |
| CI-02 | Phase 1 | Complete |
| CI-03 | Phase 1 | Complete |
| CI-04 | Phase 1 | Complete |
| CI-05 | Phase 1 | Complete |
| CI-06 | Phase 1 | Complete |
| CI-07 | Phase 1 | Complete |
| CI-08 | Phase 1 | Complete |
| GITOPS-01 | Phase 2 | Pending |
| GITOPS-02 | Phase 2 | Pending |
| GITOPS-03 | Phase 2 | Pending |
| GITOPS-04 | Phase 2 | Pending |
| GITOPS-05 | Phase 2 | Pending |
| GITOPS-06 | Phase 2 | Pending |
| GITOPS-07 | Phase 2 | Pending |
| FOUND-01 | Phase 3 | Pending |
| FOUND-02 | Phase 3 | Pending |
| FOUND-03 | Phase 3 | Pending |
| FOUND-04 | Phase 3 | Pending |
| FOUND-05 | Phase 3 | Pending |
| FOUND-06 | Phase 3 | Pending |
| STOR-01 | Phase 4 | Pending |
| STOR-02 | Phase 4 | Pending |
| STOR-03 | Phase 4 | Pending |
| STOR-04 | Phase 4 | Pending |
| STOR-05 | Phase 4 | Pending |
| DATA-01 | Phase 5 | Pending |
| DATA-02 | Phase 5 | Pending |
| DATA-03 | Phase 5 | Pending |
| DATA-04 | Phase 5 | Pending |
| DATA-05 | Phase 5 | Pending |
| DATA-06 | Phase 5 | Pending |
| DATA-07 | Phase 5 | Pending |
| DATA-08 | Phase 5 | Pending |
| DATA-09 | Phase 5 | Pending |
| APP-01 | Phase 6 | Pending |
| APP-02 | Phase 6 | Pending |
| APP-03 | Phase 6 | Pending |
| APP-04 | Phase 6 | Pending |
| APP-05 | Phase 6 | Pending |
| APP-06 | Phase 6 | Pending |
| APP-07 | Phase 6 | Pending |
| APP-08 | Phase 6 | Pending |
| APP-09 | Phase 6 | Pending |
| APP-10 | Phase 6 | Pending |
| APP-11 | Phase 6 | Pending |
| APP-12 | Phase 6 | Pending |
| APP-13 | Phase 6 | Pending |
| APP-14 | Phase 6 | Pending |
| APP-15 | Phase 6 | Pending |
| APP-16 | Phase 6 | Pending |
| ROUTE-01 | Phase 7 | Pending |
| ROUTE-02 | Phase 7 | Pending |
| ROUTE-03 | Phase 7 | Pending |
| ROUTE-04 | Phase 7 | Pending |
| ROUTE-05 | Phase 7 | Pending |
| ROUTE-06 | Phase 7 | Pending |
| ROUTE-07 | Phase 7 | Pending |
| ROUTE-08 | Phase 7 | Pending |

---
*Requirements defined: 2026-03-27*
*Last updated: 2026-03-27 after roadmap creation*
