# Phase 3: Foundation Resources - Research

**Researched:** 2026-03-27
**Domain:** Kubernetes Namespace Configuration and RBAC
**Confidence:** HIGH

## Summary

Phase 3 establishes the configuration foundation for the Firecrawl deployment on GKE. This phase creates the `firecrawl` namespace with resource quotas, ServiceAccounts for application pods, RBAC roles following least-privilege principles, ConfigMaps for externalized application configuration, and Secrets for sensitive credentials. The critical distinction is that ConfigMaps are committed to Git (GitOps pattern), while Secrets are created manually via kubectl and never committed to version control.

Kubernetes namespace isolation provides the foundation for multi-tenancy and resource governance. Resource quotas prevent runaway resource consumption that could affect other cluster workloads. ServiceAccounts enable workload identity and RBAC enforcement. ConfigMaps externalize environment-specific configuration from container images, enabling the same image to run in multiple environments. Secrets provide base64 encoding and RBAC-controlled access for sensitive data like database passwords and API keys.

**Primary recommendation:** Use LimitRange in addition to ResourceQuota to set default resource limits on pods, preventing deployments without explicit limits. Create separate ServiceAccounts for each workload type (API, workers, UI) to enable fine-grained RBAC. Structure ConfigMaps by concern (database, redis, application) rather than one monolithic ConfigMap. Document the manual Secret creation process with exact kubectl commands in a runbook.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FOUND-01 | firecrawl namespace created with resource quotas | Namespace manifest with ResourceQuota and LimitRange for memory/CPU governance |
| FOUND-02 | ServiceAccounts created for application pods | Separate ServiceAccounts per workload type (api, worker, ui, playwright) for least-privilege RBAC |
| FOUND-03 | RBAC roles configured for service accounts | Role/RoleBinding for pod operations, no cluster-level permissions needed |
| FOUND-04 | ConfigMaps created for application configuration | Structured ConfigMaps for database, redis, and application settings (committed to Git) |
| FOUND-05 | Secrets created manually via kubectl (not committed to Git) | Manual creation pattern with documented kubectl commands, never in version control |
| FOUND-06 | Required secrets include database passwords and API keys | Secret structure based on .env.example analysis: database credentials, Redis URL, API keys |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Kubernetes | 1.27+ | Container orchestration | GKE cluster baseline version |
| kubectl | 1.27+ | Cluster management CLI | Matches server version, manual Secret creation |
| Kustomize | 5.0+ (built into kubectl) | Manifest templating | Native K8s tooling, already used in Phase 1 |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| kustomize-sops | N/A | Encrypted secrets in Git | Deferred to v2, manual kubectl for v1 |
| sealed-secrets | N/A | GitOps-friendly secret encryption | Deferred to v2, manual kubectl for v1 |
| external-secrets | N/A | External secret management integration | Deferred to v2, out of scope per REQUIREMENTS.md |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| ResourceQuota + LimitRange | Only ResourceQuota | LimitRange provides pod-level defaults, preventing deployments without limits |
| Manual kubectl secrets | Sealed Secrets or SOPS | Manual approach simpler for v1, encrypted GitOps secrets add complexity |
| Separate ServiceAccounts | Single default ServiceAccount | Separate accounts enable fine-grained RBAC, defense in depth |
| Structured ConfigMaps | Single monolithic ConfigMap | Structured approach enables partial updates, clearer ownership |

**Installation:**
```bash
# kubectl and kustomize are pre-installed in GKE clusters
kubectl version --client
kubectl kustomize --help
```

**Version verification:** Confirmed 2026-03-27. Kubernetes 1.27+ is current stable baseline for GKE. kubectl client version should match cluster server version (±1 minor version skew supported).

## Architecture Patterns

### Recommended Project Structure
```
k8s/base/
├── namespace.yaml              # Namespace with ResourceQuota + LimitRange
├── serviceaccounts.yaml        # ServiceAccounts for api, worker, ui, playwright
├── rbac.yaml                   # Roles and RoleBindings for ServiceAccounts
├── configmap-database.yaml     # Database connection configuration
├── configmap-redis.yaml        # Redis connection configuration
├── configmap-application.yaml  # Application-specific configuration
├── secrets-README.md           # Manual Secret creation documentation
└── kustomization.yaml          # Includes all foundation resources
```

### Pattern 1: Namespace with Resource Governance

**What:** Namespace manifest with ResourceQuota (namespace-level limits) and LimitRange (pod-level defaults and constraints).

**When to use:** All multi-tenant clusters or clusters with multiple workloads. ResourceQuota prevents namespace from consuming all cluster resources. LimitRange ensures all pods have resource limits even if developers forget to specify them.

**Example:**
```yaml
# namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: firecrawl
  labels:
    name: firecrawl
    managed-by: argocd
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: firecrawl-quota
  namespace: firecrawl
spec:
  hard:
    requests.cpu: "10"        # Total CPU requests across all pods
    requests.memory: "20Gi"   # Total memory requests across all pods
    limits.cpu: "20"          # Total CPU limits across all pods
    limits.memory: "40Gi"     # Total memory limits across all pods
    persistentvolumeclaims: "5"  # Max number of PVCs
    pods: "50"                # Max number of pods
---
apiVersion: v1
kind: LimitRange
metadata:
  name: firecrawl-limits
  namespace: firecrawl
spec:
  limits:
    - type: Container
      default:                # Default limits if not specified
        cpu: "1"
        memory: "2Gi"
      defaultRequest:         # Default requests if not specified
        cpu: "100m"
        memory: "256Mi"
      max:                    # Maximum allowed
        cpu: "4"
        memory: "8Gi"
      min:                    # Minimum required
        cpu: "50m"
        memory: "128Mi"
    - type: Pod
      max:
        cpu: "8"
        memory: "16Gi"
```

**Rationale:** ResourceQuota prevents runaway resource consumption. LimitRange provides safety net for missing resource specifications and enforces reasonable bounds.

### Pattern 2: ServiceAccount per Workload Type

**What:** Separate ServiceAccount for each logical workload component (API, workers, UI, Playwright) rather than using default ServiceAccount.

**When to use:** Always for production deployments. Enables least-privilege RBAC, workload identity tracking, and potential future integration with Workload Identity Federation.

**Example:**
```yaml
# serviceaccounts.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: firecrawl-api
  namespace: firecrawl
  labels:
    app: firecrawl
    component: api
automountServiceAccountToken: true  # Needed if pods need K8s API access
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: firecrawl-worker
  namespace: firecrawl
  labels:
    app: firecrawl
    component: worker
automountServiceAccountToken: true
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: firecrawl-ui
  namespace: firecrawl
  labels:
    app: firecrawl
    component: ui
automountServiceAccountToken: false  # UI likely doesn't need K8s API access
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: firecrawl-playwright
  namespace: firecrawl
  labels:
    app: firecrawl
    component: playwright
automountServiceAccountToken: false  # Browser service doesn't need K8s API
```

**Rationale:** Separate ServiceAccounts enable fine-grained RBAC policies. If API needs to read ConfigMaps but workers don't, separate accounts enforce this. Also enables audit trails showing which workload performed which action.

### Pattern 3: Least-Privilege RBAC

**What:** Role and RoleBinding (namespace-scoped) granting minimal permissions needed by application pods. For Firecrawl, most workloads need no K8s API access. If needed, grant only specific verbs on specific resources.

**When to use:** Always. Default K8s RBAC grants no permissions, which is correct for most application pods. Only add permissions when required for legitimate functionality.

**Example:**
```yaml
# rbac.yaml
# Example: If API needs to read ConfigMaps dynamically
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: firecrawl-api-role
  namespace: firecrawl
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list"]
    # NO "create", "update", "delete" - read-only
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: firecrawl-api-binding
  namespace: firecrawl
subjects:
  - kind: ServiceAccount
    name: firecrawl-api
    namespace: firecrawl
roleRef:
  kind: Role
  name: firecrawl-api-role
  apiGroup: rbac.authorization.k8s.io
---
# Workers, UI, Playwright likely need no permissions
# No Role/RoleBinding created = no permissions granted (secure default)
```

**Rationale:** Least-privilege reduces blast radius if pod is compromised. Most application pods consume configuration via environment variables and don't need K8s API access.

### Pattern 4: Structured ConfigMaps

**What:** Multiple ConfigMaps organized by concern (database, redis, application) rather than one monolithic ConfigMap. Each ConfigMap committed to Git and managed by Argo CD.

**When to use:** Always for GitOps deployments. Structured approach enables partial updates (change Redis config without restarting API), clearer ownership, and better merge conflict resolution.

**Example:**
```yaml
# configmap-database.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: firecrawl-database
  namespace: firecrawl
  labels:
    app: firecrawl
    config-type: database
data:
  POSTGRES_HOST: "postgres-service.firecrawl.svc.cluster.local"
  POSTGRES_PORT: "5432"
  POSTGRES_DB: "firecrawl"
  USE_DB_AUTHENTICATION: "true"
---
# configmap-redis.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: firecrawl-redis
  namespace: firecrawl
  labels:
    app: firecrawl
    config-type: redis
data:
  REDIS_URL: "redis://redis-service.firecrawl.svc.cluster.local:6379"
  REDIS_RATE_LIMIT_URL: "redis://redis-service.firecrawl.svc.cluster.local:6379"
---
# configmap-application.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: firecrawl-application
  namespace: firecrawl
  labels:
    app: firecrawl
    config-type: application
data:
  HOST: "0.0.0.0"
  PORT: "3002"
  NUM_WORKERS_PER_QUEUE: "8"
  CRAWL_CONCURRENT_REQUESTS: "10"
  MAX_CONCURRENT_JOBS: "5"
  BROWSER_POOL_SIZE: "5"
  LOGGING_LEVEL: "INFO"
  PLAYWRIGHT_MICROSERVICE_URL: "http://playwright-service.firecrawl.svc.cluster.local:3000/scrape"
```

**Rationale:** Structured ConfigMaps improve maintainability and blast radius. Changing Redis URL doesn't require updating unrelated database configuration. Git diffs are clearer when configs are separated.

### Pattern 5: Manual Secret Creation (Not in Git)

**What:** Secrets created manually via `kubectl create secret` commands and documented in a runbook. Never committed to Git even if base64 encoded. Secret manifests with placeholder values can exist in Git for structure documentation, but actual secrets created out-of-band.

**When to use:** Always for production. Base64 encoding in Kubernetes Secrets is NOT encryption, just encoding. Git history retains secrets forever even if deleted from HEAD.

**Example:**
```bash
# secrets-README.md content (committed to Git)
# Create secrets manually before deploying application

# Database credentials
kubectl create secret generic firecrawl-database-secret \
  --from-literal=POSTGRES_USER=firecrawl \
  --from-literal=POSTGRES_PASSWORD='<GENERATE_SECURE_PASSWORD>' \
  --namespace=firecrawl \
  --dry-run=client -o yaml | kubectl apply -f -

# Application secrets
kubectl create secret generic firecrawl-api-secrets \
  --from-literal=SUPABASE_ANON_TOKEN='<SUPABASE_TOKEN>' \
  --from-literal=SUPABASE_SERVICE_TOKEN='<SUPABASE_SERVICE_TOKEN>' \
  --from-literal=OPENAI_API_KEY='<OPENAI_KEY>' \
  --from-literal=BULL_AUTH_KEY='<BULL_KEY>' \
  --namespace=firecrawl \
  --dry-run=client -o yaml | kubectl apply -f -

# Verify secrets exist
kubectl get secrets -n firecrawl
kubectl describe secret firecrawl-database-secret -n firecrawl  # Shows keys but not values
```

**Rationale:** Git history is immutable and secrets cannot be truly removed once committed. Manual creation separates secret lifecycle from application deployment lifecycle. Runbook provides reproducibility without exposing credentials.

### Pattern 6: ConfigMap and Secret Environment Variable Injection

**What:** Reference ConfigMaps and Secrets in Deployment manifests via `envFrom` (inject all keys) or `env` with `valueFrom` (inject specific keys). This is implemented in Phase 6, but foundation resources must be structured to support it.

**When to use:** Always for 12-factor applications that consume configuration via environment variables.

**Example (for context, implemented in Phase 6):**
```yaml
# api-deployment.yaml (Phase 6)
spec:
  template:
    spec:
      serviceAccountName: firecrawl-api
      containers:
        - name: api
          image: firecrawl-api
          envFrom:
            - configMapRef:
                name: firecrawl-database
            - configMapRef:
                name: firecrawl-redis
            - configMapRef:
                name: firecrawl-application
            - secretRef:
                name: firecrawl-database-secret
            - secretRef:
                name: firecrawl-api-secrets
```

**Rationale:** `envFrom` automatically injects all keys from ConfigMap/Secret as environment variables. Cleaner than listing 50+ individual variables. Supports additive changes (add key to ConfigMap, automatically available in pods on restart).

### Anti-Patterns to Avoid

- **Single monolithic ConfigMap:** Harder to maintain, forces full restarts on any config change, merge conflicts in Git
- **Secrets committed to Git:** Irreversible security breach, credentials exposed in Git history forever
- **Default ServiceAccount for all workloads:** Prevents least-privilege RBAC, no workload identity tracking
- **No ResourceQuota/LimitRange:** Runaway pods can exhaust node resources, affecting other cluster workloads
- **ClusterRole/ClusterRoleBinding for app workloads:** Over-privileged, grants cross-namespace access when namespace-scoped Role is sufficient
- **automountServiceAccountToken: true when not needed:** Unnecessary attack surface, pods shouldn't have K8s API credentials if not used
- **Inline secrets in Deployment manifests:** Same security problem as committing to Git, credentials in manifest files

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Secret encryption in Git | Custom base64 wrapper scripts | Manual kubectl + runbook (v1), Sealed Secrets or SOPS (v2) | Secret rotation, key management, and auditing are complex. Manual approach is safer than incorrect encryption. |
| RBAC policy generation | Custom scripts to generate Role manifests | Manual manifest creation with documented patterns | RBAC policies are relatively static and benefit from explicit review. Generation adds complexity without value for ~5 ServiceAccounts. |
| ConfigMap validation | Custom schema validation tools | Kubernetes native validation + Argo CD health checks | Kubernetes apiserver validates structure, Argo CD validates deployment health. Additional validation is premature. |
| Environment variable templating | Custom templating engine | Kustomize ConfigMapGenerator (if needed), plain manifests (sufficient for v1) | Plain YAML manifests are simple and version-controlled. Templating adds complexity without clear benefit for single-environment deployment. |

**Key insight:** Foundation resources are relatively static and benefit from explicit, reviewable manifests. Tooling and automation add value for frequently-changing resources (image tags in Phase 1), but ConfigMaps and Secrets change infrequently and should be explicit.

## Common Pitfalls

### Pitfall 1: Secrets Committed to Git History

**What goes wrong:** Developer commits Kubernetes Secret manifest with base64-encoded credentials to Git. Even if secret is deleted from HEAD, it remains in Git history forever. Anyone with repository access (or if repository becomes public) can extract credentials.

**Why it happens:** Misunderstanding that base64 is encoding, not encryption. Desire to keep "all configuration in Git" without understanding security implications.

**How to avoid:**
- Document manual secret creation process in runbook (`secrets-README.md`)
- Never create Secret manifests in k8s/ directory (except templates with placeholder values)
- Add `*secret*.yaml` to .gitignore as safety net
- Use pre-commit hooks to scan for common secret patterns (AWS keys, passwords, tokens)

**Warning signs:**
- Secret manifest files in k8s/ directory with data: or stringData: fields
- Base64 strings in Git diffs (may be credentials)
- "All configuration should be in Git" statements without secret exclusion

### Pitfall 2: No Resource Limits Causing Node Exhaustion

**What goes wrong:** Pods deployed without memory or CPU limits. Node.js process memory leak or CPU-intensive operation causes pod to consume all available node resources. Kubelet OOMKiller terminates random pods to reclaim memory, including unrelated services. Node becomes unresponsive.

**Why it happens:** Kubernetes defaults to unlimited resources if not specified. Developers focus on functionality and forget operational concerns. LimitRange not configured to provide safety net.

**How to avoid:**
- Implement LimitRange with default limits (provides safety net)
- Make resource limits mandatory in Deployment templates (Phase 6)
- Set Node.js `--max-old-space-size` to 85% of container memory limit
- Monitor resource usage in staging to tune limits appropriately

**Warning signs:**
- Pods consuming >4Gi memory (likely misconfigured)
- OOMKilled events in `kubectl describe pod`
- Node memory pressure causing pod evictions
- Horizontal scaling not improving performance (node-level bottleneck)

### Pitfall 3: Overly Permissive RBAC

**What goes wrong:** ServiceAccount granted ClusterRole with cluster-admin or broad permissions. Compromised pod can read secrets from other namespaces, delete critical resources, or escalate privileges. Security breach affects entire cluster, not just compromised application.

**Why it happens:** "It doesn't work" debugging leads to granting escalating permissions until error goes away. Lack of understanding that most application pods need no K8s API access.

**How to avoid:**
- Start with no permissions (default K8s RBAC)
- Add permissions only when specific functionality requires K8s API access
- Use namespace-scoped Role, not ClusterRole
- Audit what K8s API calls application actually makes (pod logs, audit logs)
- Set `automountServiceAccountToken: false` for pods that don't need K8s API

**Warning signs:**
- RoleBinding referencing ClusterRole for application workloads
- Verbs include "create", "delete", "patch" for application ServiceAccounts
- Resources include "*" wildcard
- Application logs show K8s API authentication errors (may need permissions, or may be unnecessary calls)

### Pitfall 4: ConfigMap Updates Not Triggering Pod Restarts

**What goes wrong:** Update ConfigMap in Git, Argo CD syncs successfully, but running pods still use old configuration. Application behavior doesn't match expected config. Requires manual pod restart to pick up changes.

**Why it happens:** Kubernetes doesn't automatically restart pods when ConfigMaps change. ConfigMaps are mounted at pod start time (environment variables) or continuously updated (volume mounts, but application must watch for changes).

**How to avoid:**
- Document that ConfigMap changes require pod restarts (`kubectl rollout restart deployment/firecrawl-api`)
- Use Reloader or similar tool to automatically restart pods on ConfigMap changes (deferred to v2)
- For frequently-changing config, use volume mounts and implement file watching in application
- Use Deployment annotations to force rollout: `kubectl patch deployment firecrawl-api --patch '{"spec": {"template": {"metadata": {"annotations": {"configHash": "$(date +%s)"}}}}}'`

**Warning signs:**
- Config changes deployed but application behavior unchanged
- Inconsistent behavior across pods (some restarted, some using old config)
- Manual pod deletion required after config changes

### Pitfall 5: Namespace ResourceQuota Blocking Deployments

**What goes wrong:** ResourceQuota set too low for anticipated workload. New deployments fail with "exceeded quota" errors. Application cannot scale or deploy updates. Requires manual quota adjustment and redeployment.

**Why it happens:** Conservative quota values set without understanding actual resource requirements. Quotas set at application level (per-pod) don't account for multiple replicas. No buffer for temporary spikes during rolling updates.

**How to avoid:**
- Set quotas with 2x headroom above expected steady-state usage
- Account for rolling update overlaps (old and new pods running simultaneously)
- Monitor quota usage: `kubectl describe resourcequota -n firecrawl`
- Document quota adjustment process in runbook
- Start with generous quotas, tighten after observing actual usage patterns

**Warning signs:**
- "exceeded quota" errors in Argo CD sync status
- Pods stuck in Pending state with quota-related events
- Horizontal autoscaling fails to create new pods
- Cannot deploy new services within namespace

### Pitfall 6: Mixing Secret and ConfigMap Data

**What goes wrong:** Non-sensitive configuration stored in Secrets "because it's there", or sensitive credentials stored in ConfigMaps "for convenience". Secrets unnecessarily require manual management overhead. Credentials exposed in Git or logs.

**Why it happens:** Unclear distinction between sensitive and non-sensitive data. Using Secrets as general-purpose key-value store.

**How to avoid:**
- Clear classification: ConfigMaps for non-sensitive configuration (committed to Git), Secrets for credentials and sensitive data (manual creation)
- Rule of thumb: If value would be acceptable in a public GitHub repo, use ConfigMap. Otherwise, use Secret.
- Examples: Database host/port/name = ConfigMap. Database password = Secret.
- Examples: Redis URL with auth token = Secret. Redis URL without auth = ConfigMap.

**Warning signs:**
- Secret containing only non-sensitive configuration (port numbers, hostnames without credentials)
- ConfigMap containing connection strings with embedded passwords
- Debugging logs accidentally exposing Secret values

## Code Examples

Verified patterns from Kubernetes official documentation and established GitOps practices.

### Namespace with Resource Governance

```yaml
# Source: Kubernetes official docs - Resource Quotas and Limit Ranges
# https://kubernetes.io/docs/concepts/policy/resource-quotas/
# https://kubernetes.io/docs/concepts/policy/limit-range/
apiVersion: v1
kind: Namespace
metadata:
  name: firecrawl
  labels:
    name: firecrawl
    managed-by: argocd
    environment: production
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: firecrawl-quota
  namespace: firecrawl
spec:
  hard:
    # Compute resources
    requests.cpu: "10"
    requests.memory: "20Gi"
    limits.cpu: "20"
    limits.memory: "40Gi"
    # Storage
    persistentvolumeclaims: "5"
    requests.storage: "50Gi"
    # Object counts
    pods: "50"
    services: "10"
    configmaps: "20"
    secrets: "20"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: firecrawl-limits
  namespace: firecrawl
spec:
  limits:
    # Container-level limits
    - type: Container
      default:
        cpu: "1"
        memory: "2Gi"
      defaultRequest:
        cpu: "100m"
        memory: "256Mi"
      max:
        cpu: "4"
        memory: "8Gi"
      min:
        cpu: "50m"
        memory: "128Mi"
    # Pod-level limits (sum of all containers)
    - type: Pod
      max:
        cpu: "8"
        memory: "16Gi"
    # PVC limits
    - type: PersistentVolumeClaim
      max:
        storage: "20Gi"
      min:
        storage: "1Gi"
```

### ServiceAccounts with Least Privilege

```yaml
# Source: Kubernetes official docs - Configure Service Accounts for Pods
# https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: firecrawl-api
  namespace: firecrawl
  labels:
    app: firecrawl
    component: api
  annotations:
    description: "ServiceAccount for Firecrawl API pods"
automountServiceAccountToken: true  # API may need ConfigMap access
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: firecrawl-worker
  namespace: firecrawl
  labels:
    app: firecrawl
    component: worker
automountServiceAccountToken: true  # Workers may need ConfigMap access
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: firecrawl-ui
  namespace: firecrawl
  labels:
    app: firecrawl
    component: ui
automountServiceAccountToken: false  # UI is frontend, no K8s API access needed
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: firecrawl-playwright
  namespace: firecrawl
  labels:
    app: firecrawl
    component: playwright
automountServiceAccountToken: false  # Browser service, no K8s API access needed
```

### RBAC for ConfigMap Read Access

```yaml
# Source: Kubernetes official docs - Using RBAC Authorization
# https://kubernetes.io/docs/reference/access-authn-authz/rbac/
---
# Minimal permissions: read ConfigMaps only (if needed)
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: firecrawl-api-role
  namespace: firecrawl
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "watch"]
    # Read-only, no create/update/delete
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: firecrawl-api-binding
  namespace: firecrawl
subjects:
  - kind: ServiceAccount
    name: firecrawl-api
    namespace: firecrawl
roleRef:
  kind: Role
  name: firecrawl-api-role
  apiGroup: rbac.authorization.k8s.io
---
# Same pattern for workers if needed
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: firecrawl-worker-binding
  namespace: firecrawl
subjects:
  - kind: ServiceAccount
    name: firecrawl-worker
    namespace: firecrawl
roleRef:
  kind: Role
  name: firecrawl-api-role  # Reuse same Role
  apiGroup: rbac.authorization.k8s.io
```

### Structured ConfigMaps

```yaml
# Source: Kubernetes official docs - ConfigMaps
# https://kubernetes.io/docs/concepts/configuration/configmap/
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: firecrawl-database
  namespace: firecrawl
  labels:
    app: firecrawl
    config-type: database
data:
  # Non-sensitive database connection info
  POSTGRES_HOST: "postgres-service.firecrawl.svc.cluster.local"
  POSTGRES_PORT: "5432"
  POSTGRES_DB: "firecrawl"
  # Password in Secret, not here
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: firecrawl-redis
  namespace: firecrawl
  labels:
    app: firecrawl
    config-type: redis
data:
  # Redis connection without auth (if using passwordless)
  # Or use Secret if Redis has authentication
  REDIS_URL: "redis://redis-service.firecrawl.svc.cluster.local:6379"
  REDIS_RATE_LIMIT_URL: "redis://redis-service.firecrawl.svc.cluster.local:6379"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: firecrawl-application
  namespace: firecrawl
  labels:
    app: firecrawl
    config-type: application
data:
  # Application configuration
  HOST: "0.0.0.0"
  PORT: "3002"
  NUM_WORKERS_PER_QUEUE: "8"
  CRAWL_CONCURRENT_REQUESTS: "10"
  MAX_CONCURRENT_JOBS: "5"
  BROWSER_POOL_SIZE: "5"
  LOGGING_LEVEL: "INFO"
  USE_DB_AUTHENTICATION: "true"
  # Service URLs using K8s DNS
  PLAYWRIGHT_MICROSERVICE_URL: "http://playwright-service.firecrawl.svc.cluster.local:3000/scrape"
  FIRECRAWL_APP_HOST: "firecrawl-api-service"
  FIRECRAWL_APP_PORT: "3002"
  FIRECRAWL_APP_SCHEME: "http"
```

### Manual Secret Creation Runbook

```markdown
# Source: Kubernetes official docs - Secrets
# https://kubernetes.io/docs/concepts/configuration/secret/

# secrets-README.md - Committed to Git, documents process without exposing credentials

## Required Secrets

This document describes the secrets that must be created manually before deploying Firecrawl.
Secrets are NOT committed to Git. Use kubectl commands below to create them.

### 1. Database Secret

Contains Postgres credentials.

```bash
kubectl create secret generic firecrawl-database-secret \
  --from-literal=POSTGRES_USER=firecrawl \
  --from-literal=POSTGRES_PASSWORD='<GENERATE_SECURE_PASSWORD>' \
  --namespace=firecrawl \
  --dry-run=client -o yaml | kubectl apply -f -
```

Password requirements:
- Minimum 20 characters
- Mix of uppercase, lowercase, numbers, symbols
- Generate with: `openssl rand -base64 32`

### 2. Application API Keys

Contains third-party API keys and tokens.

```bash
kubectl create secret generic firecrawl-api-secrets \
  --from-literal=OPENAI_API_KEY='sk-...' \
  --from-literal=SUPABASE_ANON_TOKEN='<TOKEN>' \
  --from-literal=SUPABASE_SERVICE_TOKEN='<TOKEN>' \
  --from-literal=BULL_AUTH_KEY='<GENERATE>' \
  --from-literal=RESEND_API_KEY='<KEY_IF_USED>' \
  --from-literal=SEARCHAPI_API_KEY='<KEY_IF_USED>' \
  --namespace=firecrawl \
  --dry-run=client -o yaml | kubectl apply -f -
```

Optional keys (add only if features are used):
- LLAMAPARSE_API_KEY
- SCRAPING_BEE_API_KEY
- STRIPE_SECRET_KEY (if billing enabled)
- SLACK_WEBHOOK_URL (if notifications enabled)

### 3. Verify Secrets

```bash
# List secrets
kubectl get secrets -n firecrawl

# Verify keys exist (does NOT show values)
kubectl describe secret firecrawl-database-secret -n firecrawl
kubectl describe secret firecrawl-api-secrets -n firecrawl
```

### 4. Update Secrets (if needed)

```bash
# Update individual key
kubectl create secret generic firecrawl-api-secrets \
  --from-literal=OPENAI_API_KEY='sk-new-key...' \
  --namespace=firecrawl \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart pods to pick up new secret values
kubectl rollout restart deployment/firecrawl-api -n firecrawl
```

## Security Notes

- Never commit secrets to Git, even base64 encoded
- Rotate secrets regularly (90 day rotation recommended)
- Use separate secrets for dev/staging/prod environments
- Audit secret access: `kubectl get events -n firecrawl --field-selector involvedObject.kind=Secret`
- Consider sealed-secrets or external-secrets for production (v2 roadmap)
```

### Environment Variable Injection Pattern

```yaml
# Source: Kubernetes official docs - Configure a Pod to Use a ConfigMap
# https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/
# This is implemented in Phase 6, shown here for context

# Deployment manifest referencing ConfigMaps and Secrets
apiVersion: apps/v1
kind: Deployment
metadata:
  name: firecrawl-api
  namespace: firecrawl
spec:
  template:
    spec:
      serviceAccountName: firecrawl-api  # Phase 3 foundation
      containers:
        - name: api
          image: firecrawl-api
          # Inject all ConfigMap and Secret keys as environment variables
          envFrom:
            # ConfigMaps (committed to Git)
            - configMapRef:
                name: firecrawl-database
            - configMapRef:
                name: firecrawl-redis
            - configMapRef:
                name: firecrawl-application
            # Secrets (created manually)
            - secretRef:
                name: firecrawl-database-secret
            - secretRef:
                name: firecrawl-api-secrets
          # Or inject specific keys if needed
          env:
            - name: SPECIFIC_KEY
              valueFrom:
                configMapKeyRef:
                  name: firecrawl-application
                  key: PORT
```

## Validation Architecture

> Nyquist validation is enabled (workflow.nyquist_validation=true in .planning/config.json)

### Test Framework
| Property | Value |
|----------|-------|
| Framework | kubectl + bash validation (no application framework needed) |
| Config file | none — Wave 0 creates validation scripts |
| Quick run command | `./k8s/validate-foundation.sh` |
| Full suite command | `./k8s/validate-foundation.sh --full` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FOUND-01 | Namespace exists with ResourceQuota and LimitRange | smoke | `kubectl get namespace firecrawl && kubectl get resourcequota -n firecrawl && kubectl get limitrange -n firecrawl` | ❌ Wave 0 |
| FOUND-02 | ServiceAccounts created for api, worker, ui, playwright | smoke | `kubectl get serviceaccount -n firecrawl \| grep -E 'firecrawl-(api\|worker\|ui\|playwright)'` | ❌ Wave 0 |
| FOUND-03 | RBAC roles configured for service accounts | smoke | `kubectl get role,rolebinding -n firecrawl` | ❌ Wave 0 |
| FOUND-04 | ConfigMaps created for database, redis, application | smoke | `kubectl get configmap -n firecrawl \| grep -E 'firecrawl-(database\|redis\|application)'` | ❌ Wave 0 |
| FOUND-05 | Secrets created manually (documented but not automated test) | manual-only | Documented in secrets-README.md, cannot automate without exposing credentials | ❌ Wave 0 |
| FOUND-06 | Required secrets exist with correct keys | smoke | `kubectl get secret firecrawl-database-secret -n firecrawl -o jsonpath='{.data}' \| grep -E 'POSTGRES_USER\|POSTGRES_PASSWORD'` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `./k8s/validate-foundation.sh` (smoke tests, < 30 seconds)
- **Per wave merge:** `./k8s/validate-foundation.sh --full` (full validation including RBAC permission checks)
- **Phase gate:** Full suite green + manual Secret verification before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `k8s/validate-foundation.sh` — smoke tests for FOUND-01 through FOUND-06
- [ ] `k8s/secrets-README.md` — manual Secret creation documentation (committed to Git)
- [ ] Validation script should check resource exists AND has expected structure (e.g., ResourceQuota has CPU/memory limits)

## Sources

### Primary (HIGH confidence)
- Kubernetes official documentation v1.27-1.29 - Namespace, ResourceQuota, LimitRange, ServiceAccount, RBAC, ConfigMap, Secret patterns
- Kubernetes API reference - Resource structure and field validation
- GKE documentation - Default storage classes, Workload Identity patterns (future use)
- GitOps patterns from Argo CD documentation - ConfigMap/Secret management in GitOps workflows

### Secondary (MEDIUM confidence)
- Kubernetes best practices guides - Resource governance, least-privilege RBAC
- 12-factor app methodology - Configuration via environment variables
- Security hardening guides - Secret management, RBAC policies

### Tertiary (LOW confidence, needs validation)
- Specific GKE cluster configuration (node zones, existing RBAC policies) - unknown until inspected
- Firecrawl application's actual K8s API access requirements - assume minimal based on application nature
- Optimal ResourceQuota values - depends on actual workload sizing from Phase 6 research

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - kubectl and Kustomize are established, versions stable
- Architecture: HIGH - Namespace, RBAC, ConfigMap, Secret patterns are fundamental K8s concepts
- Pitfalls: HIGH - Common issues well-documented in K8s community and production incident reports

**Research date:** 2026-03-27
**Valid until:** 90 days (stable domain, infrequent changes to K8s core APIs)
