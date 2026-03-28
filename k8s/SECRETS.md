# Kubernetes Secrets Setup

This document describes the secrets required for Firecrawl deployment.

## Required Secrets

### 1. GitHub Repository Secrets

Set these in GitHub repository Settings → Secrets and variables → Actions:

```bash
# GCP Authentication (already set)
GCP_SA_KEY=<contents of ~/.gcp/credentials.json>

# OpenAI API Key
OPENAI_API_KEY=<your-openai-api-key>

# Supabase Credentials
SUPABASE_ANON_TOKEN=<your-supabase-anon-token>
SUPABASE_SERVICE_TOKEN=<your-supabase-service-role-key>
SUPABASE_URL=<your-supabase-url>
SUPABASE_REPLICA_URL=<your-supabase-replica-url-or-same-as-url>

# Database Credentials (Supabase PostgreSQL)
POSTGRES_USER=postgres
POSTGRES_PASSWORD=<your-supabase-db-password>

# Application Secrets
AUTUMN_SECRET_KEY=<64-char-hex-string-from-openssl-rand-hex-32>
BULL_AUTH_KEY=<random-string-for-bull-queue-auth>
```

### 2. Kubernetes Secrets

These secrets must be created manually in the cluster **once** before deployment:

#### firecrawl-secrets

```bash
kubectl create secret generic firecrawl-secrets \
  --from-literal=SUPABASE_ANON_TOKEN='<value>' \
  --from-literal=SUPABASE_SERVICE_TOKEN='<value>' \
  --from-literal=SUPABASE_URL='<value>' \
  --from-literal=SUPABASE_REPLICA_URL='<value>' \
  --from-literal=AUTUMN_SECRET_KEY='<value>' \
  --from-literal=OPENAI_API_KEY='<value>' \
  --from-literal=BULL_AUTH_KEY='<value>' \
  -n firecrawl
```

#### firecrawl-database-secret

```bash
kubectl create secret generic firecrawl-database-secret \
  --from-literal=POSTGRES_USER='postgres' \
  --from-literal=POSTGRES_PASSWORD='<value>' \
  -n firecrawl
```

## Generating Secret Values

### AUTUMN_SECRET_KEY
```bash
openssl rand -hex 32
```

### BULL_AUTH_KEY
```bash
openssl rand -hex 16
```

## Configuration Files

The following ConfigMaps reference these secrets:

- `configmap-database.yaml` - Database connection settings
- `configmap-application.yaml` - Application settings
- `configmap-redis.yaml` - Redis connection settings

Deployments use `envFrom` to load secrets:

```yaml
envFrom:
  - configMapRef:
      name: firecrawl-application
  - configMapRef:
      name: firecrawl-database
  - configMapRef:
      name: firecrawl-redis
  - secretRef:
      name: firecrawl-database-secret
  - secretRef:
      name: firecrawl-secrets
```

## Security Notes

- **Never commit `.env` files** - they contain actual secret values
- Secrets are created manually via kubectl and not stored in Git
- GitHub Actions uses repository secrets for CI/CD operations
- Argo CD reads manifests from Git but secrets remain in the cluster
- ConfigMaps (non-sensitive config) are committed to Git
- Secrets (sensitive data) are managed separately

## Initial Setup Checklist

1. ✅ Set GitHub repository secrets (GCP_SA_KEY, OPENAI_API_KEY, etc.)
2. ✅ Create Kubernetes namespace: `kubectl create namespace firecrawl`
3. ✅ Create `firecrawl-secrets` secret in cluster
4. ✅ Create `firecrawl-database-secret` secret in cluster
5. ✅ Deploy Argo CD Application manifest
6. ✅ Push code changes to trigger CI/CD pipeline
7. ✅ Verify images are built and kustomization.yaml is updated
8. ✅ Verify Argo CD syncs manifests to cluster
9. ✅ Verify all pods are running and healthy

## Updating Secrets

To update secrets after initial deployment:

```bash
# Delete existing secret
kubectl delete secret firecrawl-secrets -n firecrawl

# Recreate with new values
kubectl create secret generic firecrawl-secrets \
  --from-literal=... \
  -n firecrawl

# Restart deployments to pick up new secrets
kubectl rollout restart deployment firecrawl-api worker-extract worker-nuq worker-prefetch -n firecrawl
```

## Current Configuration

- **Database**: Supabase PostgreSQL (external managed service)
- **Redis**: In-cluster StatefulSet
- **Authentication**: Supabase with USE_DB_AUTHENTICATION=true
- **Blocklist**: Disabled (DISABLE_BLOCKLIST=true) to avoid requiring blocklist table
