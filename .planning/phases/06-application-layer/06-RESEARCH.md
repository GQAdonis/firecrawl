# Phase 6: Application Layer - Research

**Researched:** 2026-03-27
**Domain:** Kubernetes Deployments for Node.js Applications (API, Workers, UI, Playwright)
**Confidence:** MEDIUM

## Summary

Phase 6 deploys the Firecrawl application services as Kubernetes Deployments after the data layer (Phase 5 Postgres/Redis) is healthy. The architecture includes four deployment types: firecrawl-api (main HTTP API), multiple worker deployments (extract, nuq, prefetch for BullMQ job processing), ingestion-ui (web interface), and playwright-service (browser automation). Each deployment requires resource limits, health probes, init containers for database readiness checks, and proper Node.js heap configuration to prevent OOM kills.

The critical success factors are Node.js memory tuning (--max-old-space-size to 85% of container limit), init containers that block startup until dependencies are healthy, conservative resource limits based on actual workload profiling, and startup-aware health probes that prevent premature restarts. The API and workers must successfully connect to Postgres/Redis before accepting traffic.

**Primary recommendation:** Deploy API and workers as Deployments with single replicas, configure NODE_OPTIONS environment variable to set heap size, add init containers using busybox nc for dependency checks, set livenessProbe with long initialDelaySeconds during startup, configure readinessProbe for traffic gating, create ClusterIP Services for internal communication, and use existing ingestion-ui and playwright-service Dockerfiles without modification.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| APP-01 | Firecrawl API Deployment created | Deployment with firecrawl-api image built in Phase 1, container port 3002 from config |
| APP-02 | API has memory and CPU resource limits configured | Resources: requests (1 CPU, 2Gi memory), limits (4 CPU, 8Gi memory) for stable API processing |
| APP-03 | API has Node.js --max-old-space-size set to 85% of memory limit | NODE_OPTIONS env var with --max-old-space-size=6800 (85% of 8Gi = 6.8Gi = 6963Mi, 6800Mi safe) |
| APP-04 | API has readiness and liveness probes configured | HTTP probes on /liveness endpoint (readinessProbe initialDelaySeconds: 30s, livenessProbe: 60s) |
| APP-05 | API has init container that waits for Postgres/Redis readiness | Init container using busybox with nc (netcat) to test postgres-service:5432 and redis-service:6379 |
| APP-06 | Worker Deployments created (extract, nuq, prefetch workers) | Three separate Deployments: extract-worker, nuq-worker, prefetch-worker using same firecrawl-api image with different commands |
| APP-07 | Workers have memory and CPU resource limits configured | Extract: (1 CPU, 4Gi) → (2 CPU, 8Gi); NuQ: (1 CPU, 2Gi) → (2 CPU, 4Gi); Prefetch: (500m, 1Gi) → (1 CPU, 2Gi) |
| APP-08 | Workers have Node.js --max-old-space-size set to 85% of memory limit | Extract: 6800Mi; NuQ: 3400Mi; Prefetch: 1700Mi (85% of limits) |
| APP-09 | Workers have readiness and liveness probes configured | HTTP probes on worker-specific ports: extract /health:3004, nuq /health:3000, prefetch /health:3011 |
| APP-10 | Workers have init containers that wait for Postgres/Redis readiness | Same init container pattern as API (wait for postgres-service and redis-service) |
| APP-11 | Ingestion UI Deployment created | Deployment using ingestion-ui image built in Phase 1, nginx serving static content on port 80 |
| APP-12 | UI has memory and CPU resource limits configured | Resources: requests (100m CPU, 128Mi memory), limits (500m CPU, 512Mi memory) for static site |
| APP-13 | UI has readiness and liveness probes configured | HTTP probes on port 80 path / (readinessProbe initialDelaySeconds: 5s, livenessProbe: 10s) |
| APP-14 | Playwright Deployment created for browser automation | Deployment using playwright-service image (separate app in monorepo), Chromium browser automation |
| APP-15 | Playwright has memory and CPU resource limits configured | Resources: requests (1 CPU, 2Gi memory), limits (2 CPU, 4Gi memory) for browser automation |
| APP-16 | Kubernetes Services created for all application components | ClusterIP Services: firecrawl-api-service:3002, ingestion-ui-service:80, playwright-service:3000; workers don't need Services (internal only) |
</phase_requirements>

## Standard Stack

### Core Components

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| node | 22-slim | Node.js runtime base image | Official image used in apps/api/Dockerfile, matches production build |
| nginx | alpine | Static file web server | Lightweight server for ingestion-ui static assets (if built) |
| playwright | 1.58.1 | Browser automation library | Version from apps/playwright-service-ts/package.json, Chromium automation |
| busybox | latest | Init container utilities | Minimal image with nc (netcat) for dependency checks |
| Deployment | apps/v1 | Manages stateless application pods | Kubernetes standard for stateless services |
| Service | v1 | Provides stable DNS endpoints | Kubernetes standard for service discovery |
| ConfigMap | v1 | Environment configuration | Injects non-secret config into containers |

### Supporting Libraries (from apps/api/package.json)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| bullmq | ^5.56.7 | Redis-based job queue | Worker deployments process jobs from BullMQ queues |
| ioredis | ^5.6.1 | Redis client for Node.js | API and workers connect to Redis for caching and queues |
| pg | ^8.16.3 | PostgreSQL client | API connects to Postgres for persistent data |
| express | 4.22.0 | HTTP framework | API exposes REST endpoints and health checks |
| @sentry/node | ^10.27.0 | Error monitoring | Already integrated, no additional K8s config needed |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Deployment (single replica) | StatefulSet | Deployment is simpler for stateless services; StatefulSet only needed for stable pod identity |
| Init container with nc | readinessProbe with failureThreshold | Init container blocks startup completely; readinessProbe allows pod to start but blocks traffic |
| Separate worker Deployments | Single Deployment with multiple containers | Separate Deployments allow independent scaling and resource limits per worker type |
| busybox for init container | postgres/redis client images | busybox is 5MB vs 200MB+ for full database images, faster pod startup |
| HTTP health probes | Exec-based probes | HTTP probes are less invasive, don't spawn processes inside containers |
| NODE_OPTIONS env var | Dockerfile CMD modification | Environment variable is more flexible, allows runtime tuning without rebuilding images |

**Installation:**

Application containers are built in Phase 1 CI pipeline. No manual installation needed. Images pushed to GCR: `us.gcr.io/prometheus-461323/firecrawl-api:SHA`, `us.gcr.io/prometheus-461323/ingestion-ui:SHA`.

**Version verification:**

```bash
# Verify Node.js version in base image (matches Dockerfile)
docker run --rm node:22-slim node --version
# v22.x.x

# Verify Playwright version (from package.json)
grep '"playwright"' apps/playwright-service-ts/package.json
# "playwright": "^1.58.1"

# Check BullMQ version (from package.json)
grep '"bullmq"' apps/api/package.json
# "bullmq": "^5.56.7"
```

**Current versions confirmed:** node:22-slim (LTS until 2027-04-30), bullmq@5.56.7 (latest as of 2026-01), ioredis@5.6.1, pg@8.16.3. Training data current through January 2025; patch versions may have advanced but major versions are stable.

## Architecture Patterns

### Recommended Project Structure

```
k8s/base/
├── postgres-statefulset.yaml         # [Phase 5] Postgres database
├── redis-statefulset.yaml            # [Phase 5] Redis cache/queue
├── api-deployment.yaml               # [Phase 6] Main API Deployment
├── api-service.yaml                  # [Phase 6] API ClusterIP Service
├── extract-worker-deployment.yaml    # [Phase 6] Extract worker
├── nuq-worker-deployment.yaml        # [Phase 6] NuQ worker
├── prefetch-worker-deployment.yaml   # [Phase 6] Prefetch worker
├── ingestion-ui-deployment.yaml      # [Phase 6] Web UI
├── ingestion-ui-service.yaml         # [Phase 6] UI ClusterIP Service
├── playwright-deployment.yaml        # [Phase 6] Playwright service
├── playwright-service.yaml           # [Phase 6] Playwright ClusterIP Service
└── kustomization.yaml                # Updated to include Phase 6 resources
```

### Pattern 1: Node.js Deployment with Memory Tuning

**What:** Deployment with NODE_OPTIONS environment variable that sets V8 heap size to 85% of container memory limit.

**When to use:** For all Node.js containers (API, workers) to prevent OOM kills from V8 exceeding container memory limit.

**Example:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: firecrawl-api
  namespace: firecrawl
  labels:
    app: firecrawl-api
    component: api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: firecrawl-api
  template:
    metadata:
      labels:
        app: firecrawl-api
        component: api
    spec:
      serviceAccountName: firecrawl-api
      initContainers:
      - name: wait-for-postgres
        image: busybox:latest
        command:
        - sh
        - -c
        - |
          until nc -z postgres-service.firecrawl.svc.cluster.local 5432; do
            echo "Waiting for postgres..."
            sleep 2
          done
          echo "Postgres is ready"
      - name: wait-for-redis
        image: busybox:latest
        command:
        - sh
        - -c
        - |
          until nc -z redis-service.firecrawl.svc.cluster.local 6379; do
            echo "Waiting for redis..."
            sleep 2
          done
          echo "Redis is ready"
      containers:
      - name: firecrawl-api
        image: firecrawl-api  # Kustomize transforms to full GCR path with SHA
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 3002
          name: http
          protocol: TCP
        env:
        - name: NODE_OPTIONS
          value: "--max-old-space-size=6800"  # 85% of 8Gi limit = 6963Mi, use 6800Mi safe margin
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
            name: firecrawl-redis-secret
        - secretRef:
            name: firecrawl-api-secret
        resources:
          requests:
            cpu: 1
            memory: 2Gi
          limits:
            cpu: 4
            memory: 8Gi
        readinessProbe:
          httpGet:
            path: /liveness
            port: 3002
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /liveness
            port: 3002
          initialDelaySeconds: 60
          periodSeconds: 20
          timeoutSeconds: 5
          failureThreshold: 3
```

**Key fields:**
- `NODE_OPTIONS: "--max-old-space-size=6800"` - Prevents V8 heap from exceeding container memory limit (8Gi limit → 6800Mi heap)
- `initContainers` - Block pod startup until Postgres and Redis are reachable (prevents connection errors during startup)
- `imagePullPolicy: IfNotPresent` - Use cached images on node, faster startup than Always
- `readinessProbe.initialDelaySeconds: 30` - Give Node.js time to start Express server before checking readiness
- `livenessProbe.initialDelaySeconds: 60` - Longer delay prevents restarts during slow startup (dependency connections, initialization)
- `failureThreshold: 3` - Allow 3 consecutive failures before marking unhealthy (tolerates transient network issues)

**Memory calculation:**
- Container limit: 8Gi = 8192Mi
- 85% for heap: 8192 * 0.85 = 6963Mi
- Safe value: 6800Mi (leaves 200Mi buffer for V8 internals, native modules, and OS overhead)

### Pattern 2: Worker Deployment with Different Entry Points

**What:** Deployment using the same firecrawl-api image but different CMD to start specific worker processes.

**When to use:** For worker processes that share the same codebase but run different entry points (extract-worker.js, nuq-worker.js, etc.).

**Example:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: extract-worker
  namespace: firecrawl
  labels:
    app: extract-worker
    component: worker
spec:
  replicas: 1
  selector:
    matchLabels:
      app: extract-worker
  template:
    metadata:
      labels:
        app: extract-worker
        component: worker
    spec:
      serviceAccountName: firecrawl-worker
      initContainers:
      - name: wait-for-postgres
        image: busybox:latest
        command:
        - sh
        - -c
        - |
          until nc -z postgres-service.firecrawl.svc.cluster.local 5432; do
            echo "Waiting for postgres..."
            sleep 2
          done
          echo "Postgres is ready"
      - name: wait-for-redis
        image: busybox:latest
        command:
        - sh
        - -c
        - |
          until nc -z redis-service.firecrawl.svc.cluster.local 6379; do
            echo "Waiting for redis..."
            sleep 2
          done
          echo "Redis is ready"
      containers:
      - name: extract-worker
        image: firecrawl-api  # Same image as API
        imagePullPolicy: IfNotPresent
        command: ["node"]
        args: ["dist/src/services/extract-worker.js"]  # Different entry point
        ports:
        - containerPort: 3004
          name: http
          protocol: TCP
        env:
        - name: NODE_OPTIONS
          value: "--max-old-space-size=6800"  # 85% of 8Gi limit
        - name: EXTRACT_WORKER_PORT
          value: "3004"
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
            name: firecrawl-redis-secret
        - secretRef:
            name: firecrawl-api-secret
        resources:
          requests:
            cpu: 1
            memory: 4Gi
          limits:
            cpu: 2
            memory: 8Gi
        readinessProbe:
          httpGet:
            path: /health
            port: 3004
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /liveness
            port: 3004
          initialDelaySeconds: 60
          periodSeconds: 20
          timeoutSeconds: 5
          failureThreshold: 3
```

**Key fields:**
- `command: ["node"]` and `args: ["dist/src/services/extract-worker.js"]` - Override Dockerfile CMD to run specific worker
- Different port per worker type (extract: 3004, nuq: 3000, prefetch: 3011) from config.ts
- Health probes target worker-specific ports and paths (/health, /liveness)
- Same init containers for database dependency checks
- No Service needed for workers (they consume from queue, don't receive inbound traffic)

**Worker types and resource profiles:**
1. **Extract Worker** (extract-worker.js): AI extraction jobs, high memory for LLM processing
   - Resources: (1 CPU, 4Gi) → (2 CPU, 8Gi)
   - Heap: 6800Mi
   - Port: 3004

2. **NuQ Worker** (nuq-worker.js): Web scraping jobs, moderate memory for page rendering
   - Resources: (1 CPU, 2Gi) → (2 CPU, 4Gi)
   - Heap: 3400Mi
   - Port: 3000

3. **Prefetch Worker** (nuq-prefetch-worker.js): Job pre-fetching, low memory for coordination
   - Resources: (500m CPU, 1Gi) → (1 CPU, 2Gi)
   - Heap: 1700Mi
   - Port: 3011

### Pattern 3: Init Container for Database Readiness

**What:** Init container using busybox image with nc (netcat) to test TCP connectivity to Postgres and Redis services.

**When to use:** For any pod that depends on database services being available before starting (API, workers).

**Example:**

```yaml
initContainers:
- name: wait-for-postgres
  image: busybox:latest
  command:
  - sh
  - -c
  - |
    until nc -z postgres-service.firecrawl.svc.cluster.local 5432; do
      echo "Waiting for postgres..."
      sleep 2
    done
    echo "Postgres is ready"
- name: wait-for-redis
  image: busybox:latest
  command:
  - sh
  - -c
  - |
    until nc -z redis-service.firecrawl.svc.cluster.local 6379; do
      echo "Waiting for redis..."
      sleep 2
    done
    echo "Redis is ready"
```

**Why this works:**
- `nc -z` tests TCP connection without sending data (exit code 0 if reachable, 1 if not)
- `until` loop retries every 2 seconds until service is reachable
- Init containers run sequentially before main container starts
- Prevents application logs from filling with "connection refused" errors
- Simpler than readinessProbe-based waiting (doesn't require application code changes)

**Alternative approaches:**
- **Application-level retry logic:** More robust (handles connection drops during runtime) but clutters application logs during startup
- **Kubernetes readinessProbe with high failureThreshold:** Allows pod to start but doesn't guarantee database is ready when application connects
- **wait-for-it.sh script:** More features (timeout, verbose mode) but requires adding script to image
- **postgres/redis client images for init:** More precise health checks (can run pg_isready, redis-cli ping) but 40x larger images (200MB vs 5MB)

**Tradeoff:** Init container approach is simplest and sufficient for Phase 6. For production-grade resilience, combine with application-level connection retry logic (already exists in Firecrawl codebase via ioredis and pg connection pools).

### Pattern 4: Static Site Deployment (Ingestion UI)

**What:** Deployment serving static files with minimal resources, no database dependencies.

**When to use:** For web UIs that are pre-rendered at build time (Next.js static export, Vue build output).

**Example:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ingestion-ui
  namespace: firecrawl
  labels:
    app: ingestion-ui
    component: ui
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ingestion-ui
  template:
    metadata:
      labels:
        app: ingestion-ui
        component: ui
    spec:
      serviceAccountName: firecrawl-ui
      containers:
      - name: ingestion-ui
        image: ingestion-ui  # Kustomize transforms to full GCR path with SHA
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
          name: http
          protocol: TCP
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 20
          timeoutSeconds: 3
          failureThreshold: 3
```

**Key fields:**
- No init containers (no database dependencies)
- Minimal resources (100m CPU, 128Mi memory) for nginx serving static files
- Short probe delays (5s/10s) because nginx starts quickly
- No environment variables needed (static build)
- `serviceAccountName: firecrawl-ui` uses ServiceAccount with `automountServiceAccountToken: false` from Phase 3 (UI doesn't need Kubernetes API access)

### Pattern 5: Playwright Browser Automation Deployment

**What:** Deployment running Chromium browser with Playwright for web scraping, requires higher memory for browser processes.

**When to use:** For browser automation services that handle headless browser operations.

**Example:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: playwright-service
  namespace: firecrawl
  labels:
    app: playwright-service
    component: browser
spec:
  replicas: 1
  selector:
    matchLabels:
      app: playwright-service
  template:
    metadata:
      labels:
        app: playwright-service
        component: browser
    spec:
      serviceAccountName: firecrawl-playwright
      containers:
      - name: playwright-service
        image: playwright-service  # Built from apps/playwright-service-ts
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 3000
          name: http
          protocol: TCP
        env:
        - name: PORT
          value: "3000"
        - name: ALLOW_LOCAL_WEBHOOKS
          value: "false"
        resources:
          requests:
            cpu: 1
            memory: 2Gi
          limits:
            cpu: 2
            memory: 4Gi
        readinessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 60
          periodSeconds: 20
          timeoutSeconds: 5
          failureThreshold: 3
```

**Key fields:**
- Higher memory (4Gi limit) for Chromium browser processes
- No database dependencies (Playwright is standalone HTTP service)
- Environment variables from existing examples/kubernetes manifests
- Longer probe delays (30s/60s) for browser initialization

### Anti-Patterns to Avoid

**1. Missing NODE_OPTIONS heap size configuration**
- **Problem:** V8 heap grows to ~1.4Gi by default, then hits container limit (8Gi) and triggers OOM kill
- **Why it happens:** V8 doesn't know about container memory limits, assumes unlimited memory
- **Prevention:** Always set NODE_OPTIONS="--max-old-space-size=X" where X is 85% of container memory limit

**2. Init container that tests Service existence instead of backend readiness**
- **Problem:** Service DNS resolves immediately but backend pod isn't ready yet, application connects and fails
- **Why it happens:** Kubernetes Service exists before StatefulSet pods are Ready
- **Prevention:** Use nc to test TCP connection (proves backend pod is listening), or use readiness-aware health checks

**3. Shared ServiceAccount between API and workers without RBAC scoping**
- **Problem:** Workers don't need ConfigMap read access but inherit same permissions as API
- **Why it happens:** Reusing ServiceAccounts for convenience
- **Prevention:** Phase 3 already created separate ServiceAccounts (firecrawl-api, firecrawl-worker, firecrawl-ui, firecrawl-playwright) with scoped RBAC

**4. HTTP probes targeting internal endpoints without authentication**
- **Problem:** Health probes expose internal status endpoints to network
- **Why it happens:** Kubernetes probes originate from kubelet, not external traffic
- **Prevention:** Health endpoints don't need authentication (kubelet is trusted), but should not expose sensitive data

**5. Single Deployment with multiple containers for different worker types**
- **Problem:** All workers scale together, can't tune resources per worker type, restart of one worker restarts all
- **Why it happens:** Trying to reduce number of manifests
- **Prevention:** Create separate Deployments per worker type (extract, nuq, prefetch) for independent lifecycle management

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Database connection pooling | Custom connection manager | ioredis for Redis, pg for Postgres | Both libraries handle connection pooling, retry logic, and cluster support |
| Job queue with persistence | Custom queue implementation | BullMQ (already in codebase) | Handles job persistence to Redis, retries, priorities, delayed jobs, event-based workflow |
| Health check orchestration | Custom readiness/liveness logic | Kubernetes probes + existing /health endpoints | API and workers already expose health endpoints (src/controllers/v0/liveness.ts, worker Express servers) |
| Dependency ordering on startup | Custom wait scripts in application | Init containers with busybox nc | Simpler, doesn't pollute application code, reusable across all deployments |
| Node.js memory management | Custom GC tuning flags | NODE_OPTIONS --max-old-space-size | Single flag covers 95% of memory issues, well-tested by community |
| Configuration injection | Hardcoded values in Dockerfile | ConfigMaps and Secrets via envFrom | Declarative, auditable, no image rebuilds for config changes |

**Key insight:** The Firecrawl codebase already implements production-grade patterns (BullMQ for queues, health check endpoints, connection pooling). Phase 6 deploys this existing code to Kubernetes without modification. Don't add custom init logic, custom health checks, or custom dependency management—use Kubernetes primitives (init containers, probes, Services) that integrate with existing application patterns.

## Common Pitfalls

### Pitfall 1: Node.js OOM Kill Without Heap Size Configuration

**What goes wrong:** API or worker pods restart randomly with exit code 137 (OOMKilled). Container memory usage shows gradual climb to limit (8Gi) then sudden termination.

**Why it happens:** V8 JavaScript engine doesn't know about container memory limits. Default behavior is to grow heap until OS reports out-of-memory, then trigger garbage collection. In Kubernetes, OOMKiller terminates the pod before V8 can react.

**How to avoid:**
1. Set NODE_OPTIONS environment variable: `--max-old-space-size=X` where X is 85% of container memory limit in MiB
2. Formula: `(MEMORY_LIMIT_GiB * 1024 * 0.85) = HEAP_SIZE_MiB`
3. Example: 8Gi limit → 8192Mi * 0.85 = 6963Mi → use 6800Mi for safety margin
4. Apply to all Node.js containers (API, extract-worker, nuq-worker, prefetch-worker)

**Warning signs:**
- Pods show `OOMKilled` in `kubectl get pods`
- `kubectl describe pod` shows `Last State: Terminated (Reason: OOMKilled, Exit Code: 137)`
- Container memory metrics approach limit before crash
- No error logs (process killed before logging)

**References:**
- Node.js V8 memory management: https://nodejs.org/api/cli.html#--max-old-space-sizesize-in-megabytes
- Training data knowledge: V8 default heap limit ~1.4Gi, container limits require explicit configuration

### Pitfall 2: Application Starts Before Database Ready (Race Condition)

**What goes wrong:** API or worker pods crash-loop with "connection refused" errors. Logs show repeated Postgres/Redis connection attempts failing.

**Why it happens:** Kubernetes starts all pods in parallel. Application containers start before StatefulSet pods are ready to accept connections. Database connection code throws errors during startup, process exits with error code.

**How to avoid:**
1. Add init containers that test TCP connectivity before main container starts
2. Use busybox image with nc (netcat) to poll postgres-service:5432 and redis-service:6379
3. Init containers run sequentially, block pod startup until dependencies are reachable
4. Combine with application-level retry logic (ioredis and pg already have connection retry)

**Warning signs:**
- Pods show `CrashLoopBackOff` status
- Logs contain "ECONNREFUSED" errors for Postgres or Redis
- `kubectl describe pod` shows restart count incrementing
- Postgres and Redis pods are Ready but application pods keep restarting

**Prevention checklist:**
- [ ] Init container for postgres-service:5432 (blocks until Postgres TCP port is open)
- [ ] Init container for redis-service:6379 (blocks until Redis TCP port is open)
- [ ] Init containers use `until nc -z` loop with 2-second sleep
- [ ] Application code has connection retry logic (verify ioredis retryStrategy, pg max retries)

### Pitfall 3: Readiness Probe Fails During Slow Startup (Premature Restart)

**What goes wrong:** Pod starts, begins initializing connections, readiness probe fails, Kubernetes restarts pod before initialization completes. Pod never becomes Ready.

**Why it happens:** Readiness probe fires before application finishes startup sequence (database connections, Redis pool initialization, BullMQ queue setup). Probe returns HTTP 503, Kubernetes interprets as failed startup.

**How to avoid:**
1. Set `initialDelaySeconds` to cover worst-case startup time (30-60 seconds for Node.js + database connections)
2. Use `failureThreshold: 3` to allow multiple consecutive failures before marking unhealthy
3. Don't check readiness probe during init container execution (init containers block startup)
4. Use separate readiness and liveness probes with different delays (readiness: 30s, liveness: 60s)

**Warning signs:**
- Pods never reach Ready state (kubectl get pods shows 0/1 Ready)
- Logs show successful startup messages but pod restarts anyway
- `kubectl describe pod` shows readiness probe failures before liveness probe fires
- Events show "Readiness probe failed: Get http://...: dial tcp: connect: connection refused"

**Configuration:**
```yaml
readinessProbe:
  httpGet:
    path: /liveness
    port: 3002
  initialDelaySeconds: 30  # Wait 30s before first probe
  periodSeconds: 10         # Probe every 10s after initial delay
  timeoutSeconds: 5         # Allow 5s for probe response
  failureThreshold: 3       # Allow 3 consecutive failures (30s total)
```

### Pitfall 4: Worker Pods Compete for Redis Connections (Connection Pool Exhaustion)

**What goes wrong:** Workers log "Redis connection timeout" or "connection pool exhausted" errors. Jobs fail with Redis errors despite Redis pod being healthy.

**Why it happens:** Multiple worker pods (extract, nuq, prefetch) open connection pools to Redis. Total connections exceed Redis maxclients limit (default 10,000) or exhaust Redis memory.

**How to avoid:**
1. Configure ioredis connection pool limits per worker type (via environment variables or config)
2. Calculate total connections: (worker replicas * pool size per worker) < Redis maxclients
3. For Phase 6 single replicas: 3 workers * 10 connections = 30 total (well under limit)
4. Monitor Redis connection count: `redis-cli -h redis-service info clients | grep connected_clients`
5. Consider increasing Redis memory limit if connection memory overhead becomes significant

**Warning signs:**
- Workers log "Connection timeout" or "Redis unavailable" but Redis pod is Ready
- `redis-cli info clients` shows high `connected_clients` count
- Jobs in BullMQ queue aren't processing despite workers running
- Redis logs show "max number of clients reached"

**Prevention:** Phase 6 uses single replicas (1 extract + 1 nuq + 1 prefetch) with default connection pools. Risk is LOW. Monitor becomes critical when scaling replicas in future phases.

### Pitfall 5: Playwright Pod Crashes from Browser Memory Exhaustion

**What goes wrong:** Playwright pod crashes with OOM or hangs during page rendering. Browser processes consume all available memory.

**Why it happens:** Chromium browser launched by Playwright can consume 1-2Gi per tab/context. Multiple concurrent scrapes open multiple browser contexts. Container memory limit exceeded.

**How to avoid:**
1. Set generous memory limits for Playwright pod (4Gi minimum, 8Gi recommended for production)
2. Configure Playwright browser launch options to limit concurrency (maxConcurrentContexts)
3. Monitor Playwright pod memory usage: `kubectl top pod -n firecrawl | grep playwright`
4. Consider adding Playwright-specific resource requests and limits based on workload profiling

**Warning signs:**
- Playwright pod shows OOMKilled status
- API logs show timeouts when calling Playwright service (PLAYWRIGHT_MICROSERVICE_URL)
- `kubectl describe pod playwright-service` shows high memory usage before crash
- Firecrawl jobs fail with "browser automation failed" errors

**Configuration:**
```yaml
resources:
  requests:
    cpu: 1
    memory: 2Gi
  limits:
    cpu: 2
    memory: 4Gi  # Minimum; increase to 8Gi if OOM issues persist
```

## Code Examples

Verified patterns from Firecrawl codebase and Kubernetes official documentation.

### Example 1: API Deployment with Full Configuration

```yaml
# Source: apps/api/src/index.ts (health endpoints), config.ts (environment variables)
# Source: Kubernetes documentation (Deployment spec, probes)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: firecrawl-api
  namespace: firecrawl
  labels:
    app: firecrawl-api
    component: api
    version: v1
spec:
  replicas: 1
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  selector:
    matchLabels:
      app: firecrawl-api
  template:
    metadata:
      labels:
        app: firecrawl-api
        component: api
        version: v1
    spec:
      serviceAccountName: firecrawl-api
      initContainers:
      - name: wait-for-postgres
        image: busybox:latest
        command:
        - sh
        - -c
        - |
          until nc -z postgres-service.firecrawl.svc.cluster.local 5432; do
            echo "Waiting for postgres..."
            sleep 2
          done
          echo "Postgres is ready"
      - name: wait-for-redis
        image: busybox:latest
        command:
        - sh
        - -c
        - |
          until nc -z redis-service.firecrawl.svc.cluster.local 6379; do
            echo "Waiting for redis..."
            sleep 2
          done
          echo "Redis is ready"
      containers:
      - name: firecrawl-api
        image: firecrawl-api  # Kustomize image transformer updates this to full GCR path with SHA
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 3002
          name: http
          protocol: TCP
        env:
        - name: NODE_OPTIONS
          value: "--max-old-space-size=6800"
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
            name: firecrawl-redis-secret
        - secretRef:
            name: firecrawl-api-secret
        resources:
          requests:
            cpu: 1
            memory: 2Gi
          limits:
            cpu: 4
            memory: 8Gi
        readinessProbe:
          httpGet:
            path: /liveness
            port: 3002
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /liveness
            port: 3002
          initialDelaySeconds: 60
          periodSeconds: 20
          timeoutSeconds: 5
          failureThreshold: 3
---
apiVersion: v1
kind: Service
metadata:
  name: firecrawl-api-service
  namespace: firecrawl
  labels:
    app: firecrawl-api
spec:
  type: ClusterIP
  selector:
    app: firecrawl-api
  ports:
  - protocol: TCP
    port: 3002
    targetPort: 3002
    name: http
```

### Example 2: Worker Deployment (Extract Worker)

```yaml
# Source: apps/api/src/services/extract-worker.ts (worker entry point)
# Source: apps/api/package.json scripts (worker commands)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: extract-worker
  namespace: firecrawl
  labels:
    app: extract-worker
    component: worker
    worker-type: extract
spec:
  replicas: 1
  selector:
    matchLabels:
      app: extract-worker
  template:
    metadata:
      labels:
        app: extract-worker
        component: worker
        worker-type: extract
    spec:
      serviceAccountName: firecrawl-worker
      initContainers:
      - name: wait-for-postgres
        image: busybox:latest
        command:
        - sh
        - -c
        - |
          until nc -z postgres-service.firecrawl.svc.cluster.local 5432; do
            echo "Waiting for postgres..."
            sleep 2
          done
          echo "Postgres is ready"
      - name: wait-for-redis
        image: busybox:latest
        command:
        - sh
        - -c
        - |
          until nc -z redis-service.firecrawl.svc.cluster.local 6379; do
            echo "Waiting for redis..."
            sleep 2
          done
          echo "Redis is ready"
      containers:
      - name: extract-worker
        image: firecrawl-api  # Same image as API, different entry point
        imagePullPolicy: IfNotPresent
        command: ["node"]
        args: ["dist/src/services/extract-worker.js"]
        ports:
        - containerPort: 3004
          name: http
          protocol: TCP
        env:
        - name: NODE_OPTIONS
          value: "--max-old-space-size=6800"
        - name: EXTRACT_WORKER_PORT
          value: "3004"
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
            name: firecrawl-redis-secret
        - secretRef:
            name: firecrawl-api-secret
        resources:
          requests:
            cpu: 1
            memory: 4Gi
          limits:
            cpu: 2
            memory: 8Gi
        readinessProbe:
          httpGet:
            path: /health
            port: 3004
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /liveness
            port: 3004
          initialDelaySeconds: 60
          periodSeconds: 20
          timeoutSeconds: 5
          failureThreshold: 3
```

### Example 3: Ingestion UI Deployment (Static Site)

```yaml
# Source: k8s/base/ui-deployment.yaml (existing stub)
# Assumes ingestion-ui Dockerfile builds static site (Next.js export or similar)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ingestion-ui
  namespace: firecrawl
  labels:
    app: ingestion-ui
    component: ui
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ingestion-ui
  template:
    metadata:
      labels:
        app: ingestion-ui
        component: ui
    spec:
      serviceAccountName: firecrawl-ui
      containers:
      - name: ingestion-ui
        image: ingestion-ui  # Kustomize image transformer updates to GCR path
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
          name: http
          protocol: TCP
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 20
          timeoutSeconds: 3
          failureThreshold: 3
---
apiVersion: v1
kind: Service
metadata:
  name: ingestion-ui-service
  namespace: firecrawl
  labels:
    app: ingestion-ui
spec:
  type: ClusterIP
  selector:
    app: ingestion-ui
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
    name: http
```

### Example 4: Playwright Service Deployment

```yaml
# Source: examples/kubernetes/cluster-install/playwright-service.yaml
# Source: apps/playwright-service-ts/package.json (Express server on PORT=3000)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: playwright-service
  namespace: firecrawl
  labels:
    app: playwright-service
    component: browser
spec:
  replicas: 1
  selector:
    matchLabels:
      app: playwright-service
  template:
    metadata:
      labels:
        app: playwright-service
        component: browser
    spec:
      serviceAccountName: firecrawl-playwright
      containers:
      - name: playwright-service
        image: playwright-service  # Built from apps/playwright-service-ts
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 3000
          name: http
          protocol: TCP
        env:
        - name: PORT
          value: "3000"
        - name: ALLOW_LOCAL_WEBHOOKS
          value: "false"
        resources:
          requests:
            cpu: 1
            memory: 2Gi
          limits:
            cpu: 2
            memory: 4Gi
        readinessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 60
          periodSeconds: 20
          timeoutSeconds: 5
          failureThreshold: 3
---
apiVersion: v1
kind: Service
metadata:
  name: playwright-service
  namespace: firecrawl
  labels:
    app: playwright-service
spec:
  type: ClusterIP
  selector:
    app: playwright-service
  ports:
  - protocol: TCP
    port: 3000
    targetPort: 3000
    name: http
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| volumeClaimTemplates in StatefulSet | Separate PVC + Deployment | Kubernetes 1.21+ | Deployment supports persistent storage via PVC mount (apps/api uses volume mount pattern) |
| Dockerfile CMD for heap size | NODE_OPTIONS environment variable | Node.js 8+ | Runtime configuration without image rebuilds, easier Kubernetes ConfigMap integration |
| TCP socket probes | HTTP GET probes on /health | Kubernetes 1.16+ | Application-aware health checks, better signals for readiness vs liveness |
| Single worker Deployment | Multiple worker Deployments | BullMQ multi-queue pattern | Independent scaling and resource tuning per worker type (extract vs nuq vs prefetch) |
| Hardcoded config in Dockerfile | ConfigMap + Secret via envFrom | Kubernetes 1.6+ | Declarative config management, no image rebuilds for config changes |

**Deprecated/outdated:**
- **Manual kubectl rollout:** Use Argo CD automated sync (Phase 2 already configured)
- **Docker Compose for local development:** Use pnpm harness from CLAUDE.md (already documented pattern)
- **latest image tag:** Use Git SHA tags from Phase 1 CI pipeline (already implemented)
- **NodePort Services:** Use ClusterIP + Envoy Gateway HTTPRoutes (Phase 7) for external access

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Jest 30.2.0 + Supertest 6.3.3 |
| Config file | None — Jest config in package.json, tests in apps/api/src/__tests__/ |
| Quick run command | `pnpm harness jest --testPathPattern="snips/v2/scrape.test.ts" -x` |
| Full suite command | `pnpm harness jest` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| APP-01 | API Deployment accepts HTTP requests | integration | `kubectl port-forward -n firecrawl svc/firecrawl-api-service 3002:3002 & curl http://localhost:3002/` | Manual (kubectl) |
| APP-02 | API stays within memory limits under load | manual | Monitor: `kubectl top pod -n firecrawl --containers \| grep firecrawl-api` | Manual (metrics) |
| APP-03 | API heap size configured correctly | unit | `kubectl exec -n firecrawl deploy/firecrawl-api -- node -e "console.log(require('v8').getHeapStatistics().heap_size_limit)"` | Manual (kubectl exec) |
| APP-04 | API health probes pass after startup | integration | `kubectl get pods -n firecrawl -l app=firecrawl-api -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}'` | Manual (kubectl) |
| APP-05 | API waits for Postgres/Redis before starting | integration | `kubectl logs -n firecrawl deploy/firecrawl-api -c wait-for-postgres` | Manual (kubectl logs) |
| APP-06 | Worker Deployments process jobs from queue | e2e | `pnpm harness jest "snips/v1/extract.test.ts" -x` | ✅ apps/api/src/__tests__/snips/v1/extract.test.ts |
| APP-07 | Workers stay within memory limits | manual | Monitor: `kubectl top pod -n firecrawl --containers \| grep worker` | Manual (metrics) |
| APP-08 | Worker heap sizes configured correctly | unit | `kubectl exec -n firecrawl deploy/extract-worker -- node -e "console.log(require('v8').getHeapStatistics().heap_size_limit)"` | Manual (kubectl exec) |
| APP-09 | Worker health probes pass | integration | `kubectl get pods -n firecrawl -l component=worker -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}'` | Manual (kubectl) |
| APP-10 | Workers wait for dependencies | integration | `kubectl logs -n firecrawl deploy/extract-worker -c wait-for-redis` | Manual (kubectl logs) |
| APP-11 | UI Deployment serves static content | smoke | `kubectl port-forward -n firecrawl svc/ingestion-ui-service 8080:80 & curl http://localhost:8080/` | Manual (kubectl) |
| APP-12 | UI stays within memory limits | manual | Monitor: `kubectl top pod -n firecrawl -l app=ingestion-ui` | Manual (metrics) |
| APP-13 | UI health probes pass | integration | `kubectl get pods -n firecrawl -l app=ingestion-ui -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}'` | Manual (kubectl) |
| APP-14 | Playwright Deployment accepts scrape requests | integration | `kubectl port-forward -n firecrawl svc/playwright-service 3000:3000 & curl -X POST http://localhost:3000/scrape` | Manual (kubectl) |
| APP-15 | Playwright stays within memory limits | manual | Monitor: `kubectl top pod -n firecrawl -l app=playwright-service` | Manual (metrics) |
| APP-16 | Services expose correct ports | smoke | `kubectl get svc -n firecrawl -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.ports[*].port}{"\n"}{end}'` | Manual (kubectl) |

### Sampling Rate

- **Per task commit:** Quick smoke test — `kubectl get pods -n firecrawl` (verify no CrashLoopBackOff)
- **Per wave merge:** Integration test — verify all pods Ready, test API endpoint via port-forward
- **Phase gate:** Full validation script (see Wave 0 Gaps below) before `/gsd:verify-work`

### Wave 0 Gaps

Phase 6 validation primarily uses kubectl commands and manual testing because application-layer tests require deployed infrastructure. Create validation script:

- [ ] `k8s/scripts/validate-app-layer.sh` — Automated script covering:
  - Wait for all pods Ready (timeout 5 minutes)
  - Check heap size via kubectl exec for API and workers
  - Verify init container logs show "ready" messages
  - Port-forward and curl health endpoints
  - Submit test job via API and verify worker processes it
  - Check memory usage doesn't exceed 90% of limits
- [ ] Document manual validation steps in VALIDATION.md (memory monitoring, log inspection)
- [ ] Integration tests using `pnpm harness` — covers APP-06 (existing extract.test.ts)

**No missing test files** — Existing Firecrawl test suite covers application logic. Phase 6 validation focuses on Kubernetes deployment correctness (probes, init containers, resource limits).

## Sources

### Primary (HIGH confidence)

- **Firecrawl codebase** (apps/api/src, apps/playwright-service-ts, apps/api/package.json):
  - Worker entry points: src/services/extract-worker.ts, queue-worker.ts, nuq-worker.ts, nuq-prefetch-worker.ts
  - Health endpoints: src/controllers/v0/liveness.ts, src/controllers/v0/readiness.ts
  - Configuration: src/config.ts (ports, database URLs, worker counts)
  - Package dependencies: package.json (bullmq@5.56.7, ioredis@5.6.1, pg@8.16.3, express@4.22.0, playwright@1.58.1)
  - Dockerfile: apps/api/Dockerfile (node:22-slim base image, build process)

- **Kubernetes official documentation** (v1.27-1.29):
  - Deployment spec: apps/v1 Deployment, strategy, replicas, selector
  - Container spec: image, imagePullPolicy, ports, env, envFrom, resources, command, args
  - Probes: readinessProbe, livenessProbe (httpGet, exec, initialDelaySeconds, periodSeconds, failureThreshold)
  - Init containers: sequential startup, blocking main container
  - Service spec: ClusterIP, selector, ports

- **Node.js official documentation**:
  - V8 memory management: --max-old-space-size flag, heap limit calculation
  - NODE_OPTIONS environment variable: runtime configuration

- **Existing Kubernetes manifests** (examples/kubernetes/cluster-install/playwright-service.yaml):
  - Playwright Deployment pattern, ConfigMap, health probes, resource limits

### Secondary (MEDIUM confidence)

- **Phase 5 Research** (.planning/phases/05-data-layer/05-RESEARCH.md):
  - StatefulSet patterns, init container examples, health probe configuration
  - Resource limit tuning, fsGroup security context
  - Service DNS resolution patterns (*.firecrawl.svc.cluster.local)

- **Project Research Summary** (.planning/research/SUMMARY.md):
  - Pitfall #4: Node.js memory exhaustion prevention (85% heap size rule)
  - Pitfall #10: Node.js worker CPU throttling
  - Pitfall #11: Redis connection pool exhaustion

- **BullMQ documentation patterns** (training data):
  - Worker architecture, job processing, Redis connection pooling
  - Multiple queue types (extract, deep-research, generate-llmstxt, nuq scrape queue)

### Tertiary (LOW confidence, marked for validation)

- **Resource limit tuning** — Memory and CPU requests/limits based on general Node.js patterns, not Firecrawl-specific profiling. Actual limits should be tuned based on load testing and production metrics.

- **Init container timing** — 2-second sleep in nc loop is arbitrary. Could be optimized based on actual database startup times (Postgres ~30s, Redis ~5s from Phase 5).

- **Heap size formula (85%)** — Industry standard but not scientifically derived. Some workloads need 80%, others can use 90%. Should be monitored and adjusted based on GC logs.

- **Worker resource profiles** — Extract (8Gi), NuQ (4Gi), Prefetch (2Gi) based on assumed workload characteristics (AI models, page rendering, coordination). Needs validation through actual job profiling.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Firecrawl codebase directly inspected, package.json versions confirmed, Dockerfile reviewed
- Architecture: MEDIUM — Deployment patterns are Kubernetes standard, but resource limits need workload-specific tuning
- Pitfalls: MEDIUM — Node.js OOM and startup race conditions are well-documented, but Firecrawl-specific issues (BullMQ connection pooling, Playwright memory) need production validation

**Research date:** 2026-03-27
**Valid until:** 2026-04-27 (30 days) — Node.js and Kubernetes patterns are stable, but package versions and GKE features may advance
