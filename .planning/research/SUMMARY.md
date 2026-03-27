# Project Research Summary

**Project:** Firecrawl GKE Deployment Automation
**Domain:** Kubernetes GitOps Deployment Pipeline
**Researched:** 2026-03-27
**Confidence:** MEDIUM

## Executive Summary

This project implements a production-ready GitOps deployment pipeline for Firecrawl (a web scraping API) on Google Kubernetes Engine (GKE). The recommended approach follows a pull-based GitOps model where GitHub Actions builds and publishes container images, then commits updated manifests to Git. Argo CD (already installed in the cluster) continuously monitors the Git repository and automatically syncs changes to the cluster. This architecture separates concerns cleanly: CI builds artifacts, CD deploys them, and Git serves as the single source of truth.

The core stack is intentionally minimal and leverages existing cluster infrastructure. GitHub Actions handles CI, Google Container Registry stores images, Kustomize manages manifests, and Argo CD orchestrates deployments. Envoy Gateway (already deployed) provides ingress routing via HTTPRoutes. The architecture avoids unnecessary complexity—no Helm charts, no external secret managers, and no service mesh for v1. This simplicity reduces operational burden while maintaining production-grade reliability.

The primary risks center on configuration correctness rather than architectural complexity. Critical pitfalls include using mutable image tags (breaks auditability), race conditions between image pushes and manifest updates, StatefulSet volume binding failures due to zone constraints, and missing resource limits causing node exhaustion. Prevention strategies include immutable SHA-based image tags, verification loops in CI, immediate-binding storage classes, and mandatory resource limits on all pods. With proper configuration, the deployment workflow completes in approximately 15 minutes from code push to live traffic.

## Key Findings

### Recommended Stack

The stack builds on existing infrastructure rather than introducing new components. Argo CD and Envoy Gateway are already installed in the cluster—the deployment pipeline integrates with these rather than replacing them. GitHub Actions provides the CI layer without requiring a separate server. Google Container Registry offers native GCP integration. Kustomize handles manifest management using native Kubernetes tooling, avoiding Helm's templating complexity.

**Core technologies:**
- **GitHub Actions (SaaS):** CI orchestration — native GitHub integration, builds images and updates manifests
- **Argo CD v2.10+:** GitOps continuous deployment — already installed, declarative sync from Git to cluster
- **Google Container Registry (GCR):** Container image storage — native GCP integration with prometheus-461323 project
- **Kustomize v5.3+ (built into kubectl):** Manifest templating — simpler than Helm for single-environment, native K8s tooling
- **Envoy Gateway (existing):** Ingress/routing — already deployed, HTTPRoute configuration for external access
- **Docker Buildx v0.12+:** Multi-platform image builds — standard for optimized container builds with layer caching

**Image tagging strategy:**
- Use short Git SHA (7 characters) as primary tag: `firecrawl-api:abc1234`
- Immutable tags enable auditability, rollbacks, and prevent GitOps sync detection failures
- Never use `latest` or `main` tags in production

### Expected Features

The feature landscape divides into three tiers: table stakes (production-critical), differentiators (operational excellence), and anti-features (explicitly avoided patterns). Phase 1 focuses on core GitOps pipeline and automated sync. Phase 2 adds production readiness through resource limits, persistent storage, health checks, and TLS termination. Phase 3 and beyond address operational excellence features that improve observability but aren't critical for launch.

**Must have (table stakes):**
- Automated manifest updates — CI writes new image tags after build
- Declarative configuration — all cluster state defined in Git
- Automated sync to cluster — Argo CD watches repo and deploys changes
- Health checks — Argo CD monitors deployment success/failure
- Rollback capability — git revert + Argo CD sync
- Resource limits — CPU/memory constraints prevent node exhaustion
- Persistent storage — StatefulSets with PVCs for Postgres/Redis
- Readiness/liveness probes — traffic routing and auto-restart
- TLS termination — HTTPS via Envoy Gateway HTTPRoutes
- Namespace isolation — dedicated firecrawl namespace
- Service discovery — Kubernetes Services for internal communication
- Secrets management — Kubernetes Secrets (base64, not in Git)

**Should have (competitive):**
- Sync status notifications — webhooks to Slack/email for deployment alerts
- Diff preview — Argo CD UI shows changes before sync
- Prune resources — auto-cleanup of deleted manifests
- Self-heal — auto-revert manual cluster changes
- Init containers — database migrations before app starts
- Pod disruption budgets — maintain availability during rolling updates
- Image vulnerability scanning — Trivy in CI pipeline

**Defer (v2+):**
- Horizontal pod autoscaling — fixed replicas acceptable initially (per PROJECT.md constraints)
- Blue-green/canary deployments — direct replacement strategy sufficient for v1
- Multi-cluster support — single production cluster initially
- Backup automation — manual backup process acceptable for v1
- Log aggregation/metrics — existing Sentry integration sufficient

**Anti-features (explicitly avoid):**
- Manual kubectl apply from CI — violates GitOps principles
- Mutable image tags (latest) — non-deterministic, can't rollback
- Secrets in Git — security risk even if base64 encoded
- Imperative scripts — hard to audit, drift-prone
- Cluster-admin permissions — overly permissive
- No resource limits — causes node instability

### Architecture Approach

The architecture implements a pull-based deployment model with clear separation between CI and CD concerns. GitHub Actions (CI) builds container images and updates manifests in Git but never touches the cluster directly. Argo CD (CD) continuously monitors Git and reconciles cluster state with the declared configuration. This separation ensures all deployments are auditable via Git history and cluster credentials never leave the Kubernetes control plane.

**Data flow sequence:**
1. Developer pushes code to main branch
2. GitHub Actions builds Docker images (5-10 minutes)
3. Images tagged with Git SHA and pushed to GCR
4. GitHub Actions updates k8s/*.yaml with new image tags
5. GitHub Actions commits manifest changes back to main
6. Argo CD detects Git change (3-minute poll or webhook)
7. Argo CD reconciles desired state (Git) vs actual state (cluster)
8. Kubernetes executes rolling update
9. Argo CD monitors health and reports status
10. Total deployment time: approximately 15 minutes

**Major components:**
1. **GitHub Actions (CI boundary)** — builds artifacts, runs tests, publishes to registry, updates desired state in Git
2. **Argo CD Application Controller** — continuously reconciles Git state with cluster state, executes deployments
3. **Argo CD Repo Server** — clones Git repos, renders manifests, caches repo state
4. **Envoy Gateway** — routes external traffic to services, terminates TLS at edge
5. **StatefulSets (Postgres/Redis)** — manage stateful services with persistent storage
6. **Deployments (API/Workers/UI)** — manage stateless application services

**Component boundaries:**
- GitHub Actions has GCR credentials only, never cluster credentials
- Argo CD has cluster credentials, never builds images
- Envoy Gateway terminates TLS, backends use plain HTTP
- StatefulSets deployed before Deployments (dependency ordering)
- HTTPRoutes configured last (depend on Services existing)

**Deployment ordering (critical dependencies):**
1. **Foundation:** Namespace, RBAC, ConfigMaps, Secrets (no runtime dependencies)
2. **Storage:** PersistentVolumeClaims with immediate-binding storage class
3. **Data layer:** Postgres and Redis StatefulSets (depend on PVCs, must be healthy before proceeding)
4. **Support services:** Playwright Deployment (parallel with data layer)
5. **Application layer:** API, Worker, UI Deployments (depend on Postgres, Redis, Playwright)
6. **External access:** HTTPRoutes (depend on Services, configured last)

### Critical Pitfalls

Research identified 15 pitfalls across critical, moderate, and minor severity. The critical pitfalls can cause production outages or architectural rewrites. Prevention strategies are specific and actionable.

1. **Image tag mutation without sync detection** — Using mutable tags like `latest` causes Argo CD to miss deployments because manifests don't change even when images do. Prevention: Use immutable Git SHA-based tags (`firecrawl-api:abc1234`). This is the most common GitOps failure mode.

2. **Race condition between image push and manifest update** — GitHub Actions updates manifests before GCR finishes processing the image, causing ImagePullBackOff errors. Prevention: Verify image availability with `gcloud container images describe` before committing manifests. Add retry logic with exponential backoff.

3. **StatefulSet volume binding failure on node constraints** — PersistentVolumeClaims request immediate-binding storage but volume provisions in zone A while only zone B nodes are available, leaving postgres in Pending state permanently. Prevention: Use `volumeBindingMode: WaitForFirstConsumer` storage class (GKE 1.23+ default). Verify node topology matches storage zones before deployment.

4. **Missing resource limits cause node memory exhaustion** — Node.js processes without memory limits grow unbounded, triggering OOMKiller which terminates random pods including unrelated services. Prevention: Define memory limits on all containers and set Node.js `--max-old-space-size` to 85% of container limit.

5. **Argo CD self-sync loop from automatic manifest updates** — GitHub Actions commits to main trigger workflow which commits to main again, creating infinite loop. Prevention: Use `[skip ci]` in manifest commit messages or configure workflow with `if: "!contains(github.event.head_commit.message, '[skip ci]')"`.

6. **Hardcoded secrets in manifests committed to Git** — Developers commit Kubernetes Secrets with base64-encoded values directly to repository, exposing credentials in Git history. Prevention: Create secrets manually via kubectl, never commit to Git. Use external secret management for production (out of scope for v1).

7. **Single Postgres instance without backup strategy** — Volume corruption or accidental deletion causes total data loss with no recovery path. Prevention: Implement pg_dump CronJob to GCS before any production data. Set PersistentVolume reclaim policy to Retain.

8. **Service mesh TLS configuration mismatch** — Envoy Gateway configured for HTTPS but backend Service expects HTTP, or vice versa, resulting in SSL handshake errors and 502 Bad Gateway. Prevention: Document TLS termination architecture explicitly, verify HTTPRoute backend references match Service protocol, test internal and external connectivity separately.

## Implications for Roadmap

Based on research, the roadmap should follow a sequential phase structure dictated by dependency chains. StatefulSets must be healthy before Deployments start. Storage must bind before StatefulSets deploy. The CI pipeline must be correct from day one because mutable tags create silent failures that are difficult to debug. This suggests 5-7 phases with clear validation gates between each.

### Phase 1: CI/CD Pipeline Foundation
**Rationale:** The CI pipeline must be correct before any deployments because image tag mutation causes silent failures. GitHub Actions configuration, image tagging strategy, and manifest update logic form the foundation for all subsequent work.

**Delivers:**
- GitHub Actions workflow that builds images on push to main
- Docker images tagged with Git SHA (immutable, auditable)
- Automated manifest updates that commit new tags to k8s/ directory
- Prevention of infinite workflow loops via [skip ci] or conditional triggers
- Verification that images exist in GCR before manifest updates

**Addresses:**
- Automated manifest updates (table stakes)
- Declarative configuration (table stakes)
- Immutable image tags (anti-pattern prevention)

**Avoids:**
- Pitfall #1: Image tag mutation without sync detection
- Pitfall #2: Race condition between image push and manifest update
- Pitfall #5: Argo CD self-sync loop from automatic manifest updates

**Research flag:** Standard patterns, skip phase research. GitHub Actions + GCR integration is well-documented.

### Phase 2: Argo CD Integration
**Rationale:** Once CI produces correct manifests, establish the CD layer. Argo CD is already installed—this phase creates the Application manifest and configures sync policies. Must happen before any application resources are deployed to ensure GitOps enforcement from the start.

**Delivers:**
- Argo CD Application manifest pointing to firecrawl repo k8s/ directory
- Automated sync policy (prune: true, selfHeal: true)
- Namespace creation via Argo CD
- Sync timeout configured for large image pulls (20 minutes)
- Health assessment enabled for all resource types

**Addresses:**
- Automated sync to cluster (table stakes)
- Health checks (table stakes)
- Rollback capability (table stakes)
- Drift detection and self-heal (differentiator)

**Avoids:**
- Pitfall #9: Argo CD sync timeout on large image pulls

**Research flag:** Standard patterns, skip phase research. Argo CD Application spec is straightforward.

### Phase 3: Foundation Resources
**Rationale:** Namespace, RBAC, ConfigMaps, and Secrets have no runtime dependencies and are required by all subsequent resources. This phase establishes the configuration foundation and validates that secrets management follows security best practices.

**Delivers:**
- Namespace with resource quotas and LimitRange defaults
- ServiceAccounts and RBAC for application pods
- ConfigMaps with externalized application configuration
- Secrets created manually (not in Git) for database passwords, API keys
- Documentation of required environment variables and their mapping

**Addresses:**
- Namespace isolation (table stakes)
- ConfigMaps for configuration (table stakes)
- Secrets management without Git commits (table stakes, anti-pattern prevention)

**Avoids:**
- Pitfall #6: Hardcoded secrets in manifests committed to Git
- Pitfall #12: Incomplete environment variable configuration in manifests

**Research flag:** Standard patterns, skip phase research. Basic Kubernetes resources.

### Phase 4: Storage Layer
**Rationale:** StatefulSets block until PVCs bind. Provisioning PVCs separately allows validation of storage class configuration and zone topology before deploying stateful services. This phase must complete successfully before Phase 5.

**Delivers:**
- PersistentVolumeClaim manifests for Postgres (10Gi)
- PersistentVolumeClaim manifests for Redis (1Gi)
- Verification of immediate-binding storage class availability
- Validation that node zones match storage class zones
- PersistentVolume reclaim policy set to Retain (prevent accidental data loss)

**Addresses:**
- Persistent storage (table stakes)
- Data persistence for StatefulSets

**Avoids:**
- Pitfall #3: StatefulSet volume binding failure on node constraints

**Research flag:** Needs validation. GKE-specific storage class configuration requires verification against client-cluster setup. Recommend `gsd:research-phase` to investigate storage classes, zones, and binding modes.

### Phase 5: Data Layer
**Rationale:** Postgres and Redis are critical dependencies for all application services. They must be healthy and accepting connections before API or workers start. This phase includes initialization strategy (schema setup, migrations) and backup implementation.

**Delivers:**
- Postgres StatefulSet with resource limits and health probes
- Redis StatefulSet with persistence enabled and resource limits
- Kubernetes Services for internal DNS resolution
- Database initialization strategy (init container or manual setup)
- CronJob for automated pg_dump backups to GCS (every 6 hours)
- Documented restoration procedure in runbook

**Addresses:**
- StatefulSets for stateful services (table stakes)
- Service discovery (table stakes)
- Readiness/liveness probes (table stakes)
- Resource limits (table stakes)
- Backup strategy before production data

**Avoids:**
- Pitfall #4: Missing resource limits cause node memory exhaustion
- Pitfall #7: Single Postgres instance without backup strategy

**Research flag:** Standard patterns, skip phase research. StatefulSet + Service configuration is well-documented. Backup CronJob follows established patterns.

### Phase 6: Application Layer
**Rationale:** API, workers, and UI depend on Postgres, Redis, and Playwright being healthy. This phase uses init containers to enforce startup ordering and validates resource limit configuration through load testing.

**Delivers:**
- API Deployment with resource limits and health probes
- Worker Deployments (multiple types: extract, nuq, prefetch) with resource limits
- Ingestion UI Deployment with resource limits
- Playwright Deployment for browser automation
- Init containers that wait for Postgres/Redis readiness before starting main containers
- Node.js `--max-old-space-size` configured to 85% of memory limits
- Kubernetes Services for all application components

**Addresses:**
- Deployments for stateless services (table stakes)
- Readiness/liveness probes (table stakes)
- Resource limits with Node.js heap configuration (table stakes)
- Init containers for dependency ordering (differentiator)

**Avoids:**
- Pitfall #4: Missing resource limits cause node memory exhaustion (Node.js specific)
- Pitfall #10: Node.js worker process CPU throttling
- Pitfall #11: Redis connection pool exhaustion from multiple workers

**Research flag:** Needs validation. BullMQ worker configuration, Redis connection pool sizing, and resource limit tuning require load testing. Recommend `gsd:research-phase` to investigate optimal worker configuration and resource allocation.

### Phase 7: External Access
**Rationale:** HTTPRoutes depend on Services existing and backend health. Routing configuration comes last to prevent external traffic before the application is ready. TLS certificate management must be validated against existing Envoy Gateway setup.

**Delivers:**
- HTTPRoute for API (firecrawl-api.prometheusags.ai)
- HTTPRoute for Ingestion UI (firecrawl.prometheusags.ai)
- TLS termination at Envoy Gateway using existing certificates
- HTTP to HTTPS redirect configuration
- Validation that backend protocol matches Gateway expectations (HTTP internally)
- External connectivity testing from internet

**Addresses:**
- TLS termination (table stakes)
- Envoy Gateway HTTPRoute configuration (existing infrastructure integration)

**Avoids:**
- Pitfall #8: Service mesh TLS configuration mismatch

**Research flag:** Needs validation. Envoy Gateway HTTPRoute configuration specific to client-cluster requires verification. TLS certificate structure in candle-vllm secret needs inspection. Recommend `gsd:research-phase` to investigate Gateway configuration, certificate format, and cross-namespace certificate references.

### Phase Ordering Rationale

- **Sequential phases 1-7:** Each phase depends on successful completion of previous phases. Storage must bind before StatefulSets deploy. StatefulSets must be healthy before Deployments start. Services must exist before HTTPRoutes reference them.
- **Critical path:** CI/CD (Phase 1) → Argo CD (Phase 2) → Configuration (Phase 3) → Storage (Phase 4) → Data Layer (Phase 5) → Application Layer (Phase 6) → External Access (Phase 7)
- **No parallelization:** Unlike typical application development, GitOps infrastructure deployment follows strict dependency chains. Attempting parallel phases risks configuration errors that are difficult to debug.
- **Validation gates:** Each phase ends with explicit validation before proceeding. Phase 4 validates PVC binding. Phase 5 validates StatefulSet readiness. Phase 6 validates application health. Phase 7 validates external connectivity.
- **Pitfall avoidance:** Phase ordering explicitly avoids race conditions. CI pipeline is correct before any resources deploy. Storage binds before StatefulSets start. Secrets are created before applications reference them.

### Research Flags

Phases likely needing deeper research during planning:

- **Phase 4 (Storage Layer):** GKE storage class configuration, zone topology, and binding modes are cluster-specific. Client-cluster may have custom storage classes. Immediate-binding vs WaitForFirstConsumer affects StatefulSet scheduling. Research needed to verify storage class availability and configuration.

- **Phase 6 (Application Layer):** BullMQ worker configuration, Redis connection pool sizing, and resource limits require application-specific knowledge. Optimal memory limits depend on workload characteristics (image size, processing time). CPU limits affect Node.js event loop performance. Research needed to understand Firecrawl's resource consumption patterns and tune accordingly.

- **Phase 7 (External Access):** Envoy Gateway HTTPRoute configuration in client-cluster may differ from standard patterns. TLS certificate structure in candle-vllm secret needs inspection. Cross-namespace certificate references may require additional RBAC. Research needed to understand existing Gateway setup and integration requirements.

Phases with standard patterns (skip research-phase):

- **Phase 1 (CI/CD Pipeline Foundation):** GitHub Actions + Docker + GCR integration follows established patterns. Image tagging strategy is standard GitOps practice.

- **Phase 2 (Argo CD Integration):** Argo CD Application spec is straightforward. Sync policy configuration is well-documented.

- **Phase 3 (Foundation Resources):** Namespace, RBAC, ConfigMaps, and Secrets are basic Kubernetes resources with standard patterns.

- **Phase 5 (Data Layer):** StatefulSet + Service configuration for Postgres/Redis follows established patterns. Backup CronJob uses standard pg_dump approach.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM | GitHub Actions + Argo CD + GKE is established pattern. Unable to verify specific version numbers (training data through January 2025). Google action versions and Argo CD releases may have advanced. Core recommendations (immutable tags, GitOps separation) are version-independent. |
| Features | MEDIUM | Feature prioritization based on GitOps and Kubernetes best practices from training data. Table stakes features are well-established (automated sync, health checks, resource limits). Differentiator features aligned with PROJECT.md constraints (defer HPA, multi-cluster). Unable to access current community discussions about emerging GitOps features. |
| Architecture | MEDIUM | Pull-based GitOps model is industry standard. Component boundaries (CI vs CD) are architectural fundamentals. Deployment ordering based on Kubernetes dependency semantics. Unable to verify client-cluster-specific configurations (Envoy Gateway version, storage class defaults, existing RBAC). Architecture patterns are sound but implementation details need validation. |
| Pitfalls | MEDIUM | Critical pitfalls based on well-documented GitOps issues (image tag mutation, sync loops, volume binding). Severity classifications based on production incident patterns from training data. Unable to verify latest Argo CD version-specific bugs or GKE behavior changes. Prevention strategies are established best practices but may need adjustment for specific tool versions. |

**Overall confidence:** MEDIUM

The architectural approach and phase structure are sound, based on established GitOps principles and Kubernetes patterns. The core recommendations (immutable tags, pull-based deployment, clear CI/CD separation) are version-independent fundamentals. However, implementation details require validation against the specific client-cluster configuration, current tool versions, and Firecrawl's resource characteristics.

### Gaps to Address

Areas where research was inconclusive or needs validation during implementation:

- **Storage class configuration:** Unable to verify which storage classes exist in client-cluster or their binding modes. GKE defaults changed in version 1.23+ to WaitForFirstConsumer. Custom storage classes may exist. Validation needed during Phase 4 planning via `kubectl get storageclass` and inspection of volumeBindingMode.

- **Envoy Gateway configuration:** Unable to inspect existing Gateway resources in client-cluster. HTTPRoute API is beta (v1beta1) and may have version-specific behavior. TLS certificate structure in candle-vllm secret unknown. Cross-namespace certificate references may require additional configuration. Validation needed during Phase 7 planning via `kubectl describe gateway` and inspection of existing HTTPRoutes.

- **Resource limit tuning:** Firecrawl workload characteristics (memory usage, CPU requirements) unknown. Node.js heap sizing depends on actual image processing requirements. BullMQ worker count and Redis connection pool size depend on queue throughput. Validation needed during Phase 6 planning through load testing and profiling.

- **Argo CD version and configuration:** Unable to verify which Argo CD version is installed in client-cluster or its current configuration (sync timeout, polling interval, RBAC). Version-specific features (sync waves, sync options) may differ. Validation needed during Phase 2 planning via `argocd version` and inspection of argocd-cm ConfigMap.

- **Node topology and zones:** Unable to verify which GCP zones client-cluster nodes are distributed across. StatefulSet scheduling depends on node zones matching storage zones. Validation needed during Phase 4 planning via `kubectl get nodes -o=jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}{end}'`.

- **GitHub Actions rate limiting:** Docker Hub rate limits may affect base image pulls. Unable to verify if repository has Docker Hub authentication configured. Validation needed during Phase 1 planning by checking secrets and considering GCR-based base images.

## Sources

### Primary (HIGH confidence)
- Kubernetes official documentation patterns (v1.27-1.29) — StatefulSet behavior, PVC binding, resource management, health probes
- Argo CD documentation patterns (v2.8-2.10) — GitOps reconciliation, sync policies, health assessment, Application spec
- GitHub Actions documentation patterns — workflow syntax, conditional triggers, secret management, multi-job workflows
- Google Cloud GKE documentation — GCR integration, storage classes, Workload Identity, zone topology

### Secondary (MEDIUM confidence)
- GitOps principles from OpenGitOps/Weaveworks — pull-based deployment model, single source of truth, continuous reconciliation
- Node.js in Kubernetes production patterns — V8 heap sizing, memory limits, CPU throttling behavior
- Docker BuildKit and multi-stage builds — layer caching, build optimization, multi-platform images
- Envoy Gateway API patterns — HTTPRoute configuration, TLS termination, backend references

### Tertiary (LOW confidence, needs validation)
- Specific version numbers for tools (Argo CD v2.10+, Kustomize v5.3+) — based on training data through January 2025, may be outdated
- GitHub Actions rate limiting thresholds — Docker Hub policies change frequently, current limits unknown
- GKE storage class defaults for prometheus-461323 project — project-specific configuration unknown
- Envoy Gateway HTTPRoute syntax in client-cluster — beta API may have version-specific behavior
- Firecrawl resource consumption patterns — application-specific, requires profiling

### Research Limitations
- Unable to access external web sources during research phase (tool restrictions)
- Relying on training data knowledge current as of January 2025
- Cannot verify latest Argo CD releases or GKE feature additions
- No access to Context7 for library-specific documentation (BullMQ, IORedis)
- Unable to inspect client-cluster configuration directly
- Cannot profile Firecrawl application resource usage without deployment

**Validation strategy:** During roadmap execution, each phase with a "needs validation" research flag should begin with targeted investigation of the specific gap. Phase 4 planning starts with `kubectl get storageclass`. Phase 6 planning includes load testing to determine resource limits. Phase 7 planning inspects existing Gateway configuration. This iterative validation approach addresses gaps incrementally rather than blocking the entire roadmap.

---

*Research completed: 2026-03-27*
*Ready for roadmap: yes*
