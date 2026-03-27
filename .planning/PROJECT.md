# Firecrawl GKE Deployment Automation

## What This Is

An automated GitOps deployment pipeline for the Firecrawl web scraping API to Google Kubernetes Engine. GitHub Actions builds container images and updates Kubernetes manifests, while Argo CD handles the actual deployment to the cluster. All services (API, ingestion UI, postgres, redis, playwright) run in a dedicated namespace with external access via Envoy Gateway HTTPRoutes.

## Core Value

Deployments are automated, auditable, and easy to rollback. Every deployment is a git commit that can be reverted if needed.

## Requirements

### Validated

<!-- Existing Firecrawl capabilities already in the codebase -->

- ✓ Web scraping API with multi-version support (v0, v1, v2) — existing
- ✓ Background job processing with BullMQ — existing
- ✓ AI integrations (OpenAI, Anthropic, Google, Groq, Ollama) — existing
- ✓ Distributed worker architecture — existing
- ✓ API key authentication and team-based access control — existing
- ✓ Configurable rate limiting and concurrency — existing
- ✓ Sentry error tracking and structured logging — existing
- ✓ Playwright service for browser automation — existing

### Active

<!-- New deployment automation requirements -->

- [ ] GitHub Actions workflow builds API and ingestion-ui images on main branch push
- [ ] Images pushed to Google Container Registry (GCR) for prometheus-461323 project
- [ ] Kubernetes manifests in firecrawl/k8s/ directory updated with new image tags
- [ ] Argo CD automatically syncs manifest changes to client-cluster
- [ ] All services deploy to dedicated firecrawl namespace
- [ ] Postgres runs as StatefulSet with PersistentVolume (immediate-binding storage class)
- [ ] Redis runs as StatefulSet with PersistentVolume
- [ ] Playwright service runs as Deployment
- [ ] Envoy Gateway HTTPRoute for API at firecrawl-api.prometheusags.ai
- [ ] Envoy Gateway HTTPRoute for ingestion-ui at firecrawl.prometheusags.ai
- [ ] HTTPRoutes configured with SSL redirect and TLS termination
- [ ] TLS certificate cloned from existing candle-vllm secret
- [ ] Services can communicate internally via Kubernetes service discovery
- [ ] Deployment status visible in Argo CD dashboard

### Out of Scope

- Multi-environment setup (dev/staging/prod) — single production environment for now
- Horizontal pod autoscaling — fixed replica counts initially
- Blue-green or canary deployments — direct replacement strategy
- Backup automation for postgres — manual backup process acceptable for v1
- Custom metrics/monitoring dashboards — rely on existing Sentry integration
- Secret management via external tools (Vault, Sealed Secrets) — Kubernetes secrets sufficient

## Context

**Existing Codebase:**
- Firecrawl is a TypeScript/Node.js monorepo with API and worker services
- Uses Express for HTTP, BullMQ for job queues, Playwright for browser automation
- Supports multiple AI providers and configurable scraping engines
- Currently lacks container orchestration setup

**Infrastructure:**
- GCP project: prometheus-461323
- GKE cluster: client-cluster (already exists)
- Envoy Gateway already installed in cluster
- Argo CD already installed and running in cluster
- GCP credentials available at /Users/gqadonis/.gcp/credentials.json

**Domain Requirements:**
- API: firecrawl-api.prometheusags.ai
- Ingestion UI: firecrawl.prometheusags.ai
- TLS certificate from existing candle-vllm secret

## Constraints

- **Platform**: Google Kubernetes Engine only — no other cloud providers
- **Cluster**: client-cluster in prometheus-461323 project — cannot create new cluster
- **Namespace**: firecrawl — isolated from other cluster workloads
- **GitOps Tool**: Argo CD — already installed, must use it
- **Routing**: Envoy Gateway — already installed, must use HTTPRoutes
- **Trigger**: main branch only — no deployment from feature branches
- **Storage**: Immediate-binding storage class for postgres — required for proper operation
- **Monorepo**: All manifests in firecrawl/k8s/ — no separate manifest repo

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| GitOps pattern with Argo CD | Separates CI (build) from CD (deploy), provides auditability and easy rollbacks | — Pending |
| In-cluster postgres/redis | Simpler setup than managed services, sufficient for initial deployment | — Pending |
| Manifests in same repo | Simpler workflow, no need to manage separate repo permissions | — Pending |
| Envoy Gateway HTTPRoutes | Leverage existing installation, modern K8s native routing | — Pending |
| firecrawl namespace | Isolates workloads, clean separation from other cluster services | — Pending |
| Immediate-binding storage class | Ensures postgres PV binds immediately, prevents startup issues | — Pending |

---
*Last updated: 2026-03-27 after initialization*
