# Firecrawl API Deployment

This API is automatically deployed via CI/CD when changes are pushed to main.

## CI/CD Pipeline

The GitHub Actions workflow builds and deploys on every push to `apps/api/**`:

1. **Build**: Docker image built from `Dockerfile`
2. **Tag**: Tagged with git SHA (7 chars)
3. **Push**: Pushed to GCR `gcr.io/prometheus-461323/firecrawl-api`
4. **Update**: Kustomization manifest updated with new tag
5. **Sync**: Argo CD auto-syncs to Kubernetes cluster

## Configuration

Environment variables are managed via:
- **ConfigMaps**: Non-sensitive configuration (committed to Git)
- **Secrets**: Sensitive credentials (managed separately via kubectl)

See `../../k8s/SECRETS.md` for full secrets documentation.

## Manual Deployment

To deploy manually:

```bash
# Build image
docker build -t gcr.io/prometheus-461323/firecrawl-api:latest .

# Push to GCR
docker push gcr.io/prometheus-461323/firecrawl-api:latest

# Update kustomization
cd ../../k8s/base
kustomize edit set image firecrawl-api=gcr.io/prometheus-461323/firecrawl-api:latest

# Apply to cluster (or let Argo CD sync)
kubectl apply -k .
```

## Health Checks

The deployment includes:
- **Readiness probe**: `GET /health` on port 3002
- **Liveness probe**: `GET /health` on port 3002
- **Init containers**: Wait for Postgres and Redis availability

## Resources

- **Requests**: 1Gi memory, 500m CPU
- **Limits**: 2Gi memory, 1000m CPU
- **Node.js heap**: 1740 MiB (85% of 2048 MiB limit)
