# Firecrawl Secrets - Manual Creation Guide

**IMPORTANT:** Secrets are NEVER committed to Git. This document provides instructions for creating secrets manually via kubectl.

## Prerequisites

The firecrawl namespace must exist before creating secrets:

```bash
kubectl get namespace firecrawl
```

If the namespace doesn't exist, apply the base manifests first:

```bash
kubectl apply -k k8s/base/
```

## Required Secrets

### 1. Database Secret

Contains Postgres credentials for database authentication.

```bash
kubectl create secret generic firecrawl-database-secret \
  --from-literal=POSTGRES_USER=firecrawl \
  --from-literal=POSTGRES_PASSWORD='<GENERATE: openssl rand -base64 32>' \
  --namespace=firecrawl \
  --dry-run=client -o yaml | kubectl apply -f -
```

**Password requirements:**
- Minimum 20 characters
- Mix of uppercase, lowercase, numbers, symbols
- Generate with: `openssl rand -base64 32`

### 2. Application API Secrets

Contains third-party API keys and authentication tokens required for Firecrawl operation.

```bash
kubectl create secret generic firecrawl-api-secrets \
  --from-literal=OPENAI_API_KEY='<FROM_OPENAI_DASHBOARD>' \
  --from-literal=SUPABASE_ANON_TOKEN='<FROM_SUPABASE_DASHBOARD>' \
  --from-literal=SUPABASE_SERVICE_TOKEN='<FROM_SUPABASE_DASHBOARD>' \
  --from-literal=SUPABASE_URL='<FROM_SUPABASE_DASHBOARD>' \
  --from-literal=BULL_AUTH_KEY='<GENERATE: openssl rand -hex 16>' \
  --namespace=firecrawl \
  --dry-run=client -o yaml | kubectl apply -f -
```

**Where to get credentials:**
- **OPENAI_API_KEY**: OpenAI Dashboard → API Keys → Create new secret key
- **SUPABASE_ANON_TOKEN**: Supabase Dashboard → Settings → API → anon public key
- **SUPABASE_SERVICE_TOKEN**: Supabase Dashboard → Settings → API → service_role key (secret)
- **SUPABASE_URL**: Supabase Dashboard → Settings → API → Project URL
- **BULL_AUTH_KEY**: Generate with `openssl rand -hex 16`

### 3. Optional Secrets

Add these keys to `firecrawl-api-secrets` if the corresponding features are enabled:

```bash
# If using SearchAPI for search functionality
--from-literal=SEARCHAPI_API_KEY='<FROM_SEARCHAPI_DASHBOARD>' \

# If using LlamaParse for PDF parsing
--from-literal=LLAMAPARSE_API_KEY='<FROM_LLAMAPARSE_DASHBOARD>' \

# If using ScrapingBee for JS blocking handling
--from-literal=SCRAPING_BEE_API_KEY='<FROM_SCRAPINGBEE_DASHBOARD>' \

# If using Slack notifications
--from-literal=SLACK_WEBHOOK_URL='<FROM_SLACK_WEBHOOK_CONFIG>' \

# If using Stripe for billing
--from-literal=STRIPE_SECRET_KEY='<FROM_STRIPE_DASHBOARD>' \

# If using PostHog for analytics
--from-literal=POSTHOG_API_KEY='<FROM_POSTHOG_DASHBOARD>' \
--from-literal=POSTHOG_HOST='<FROM_POSTHOG_CONFIG>' \

# If using test API key
--from-literal=TEST_API_KEY='<GENERATE_OR_CONFIGURE>'
```

## Verification

After creating secrets, verify they exist and contain the expected keys:

```bash
# List all secrets in firecrawl namespace
kubectl get secrets -n firecrawl

# Verify database secret keys (does NOT show values)
kubectl describe secret firecrawl-database-secret -n firecrawl

# Verify API secrets keys (does NOT show values)
kubectl describe secret firecrawl-api-secrets -n firecrawl
```

Expected output should show the secret names and key counts, but NOT the actual values.

## Updating Secrets

To update a secret value, recreate the secret with the new value:

```bash
# Example: Update OpenAI API key
kubectl create secret generic firecrawl-api-secrets \
  --from-literal=OPENAI_API_KEY='sk-new-key-here' \
  --from-literal=SUPABASE_ANON_TOKEN='<KEEP_EXISTING_VALUE>' \
  --from-literal=SUPABASE_SERVICE_TOKEN='<KEEP_EXISTING_VALUE>' \
  --from-literal=SUPABASE_URL='<KEEP_EXISTING_VALUE>' \
  --from-literal=BULL_AUTH_KEY='<KEEP_EXISTING_VALUE>' \
  --namespace=firecrawl \
  --dry-run=client -o yaml | kubectl apply -f -
```

**Note:** When updating secrets, you must include ALL keys. Missing keys will be removed from the secret.

After updating secrets, restart pods to pick up the new values:

```bash
# Restart API deployment
kubectl rollout restart deployment/firecrawl-api -n firecrawl

# Restart worker deployment
kubectl rollout restart deployment/firecrawl-worker -n firecrawl
```

## Security Best Practices

1. **Never commit secrets to Git** - Even base64-encoded secrets in Git history can be extracted
2. **Rotate secrets regularly** - Recommended: 90-day rotation for production credentials
3. **Use separate secrets for environments** - Dev, staging, and production should have different credentials
4. **Limit access to secrets** - Use Kubernetes RBAC to restrict which ServiceAccounts can read secrets
5. **Audit secret access** - Monitor secret access logs: `kubectl get events -n firecrawl --field-selector involvedObject.kind=Secret`
6. **Consider sealed-secrets or external-secrets** - For GitOps-friendly secret management in v2 (deferred from v1 for simplicity)

## Troubleshooting

### Secret not found error

If pods fail to start with "secret not found" errors:

```bash
# Verify secrets exist
kubectl get secrets -n firecrawl

# Check pod events for details
kubectl describe pod <pod-name> -n firecrawl
```

### Invalid credentials error

If application starts but fails to authenticate:

```bash
# Verify secret has correct keys
kubectl get secret firecrawl-api-secrets -n firecrawl -o jsonpath='{.data}' | jq 'keys'

# Check if values are properly set (will show base64, decode to verify)
kubectl get secret firecrawl-api-secrets -n firecrawl -o jsonpath='{.data.OPENAI_API_KEY}' | base64 -d
```

### Pods not picking up secret changes

Kubernetes doesn't automatically restart pods when secrets change. Manual restart required:

```bash
kubectl rollout restart deployment/firecrawl-api -n firecrawl
```
