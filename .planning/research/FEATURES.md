# Feature Landscape: Kubernetes GitOps Deployment

**Domain:** Production Kubernetes GitOps deployment with Argo CD
**Researched:** 2026-03-27
**Confidence:** MEDIUM (based on established GitOps principles and Kubernetes best practices; no external verification available)

## Table Stakes

Features users expect in a production GitOps deployment. Missing = deployment is fragile or unmanageable.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Automated manifest updates** | Core GitOps principle: CI updates manifests with new image tags | Low | GitHub Actions writes new tags to k8s/ manifests after build |
| **Declarative configuration** | All cluster state defined in Git | Low | Kubernetes YAML manifests in repository |
| **Automated sync to cluster** | Changes in Git automatically deployed | Low | Argo CD watches repo and syncs changes |
| **Health checks** | Know if deployment succeeded | Medium | Argo CD built-in health checks for Deployments, StatefulSets, Services |
| **Rollback capability** | Production will break; need quick recovery | Low | Git revert + Argo CD sync (inherent in GitOps) |
| **Namespace isolation** | Workloads don't interfere with other cluster tenants | Low | Dedicated firecrawl namespace |
| **Resource limits** | Prevent resource exhaustion | Low | CPU/memory requests and limits on all pods |
| **Persistent storage** | Stateful services (postgres, redis) survive pod restarts | Medium | PersistentVolumeClaims with immediate-binding storage class |
| **Service discovery** | Components communicate via DNS | Low | Kubernetes Services (built-in) |
| **TLS termination** | HTTPS for external endpoints | Medium | Envoy Gateway HTTPRoutes with TLS certificates |
| **Readiness probes** | Traffic only to healthy pods | Low | HTTP/TCP probes on all services |
| **Liveness probes** | Auto-restart crashed pods | Low | HTTP/TCP probes on all services |
| **Image pull secrets** | Private container registry access | Low | GCR authentication via service account or imagePullSecrets |
| **ConfigMaps** | Non-sensitive configuration externalized | Low | Environment variables, config files |
| **Secrets management** | Sensitive data not in plain text | Low | Kubernetes Secrets (base64 encoded) |
| **Single source of truth** | Git is authoritative state | Low | No manual kubectl apply (Argo CD enforces) |

## Differentiators

Features that improve operability but aren't critical for initial deployment.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Sync status notifications** | Know when deployments complete or fail | Low | Argo CD webhooks to Slack/email |
| **Diff preview** | See what will change before sync | Low | Argo CD UI shows git diff vs cluster state |
| **Manual sync gates** | Prevent automatic deployment of breaking changes | Low | Argo CD manual sync mode (vs auto-sync) |
| **Prune resources** | Remove resources deleted from git | Low | Argo CD prune flag (auto-cleanup) |
| **Self-heal** | Auto-revert manual cluster changes | Low | Argo CD self-heal mode (enforce git state) |
| **Multi-arch images** | Support arm64 and amd64 nodes | Medium | Docker manifest lists (existing workflow has this) |
| **Init containers** | Database migrations before app starts | Low | Kubernetes init containers for schema setup |
| **Pod disruption budgets** | Maintain availability during rolling updates | Low | PDB ensures minimum replicas during updates |
| **Network policies** | Restrict pod-to-pod communication | Medium | Kubernetes NetworkPolicy (defense in depth) |
| **Resource quotas** | Prevent namespace resource exhaustion | Low | Kubernetes ResourceQuota for namespace |
| **Horizontal pod autoscaling** | Scale based on CPU/memory | Medium | HPA for stateless services (API, workers) |
| **Readiness gates** | Custom deployment validation | High | Complex logic for determining "ready" state |
| **Blue-green deployments** | Zero-downtime with instant rollback | High | Two full environments, switch traffic atomically |
| **Canary deployments** | Gradual rollout with traffic splitting | High | Progressive delivery (Argo Rollouts) |
| **Image promotion** | Dev → staging → prod workflow | Medium | Separate Argo CD applications per environment |
| **Drift detection** | Alert when cluster state diverges from git | Low | Argo CD built-in (out-of-sync status) |
| **RBAC for Argo CD** | Control who can deploy what | Medium | Argo CD RBAC policies (team-based access) |
| **Git commit status** | Deployment status as GitHub check | Low | Argo CD GitHub integration |
| **Multi-cluster support** | Deploy to dev/staging/prod clusters | High | Argo CD ApplicationSets (out of scope per PROJECT.md) |
| **Helm chart management** | Package and version manifests | Medium | Existing helm chart in examples/ (could adopt) |
| **Kustomize overlays** | Environment-specific patches | Medium | Alternative to Helm for customization |
| **Image vulnerability scanning** | Catch CVEs before deployment | Medium | Trivy in CI pipeline |
| **Pod security policies** | Enforce security constraints | Medium | Pod Security Standards (restricted profile) |
| **Service mesh integration** | Advanced traffic management, mTLS | High | Istio/Linkerd (overkill for single-environment) |
| **Backup automation** | Scheduled postgres/redis backups | Medium | Velero or custom CronJob (out of scope for v1) |
| **Log aggregation** | Centralized logs from all pods | Medium | Fluentd/Loki (rely on existing Sentry per PROJECT.md) |
| **Metrics and dashboards** | Prometheus/Grafana observability | High | Out of scope (existing Sentry per PROJECT.md) |
| **Cost allocation** | Track resource costs per namespace | Low | Kubernetes labels + GCP billing tags |
| **Git webhook validation** | Block invalid manifests before merge | Medium | Pre-commit hooks, CI validation |

## Anti-Features

Features to explicitly NOT build.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Manual kubectl apply** | Violates GitOps principle (git is source of truth) | All changes via git commits + Argo CD sync |
| **Mutable image tags (latest)** | Non-deterministic deployments, can't rollback reliably | SHA or semantic version tags (commit SHA recommended) |
| **Secrets in git** | Security risk (credentials exposed in history) | Kubernetes Secrets (or external secret management in future) |
| **Imperative scripts** | Hard to audit, non-idempotent, drift-prone | Declarative manifests only |
| **Direct database access from CI** | Creates hidden dependencies, hard to audit | Migrations in init containers or manual process |
| **Embedded configuration** | Requires rebuild to change config | ConfigMaps and environment variables |
| **Tight coupling to CI tool** | Lock-in, hard to migrate | Separate CI (build) from CD (deploy) concerns |
| **Single giant manifest** | Hard to maintain, all-or-nothing deploys | Separate files per resource type or service |
| **Environment-specific repos** | Duplication, inconsistency between envs | Single repo with overlays or multi-app (out of scope) |
| **Cluster-admin for Argo CD** | Overly permissive, security risk | Namespace-scoped permissions |
| **No resource limits** | Noisy neighbors, cluster instability | Requests and limits on all containers |
| **Hostpath volumes** | Not portable, security risk | PersistentVolumeClaims with storage class |
| **Root containers** | Security risk | Non-root user in Dockerfile |
| **Privileged pods** | Security risk | Run unprivileged unless absolutely required |

## Feature Dependencies

```
Automated manifest updates → Declarative configuration (must have manifests to update)
Automated sync to cluster → Automated manifest updates (nothing to sync without updates)
Rollback capability → Automated sync to cluster (rollback is reverse sync)
Health checks → Readiness probes (health determined by probes)
TLS termination → Service discovery (HTTPRoute needs Service backend)
Persistent storage → StatefulSets (StatefulSet manages PVC lifecycle)
Multi-arch images → Container registry (must support manifest lists)
Sync status notifications → Automated sync to cluster (nothing to notify about)
Self-heal → Automated sync to cluster (self-heal is continuous sync)
Init containers → Persistent storage (migrations need database to exist)
Blue-green deployments → Horizontal pod autoscaling (need multiple replicas)
Canary deployments → Horizontal pod autoscaling (need traffic splitting)
Image promotion → Multi-cluster support (dev/staging/prod clusters)
```

## MVP Recommendation

Prioritize these for initial deployment:

### Phase 1: Core GitOps Pipeline
1. **Automated manifest updates** - CI writes new image tags to k8s/ directory
2. **Declarative configuration** - All Kubernetes manifests in firecrawl/k8s/
3. **Automated sync to cluster** - Argo CD Application watching repo
4. **Health checks** - Argo CD health assessment enabled
5. **Rollback capability** - Git revert process documented

### Phase 2: Production Readiness
6. **Resource limits** - CPU/memory on all pods
7. **Persistent storage** - PVCs for postgres and redis
8. **Readiness probes** - HTTP probes on API, TCP on databases
9. **Liveness probes** - HTTP probes on API, TCP on databases
10. **TLS termination** - HTTPRoutes with SSL redirect
11. **Namespace isolation** - Dedicated firecrawl namespace
12. **Service discovery** - Kubernetes Services for all components
13. **ConfigMaps** - Externalized configuration
14. **Secrets management** - Kubernetes Secrets for API keys

### Phase 3: Operational Excellence (Defer)
- **Sync status notifications** - Slack integration for deploy alerts
- **Diff preview** - Use Argo CD UI before sync
- **Prune resources** - Auto-cleanup deleted resources
- **Self-heal** - Auto-revert manual changes

### Defer to Future Milestones
- **Horizontal pod autoscaling** - Fixed replicas acceptable initially (per PROJECT.md)
- **Blue-green/canary deployments** - Direct replacement strategy initially (per PROJECT.md)
- **Multi-cluster support** - Single production cluster initially (per PROJECT.md)
- **Backup automation** - Manual backup process acceptable for v1 (per PROJECT.md)
- **Log aggregation/metrics** - Existing Sentry integration sufficient (per PROJECT.md)

## Complexity Assessment

| Complexity | Features | Estimated Effort |
|------------|----------|-----------------|
| **Low** | Most table stakes features | 1-2 days total |
| **Medium** | Persistent storage, TLS, Helm adoption | 3-5 days total |
| **High** | Blue-green, canary, service mesh | 1-2 weeks each (out of scope) |

## Implementation Notes

### Critical Path
The dependency chain determines order:
1. Declarative configuration (manifests must exist)
2. Automated manifest updates (CI updates manifests)
3. Automated sync to cluster (Argo CD deploys manifests)
4. Health checks (verify deployment success)
5. Everything else (can be parallel)

### Risk Areas
- **Persistent storage**: Storage class must support immediate binding (per PROJECT.md constraint). WaitForFirstConsumer will cause startup failures.
- **TLS certificates**: Must clone from existing candle-vllm secret. Certificate renewal not automated initially.
- **Resource limits**: Too low = OOMKilled, too high = wasted resources. Requires load testing to tune.
- **Database initialization**: Schema must exist before app starts. Init container or manual setup required.

### GitOps Anti-Patterns to Avoid
- **Mutable tags**: Use commit SHA, not `latest` or `main`
- **Manual edits**: Never `kubectl edit` - always git commit
- **Secrets in git**: Even base64 is readable in git history
- **CI deploys**: CI builds images, CD (Argo) deploys them
- **No rollback plan**: Document git revert + sync process

## Firecrawl-Specific Considerations

Based on existing codebase analysis:

### Already Implemented
- Multi-worker architecture (API, worker, extract-worker, nuq-worker, nuq-prefetch-worker)
- Helm chart with configurable replicas and resources (examples/kubernetes/firecrawl-helm/)
- GitHub Actions multi-arch image builds (.github/workflows/deploy-image.yml)
- Comprehensive configuration via environment variables (ConfigMap-ready)
- Secrets externalization (Secret-ready)

### Needs Implementation
- Argo CD Application manifest (connects repo to cluster)
- GitHub Actions manifest update step (write new image tags to k8s/)
- HTTPRoute manifests (Envoy Gateway ingress)
- PersistentVolumeClaim manifests with immediate-binding storage class
- Readiness/liveness probe configuration in Deployments
- Resource requests/limits tuning for production
- Database initialization strategy (init container or manual)

### Architecture Implications
- **Multi-component coordination**: 5+ worker types must start in correct order (database first, then workers)
- **Stateful services**: Postgres and Redis need persistent storage (data loss = unacceptable)
- **Job queue**: BullMQ Redis dependency means Redis must be healthy before workers start
- **AI integrations**: External service dependencies (OpenAI, Anthropic) mean retries/timeouts critical
- **Browser automation**: Playwright service resource-intensive (memory limits important)

## Sources

- GitOps Principles (OpenGitOps standards) - MEDIUM confidence (training data)
- Argo CD best practices (official documentation concepts) - MEDIUM confidence (training data)
- Kubernetes production patterns (CNCF recommendations) - MEDIUM confidence (training data)
- Firecrawl codebase analysis (examples/kubernetes/, .github/workflows/) - HIGH confidence (verified)
- PROJECT.md constraints and out-of-scope features - HIGH confidence (verified)

**Verification Status:** This research is based on established GitOps and Kubernetes best practices from training data (January 2025 cutoff) and analysis of the existing Firecrawl codebase. External documentation was unavailable for verification. Recommendations align with PROJECT.md constraints and existing infrastructure (Argo CD, Envoy Gateway, GKE).
