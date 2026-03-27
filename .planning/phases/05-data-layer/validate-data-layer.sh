#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0
SKIP=0
NAMESPACE="firecrawl"

check() {
  local id="$1" desc="$2" cmd="$3"
  printf "%-8s %-60s " "$id" "$desc"
  if eval "$cmd" >/dev/null 2>&1; then
    echo "PASS"
    PASS=$((PASS + 1))
  else
    echo "FAIL"
    FAIL=$((FAIL + 1))
  fi
}

check_manifest() {
  local id="$1" desc="$2" file="$3" pattern="$4"
  printf "%-8s %-60s " "$id" "$desc"
  if [ -f "$file" ] && grep -q "$pattern" "$file"; then
    echo "PASS"
    PASS=$((PASS + 1))
  elif [ ! -f "$file" ]; then
    echo "SKIP (file not found: $file)"
    SKIP=$((SKIP + 1))
  else
    echo "FAIL"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Phase 5: Data Layer Validation ==="
echo ""

# DATA-01: Postgres StatefulSet with PVC mount
check_manifest "DATA-01" "Postgres StatefulSet exists" \
  "k8s/base/postgres-statefulset.yaml" "kind: StatefulSet"
check_manifest "DATA-01" "Postgres PVC mount (postgres-data)" \
  "k8s/base/postgres-statefulset.yaml" "claimName: postgres-data"

# DATA-02: Postgres resource limits
check_manifest "DATA-02" "Postgres CPU request (500m)" \
  "k8s/base/postgres-statefulset.yaml" "cpu: 500m"
check_manifest "DATA-02" "Postgres memory limit (4Gi)" \
  "k8s/base/postgres-statefulset.yaml" "memory: 4Gi"

# DATA-03: Postgres health probes
check_manifest "DATA-03" "Postgres readiness probe (pg_isready)" \
  "k8s/base/postgres-statefulset.yaml" "pg_isready"
check_manifest "DATA-03" "Postgres liveness initial delay (60s)" \
  "k8s/base/postgres-statefulset.yaml" "initialDelaySeconds: 60"

# DATA-04: Redis StatefulSet with PVC mount
check_manifest "DATA-04" "Redis StatefulSet exists" \
  "k8s/base/redis-statefulset.yaml" "kind: StatefulSet"
check_manifest "DATA-04" "Redis PVC mount (redis-data)" \
  "k8s/base/redis-statefulset.yaml" "claimName: redis-data"

# DATA-05: Redis resource limits
check_manifest "DATA-05" "Redis CPU request (200m)" \
  "k8s/base/redis-statefulset.yaml" "cpu: 200m"
check_manifest "DATA-05" "Redis memory limit (2Gi)" \
  "k8s/base/redis-statefulset.yaml" "memory: 2Gi"

# DATA-06: Redis health probes
check_manifest "DATA-06" "Redis readiness probe (redis-cli ping)" \
  "k8s/base/redis-statefulset.yaml" "redis-cli"
check_manifest "DATA-06" "Redis AOF persistence enabled" \
  "k8s/base/redis-statefulset.yaml" "appendonly"

# DATA-07: ClusterIP Services
check_manifest "DATA-07" "Postgres Service (port 5432)" \
  "k8s/base/postgres-service.yaml" "port: 5432"
check_manifest "DATA-07" "Redis Service (port 6379)" \
  "k8s/base/redis-service.yaml" "port: 6379"
check_manifest "DATA-07" "Postgres Service in kustomization" \
  "k8s/base/kustomization.yaml" "postgres-service.yaml"
check_manifest "DATA-07" "Redis Service in kustomization" \
  "k8s/base/kustomization.yaml" "redis-service.yaml"

# DATA-08: Backup CronJob (created in Plan 02)
check_manifest "DATA-08" "Backup CronJob exists" \
  "k8s/base/backup-cronjob.yaml" "kind: CronJob"
check_manifest "DATA-08" "Backup schedule (every 6 hours)" \
  "k8s/base/backup-cronjob.yaml" '0 \*/6 \* \* \*'
check_manifest "DATA-08" "Backup ServiceAccount with Workload Identity" \
  "k8s/base/backup-serviceaccount.yaml" "iam.gke.io/gcp-service-account"

# Optional: live cluster checks (only if kubectl is configured)
echo ""
if kubectl cluster-info >/dev/null 2>&1; then
  echo "=== Live Cluster Checks ==="
  check "LIVE" "Postgres StatefulSet ready" \
    "kubectl get statefulset postgres -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' | grep -q '1'"
  check "LIVE" "Redis StatefulSet ready" \
    "kubectl get statefulset redis -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' | grep -q '1'"
  check "LIVE" "Postgres Service exists" \
    "kubectl get svc postgres-service -n $NAMESPACE"
  check "LIVE" "Redis Service exists" \
    "kubectl get svc redis-service -n $NAMESPACE"
  check "LIVE" "Backup CronJob exists" \
    "kubectl get cronjob postgres-backup -n $NAMESPACE"
else
  echo "(Skipping live cluster checks - kubectl not configured or cluster unreachable)"
fi

echo ""
echo "=== Summary ==="
echo "PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "RESULT: FAIL"
  exit 1
else
  echo "RESULT: PASS"
  exit 0
fi
