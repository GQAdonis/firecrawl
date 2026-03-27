# Domain Pitfalls: Kubernetes GitOps with Argo CD + GitHub Actions + GKE

**Domain:** Node.js web application deployment to GKE using GitOps
**Researched:** 2026-03-27
**Confidence:** MEDIUM (based on well-documented patterns and common issues)

## Critical Pitfalls

Mistakes that cause rewrites, production outages, or major architectural issues.

### Pitfall 1: Image Tag Mutation Without Sync Detection
**What goes wrong:** Argo CD doesn't detect when a mutable image tag (like `latest` or `main`) points to a new image SHA. The deployment shows as "synced" but runs stale code, causing silent failures where new features don't deploy.

**Why it happens:** Kubernetes manifests reference tags, not image digests. When GitHub Actions pushes a new image with the same tag, the manifest YAML doesn't change, so Argo CD sees no diff to sync.

**Consequences:**
- Deployments appear successful but run old code
- Debugging is extremely difficult (manifest looks correct)
- Rollbacks are ambiguous (which image was actually deployed?)
- Production incidents from assuming new code is live

**Prevention:**
- Use immutable tags with Git SHA or build number: `gcr.io/prometheus-461323/firecrawl-api:${GITHUB_SHA:0:7}`
- Never use `latest`, `main`, `dev` tags in production
- Include image digest in manifest for verification: `image: foo:tag@sha256:abc123`
- Configure Argo CD sync with `--force` flag if needed (caution: can mask other issues)

**Detection:**
- Pods show old creation time despite "recent" deployment
- `kubectl describe pod` shows image pulled hours/days ago
- Application logs show old version/commit SHA
- Features merged to main aren't visible in deployed app

**Phase to address:** Phase 1 (CI/CD Setup) - Must be correct from day one

---

### Pitfall 2: Race Condition Between Image Push and Manifest Update
**What goes wrong:** GitHub Actions updates Kubernetes manifests with a new image tag before GCR finishes processing the image. Argo CD syncs immediately, but Kubernetes can't pull the image because it's not yet available in the registry, causing `ImagePullBackOff` errors.

**Why it happens:** Image push and manifest commit are separate sequential steps. Network latency or GCR's image processing delay creates a timing window where manifest references non-existent image.

**Consequences:**
- Deployments fail intermittently (works sometimes, fails others)
- Pods stuck in `ImagePullBackOff` or `ErrImagePull`
- Rollback cascade as Argo CD may revert to previous version
- False "registry authentication" debugging (auth is fine, timing is wrong)

**Prevention:**
- Wait for image availability before committing manifest:
  ```bash
  # After docker push
  gcloud container images describe gcr.io/prometheus-461323/firecrawl-api:${TAG} --format=json
  # Retry with exponential backoff until successful
  ```
- Use GitHub Actions step ordering with explicit dependencies
- Consider using Argo CD sync waves (annotation: `argocd.argoproj.io/sync-wave`) to delay dependent resources
- Set longer `imagePullBackOff` timeout in dev/staging to surface issue early

**Detection:**
- `ImagePullBackOff` on freshly pushed images
- `kubectl describe pod` shows "Failed to pull image: not found"
- GCR shows image exists but pod events show 404
- Timing correlation: fails within 30-60s of GitHub Actions completing

**Phase to address:** Phase 1 (CI/CD Setup) - Critical for reliable deployments

---

### Pitfall 3: StatefulSet Volume Binding Failure on Node Constraints
**What goes wrong:** Postgres StatefulSet PVC requests volume with `immediate-binding` storage class, but no nodes in the cluster satisfy zone/affinity constraints. Volume provisions successfully but never binds to a node, leaving postgres pod in `Pending` state permanently.

**Why it happens:** GKE's zonal storage (pd-ssd, pd-standard) must attach to nodes in the same zone. If StatefulSet anti-affinity or node selectors restrict scheduling, volume may exist in zone A while only zone B nodes are available.

**Consequences:**
- Postgres never starts, API can't function
- PVC shows "Bound" but pod stays "Pending"
- Entire application stack is down
- Not obvious from pod events (focus is on scheduling, not volume)
- Regional PD is 2-3x more expensive (common but costly workaround)

**Prevention:**
- Use `volumeBindingMode: WaitForFirstConsumer` storage class (default for GKE 1.23+)
- Verify node topology matches storage class zones:
  ```bash
  kubectl get nodes -o=jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}{end}'
  ```
- Test StatefulSet scheduling in namespace before production:
  ```yaml
  # Add to postgres StatefulSet
  spec:
    template:
      spec:
        topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
  ```
- Document required node zones in PROJECT.md constraints

**Detection:**
- `kubectl get pvc` shows "Bound" but pod is "Pending"
- `kubectl describe pod postgres-0` shows "0/N nodes available: N node(s) had volume node affinity conflict"
- `kubectl get events` shows repeated scheduling attempts
- No postgres logs (container never starts)

**Phase to address:** Phase 2 (Database Setup) - Must validate before deploying postgres

---

### Pitfall 4: Missing Resource Limits Cause Node Memory Exhaustion
**What goes wrong:** Node.js processes (API, workers) don't have memory limits defined. Under load, one process allocates beyond node capacity, triggering OOMKiller which terminates random pods on the node, including unrelated services.

**Why it happens:** Node.js V8 heap grows unbounded by default. Without Kubernetes `resources.limits.memory`, cgroup doesn't restrict allocation. GKE nodes have shared memory, so one tenant can starve others.

**Consequences:**
- Cascading pod failures across namespace
- "Random" pod restarts under load
- Difficult root cause analysis (OOMKilled pod may not be the culprit)
- Potential eviction of critical services like postgres
- Cluster instability affecting other tenants

**Prevention:**
- Define memory limits for all containers:
  ```yaml
  resources:
    requests:
      memory: "512Mi"
      cpu: "500m"
    limits:
      memory: "1Gi"
      cpu: "1000m"
  ```
- Set Node.js `--max-old-space-size` to 85% of container limit:
  ```dockerfile
  CMD ["node", "--max-old-space-size=870", "dist/src/index.js"]
  # 870MB = 85% of 1024MB limit
  ```
- Configure `LimitRange` in namespace to enforce defaults:
  ```yaml
  apiVersion: v1
  kind: LimitRange
  metadata:
    name: firecrawl-limits
  spec:
    limits:
    - default:
        memory: 1Gi
        cpu: 1000m
      defaultRequest:
        memory: 512Mi
        cpu: 500m
      type: Container
  ```
- Monitor with `kubectl top pods` and set up memory usage alerts

**Detection:**
- `kubectl describe pod` shows `OOMKilled` in last termination reason
- Pods restart frequently under load
- `kubectl top nodes` shows memory near 100%
- Application logs abruptly stop (no graceful shutdown)
- Prometheus/metrics show memory spikes before crash

**Phase to address:** Phase 3 (Resource Configuration) - Required before load testing

---

### Pitfall 5: Argo CD Self-Sync Loop from Automatic Manifest Updates
**What goes wrong:** GitHub Actions commits updated manifests to the same branch Argo CD watches. If the workflow triggers on push to that branch, each deployment triggers another workflow run, creating an infinite loop of commits and syncs.

**Why it happens:** Workflow has `on: push: branches: [main]` and commits to `main` after building images. GitHub Actions sees its own commit as a trigger, runs again, commits again, repeats forever.

**Consequences:**
- Hundreds of redundant workflow runs consume GitHub Actions minutes
- Argo CD continuously syncs, creating deployment churn
- Hard to identify legitimate deployments vs loop iterations
- Potential rate limiting from GitHub or GCR
- Difficult to stop once started (requires manual intervention)

**Prevention:**
- Skip workflow on bot commits using conditional:
  ```yaml
  on:
    push:
      branches: [main]
  jobs:
    build:
      if: "!contains(github.event.head_commit.message, '[skip ci]')"
  ```
- Use personal access token (PAT) or GitHub App token for commits that shouldn't trigger workflows
- Commit manifest updates with `[skip ci]` in message:
  ```bash
  git commit -m "Update image tags [skip ci]"
  ```
- Alternative: Use separate manifest branch (`gitops-main`) that workflow doesn't watch
- Configure Argo CD to ignore specific manifest fields that change frequently

**Detection:**
- GitHub Actions shows rapid-fire workflow runs (multiple per minute)
- All recent commits have same message ("Update image tags")
- Commit author is `github-actions[bot]`
- Argo CD UI shows continuous sync activity
- No actual code changes between deployments

**Phase to address:** Phase 1 (CI/CD Setup) - Prevent before first deployment

---

### Pitfall 6: Hardcoded Secrets in Manifests Committed to Git
**What goes wrong:** Developers commit Kubernetes Secret manifests with base64-encoded sensitive values (database passwords, API keys) directly to the repository. Base64 is encoding, not encryption—secrets are fully visible to anyone with repo access and in Git history.

**Why it happens:** Kubernetes requires secrets to be base64 encoded. Developers treat this as security. GitOps requires manifests in Git. These requirements seem to conflict, leading to "just commit it" approach.

**Consequences:**
- All secrets exposed in Git history (even if file is later deleted)
- Secrets visible to all developers with repo access
- Secrets leak in PRs, code reviews, commit diffs
- Difficult to rotate (requires updating all manifests and Git history)
- Compliance violations (SOC 2, GDPR, PCI-DSS)
- Potential security breach if repo is compromised

**Prevention:**
- Create secrets manually in cluster via `kubectl create secret`:
  ```bash
  kubectl create secret generic postgres-credentials \
    --from-literal=password="$(openssl rand -base64 32)" \
    -n firecrawl
  ```
- Use external secret management (Google Secret Manager + External Secrets Operator):
  ```yaml
  apiVersion: external-secrets.io/v1beta1
  kind: ExternalSecret
  metadata:
    name: postgres-credentials
  spec:
    secretStoreRef:
      name: gcpsm
      kind: SecretStore
    target:
      name: postgres-credentials
    data:
    - secretKey: password
      remoteRef:
        key: firecrawl-postgres-password
  ```
- Alternative: Sealed Secrets (encrypts secrets in Git, only cluster can decrypt)
- Add `.gitignore` rule for `**/secret*.yaml` as safety net
- Git pre-commit hook to prevent committing base64-encoded secrets

**Detection:**
- `git log -p | grep "kind: Secret"` shows secret manifests in history
- Base64 strings visible in `git diff`
- Security scanning tools flag sensitive data
- Secrets rotation requires Git force-push to rewrite history
- Argo CD shows secrets in plain diff view

**Phase to address:** Phase 0 (Security Foundation) - Must address before any secrets exist

---

### Pitfall 7: Single Postgres Instance Without Backup Strategy
**What goes wrong:** Postgres runs as single StatefulSet replica with PersistentVolume. Volume corruption, accidental deletion, namespace wipe, or PV provider failure causes total data loss. No backups exist.

**Why it happens:** Focus on "getting it working" before implementing backup strategy. PersistentVolumes feel durable (they persist!), creating false sense of safety. Backups are seen as "phase 2" work.

**Consequences:**
- Permanent data loss from operator error
- No recovery path from corruption or bugs
- Can't test disaster recovery procedures
- Can't rollback schema migrations that corrupt data
- Business continuity failure

**Prevention:**
- Implement pg_dump backups to GCS before any production data:
  ```yaml
  apiVersion: batch/v1
  kind: CronJob
  metadata:
    name: postgres-backup
  spec:
    schedule: "0 */6 * * *"  # Every 6 hours
    jobTemplate:
      spec:
        template:
          spec:
            containers:
            - name: backup
              image: postgres:15
              command:
              - /bin/bash
              - -c
              - |
                pg_dump -Fc $DATABASE_URL | \
                gzip > /tmp/backup-$(date +%Y%m%d-%H%M%S).sql.gz
                gsutil cp /tmp/backup-*.sql.gz gs://firecrawl-backups/
  ```
- Retain PV after StatefulSet deletion with `persistentVolumeReclaimPolicy: Retain`
- Test restoration procedure monthly
- Document recovery steps in runbook
- Consider Cloud SQL for Postgres (managed backups) if budget allows

**Detection:**
- No backups exist in GCS bucket
- Can't answer "when was last backup?"
- No documented recovery procedure
- `kubectl get pv` shows `Delete` reclaim policy (should be `Retain`)
- No monitoring alert for backup job failures

**Phase to address:** Phase 2 (Database Setup) - Implement before production launch

---

### Pitfall 8: Service Mesh / Envoy Gateway TLS Configuration Mismatch
**What goes wrong:** Envoy Gateway HTTPRoute configured for HTTPS, but backend Service expects plain HTTP. Or vice versa: HTTPRoute sends HTTP while Service expects HTTPS. Results in SSL handshake errors, connection refused, or infinite redirects.

**Why it happens:** TLS termination point confusion. Multiple places can do TLS: Envoy Gateway (edge), Service (backend), Pod (application). Misconfiguration causes protocol mismatch.

**Consequences:**
- 502 Bad Gateway errors despite healthy pods
- `curl` works inside cluster but external requests fail
- SSL certificate errors that don't make sense
- Infinite redirect loops (HTTP → HTTPS → HTTP)
- Difficult debugging (error messages are cryptic)

**Prevention:**
- Document TLS termination architecture explicitly:
  ```
  External Client → [HTTPS] → Envoy Gateway (TLS terminates here)
                              ↓
                            [HTTP] → Backend Service → Pod
  ```
- Verify HTTPRoute backend reference matches Service protocol:
  ```yaml
  apiVersion: gateway.networking.k8s.io/v1beta1
  kind: HTTPRoute
  spec:
    rules:
    - backendRefs:
      - name: firecrawl-api
        port: 3002  # Must match Service port
  ---
  apiVersion: v1
  kind: Service
  spec:
    ports:
    - port: 3002
      targetPort: 3002
      protocol: TCP
  ```
- Test internal and external connectivity separately:
  ```bash
  # Internal (should work)
  kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
    curl -v http://firecrawl-api.firecrawl.svc.cluster.local:3002

  # External (should work)
  curl -v https://firecrawl-api.prometheusags.ai
  ```
- Check Envoy Gateway logs for backend connection errors:
  ```bash
  kubectl logs -n envoy-gateway-system deployment/envoy-gateway
  ```

**Detection:**
- 502 Bad Gateway or 503 Service Unavailable from external requests
- Internal requests work but external fail
- `kubectl logs` in Envoy shows "SSL handshake failed" or "connection refused"
- Browser shows "ERR_TOO_MANY_REDIRECTS"
- `openssl s_client -connect ...` shows protocol mismatch

**Phase to address:** Phase 4 (Routing Setup) - Validate before external DNS configuration

---

## Moderate Pitfalls

Issues that cause friction but are recoverable without major changes.

### Pitfall 9: Argo CD Sync Timeout on Large Image Pulls
**What goes wrong:** First deployment of large images (500MB+) times out in Argo CD sync. Argo CD marks sync as failed even though pods are actually pulling images and will eventually succeed.

**Why it happens:** Default Argo CD sync timeout (typically 5 minutes) is too short for large image downloads, especially on slower network connections or cold cache.

**Prevention:**
- Increase Argo CD sync timeout in Application spec:
  ```yaml
  apiVersion: argoproj.io/v1alpha1
  kind: Application
  spec:
    syncPolicy:
      syncOptions:
      - Timeout=20m
  ```
- Pre-pull critical images to nodes:
  ```bash
  gcloud compute ssh NODE_NAME --command="docker pull gcr.io/prometheus-461323/firecrawl-api:TAG"
  ```
- Use smaller base images (alpine, distroless)
- Optimize Docker layer caching in builds

**Detection:**
- Argo CD shows "Sync Failed" but pods are in "ContainerCreating"
- `kubectl describe pod` shows image pull in progress
- Sync succeeds on retry without changes
- Larger images take longer to fail

**Phase to address:** Phase 1 (CI/CD Setup)

---

### Pitfall 10: Node.js Worker Process CPU Throttling
**What goes wrong:** BullMQ workers processing jobs experience severe latency (10x slower) when CPU limits are set too low. Jobs that should take 1s take 10s, causing queue backlog.

**Why it happens:** Node.js is single-threaded. If CPU limit is 100m (10% of core), worker spends 90% of time throttled. Kubernetes enforces limits via CFS throttling, not nice values.

**Prevention:**
- Measure actual CPU usage before setting limits:
  ```bash
  kubectl top pods --containers -n firecrawl
  ```
- Set limits above peak usage + 50% headroom
- Consider CPU requests without limits for bursty workloads:
  ```yaml
  resources:
    requests:
      cpu: "500m"
    limits:
      memory: "1Gi"
      # No CPU limit = can burst
  ```
- Monitor CPU throttling metrics:
  ```bash
  kubectl get --raw /apis/metrics.k8s.io/v1beta1/namespaces/firecrawl/pods/worker-0 | jq
  ```

**Detection:**
- `kubectl top pods` shows CPU at 100% of limit constantly
- Job processing time 5-10x higher than expected
- Worker logs show slow operations
- Adding more workers doesn't increase throughput
- Container metrics show CPU throttling counter increasing

**Phase to address:** Phase 5 (Performance Tuning)

---

### Pitfall 11: Redis Connection Pool Exhaustion from Multiple Workers
**What goes wrong:** All BullMQ workers share single Redis service. Each worker creates connection pool (default 50 connections). 10 workers = 500 connections, exceeding Redis maxclients (default 10000 sounds fine, but each connection uses memory).

**Why it happens:** Default IORedis connection pool sizing doesn't account for multiple worker pods. Redis runs out of memory or file descriptors before hitting maxclients.

**Prevention:**
- Tune IORedis connection pool per worker:
  ```typescript
  const redis = new Redis({
    maxRetriesPerRequest: null,
    maxLoadingRetryTime: 5000,
    poolSize: 10, // Reduce from default 50
  });
  ```
- Increase Redis memory limits and maxclients:
  ```yaml
  # redis.conf
  maxclients 20000
  ```
- Monitor Redis connection count:
  ```bash
  kubectl exec -it redis-0 -- redis-cli INFO clients
  ```

**Detection:**
- Workers fail with "ERR max number of clients reached"
- Redis memory usage grows with worker count
- `redis-cli CLIENT LIST` shows hundreds of connections
- Worker pods can't establish new connections

**Phase to address:** Phase 6 (Scaling Workers)

---

### Pitfall 12: Incomplete Environment Variable Configuration in Manifests
**What goes wrong:** Application expects environment variables (REDIS_HOST, DATABASE_URL, SENTRY_DSN) but Kubernetes manifest uses different naming or structure. Pods start but fail at runtime with "undefined is not a function" errors.

**Why it happens:** Environment variable drift between local development (.env file) and Kubernetes (ConfigMap/env). No validation that required vars exist until runtime.

**Prevention:**
- Generate Kubernetes manifests from .env file:
  ```bash
  # Script to convert .env to ConfigMap
  kubectl create configmap firecrawl-config \
    --from-env-file=apps/api/.env.example \
    --dry-run=client -o yaml > k8s/configmap.yaml
  ```
- Validate required env vars at app startup:
  ```typescript
  const requiredEnvs = ['REDIS_HOST', 'DATABASE_URL', 'SENTRY_DSN'];
  for (const env of requiredEnvs) {
    if (!process.env[env]) {
      throw new Error(`Missing required environment variable: ${env}`);
    }
  }
  ```
- Document env var mapping between .env and Kubernetes
- Use init container to validate configuration before main container starts

**Detection:**
- Application crashes immediately after startup
- Logs show "Cannot read property X of undefined"
- `kubectl logs` shows missing configuration errors
- Works locally but not in Kubernetes
- Different behavior between pods (some have config, others don't)

**Phase to address:** Phase 3 (Configuration Management)

---

## Minor Pitfalls

Small issues that cause annoyance but are easily fixed.

### Pitfall 13: Argo CD Application Prune Deletes Manual Resources
**What goes wrong:** Developer creates resources manually in cluster for debugging (test pod, temporary configmap). Argo CD sync with auto-prune enabled deletes these resources as "not in Git."

**Why it happens:** GitOps principle: cluster state should match Git exactly. Manual resources violate this. Auto-prune enforces it strictly.

**Prevention:**
- Disable auto-prune for development environments
- Use annotations to exclude resources from pruning:
  ```yaml
  metadata:
    annotations:
      argocd.argoproj.io/compare-options: IgnoreExtraneous
  ```
- Create debug resources in separate namespace
- Use `kubectl apply --dry-run=client` to test before creating

**Detection:**
- Resources disappear after Argo CD sync
- Argo CD logs show "Pruned" for unexpected resources
- Manual troubleshooting work is undone automatically

**Phase to address:** Phase 1 (Argo CD Configuration)

---

### Pitfall 14: Container Image Pull Rate Limiting
**What goes wrong:** GitHub Actions pulls base images from Docker Hub (node:18, postgres:15) during build. After 100-200 pulls per 6 hours, Docker Hub rate limits anonymous pulls, causing workflow failures.

**Why it happens:** Docker Hub instituted rate limits in 2020. Anonymous pulls are limited per IP. GitHub Actions shared runners use shared IPs.

**Prevention:**
- Authenticate with Docker Hub before pulling:
  ```yaml
  - name: Login to Docker Hub
    uses: docker/login-action@v3
    with:
      username: ${{ secrets.DOCKERHUB_USERNAME }}
      password: ${{ secrets.DOCKERHUB_TOKEN }}
  ```
- Use Google Container Registry or Artifact Registry for base images:
  ```dockerfile
  FROM gcr.io/google-appengine/nodejs:18
  ```
- Cache base images in GCR:
  ```bash
  docker pull node:18
  docker tag node:18 gcr.io/prometheus-461323/node:18
  docker push gcr.io/prometheus-461323/node:18
  ```

**Detection:**
- GitHub Actions fails with "toomanyrequests: You have reached your pull rate limit"
- Intermittent failures during busy periods
- Fails early in workflow (docker pull step)

**Phase to address:** Phase 1 (CI/CD Setup)

---

### Pitfall 15: Namespace Resource Quotas Block Deployments
**What goes wrong:** GKE cluster has namespace ResourceQuota configured. Firecrawl deployment requests total resources exceeding quota, causing pods to stay pending with "forbidden: exceeded quota" error.

**Why it happens:** Cluster admins set quotas to prevent resource hogging. New deployments don't account for total namespace consumption.

**Prevention:**
- Check namespace quotas before deployment:
  ```bash
  kubectl describe quota -n firecrawl
  kubectl describe limitrange -n firecrawl
  ```
- Calculate total resource requests across all manifests:
  ```bash
  kubectl apply -f k8s/ --dry-run=server
  ```
- Request quota increase from cluster admin if needed
- Use VerticalPodAutoscaler to righsize requests

**Detection:**
- Pods stuck in "Pending" with no error events
- `kubectl describe pod` shows "failed quota: compute-resources"
- `kubectl get events` shows "Error creating: pods 'foo' is forbidden: exceeded quota"

**Phase to address:** Phase 0 (Pre-deployment Validation)

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| CI/CD Setup (Phase 1) | Image tag mutation (#1), sync loops (#5), Docker Hub rate limiting (#14) | Use immutable tags, skip CI on bot commits, authenticate pulls |
| Database Setup (Phase 2) | Volume binding failures (#3), no backup strategy (#7) | Validate storage class, implement backups immediately |
| Configuration (Phase 3) | Missing env vars (#12), resource limits (#4) | Generate from .env, set memory limits + Node.js heap |
| Routing Setup (Phase 4) | TLS termination mismatch (#8) | Document architecture, test internal vs external separately |
| Performance (Phase 5) | CPU throttling (#10) | Measure before limiting, allow bursting for workers |
| Scaling (Phase 6) | Redis connection exhaustion (#11) | Tune connection pools, monitor Redis connections |

---

## Source Notes

**Confidence Level:** MEDIUM

**Sources:**
- Kubernetes official documentation patterns (training data, January 2025)
- Argo CD community issues and best practices (training data)
- Node.js in Kubernetes production patterns (training data)
- GKE-specific behaviors documented by Google (training data)

**Research Limitations:**
- Unable to access current web sources due to tool restrictions
- Relying on training data knowledge (current as of January 2025)
- Cannot verify latest Argo CD version-specific issues
- No access to Context7 for library-specific documentation

**Validation Recommendations:**
- Verify Argo CD sync timeout defaults for current version
- Check GKE storage class defaults for prometheus-461323 project
- Confirm Envoy Gateway version and HTTPRoute API stability
- Test image pull timing in actual GCR/GitHub Actions environment
- Validate Redis maxclients defaults in planned Redis version

**High Confidence Areas:**
- Image tag mutation issues (fundamental to GitOps)
- StatefulSet volume binding (Kubernetes core behavior)
- Resource limits and OOMKiller (cgroup/kernel behavior)
- Secret management anti-patterns (security fundamentals)
- TLS termination confusion (common architectural issue)

**Medium Confidence Areas:**
- Argo CD specific timeout values (version-dependent)
- GKE node topology defaults (project-dependent)
- Redis connection pool defaults (version-dependent)
- GitHub Actions rate limiting thresholds (policy changes)

---

## Additional Considerations

### Testing Strategy
Each critical pitfall should have a validation test before production:

1. **Image Tag Mutation:** Deploy twice with same tag, verify different content deploys
2. **Race Condition:** Artificially delay image availability, confirm handling
3. **Volume Binding:** Create StatefulSet in test namespace, verify scheduling
4. **Resource Limits:** Load test with limited resources, monitor throttling
5. **Sync Loop:** Commit manifest change, verify single workflow execution
6. **Secrets:** Attempt to commit secret manifest, verify pre-commit hook blocks
7. **Backup Strategy:** Delete test database, restore from backup successfully
8. **TLS Configuration:** External HTTPS request, internal HTTP request both succeed

### Monitoring Requirements
Deploy with observability for early pitfall detection:

- Image pull duration metrics (detect race conditions)
- Argo CD sync duration and failure rate
- Pod restart count by reason (OOMKilled, Error, CrashLoopBackOff)
- PVC binding time and failures
- Redis connection count and client list
- Node memory and CPU pressure
- Workflow execution duration and failure rate

### Documentation Needs
Create runbooks for common pitfall scenarios:

- "Deployment stuck in sync" → Check image availability, verify tag mutation
- "Pods pending" → Check PVC binding, verify resource quotas, confirm node topology
- "502 Bad Gateway" → Verify TLS termination, check backend connectivity
- "Workflow loop" → Identify trigger, stop workflow, remove bad commits
- "Data loss incident" → Backup restoration procedure step-by-step
