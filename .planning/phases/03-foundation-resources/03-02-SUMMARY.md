---
phase: 03-foundation-resources
plan: 02
subsystem: kubernetes-configuration
tags:
  - configmaps
  - secrets
  - kubernetes
  - gitops
  - configuration-management
dependency_graph:
  requires:
    - "03-01 (namespace, serviceaccounts, rbac)"
  provides:
    - "structured-configmaps"
    - "secrets-runbook"
    - "database-configuration"
    - "redis-configuration"
    - "application-configuration"
  affects:
    - "phase-06-deployments (envFrom references)"
tech_stack:
  added:
    - kubectl-secret-management
  patterns:
    - structured-configmaps-by-concern
    - manual-secret-creation
    - kubernetes-dns-service-references
    - gitops-configuration-separation
key_files:
  created:
    - k8s/base/configmap-database.yaml
    - k8s/base/configmap-redis.yaml
    - k8s/base/configmap-application.yaml
    - k8s/base/secrets-README.md
  modified:
    - k8s/base/kustomization.yaml
decisions:
  - decision: "Structured ConfigMaps by concern (database, redis, application)"
    rationale: "Enables partial updates, clearer ownership, better merge conflict resolution than monolithic ConfigMap"
    alternatives: ["Single monolithic ConfigMap"]
    impact: "Phase 6 deployments can reference specific ConfigMaps via envFrom, ConfigMap changes have limited blast radius"
  - decision: "Manual kubectl secret creation with documented runbook"
    rationale: "Simpler than encrypted GitOps secrets for v1, prevents credential exposure in Git history"
    alternatives: ["Sealed Secrets", "SOPS encrypted secrets", "External Secrets Operator"]
    impact: "Secrets must be created manually before deployment, documented in secrets-README.md"
  - decision: "Kubernetes internal DNS for service hostnames"
    rationale: "Standard K8s service discovery pattern, enables namespace isolation and portability"
    alternatives: ["Hardcoded IPs", "External DNS names"]
    impact: "Services reference each other via {service}.firecrawl.svc.cluster.local format, Phase 5 services must match these names"
metrics:
  duration_seconds: 138
  tasks_completed: 2
  files_created: 4
  files_modified: 1
  commits: 2
  lines_added: 218
  completed_date: "2026-03-27"
---

# Phase 03 Plan 02: Configuration Resources Summary

ConfigMaps and Secrets documentation for externalized application configuration following 12-factor app principles and GitOps patterns.

## What Was Built

Created structured ConfigMaps for database, Redis, and application configuration with Kubernetes internal DNS service references. Documented manual secret creation process with exact kubectl commands. All non-sensitive configuration committed to Git for GitOps management, sensitive credentials documented but never committed.

## Tasks Completed

### Task 1: Create structured ConfigMaps (Commit: 19e75a64)

Created three ConfigMap files organized by concern:

**configmap-database.yaml:**
- POSTGRES_HOST: postgres-service.firecrawl.svc.cluster.local
- POSTGRES_PORT: 5432
- POSTGRES_DB: firecrawl
- USE_DB_AUTHENTICATION: true

**configmap-redis.yaml:**
- REDIS_URL: redis://redis-service.firecrawl.svc.cluster.local:6379
- REDIS_RATE_LIMIT_URL: redis://redis-service.firecrawl.svc.cluster.local:6379

**configmap-application.yaml:**
- HOST: 0.0.0.0
- PORT: 3002
- NUM_WORKERS_PER_QUEUE: 8
- CRAWL_CONCURRENT_REQUESTS: 10
- MAX_CONCURRENT_JOBS: 5
- BROWSER_POOL_SIZE: 5
- LOGGING_LEVEL: INFO
- PLAYWRIGHT_MICROSERVICE_URL: http://playwright-service.firecrawl.svc.cluster.local:3000/scrape

All values derived from apps/api/.env.example non-sensitive configuration. Service hostnames use Kubernetes internal DNS format for service discovery. No sensitive values (passwords, API keys, tokens) included in ConfigMaps.

### Task 2: Create secrets runbook and update kustomization (Commit: b5099a4b)

Created secrets-README.md documenting manual secret creation process:

**firecrawl-database-secret:**
- POSTGRES_USER
- POSTGRES_PASSWORD (generated with openssl rand -base64 32)

**firecrawl-api-secrets:**
- OPENAI_API_KEY (from OpenAI Dashboard)
- SUPABASE_ANON_TOKEN (from Supabase Dashboard)
- SUPABASE_SERVICE_TOKEN (from Supabase Dashboard)
- SUPABASE_URL (from Supabase Dashboard)
- BULL_AUTH_KEY (generated with openssl rand -hex 16)

**Optional secrets documented:**
- SEARCHAPI_API_KEY
- LLAMAPARSE_API_KEY
- SCRAPING_BEE_API_KEY
- SLACK_WEBHOOK_URL
- STRIPE_SECRET_KEY
- POSTHOG_API_KEY / POSTHOG_HOST
- TEST_API_KEY

Runbook includes:
- Exact kubectl create secret commands with placeholder markers
- Verification commands (kubectl get/describe)
- Update/rotation instructions
- Security best practices
- Troubleshooting guide

Updated kustomization.yaml to include all three ConfigMap resources in the resources list. Foundation resources (namespace, serviceaccounts, rbac, configmaps) listed before deployment resources.

Verified kustomize builds successfully with all foundation + deployment resources.

## Verification Results

**ConfigMap structure verification:**
- configmap-database.yaml contains kind: ConfigMap with name firecrawl-database ✓
- Database config includes POSTGRES_HOST, POSTGRES_PORT, POSTGRES_DB, USE_DB_AUTHENTICATION ✓
- Database config does NOT contain POSTGRES_PASSWORD or POSTGRES_USER (those are secrets) ✓
- configmap-redis.yaml contains kind: ConfigMap with name firecrawl-redis ✓
- Redis config includes REDIS_URL and REDIS_RATE_LIMIT_URL with K8s DNS hostnames ✓
- configmap-application.yaml contains kind: ConfigMap with name firecrawl-application ✓
- Application config includes HOST, PORT, NUM_WORKERS_PER_QUEUE, PLAYWRIGHT_MICROSERVICE_URL ✓
- All 3 files have namespace: firecrawl and labels app: firecrawl ✓

**Secrets runbook verification:**
- secrets-README.md contains kubectl create secret generic firecrawl-database-secret ✓
- secrets-README.md contains kubectl create secret generic firecrawl-api-secrets ✓
- Database secret documents POSTGRES_USER and POSTGRES_PASSWORD keys ✓
- API secrets document OPENAI_API_KEY, SUPABASE_ANON_TOKEN, SUPABASE_SERVICE_TOKEN, BULL_AUTH_KEY ✓
- Verification commands with kubectl get secrets -n firecrawl included ✓
- No actual secret values committed (only placeholder markers like <GENERATE:> and <FROM_>) ✓

**Kustomization verification:**
- kustomization.yaml includes configmap-database.yaml ✓
- kustomization.yaml includes configmap-redis.yaml ✓
- kustomization.yaml includes configmap-application.yaml ✓
- kustomization.yaml still includes namespace.yaml, serviceaccounts.yaml, rbac.yaml ✓
- kustomization.yaml still includes api-deployment.yaml, ui-deployment.yaml ✓
- kustomization.yaml still has images section with firecrawl-api and ingestion-ui entries ✓
- kubectl kustomize k8s/base/ completes without errors ✓
- ConfigMaps present in kustomize output ✓

All acceptance criteria met. All verification passed.

## Success Criteria Status

- [x] 3 ConfigMap files exist with correct K8s DNS hostnames for services
- [x] secrets-README.md documents firecrawl-database-secret and firecrawl-api-secrets creation
- [x] No actual secret values exist in any committed file
- [x] kustomization.yaml builds cleanly with all foundation + deployment resources
- [x] ConfigMap keys match values from apps/api/.env.example

## Deviations from Plan

None - plan executed exactly as written. All ConfigMaps created with specified keys and values. Secrets runbook includes all documented secrets and optional keys. Kustomization includes all ConfigMap resources in correct order.

## Key Decisions Made

**1. Structured ConfigMaps by concern**

Separated configuration into database, redis, and application ConfigMaps rather than one monolithic ConfigMap. Enables partial updates (change Redis config without restarting API), clearer ownership, and better merge conflict resolution. Phase 6 deployments will reference specific ConfigMaps via envFrom.

**2. Manual kubectl secret creation**

Documented manual secret creation process with exact kubectl commands instead of implementing encrypted GitOps secrets (Sealed Secrets, SOPS). Simpler approach for v1, prevents credential exposure in Git history. Secrets must be created manually before deployment using commands in secrets-README.md.

**3. Kubernetes internal DNS for service hostnames**

Used standard K8s service discovery pattern: {service-name}.{namespace}.svc.cluster.local. Enables namespace isolation and portability. Phase 5 services (postgres-service, redis-service, playwright-service) must match these DNS names.

## Integration Points

**Upstream dependencies (requires):**
- Phase 03 Plan 01: firecrawl namespace must exist
- Phase 03 Plan 01: kustomization.yaml structure from Plan 01

**Downstream dependencies (provides to):**
- Phase 05 Data Layer: Database and Redis services must match ConfigMap hostnames
  - postgres-service.firecrawl.svc.cluster.local (POSTGRES_HOST)
  - redis-service.firecrawl.svc.cluster.local (REDIS_URL)
- Phase 06 Application Layer: Deployments will reference ConfigMaps via envFrom
  - envFrom configMapRef: firecrawl-database, firecrawl-redis, firecrawl-application
  - envFrom secretRef: firecrawl-database-secret, firecrawl-api-secrets
- Phase 06 Application Layer: Playwright service must match ConfigMap hostname
  - playwright-service.firecrawl.svc.cluster.local (PLAYWRIGHT_MICROSERVICE_URL)

**Cross-phase coordination:**
- Service DNS names in ConfigMaps must match Service metadata.name in Phase 5
- Secrets must be created manually before Phase 6 deployment pods can start
- ConfigMap and Secret names must match envFrom references in Phase 6 Deployments

## Artifacts

**Created files:**
- k8s/base/configmap-database.yaml (14 lines) - Postgres connection configuration
- k8s/base/configmap-redis.yaml (12 lines) - Redis connection configuration
- k8s/base/configmap-application.yaml (15 lines) - Application runtime configuration
- k8s/base/secrets-README.md (177 lines) - Manual secret creation documentation

**Modified files:**
- k8s/base/kustomization.yaml - Added 3 ConfigMap resources to resources list

**Git commits:**
- 19e75a64: feat(03-02): create ConfigMaps for database, redis, and application
- b5099a4b: feat(03-02): add secrets runbook and update kustomization

## Technical Notes

**ConfigMap structure:**
All ConfigMaps follow standard Kubernetes manifest format with namespace: firecrawl and labels for app and config-type. Values are strings (K8s ConfigMap data values are always strings). Numeric configuration (PORT, NUM_WORKERS_PER_QUEUE) stored as quoted strings, application code must parse.

**Service DNS format:**
Kubernetes internal DNS format: {service-name}.{namespace}.svc.cluster.local. Short form ({service-name}) works within same namespace but full form used for clarity and namespace portability. DNS resolution handled by cluster CoreDNS.

**Secret management approach:**
Manual kubectl creation chosen over encrypted GitOps secrets for v1 simplicity. Secrets created via kubectl create secret generic with --from-literal flags. Base64 encoding is automatic (kubectl handles encoding). Secrets stored in etcd, access controlled by Kubernetes RBAC.

**ConfigMap vs Secret classification:**
- ConfigMap: Non-sensitive configuration that would be acceptable in public Git (hostnames, ports, feature flags)
- Secret: Credentials, API keys, tokens that grant access to services
- Database host/port/name = ConfigMap, database password = Secret
- Redis URL without auth = ConfigMap, Redis URL with password = Secret
- Application settings = ConfigMap, third-party API keys = Secret

## Next Steps

**Immediate (Phase 3 continuation):**
If Phase 3 has additional plans, execute next plan. If Phase 3 complete, proceed to Phase 4 (Storage Layer).

**Phase 4 dependencies:**
Phase 4 Storage Layer will create PersistentVolumeClaims for postgres and redis StatefulSets. No configuration dependencies on Phase 3 Plan 02 ConfigMaps.

**Phase 5 dependencies:**
Phase 5 Data Layer must create Services with names matching ConfigMap hostnames:
- postgres-service (matches POSTGRES_HOST)
- redis-service (matches REDIS_URL, REDIS_RATE_LIMIT_URL)

**Phase 6 dependencies:**
Phase 6 Application Layer Deployments must:
- Reference ConfigMaps via envFrom configMapRef
- Reference Secrets via envFrom secretRef
- Create playwright-service matching PLAYWRIGHT_MICROSERVICE_URL hostname
- Secrets must be created manually before pods can start (documented in secrets-README.md)

**Manual actions required before Phase 6:**
Operator must create secrets using kubectl commands from secrets-README.md:
1. Generate POSTGRES_PASSWORD: `openssl rand -base64 32`
2. Generate BULL_AUTH_KEY: `openssl rand -hex 16`
3. Obtain Supabase tokens from Supabase Dashboard (ANON, SERVICE, URL)
4. Obtain OpenAI API key from OpenAI Dashboard
5. Run kubectl create secret commands from secrets-README.md
6. Verify secrets exist: `kubectl get secrets -n firecrawl`

## Self-Check

Verifying claims made in this summary:

**Created files exist:**
```
/Users/gqadonis/Projects/references/firecrawl/k8s/base/configmap-database.yaml - FOUND
/Users/gqadonis/Projects/references/firecrawl/k8s/base/configmap-redis.yaml - FOUND
/Users/gqadonis/Projects/references/firecrawl/k8s/base/configmap-application.yaml - FOUND
/Users/gqadonis/Projects/references/firecrawl/k8s/base/secrets-README.md - FOUND
```

**Commits exist:**
```
19e75a64 - FOUND
b5099a4b - FOUND
```

**Kustomize builds successfully:**
```
kubectl kustomize k8s/base/ - PASS (ConfigMaps present in output)
```

## Self-Check: PASSED

All files created as documented. All commits exist in Git history. Kustomize builds successfully with ConfigMaps included. Claims verified.
