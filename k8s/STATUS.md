# Firecrawl Kubernetes Deployment Status

**Last Updated:** 2026-03-28

## ✅ Completed

### CI/CD Pipeline
- ✅ GitHub Actions workflow configured for automated builds
- ✅ Builds 3 services: firecrawl-api, ingestion-ui, playwright-service
- ✅ Images tagged with git SHA (immutable, auditable)
- ✅ Automatic kustomization.yaml updates after successful builds
- ✅ Workflow triggers on changes to `apps/api/**`, `apps/ui/ingestion-ui/**`, `apps/playwright-service-ts/**`
- ✅ Service account key authentication to GCP/GCR working

### Infrastructure
- ✅ Namespace: `firecrawl`
- ✅ ServiceAccounts created for all components
- ✅ RBAC configured
- ✅ PostgreSQL StatefulSet deployed (currently unused - using external Supabase)
- ✅ Redis StatefulSet deployed and running
- ✅ PersistentVolumeClaims bound with immediate-binding storage class

### Configuration
- ✅ ConfigMaps created: firecrawl-database, firecrawl-redis, firecrawl-application
- ✅ Secrets created: firecrawl-secrets, firecrawl-database-secret
- ✅ Database configured to use external Supabase PostgreSQL
- ✅ DISABLE_BLOCKLIST=true to avoid schema dependency
- ✅ All deployments use explicit command overrides for single-process containers
- ✅ Node.js heap tuning configured (85% of memory limit)
- ✅ Init containers wait for Postgres and Redis readiness

### Services Deployed
- ✅ ingestion-ui: Running (1/1)
- ✅ firecrawl-api: Running but not ready (health check failing)
- ⚠️ worker-extract, worker-nuq, worker-prefetch: CrashLoopBackOff
- ❌ playwright: ImagePullBackOff (waiting for CI build)

### External Access
- ✅ Envoy Gateway deployed
- ✅ Gateway listener configured for HTTP (80) and HTTPS (443)
- ✅ TLS certificate copied (prometheusags-wildcard-tls)
- ✅ HTTPRoutes created for API and UI
- ✅ HTTP → HTTPS redirect configured
- ✅ Gateway external IP: 136.114.242.214

## 🚧 In Progress

### CI/CD Build
- 🔄 Triggered build with changes to apps/api (commit 00e68e62)
- 🔄 Waiting for all 3 services to build with new tags
- 🔄 Playwright image will be available after build completes

## ❌ Blocking Issues

### 1. Workers Require RabbitMQ (NUQ_RABBITMQ_URL)

**Error:**
```
Error: NUQ_RABBITMQ_URL is not configured
```

**Impact:** All workers (extract, nuq, prefetch) are crashing

**Resolution Options:**
1. Deploy RabbitMQ StatefulSet in cluster
2. Use external managed RabbitMQ service (CloudAMQP, etc.)
3. Configure to use alternative queue backend (if supported)

**Next Steps:**
- Research Firecrawl's queue architecture
- Determine if Redis can be used as queue backend instead
- Deploy RabbitMQ if required

### 2. API Health Check Failing

**Status:** API is running but not passing readiness probe

**Impact:** Pod shows 0/1 ready

**Next Steps:**
- Check /health endpoint response
- Verify all required services are accessible
- Check logs for any startup warnings/errors

### 3. Missing Environment Variables

**Potential Issues:**
- INDEX_SUPABASE_SERVICE_TOKEN (warning in logs)
- AUTUMN_SECRET_KEY may need to be added to secrets
- Other optional environment variables may be needed

## 📋 Next Actions

### High Priority
1. **Deploy RabbitMQ**
   - Create RabbitMQ StatefulSet
   - Create RabbitMQ Service
   - Add NUQ_RABBITMQ_URL to ConfigMap or Secret
   - Restart worker deployments

2. **Debug API Health Check**
   - Curl /health endpoint from within cluster
   - Check if dependencies are all accessible
   - Review health check logic in code

3. **Wait for CI Build**
   - Monitor GitHub Actions workflow
   - Verify playwright-service image is built and pushed
   - Verify kustomization.yaml is updated with new tags

### Medium Priority
1. **DNS Configuration**
   - Add A record: firecrawl-api.prometheusags.ai → 136.114.242.214
   - Add A record: firecrawl.prometheusags.ai → 136.114.242.214
   - Test HTTPS access from external network

2. **Monitoring Setup**
   - Configure application metrics export
   - Set up Prometheus scraping
   - Create Grafana dashboards

3. **Backup Configuration**
   - Verify backup CronJob is running (currently using in-cluster Postgres, not external Supabase)
   - Update backup to target Supabase if needed
   - Test backup restoration procedure

### Low Priority
1. **Documentation**
   - Update roadmap with current status
   - Document RabbitMQ deployment
   - Create troubleshooting guide

2. **Optimization**
   - Review resource requests/limits based on actual usage
   - Configure horizontal pod autoscaling
   - Optimize Docker image sizes

## 📊 Deployment Health

| Component | Status | Ready | Notes |
|-----------|--------|-------|-------|
| postgres-0 | ✅ Running | 1/1 | In-cluster (unused, using Supabase) |
| redis-0 | ✅ Running | 1/1 | Working |
| ingestion-ui | ✅ Running | 1/1 | Healthy |
| firecrawl-api | ⚠️ Running | 0/1 | Needs health check debug |
| worker-extract | ❌ CrashLoopBackOff | 0/1 | Needs RabbitMQ |
| worker-nuq | ❌ CrashLoopBackOff | 0/1 | Needs RabbitMQ |
| worker-prefetch | ❌ CrashLoopBackOff | 0/1 | Needs RabbitMQ |
| playwright | ❌ ImagePullBackOff | 0/1 | Waiting for CI build |
| firecrawl-gateway | ✅ Programmed | - | External IP assigned |

## 🔐 Secrets Management

All secrets are documented in `SECRETS.md` and must be created manually via kubectl.

**Current Secrets:**
- ✅ firecrawl-secrets (7 keys)
- ✅ firecrawl-database-secret (2 keys)
- ✅ prometheusags-wildcard-tls (TLS certificate)

## 🚀 CI/CD Status

**Workflow:** `.github/workflows/ci-build-deploy.yml`
- Trigger: Push to main (paths: apps/api, apps/ui/ingestion-ui, apps/playwright-service-ts)
- Last Run: In progress (commit 00e68e62)
- Authentication: Service account key (GCP_SA_KEY secret)
- Registry: gcr.io/prometheus-461323
- Auto-commit: Updates kustomization.yaml with [skip ci]

## 📞 Support

For issues:
- Check pod logs: `kubectl logs <pod-name> -n firecrawl`
- Check events: `kubectl get events -n firecrawl --sort-by='.lastTimestamp'`
- Check ArgoCD: UI or `kubectl get application firecrawl -n argocd`
- Review documentation: `k8s/SECRETS.md`, `k8s/STATUS.md`
