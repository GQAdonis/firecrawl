# Postgres Backup Restoration Runbook

## Overview

Automated backups run every 6 hours via CronJob `postgres-backup` in the firecrawl namespace. Backups are compressed pg_dump files stored in `gs://firecrawl-backups/postgres/`.

Backup format: `postgres-backup-YYYYMMDD-HHMMSS.sql.gz`
Retention: 30 days (120 backups at 6-hour intervals)
RPO (Recovery Point Objective): 6 hours maximum data loss

## Prerequisites

- `kubectl` access to firecrawl namespace on client-cluster
- `gsutil` access to gs://firecrawl-backups bucket
- Postgres credentials from firecrawl-database-secret

## List Available Backups

```bash
# List all backups sorted by date (newest first)
gsutil ls -l gs://firecrawl-backups/postgres/ | sort -k2 -r | head -20

# Check most recent backup
gsutil ls -l gs://firecrawl-backups/postgres/ | sort -k2 -r | head -1
```

## Restoration Steps

### Step 1: Identify Target Backup

```bash
# List available backups
gsutil ls -l gs://firecrawl-backups/postgres/

# Choose the backup file to restore (e.g., postgres-backup-20260327-060000.sql.gz)
BACKUP_FILE="postgres-backup-YYYYMMDD-HHMMSS.sql.gz"
```

### Step 2: Scale Down Application Pods

Prevent writes during restoration to avoid data inconsistency.

```bash
# Scale down API and workers
kubectl scale deployment firecrawl-api -n firecrawl --replicas=0
kubectl scale deployment firecrawl-worker-extract -n firecrawl --replicas=0 2>/dev/null
kubectl scale deployment firecrawl-worker-nuq -n firecrawl --replicas=0 2>/dev/null
kubectl scale deployment firecrawl-worker-prefetch -n firecrawl --replicas=0 2>/dev/null

# Wait for pods to terminate
kubectl wait --for=delete pod -l app=firecrawl-api -n firecrawl --timeout=60s 2>/dev/null
```

### Step 3: Download Backup

```bash
# Download from GCS to local machine
gsutil cp gs://firecrawl-backups/postgres/${BACKUP_FILE} /tmp/${BACKUP_FILE}

# Decompress
gunzip /tmp/${BACKUP_FILE}
# Result: /tmp/postgres-backup-YYYYMMDD-HHMMSS.sql
```

### Step 4: Copy Backup to Postgres Pod

```bash
# Copy SQL file to postgres pod
kubectl cp /tmp/postgres-backup-YYYYMMDD-HHMMSS.sql firecrawl/postgres-0:/tmp/restore.sql
```

### Step 5: Restore Database

```bash
# Get database credentials
POSTGRES_USER=$(kubectl get secret firecrawl-database-secret -n firecrawl -o jsonpath='{.data.POSTGRES_USER}' | base64 -d)
POSTGRES_DB=$(kubectl get configmap firecrawl-database -n firecrawl -o jsonpath='{.data.POSTGRES_DB}')

# Execute restore
kubectl exec -n firecrawl postgres-0 -- bash -c "PGPASSWORD=\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token 2>/dev/null || echo '') psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -f /tmp/restore.sql"

# Alternative: restore using password from secret
kubectl exec -n firecrawl postgres-0 -- bash -c "psql -U \$POSTGRES_USER -d \$POSTGRES_DB -f /tmp/restore.sql"
```

### Step 6: Verify Restoration

```bash
# Check database is accessible
kubectl exec -n firecrawl postgres-0 -- pg_isready -U $POSTGRES_USER -d $POSTGRES_DB

# Check table counts (adjust table names to your schema)
kubectl exec -n firecrawl postgres-0 -- psql -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT schemaname, tablename FROM pg_tables WHERE schemaname = 'public';"

# Check row counts for key tables
kubectl exec -n firecrawl postgres-0 -- psql -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT relname, n_live_tup FROM pg_stat_user_tables ORDER BY n_live_tup DESC LIMIT 10;"
```

### Step 7: Scale Up Application Pods

```bash
# Scale up API and workers (adjust replica counts as needed)
kubectl scale deployment firecrawl-api -n firecrawl --replicas=1
kubectl scale deployment firecrawl-worker-extract -n firecrawl --replicas=1 2>/dev/null
kubectl scale deployment firecrawl-worker-nuq -n firecrawl --replicas=1 2>/dev/null
kubectl scale deployment firecrawl-worker-prefetch -n firecrawl --replicas=1 2>/dev/null

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=firecrawl-api -n firecrawl --timeout=120s
```

### Step 8: Verify Application Health

```bash
# Check all pods are running
kubectl get pods -n firecrawl

# Check API health endpoint (if available)
kubectl exec -n firecrawl $(kubectl get pod -l app=firecrawl-api -n firecrawl -o jsonpath='{.items[0].metadata.name}') -- curl -s http://localhost:3002/health 2>/dev/null || echo "Health check endpoint not available"
```

## Manual Backup Trigger

To create an immediate backup outside the 6-hour schedule:

```bash
# Trigger manual backup
kubectl create job --from=cronjob/postgres-backup manual-backup-$(date +%Y%m%d-%H%M%S) -n firecrawl

# Watch job progress
kubectl get jobs -n firecrawl -l app=postgres-backup --sort-by=.status.startTime -w

# Check job logs
kubectl logs -n firecrawl job/manual-backup-$(date +%Y%m%d-%H%M%S) -f
```

## Quarterly Restoration Testing

Perform quarterly to validate backup integrity (DATA-09 requirement).

1. Create test namespace: `kubectl create namespace firecrawl-restore-test`
2. Deploy temporary Postgres pod in test namespace
3. Download latest backup from GCS
4. Restore to test Postgres
5. Run basic queries to verify data integrity
6. Clean up: `kubectl delete namespace firecrawl-restore-test`
7. Document test results with date and outcome

## Troubleshooting

### Backup Job Failing
```bash
# Check recent job status
kubectl get jobs -n firecrawl -l app=postgres-backup --sort-by=.status.startTime

# View logs of failed job
kubectl logs -n firecrawl job/<job-name>

# Common issues:
# - GCS authentication: Check Workload Identity binding
# - Postgres connection: Check postgres-service DNS resolution
# - Disk space: Check /tmp in backup pod
```

### GCS Access Denied
```bash
# Verify Workload Identity annotation
kubectl get sa postgres-backup-sa -n firecrawl -o yaml

# Test GCS access manually
kubectl run gcs-test --rm -it --image=google/cloud-sdk:alpine --serviceaccount=postgres-backup-sa -n firecrawl -- gsutil ls gs://firecrawl-backups/
```
