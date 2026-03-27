---
phase: 6
slug: application-layer
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-27
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Jest 30.2.0 + Supertest 6.3.3 + kubectl validation scripts |
| **Config file** | Jest config in package.json, tests in apps/api/src/__tests__/ |
| **Quick run command** | `kubectl get pods -n firecrawl` (smoke test - no CrashLoopBackOff) |
| **Full suite command** | `bash k8s/scripts/validate-app-layer.sh` |
| **Estimated runtime** | ~3 minutes (includes pod wait, port-forward, health checks) |

---

## Sampling Rate

- **After every task commit:** Run `kubectl get pods -n firecrawl` (verify no CrashLoopBackOff)
- **After every plan wave:** Integration test — verify all pods Ready, test API endpoint via port-forward
- **Before `/gsd:verify-work`:** Full validation script (k8s/scripts/validate-app-layer.sh) + manual memory monitoring
- **Max feedback latency:** ~3 minutes

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| TBD | TBD | TBD | APP-01 | integration | `kubectl port-forward -n firecrawl svc/firecrawl-api-service 3002:3002 & curl http://localhost:3002/` | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | APP-02 | manual | Monitor: `kubectl top pod -n firecrawl --containers \| grep firecrawl-api` | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | APP-03 | unit | `kubectl exec -n firecrawl deploy/firecrawl-api -- node -e "console.log(require('v8').getHeapStatistics().heap_size_limit)"` | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | APP-04 | integration | `kubectl get pods -n firecrawl -l app=firecrawl-api -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}'` | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | APP-05 | integration | `kubectl logs -n firecrawl deploy/firecrawl-api -c wait-for-postgres` | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | APP-06 | e2e | `pnpm harness jest "snips/v1/extract.test.ts" -x` | ✅ apps/api/src/__tests__/snips/v1/extract.test.ts | ⬜ pending |
| TBD | TBD | TBD | APP-07 | manual | Monitor: `kubectl top pod -n firecrawl --containers \| grep worker` | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | APP-08 | unit | `kubectl exec -n firecrawl deploy/extract-worker -- node -e "console.log(require('v8').getHeapStatistics().heap_size_limit)"` | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | APP-09 | integration | `kubectl get pods -n firecrawl -l component=worker -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}'` | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | APP-10 | integration | `kubectl logs -n firecrawl deploy/extract-worker -c wait-for-redis` | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | APP-11 | smoke | `kubectl port-forward -n firecrawl svc/ingestion-ui-service 8080:80 & curl http://localhost:8080/` | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | APP-12 | manual | Monitor: `kubectl top pod -n firecrawl -l app=ingestion-ui` | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | APP-13 | integration | `kubectl get pods -n firecrawl -l app=ingestion-ui -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}'` | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | APP-14 | integration | `kubectl port-forward -n firecrawl svc/playwright-service 3000:3000 & curl -X POST http://localhost:3000/scrape` | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | APP-15 | manual | Monitor: `kubectl top pod -n firecrawl -l app=playwright-service` | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | APP-16 | smoke | `kubectl get svc -n firecrawl -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.ports[*].port}{"\n"}{end}'` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

*Note: Task IDs will be populated during planning phase. Most verification commands require deployed cluster resources.*

---

## Wave 0 Requirements

- [ ] `k8s/scripts/validate-app-layer.sh` — Automated validation script covering:
  - Wait for all pods Ready (timeout 5 minutes)
  - Check heap size via kubectl exec for API and workers
  - Verify init container logs show "ready" messages
  - Port-forward and curl health endpoints (/liveness, /health)
  - Submit test job via API and verify worker processes it
  - Check memory usage doesn't exceed 90% of limits
- [ ] Integration tests using `pnpm harness` — APP-06 covered by existing apps/api/src/__tests__/snips/v1/extract.test.ts
- [ ] Document manual validation steps in VALIDATION.md (memory monitoring, log inspection)

*Note: Existing Firecrawl test suite covers application logic. Phase 6 validation focuses on Kubernetes deployment correctness (probes, init containers, resource limits).*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| API stays within memory limits under load | APP-02 | Requires production workload or load testing | Monitor: `kubectl top pod -n firecrawl --containers \| grep firecrawl-api` - verify memory < 90% of limit (7.2Gi for 8Gi limit) |
| Workers stay within memory limits | APP-07 | Requires job processing under real workload | Monitor: `kubectl top pod -n firecrawl --containers \| grep worker` - verify each worker < 90% of limit |
| UI stays within memory limits | APP-12 | Requires user traffic or load testing | Monitor: `kubectl top pod -n firecrawl -l app=ingestion-ui` - verify memory < 90% of limit |
| Playwright stays within memory limits | APP-15 | Requires scraping workload with concurrent browser contexts | Monitor: `kubectl top pod -n firecrawl -l app=playwright-service` - verify memory < 90% of 4Gi limit |
| Application pods can process requests without crashing | Success Criterion 10 | End-to-end validation requires full workflow: submit job, process, return results | Submit test scrape job via API, verify worker picks it up from queue, verify completion, check pod logs for errors |

*Note: Resource limit validation requires production-like workload. Phase 6 deployment uses conservative limits (API 8Gi, extract-worker 8Gi, nuq-worker 4Gi, prefetch-worker 2Gi) that should be tuned based on monitoring after deployment.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (validate-app-layer.sh script, manual testing documentation)
- [ ] No watch-mode flags (N/A - kubectl commands are one-shot, pnpm harness uses -x flag for fail-fast)
- [ ] Feedback latency < 3 minutes (kubectl + port-forward + curl checks)
- [ ] `nyquist_compliant: true` set in frontmatter (pending Wave 0 completion)

**Approval:** pending (will be approved after Wave 0 completion and first successful validation run)
