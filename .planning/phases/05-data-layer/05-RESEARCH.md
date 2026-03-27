# Phase 5: Data Layer - Research

**Researched:** 2026-03-27
**Domain:** Kubernetes StatefulSets for Databases (Postgres & Redis)
**Confidence:** HIGH

## Summary

Phase 5 deploys Postgres and Redis as StatefulSets with persistent storage (mounted from Phase 4 PVCs), health probes, resource limits, internal DNS services, and automated backup to Google Cloud Storage. The architecture follows production-grade database deployment patterns on Kubernetes: StatefulSets for stable pod identity, headless Services for DNS resolution, readiness/liveness probes for health monitoring, and CronJobs for automated pg_dump backups.

The critical success factors are proper resource limit configuration (preventing OOM kills), correctly configured health probes (avoiding false positives during startup), and immediate backup automation (protecting against data loss from day one). Postgres and Redis must be fully healthy and accepting connections before Phase 6 deploys application services that depend on them.

**Primary recommendation:** Deploy Postgres and Redis StatefulSets with single replicas, mount pre-existing PVCs from Phase 4, configure exec-based health probes with generous startup delays, set conservative resource limits, create ClusterIP Services for stable DNS endpoints, and implement CronJob-based pg_dump to GCS with documented restoration procedure.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DATA-01 | Postgres StatefulSet deployed with PVC mount | StatefulSet with volumes section mounting postgres-data PVC to /var/lib/postgresql/data |
| DATA-02 | Postgres has memory and CPU resource limits configured | Resources: requests (500m CPU, 1Gi memory), limits (2 CPU, 4Gi memory) for production stability |
| DATA-03 | Postgres has readiness and liveness probes configured | Exec probes using `pg_isready`, initialDelaySeconds: 30s for startup, periodSeconds: 10s |
| DATA-04 | Redis StatefulSet deployed with PVC mount | StatefulSet with volumes section mounting redis-data PVC to /data |
| DATA-05 | Redis has memory and CPU resource limits configured | Resources: requests (200m CPU, 512Mi memory), limits (1 CPU, 2Gi memory) for cache stability |
| DATA-06 | Redis has readiness and liveness probes configured | Exec probes using `redis-cli ping`, initialDelaySeconds: 5s, periodSeconds: 10s |
| DATA-07 | Kubernetes Services created for Postgres and Redis | ClusterIP Services with stable DNS (postgres-service.firecrawl.svc.cluster.local, redis-service.firecrawl.svc.cluster.local) |
| DATA-08 | CronJob created for Postgres pg_dump backups to GCS (every 6 hours) | CronJob schedule "0 */6 * * *" with gcloud CLI image running pg_dump piped to gsutil |
| DATA-09 | Backup restoration procedure documented | Runbook with gsutil download + psql restore commands, testing instructions |
</phase_requirements>

## Standard Stack

### Core Components

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| postgres | 15-alpine | PostgreSQL database server | Official image, Alpine for minimal size, v15 is current LTS |
| redis | 7-alpine | Redis in-memory cache/queue | Official image, Alpine for minimal size, v7 is current stable |
| StatefulSet | v1 | Manages stateful database pods | Kubernetes standard for databases with stable identity |
| Service | v1 | Provides stable DNS endpoints | Kubernetes standard for service discovery |
| CronJob | v1 | Schedules periodic backup jobs | Kubernetes standard for scheduled tasks |
| google/cloud-sdk | alpine | GCS backup utility | Official Google image with gcloud and gsutil |

### Supporting Tools

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| pg_dump | built-in postgres:15 | Logical database backup | Included in postgres image, no extra installation |
| pg_isready | built-in postgres:15 | Health check utility | Postgres readiness probe |
| redis-cli | built-in redis:7 | Redis command-line client | Redis health checks via PING command |
| gsutil | google/cloud-sdk | GCS file upload/download | Backup to Google Cloud Storage buckets |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| StatefulSet (single replica) | Deployment with single replica | StatefulSet provides stable pod name and ordered startup, better for databases even without replication |
| pg_dump logical backup | Volume snapshot (CSI) | pg_dump is portable and version-independent; snapshots are faster but require restore to same Kubernetes cluster |
| CronJob backup | Manual backup scripts | CronJob ensures backups run automatically; manual requires discipline and increases risk |
| ClusterIP Service | Headless Service (clusterIP: None) | ClusterIP provides stable virtual IP; headless gives direct pod IPs but requires StatefulSet DNS awareness |
| Postgres 15 | Postgres 14 or 16 | Version 15 is current LTS with wide support; 16 is newer but less tested; 14 is older but proven |

**Installation:**

Database containers are pulled from Docker Hub official repositories. No local build required.

```bash
# Verify image availability
docker pull postgres:15-alpine
docker pull redis:7-alpine
docker pull google/cloud-sdk:alpine

# Check versions
docker run --rm postgres:15-alpine postgres --version
docker run --rm redis:7-alpine redis-server --version
```

**Version verification:** As of 2026-03-27, postgres:15-alpine is current LTS (released 2022, supported until 2027). Redis 7.0+ is stable (released 2022). Always verify latest patch versions in production.

## Architecture Patterns

### Recommended Project Structure

```
k8s/base/
├── storage-class-immediate.yaml  # [Phase 4] Custom StorageClass
├── pvc-postgres.yaml              # [Phase 4] 10Gi Postgres PVC
├── pvc-redis.yaml                 # [Phase 4] 1Gi Redis PVC
├── postgres-statefulset.yaml      # [Phase 5] Postgres StatefulSet
├── postgres-service.yaml          # [Phase 5] Postgres ClusterIP Service
├── redis-statefulset.yaml         # [Phase 5] Redis StatefulSet
├── redis-service.yaml             # [Phase 5] Redis ClusterIP Service
├── backup-cronjob.yaml            # [Phase 5] Postgres backup CronJob
├── backup-serviceaccount.yaml     # [Phase 5] SA with GCS write permissions
└── kustomization.yaml             # Updated to include Phase 5 resources
```

### Pattern 1: StatefulSet with Pre-Existing PVC Mount

**What:** StatefulSet that references a PVC created in Phase 4, rather than using volumeClaimTemplates.

**When to use:** For single-instance databases where the PVC already exists and doesn't need dynamic provisioning per replica.

**Example:**

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: firecrawl
spec:
  replicas: 1
  serviceName: postgres-service
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
        component: database
    spec:
      serviceAccountName: postgres-sa
      securityContext:
        fsGroup: 999  # postgres user in official image
      containers:
      - name: postgres
        image: postgres:15-alpine
        env:
        - name: POSTGRES_DB
          valueFrom:
            configMapKeyRef:
              name: firecrawl-database
              key: POSTGRES_DB
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: firecrawl-database-secret
              key: POSTGRES_USER
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: firecrawl-database-secret
              key: POSTGRES_PASSWORD
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        ports:
        - containerPort: 5432
          name: postgres
          protocol: TCP
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 2
            memory: 4Gi
        readinessProbe:
          exec:
            command:
            - sh
            - -c
            - pg_isready -U $POSTGRES_USER -d $POSTGRES_DB
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        livenessProbe:
          exec:
            command:
            - sh
            - -c
            - pg_isready -U $POSTGRES_USER -d $POSTGRES_DB
          initialDelaySeconds: 60
          periodSeconds: 20
          timeoutSeconds: 5
          failureThreshold: 3
      volumes:
      - name: postgres-data
        persistentVolumeClaim:
          claimName: postgres-data
```

**Key fields:**
- `serviceName: postgres-service` - Links StatefulSet to Service for DNS resolution
- `replicas: 1` - Single instance for v1 (no replication)
- `fsGroup: 999` - Ensures postgres user (UID 999 in official image) can write to PVC
- `PGDATA: /var/lib/postgresql/data/pgdata` - Subdirectory avoids "lost+found" directory issues
- `volumes` section references pre-existing PVC from Phase 4 (not volumeClaimTemplates)

### Pattern 2: Health Probes for Database Containers

**What:** Exec-based probes that run database-specific health check commands inside the container.

**When to use:** For databases where TCP socket checks are insufficient (database process might be up but not ready to accept queries).

**Postgres Probe Example:**

```yaml
readinessProbe:
  exec:
    command:
    - sh
    - -c
    - pg_isready -U $POSTGRES_USER -d $POSTGRES_DB
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3

livenessProbe:
  exec:
    command:
    - sh
    - -c
    - pg_isready -U $POSTGRES_USER -d $POSTGRES_DB
  initialDelaySeconds: 60
  periodSeconds: 20
  timeoutSeconds: 5
  failureThreshold: 3
```

**Redis Probe Example:**

```yaml
readinessProbe:
  exec:
    command:
    - redis-cli
    - ping
  initialDelaySeconds: 5
  periodSeconds: 10
  timeoutSeconds: 3
  failureThreshold: 3

livenessProbe:
  exec:
    command:
    - redis-cli
    - ping
  initialDelaySeconds: 10
  periodSeconds: 20
  timeoutSeconds: 3
  failureThreshold: 5
```

**Probe timing guidelines:**
- **initialDelaySeconds:** Postgres needs 30-60s for cold start with PVC mount; Redis needs 5-10s
- **periodSeconds:** Check every 10-20s (balance between responsiveness and overhead)
- **timeoutSeconds:** Database queries should complete in 3-5s
- **failureThreshold:** 3-5 consecutive failures before marking unhealthy (avoid false positives)
- **Liveness delay > Readiness delay:** Liveness kills pods, so wait longer to avoid premature restarts

### Pattern 3: ClusterIP Service for StatefulSet

**What:** Service with `type: ClusterIP` that provides stable DNS endpoint and load balancing to StatefulSet pods.

**When to use:** For internal database services that don't need external access. Provides stable DNS like `postgres-service.firecrawl.svc.cluster.local`.

**Example:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres-service
  namespace: firecrawl
  labels:
    app: postgres
    component: database
spec:
  type: ClusterIP
  selector:
    app: postgres
  ports:
  - name: postgres
    port: 5432
    targetPort: 5432
    protocol: TCP
```

**Key fields:**
- `type: ClusterIP` - Internal-only service (default, can be omitted)
- `selector: app: postgres` - Matches StatefulSet pod labels
- `port: 5432` - Service port (what clients connect to)
- `targetPort: 5432` - Container port (what pod listens on)
- Service name becomes DNS: `postgres-service.firecrawl.svc.cluster.local`

**DNS Resolution:** Application pods connect using service DNS from ConfigMap:
```bash
POSTGRES_HOST=postgres-service.firecrawl.svc.cluster.local
POSTGRES_PORT=5432
```

### Pattern 4: CronJob for Automated Postgres Backups to GCS

**What:** CronJob that runs pg_dump and uploads the backup to Google Cloud Storage on a schedule.

**When to use:** Production databases requiring point-in-time recovery capability (DATA-08 requirement).

**Example:**

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
  namespace: firecrawl
spec:
  schedule: "0 */6 * * *"  # Every 6 hours
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        metadata:
          labels:
            app: postgres-backup
            component: backup
        spec:
          serviceAccountName: postgres-backup-sa
          restartPolicy: OnFailure
          containers:
          - name: backup
            image: google/cloud-sdk:alpine
            command:
            - /bin/sh
            - -c
            - |
              # Install postgresql-client
              apk add --no-cache postgresql15-client

              # Set timestamp for backup file
              TIMESTAMP=$(date +%Y%m%d-%H%M%S)
              BACKUP_FILE="postgres-backup-${TIMESTAMP}.sql.gz"

              # Run pg_dump and upload to GCS
              PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump \
                -h postgres-service.firecrawl.svc.cluster.local \
                -U "${POSTGRES_USER}" \
                -d "${POSTGRES_DB}" \
                --clean --if-exists --create \
                | gzip > /tmp/${BACKUP_FILE}

              # Upload to GCS bucket
              gsutil cp /tmp/${BACKUP_FILE} gs://firecrawl-backups/postgres/

              # Cleanup old backups (keep last 30 days)
              gsutil ls gs://firecrawl-backups/postgres/ | \
                head -n -180 | \
                xargs -r gsutil rm

              echo "Backup completed: ${BACKUP_FILE}"
            env:
            - name: POSTGRES_DB
              valueFrom:
                configMapKeyRef:
                  name: firecrawl-database
                  key: POSTGRES_DB
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef:
                  name: firecrawl-database-secret
                  key: POSTGRES_USER
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: firecrawl-database-secret
                  key: POSTGRES_PASSWORD
            resources:
              requests:
                cpu: 100m
                memory: 256Mi
              limits:
                cpu: 500m
                memory: 1Gi
```

**Key fields:**
- `schedule: "0 */6 * * *"` - Every 6 hours (midnight, 6am, noon, 6pm UTC)
- `concurrencyPolicy: Forbid` - Don't start new backup if previous one is still running
- `restartPolicy: OnFailure` - Retry failed backups
- `--clean --if-exists --create` - pg_dump flags for complete database recreation
- `gzip` compression - Reduce storage costs (typically 5-10x compression)
- Cleanup old backups - Retain last 30 days (180 backups at 6-hour intervals)

**GCS Bucket Setup (prerequisite):**
```bash
# Create GCS bucket for backups
gsutil mb -p prometheus-461323 -l us-central1 gs://firecrawl-backups

# Enable versioning for protection against accidental deletion
gsutil versioning set on gs://firecrawl-backups

# Set lifecycle rule to delete objects after 90 days
cat > lifecycle.json <<EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {"age": 90}
      }
    ]
  }
}
EOF
gsutil lifecycle set lifecycle.json gs://firecrawl-backups
```

### Pattern 5: Workload Identity for GCS Access

**What:** ServiceAccount with Workload Identity Federation allowing CronJob pods to authenticate to GCS without long-lived keys.

**When to use:** When Kubernetes pods need to access Google Cloud services securely (DATA-08 backup to GCS).

**Example:**

```yaml
# kubernetes ServiceAccount
apiVersion: v1
kind: ServiceAccount
metadata:
  name: postgres-backup-sa
  namespace: firecrawl
  annotations:
    iam.gke.io/gcp-service-account: firecrawl-backup@prometheus-461323.iam.gserviceaccount.com
```

**GCP IAM Configuration (prerequisite):**

```bash
# Create GCP service account
gcloud iam service-accounts create firecrawl-backup \
  --project=prometheus-461323 \
  --display-name="Firecrawl Postgres Backup"

# Grant GCS write permissions
gcloud projects add-iam-policy-binding prometheus-461323 \
  --member="serviceAccount:firecrawl-backup@prometheus-461323.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin" \
  --condition="expression=resource.name.startsWith('projects/_/buckets/firecrawl-backups'),title=firecrawl-backups-only"

# Bind Kubernetes SA to GCP SA (Workload Identity)
gcloud iam service-accounts add-iam-policy-binding \
  firecrawl-backup@prometheus-461323.iam.gserviceaccount.com \
  --project=prometheus-461323 \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:prometheus-461323.svc.id.goog[firecrawl/postgres-backup-sa]"
```

### Anti-Patterns to Avoid

- **Using volumeClaimTemplates for single-instance databases:** Adds complexity without benefit when PVC already exists from Phase 4
- **TCPSocket probes for databases:** Database process might be running but not ready to accept queries; use exec probes with db-specific commands
- **Too-short initialDelaySeconds:** Causes restart loops when database takes 30-60s to start with cold PVC mount
- **No resource limits:** Postgres or Redis OOM kill can crash entire node; always set memory limits
- **Manual backups:** Human error and inconsistency; automate with CronJob from day one
- **Backups without testing restoration:** Untested backups are not backups; document and test restoration procedure (DATA-09)
- **Storing backup credentials in Git:** Use Workload Identity or Kubernetes Secrets, never commit GCS keys to repository

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Database high availability | Custom replication scripts | Postgres streaming replication or Patroni operator | Built-in replication is battle-tested; custom scripts miss edge cases |
| Connection pooling | Application-level connection management | PgBouncer sidecar container | Dedicated pooler handles connection limits and reduces database load |
| Backup encryption | Custom encryption wrapper around pg_dump | GCS server-side encryption (default) | GCS encrypts at rest automatically; custom crypto risks key management issues |
| Backup monitoring | Custom health check scripts | GKE Job metrics + Stackdriver | Built-in monitoring shows job success/failure without custom code |
| Redis persistence | Custom snapshot scripts | Redis AOF (appendonly.conf) or RDB snapshots | Redis has built-in persistence; custom scripts can corrupt data during writes |
| Database schema migrations | Manual SQL scripts in CronJob | Dedicated migration tool (Flyway, Liquibase, golang-migrate) or init container | Migration tools provide versioning, rollback, and idempotency guarantees |

**Key insight:** Databases have mature built-in features and well-tested operators. Attempting to build custom solutions for backups, replication, or connection pooling introduces bugs and increases operational burden. Use declarative Kubernetes patterns (StatefulSets, Services, CronJobs) with official database images and built-in tooling.

## Common Pitfalls

### Pitfall 1: Postgres Container Restart Loop from Insufficient initialDelaySeconds

**What goes wrong:** Postgres StatefulSet enters restart loop. Pod starts, liveness probe fails after 10 seconds, Kubernetes kills pod, repeat. Database never becomes healthy.

**Why it happens:** Cold start with PVC mount takes 30-60 seconds for Postgres to initialize data directory and accept connections. Default probe timing (initialDelaySeconds: 10s) is too aggressive. Liveness probe fails before Postgres finishes startup, triggering restart.

**How to avoid:**
- Set `readinessProbe.initialDelaySeconds: 30` (minimum)
- Set `livenessProbe.initialDelaySeconds: 60` (liveness should wait longer than readiness)
- Use `failureThreshold: 3` to allow 3 failed probes before marking unhealthy
- Monitor pod events with `kubectl describe pod postgres-0` for "Liveness probe failed" messages

**Warning signs:**
- Pod shows repeated restarts (restart count > 3)
- `kubectl logs postgres-0` shows startup logs followed by termination
- `kubectl describe pod postgres-0` shows "Liveness probe failed: pg_isready failed"

**Example of proper timing:**
```yaml
readinessProbe:
  initialDelaySeconds: 30  # Wait 30s before first readiness check
  periodSeconds: 10
  failureThreshold: 3
livenessProbe:
  initialDelaySeconds: 60  # Wait 60s before first liveness check
  periodSeconds: 20
  failureThreshold: 3
```

### Pitfall 2: Redis AOF Persistence Not Enabled

**What goes wrong:** Redis pod restarts and all data is lost. Queue state, rate limiting data, and cached metadata disappear. API and workers fail because they expect queue jobs to exist.

**Why it happens:** Default Redis configuration uses RDB snapshots only (periodic disk writes). If pod crashes between snapshots, all data since last snapshot is lost. For queue/cache workloads, this causes job loss and application errors.

**How to avoid:**
- Enable AOF (append-only file) persistence in Redis config
- Mount AOF file to persistent volume (redis-data PVC)
- Set `appendonly yes` in redis.conf or via command args
- Set `appendfsync everysec` for balance between durability and performance

**Warning signs:**
- Redis pod restart causes queue job loss
- Application logs show "queue job not found" errors after Redis restart
- Redis log shows "AOF is disabled" during startup

**Example configuration:**
```yaml
containers:
- name: redis
  image: redis:7-alpine
  command:
  - redis-server
  - --appendonly
  - "yes"
  - --appendfsync
  - "everysec"
  - --dir
  - "/data"
  volumeMounts:
  - name: redis-data
    mountPath: /data
```

### Pitfall 3: Backup CronJob Fails Silently Without Monitoring

**What goes wrong:** CronJob runs every 6 hours but fails due to authentication error, out-of-disk, or network timeout. No one notices for weeks. When restore is needed, latest backup is 3 weeks old.

**Why it happens:** CronJob creates Jobs that can fail without alerting. Default Kubernetes behavior is to show failed jobs in `kubectl get jobs`, but doesn't trigger notifications. Developers assume backups are working without verification.

**How to avoid:**
- Set `successfulJobsHistoryLimit: 3` and `failedJobsHistoryLimit: 3` to retain job history
- Monitor CronJob success/failure with GKE metrics or Stackdriver
- Add notification logic to backup script (Slack webhook on failure)
- Test backup restoration quarterly (DATA-09 requirement)
- Create alert on "failed jobs > 2 in last 24 hours"

**Warning signs:**
- `kubectl get jobs -n firecrawl` shows multiple failed backup jobs
- `kubectl logs job/postgres-backup-<timestamp>` shows gsutil authentication errors
- GCS bucket has no recent backups

**Example monitoring command:**
```bash
# Check backup job history
kubectl get jobs -n firecrawl -l app=postgres-backup --sort-by=.status.startTime

# Verify recent backups in GCS
gsutil ls -l gs://firecrawl-backups/postgres/ | tail -n 10
```

### Pitfall 4: Resource Limits Too Low Causing OOMKilled

**What goes wrong:** Postgres pod shows CrashLoopBackOff. Logs show "database system is shut down" repeatedly. `kubectl describe pod postgres-0` shows `OOMKilled` in last state.

**Why it happens:** Memory limit (e.g., 512Mi) is too low for Postgres shared_buffers, work_mem, and connection overhead. Under load, Postgres memory usage exceeds limit, kernel OOM killer terminates process.

**How to avoid:**
- Set conservative memory limits: Postgres minimum 1Gi request, 4Gi limit; Redis minimum 512Mi request, 2Gi limit
- Configure Postgres `shared_buffers` to 25% of memory limit (e.g., 1Gi for 4Gi limit)
- Configure Postgres `max_connections` based on memory (each connection uses ~10-50Mi)
- Monitor actual memory usage and adjust limits based on workload

**Warning signs:**
- Pod last state shows `OOMKilled: true`
- `dmesg` on node shows "Out of memory: Kill process [pid] (postgres)"
- Application shows "too many connections" errors after pod restart

**Example resource configuration:**
```yaml
resources:
  requests:
    cpu: 500m
    memory: 1Gi    # Guaranteed allocation
  limits:
    cpu: 2
    memory: 4Gi    # Maximum allowed before OOMKill
```

**Postgres configuration:**
```sql
-- Set shared_buffers to 25% of 4Gi = 1024Mi
ALTER SYSTEM SET shared_buffers = '1024MB';
-- Limit connections based on available memory
ALTER SYSTEM SET max_connections = 100;
```

### Pitfall 5: PGDATA Directory Conflict with "lost+found"

**What goes wrong:** Postgres pod fails to start with error "initdb: directory '/var/lib/postgresql/data' exists but is not empty". PVC is mounted but Postgres refuses to initialize.

**Why it happens:** Fresh ext4 filesystem has `lost+found` directory at root. Postgres initdb requires completely empty directory. Mounting PVC to `/var/lib/postgresql/data` puts `lost+found` in PGDATA, causing initialization failure.

**How to avoid:**
- Set `PGDATA` environment variable to subdirectory: `/var/lib/postgresql/data/pgdata`
- Mount PVC to parent directory (`/var/lib/postgresql/data`)
- Postgres writes data to subdirectory, avoiding `lost+found` conflict

**Warning signs:**
- `kubectl logs postgres-0` shows "directory is not empty" error
- `kubectl exec postgres-0 -- ls /var/lib/postgresql/data` shows only `lost+found`
- Pod stuck in CrashLoopBackOff on first startup

**Example fix:**
```yaml
env:
- name: PGDATA
  value: /var/lib/postgresql/data/pgdata  # Subdirectory avoids lost+found
volumeMounts:
- name: postgres-data
  mountPath: /var/lib/postgresql/data     # Parent directory
```

## Code Examples

### Postgres StatefulSet (Complete)

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: firecrawl
  labels:
    app: postgres
    component: database
spec:
  replicas: 1
  serviceName: postgres-service
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
        component: database
    spec:
      serviceAccountName: default
      securityContext:
        fsGroup: 999  # postgres user UID in official image
      containers:
      - name: postgres
        image: postgres:15-alpine
        imagePullPolicy: IfNotPresent
        env:
        - name: POSTGRES_DB
          valueFrom:
            configMapKeyRef:
              name: firecrawl-database
              key: POSTGRES_DB
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: firecrawl-database-secret
              key: POSTGRES_USER
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: firecrawl-database-secret
              key: POSTGRES_PASSWORD
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        ports:
        - containerPort: 5432
          name: postgres
          protocol: TCP
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 2
            memory: 4Gi
        readinessProbe:
          exec:
            command:
            - sh
            - -c
            - pg_isready -U $POSTGRES_USER -d $POSTGRES_DB
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        livenessProbe:
          exec:
            command:
            - sh
            - -c
            - pg_isready -U $POSTGRES_USER -d $POSTGRES_DB
          initialDelaySeconds: 60
          periodSeconds: 20
          timeoutSeconds: 5
          failureThreshold: 3
      volumes:
      - name: postgres-data
        persistentVolumeClaim:
          claimName: postgres-data
```

### Redis StatefulSet (Complete)

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  namespace: firecrawl
  labels:
    app: redis
    component: cache
spec:
  replicas: 1
  serviceName: redis-service
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
        component: cache
    spec:
      serviceAccountName: default
      securityContext:
        fsGroup: 999  # redis user UID in official image
      containers:
      - name: redis
        image: redis:7-alpine
        imagePullPolicy: IfNotPresent
        command:
        - redis-server
        - --appendonly
        - "yes"
        - --appendfsync
        - "everysec"
        - --dir
        - "/data"
        ports:
        - containerPort: 6379
          name: redis
          protocol: TCP
        volumeMounts:
        - name: redis-data
          mountPath: /data
        resources:
          requests:
            cpu: 200m
            memory: 512Mi
          limits:
            cpu: 1
            memory: 2Gi
        readinessProbe:
          exec:
            command:
            - redis-cli
            - ping
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 3
        livenessProbe:
          exec:
            command:
            - redis-cli
            - ping
          initialDelaySeconds: 10
          periodSeconds: 20
          timeoutSeconds: 3
          failureThreshold: 5
      volumes:
      - name: redis-data
        persistentVolumeClaim:
          claimName: redis-data
```

### Postgres Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres-service
  namespace: firecrawl
  labels:
    app: postgres
    component: database
spec:
  type: ClusterIP
  selector:
    app: postgres
  ports:
  - name: postgres
    port: 5432
    targetPort: 5432
    protocol: TCP
```

### Redis Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: redis-service
  namespace: firecrawl
  labels:
    app: redis
    component: cache
spec:
  type: ClusterIP
  selector:
    app: redis
  ports:
  - name: redis
    port: 6379
    targetPort: 6379
    protocol: TCP
```

### Backup CronJob with GCS Upload

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
  namespace: firecrawl
  labels:
    app: postgres-backup
    component: backup
spec:
  schedule: "0 */6 * * *"  # Every 6 hours: 00:00, 06:00, 12:00, 18:00 UTC
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        metadata:
          labels:
            app: postgres-backup
            component: backup
        spec:
          serviceAccountName: postgres-backup-sa
          restartPolicy: OnFailure
          containers:
          - name: backup
            image: google/cloud-sdk:alpine
            command:
            - /bin/sh
            - -c
            - |
              set -e

              # Install postgresql-client
              apk add --no-cache postgresql15-client

              # Set timestamp for backup file
              TIMESTAMP=$(date +%Y%m%d-%H%M%S)
              BACKUP_FILE="postgres-backup-${TIMESTAMP}.sql.gz"

              echo "Starting backup: ${BACKUP_FILE}"

              # Run pg_dump and compress
              PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump \
                -h postgres-service.firecrawl.svc.cluster.local \
                -U "${POSTGRES_USER}" \
                -d "${POSTGRES_DB}" \
                --clean --if-exists --create \
                | gzip > /tmp/${BACKUP_FILE}

              # Upload to GCS bucket
              gsutil cp /tmp/${BACKUP_FILE} gs://firecrawl-backups/postgres/

              # Verify upload
              gsutil ls gs://firecrawl-backups/postgres/${BACKUP_FILE}

              echo "Backup completed: ${BACKUP_FILE}"

              # Cleanup old backups (keep last 30 days = 120 backups at 6-hour intervals)
              CUTOFF_DATE=$(date -d '30 days ago' +%Y%m%d 2>/dev/null || date -v-30d +%Y%m%d)
              gsutil ls gs://firecrawl-backups/postgres/ | while read backup; do
                BACKUP_DATE=$(echo $backup | grep -oP '\d{8}' | head -1)
                if [ "$BACKUP_DATE" -lt "$CUTOFF_DATE" ]; then
                  echo "Deleting old backup: $backup"
                  gsutil rm $backup
                fi
              done
            env:
            - name: POSTGRES_DB
              valueFrom:
                configMapKeyRef:
                  name: firecrawl-database
                  key: POSTGRES_DB
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef:
                  name: firecrawl-database-secret
                  key: POSTGRES_USER
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: firecrawl-database-secret
                  key: POSTGRES_PASSWORD
            resources:
              requests:
                cpu: 100m
                memory: 256Mi
              limits:
                cpu: 500m
                memory: 1Gi
```

### Backup ServiceAccount with Workload Identity

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: postgres-backup-sa
  namespace: firecrawl
  labels:
    app: postgres-backup
    component: backup
  annotations:
    iam.gke.io/gcp-service-account: firecrawl-backup@prometheus-461323.iam.gserviceaccount.com
```

### Kustomization Update

```yaml
# k8s/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  # Phase 3: Foundation
  - namespace.yaml
  - serviceaccounts.yaml
  - rbac.yaml
  - configmap-database.yaml
  - configmap-redis.yaml
  - configmap-application.yaml

  # Phase 4: Storage
  - storage-class-immediate.yaml
  - pvc-postgres.yaml
  - pvc-redis.yaml

  # Phase 5: Data Layer
  - postgres-statefulset.yaml
  - postgres-service.yaml
  - redis-statefulset.yaml
  - redis-service.yaml
  - backup-serviceaccount.yaml
  - backup-cronjob.yaml

  # Future phases
  - api-deployment.yaml
  - ui-deployment.yaml
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Deployment for databases | StatefulSet with stable network identity | Kubernetes 1.5+ (2016) | StatefulSet provides ordered startup and stable pod names for databases |
| Manual database backups | Automated CronJob backups | Best practice evolution | CronJob ensures consistent backups without human error |
| pg_basebackup (physical) | pg_dump (logical) for small databases | Situational | pg_dump is portable across Postgres versions and easier to restore selectively |
| Secrets in environment variables | Secrets mounted as files | Best practice evolution (2018+) | File-based secrets reduce exposure in process listings; v1 uses env vars for simplicity |
| Redis RDB-only persistence | AOF (append-only file) for durability | Redis 2.4+ (2011) | AOF provides better durability for queue/cache workloads |
| tcpSocket probes | exec probes with database commands | Best practice evolution | Database-specific commands (pg_isready, redis-cli ping) provide better health detection |
| Long-lived GCS service account keys | Workload Identity Federation | GKE 1.13+ (2019) | Workload Identity eliminates key management and rotation burden |

**Deprecated/outdated:**
- Deployment for stateful workloads - Use StatefulSet for stable identity and ordered operations
- volumeClaimTemplates for single-instance databases - Use pre-existing PVC for simpler configuration when replicas=1
- Storing database passwords in ConfigMaps - Always use Secrets (base64 encoded, RBAC-protected)
- Manual backup scripts run from developer machines - Automate with CronJob for consistency

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | kubectl + bash validation scripts |
| Config file | none - shell scripts in .planning/phases/05-data-layer/ |
| Quick run command | `kubectl get statefulsets,svc,cronjobs -n firecrawl` |
| Full suite command | `bash .planning/phases/05-data-layer/validate-data-layer.sh` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DATA-01 | Postgres StatefulSet deployed with PVC mount | integration | `kubectl get statefulset postgres -n firecrawl -o jsonpath='{.spec.template.spec.volumes[?(@.name=="postgres-data")].persistentVolumeClaim.claimName}' \| grep -q postgres-data` | ❌ Wave 0 |
| DATA-02 | Postgres resource limits configured | unit | `kubectl get statefulset postgres -n firecrawl -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' \| grep -q 4Gi` | ❌ Wave 0 |
| DATA-03 | Postgres readiness/liveness probes configured | unit | `kubectl get statefulset postgres -n firecrawl -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.exec.command[2]}' \| grep -q pg_isready` | ❌ Wave 0 |
| DATA-04 | Redis StatefulSet deployed with PVC mount | integration | `kubectl get statefulset redis -n firecrawl -o jsonpath='{.spec.template.spec.volumes[?(@.name=="redis-data")].persistentVolumeClaim.claimName}' \| grep -q redis-data` | ❌ Wave 0 |
| DATA-05 | Redis resource limits configured | unit | `kubectl get statefulset redis -n firecrawl -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' \| grep -q 2Gi` | ❌ Wave 0 |
| DATA-06 | Redis readiness/liveness probes configured | unit | `kubectl get statefulset redis -n firecrawl -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.exec.command[1]}' \| grep -q ping` | ❌ Wave 0 |
| DATA-07 | Services exist with correct DNS | integration | `kubectl exec -n firecrawl postgres-0 -- sh -c 'pg_isready -h postgres-service.firecrawl.svc.cluster.local'` | ❌ Wave 0 |
| DATA-08 | CronJob created for backups (6 hours) | unit | `kubectl get cronjob postgres-backup -n firecrawl -o jsonpath='{.spec.schedule}' \| grep -q '0 \*/6 \* \* \*'` | ❌ Wave 0 |
| DATA-09 | Backup restoration procedure documented | manual | Read backup-restore-runbook.md for completeness | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `kubectl get statefulsets,pods,svc -n firecrawl` (verify resources exist and pods are ready)
- **Per wave merge:** `bash .planning/phases/05-data-layer/validate-data-layer.sh` (full validation including connectivity tests)
- **Phase gate:** Postgres and Redis pods in Running state with 1/1 ready, CronJob created, backup runbook documented

### Wave 0 Gaps

- [ ] `validate-data-layer.sh` - Comprehensive validation script covering DATA-01 through DATA-08
  ```bash
  #!/bin/bash
  # Check StatefulSet status and replica readiness
  # Verify PVC mounts
  # Test database connectivity (pg_isready, redis-cli ping)
  # Confirm resource limits configuration
  # Validate CronJob schedule and recent job success
  ```
- [ ] `backup-restore-runbook.md` - Documented restoration procedure (DATA-09)
  ```markdown
  # Backup Restoration Runbook

  ## Prerequisites
  - kubectl access to firecrawl namespace
  - gsutil access to firecrawl-backups bucket

  ## Restoration Steps
  1. List available backups
  2. Download selected backup
  3. Scale down application pods (prevent writes during restore)
  4. Restore database using psql
  5. Verify restoration
  6. Scale up application pods

  ## Testing Restoration (Quarterly)
  - Create test namespace
  - Restore backup to test database
  - Run application smoke tests
  - Document test results
  ```
- [ ] GCS bucket creation and Workload Identity configuration (prerequisite, not automated)
  ```bash
  # Create GCS bucket
  gsutil mb -p prometheus-461323 -l us-central1 gs://firecrawl-backups

  # Create GCP service account and bind Workload Identity
  gcloud iam service-accounts create firecrawl-backup --project=prometheus-461323
  # (Full commands in Pattern 5 above)
  ```

## Sources

### Primary (HIGH confidence)

- Kubernetes Official Documentation - kubernetes.io/docs/
  - StatefulSet concepts and configuration (v1.27-1.29)
  - Service networking and DNS resolution
  - CronJob scheduling and job management
  - Liveness and readiness probe configuration
- Postgres Official Docker Image - hub.docker.com/_/postgres
  - Environment variable configuration (POSTGRES_DB, POSTGRES_USER, PGDATA)
  - Health check commands (pg_isready)
  - File system requirements and permissions
- Redis Official Docker Image - hub.docker.com/_/redis
  - Command-line arguments for configuration
  - AOF persistence configuration (appendonly, appendfsync)
  - Health check commands (redis-cli ping)
- GKE Workload Identity Documentation - cloud.google.com/kubernetes-engine/docs/how-to/workload-identity
  - ServiceAccount annotation syntax
  - IAM policy binding for GCS access

### Secondary (MEDIUM confidence)

- Kubernetes Best Practices for StatefulSets - Various sources
  - Resource limit recommendations for databases
  - Probe timing guidelines (initialDelaySeconds, failureThreshold)
  - Volume mount patterns for databases
- PostgreSQL Administration Documentation - postgresql.org/docs/
  - pg_dump command options (--clean, --if-exists, --create)
  - Backup strategies for production databases
  - Memory configuration (shared_buffers, work_mem)
- Redis Persistence Documentation - redis.io/topics/persistence
  - AOF vs RDB tradeoffs
  - fsync policies (everysec, always, no)
- Google Cloud Storage Best Practices - cloud.google.com/storage/docs/best-practices
  - Lifecycle management for backup retention
  - Versioning for protection against deletion

### Tertiary (LOW confidence)

- Training data knowledge of postgres:15-alpine and redis:7-alpine versions - Should verify latest patch versions in production
- Probe timing recommendations (30s/60s initialDelaySeconds) - Based on typical cold-start performance; may need tuning for actual workload
- Resource limit recommendations (Postgres 1-4Gi, Redis 512Mi-2Gi) - Conservative estimates; should be tuned based on load testing in Phase 6

## Open Questions

1. **Should Postgres use streaming replication for high availability?**
   - What we know: Single-instance Postgres is simpler but introduces single point of failure
   - What's unclear: Whether v1 requires HA or if single instance is acceptable with backup/restore
   - Recommendation: Start with single instance (replicas: 1) for v1 simplicity. Document upgrade path to Patroni operator for v2.

2. **What is the optimal CronJob schedule for backups?**
   - What we know: Requirement DATA-08 specifies "every 6 hours" (0 */6 * * *)
   - What's unclear: Whether 6-hour RPO (recovery point objective) is sufficient for production workload
   - Recommendation: Implement 6-hour schedule as specified. Monitor database change rate and adjust if needed (2-hour backups for high-change workloads).

3. **Should we use pg_basebackup (physical) instead of pg_dump (logical)?**
   - What we know: pg_dump is portable across Postgres versions and easier to restore selectively; pg_basebackup is faster for large databases
   - What's unclear: Expected database size and restore requirements
   - Recommendation: Use pg_dump for v1 (simpler, more portable). Document upgrade to pg_basebackup + WAL archiving if database exceeds 100GB.

4. **Do we need connection pooling (PgBouncer)?**
   - What we know: Postgres has connection overhead (~10Mi per connection); PgBouncer reduces database load
   - What's unclear: Expected number of concurrent connections from API and workers
   - Recommendation: Skip PgBouncer for v1 (adds complexity). Monitor Postgres connection count. Add PgBouncer sidecar in Phase 6 if connections exceed 80% of max_connections.

5. **Should Redis use RDB snapshots in addition to AOF?**
   - What we know: AOF provides better durability; RDB is faster to load on restart
   - What's unclear: Whether restart time is critical (AOF replay can take minutes for large datasets)
   - Recommendation: Use AOF-only for v1 (appendonly yes, no RDB). Enable RDB in addition to AOF if restart time exceeds 5 minutes in production.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Postgres, Redis, StatefulSet, Service, and CronJob are stable, well-documented Kubernetes patterns
- Architecture: HIGH - StatefulSet with PVC mount, exec probes, and ClusterIP Services are production-proven patterns
- Pitfalls: HIGH - Probe timing issues, resource limits, PGDATA conflicts, and AOF persistence are well-documented failure modes
- Backup strategy: MEDIUM-HIGH - pg_dump to GCS is standard pattern; CronJob scheduling and Workload Identity are proven; restoration testing needs project-specific documentation

**Research date:** 2026-03-27
**Valid until:** 180 days (Database deployment patterns are stable; Postgres 15 and Redis 7 are current stable versions)

**Notes:**
- Phase 5 depends on successful Phase 4 completion (PVCs must be bound)
- Phase 6 depends on Phase 5 completion (databases must be healthy before application starts)
- Backup restoration testing (DATA-09) should be performed quarterly to validate backup integrity
- Resource limits are conservative estimates; tune based on actual workload in Phase 6
