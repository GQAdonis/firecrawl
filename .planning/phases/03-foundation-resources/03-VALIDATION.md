---
phase: 3
slug: foundation-resources
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-27
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | kubectl + bash validation (no application framework needed) |
| **Config file** | none — Wave 0 creates validation scripts |
| **Quick run command** | `./k8s/validate-foundation.sh` |
| **Full suite command** | `./k8s/validate-foundation.sh --full` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `./k8s/validate-foundation.sh` (smoke tests)
- **After every plan wave:** Run `./k8s/validate-foundation.sh --full` (full validation including RBAC permission checks)
- **Before `/gsd:verify-work`:** Full suite must be green + manual Secret verification
- **Max feedback latency:** 30 seconds

**Phase gate full validation:**
1. Run `./k8s/validate-foundation.sh --full`
2. Manual verification: All required Secrets exist per secrets-README.md
3. Verify Argo CD can see resources in firecrawl namespace

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 3-01-01 | 01 | 1 | FOUND-01 | smoke | `kubectl get namespace firecrawl && kubectl get resourcequota -n firecrawl && kubectl get limitrange -n firecrawl` | ❌ W0 | ⬜ pending |
| 3-01-02 | 01 | 1 | FOUND-02 | smoke | `kubectl get serviceaccount -n firecrawl \| grep -E 'firecrawl-(api\|worker\|ui\|playwright)'` | ❌ W0 | ⬜ pending |
| 3-01-03 | 01 | 1 | FOUND-03 | smoke | `kubectl get role,rolebinding -n firecrawl` | ❌ W0 | ⬜ pending |
| 3-01-04 | 01 | 1 | FOUND-04 | smoke | `kubectl get configmap -n firecrawl \| grep -E 'firecrawl-(database\|redis\|application)'` | ❌ W0 | ⬜ pending |
| 3-01-05 | 01 | 1 | FOUND-05, FOUND-06 | manual-only | Document Secret creation in secrets-README.md, verify manually | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `k8s/validate-foundation.sh` — smoke tests for FOUND-01 through FOUND-06
- [ ] `k8s/secrets-README.md` — manual Secret creation documentation (committed to Git)
- [ ] Validation script checks resource exists AND has expected structure (e.g., ResourceQuota has CPU/memory limits)

*Note: Wave 0 validation scripts will be created during plan execution as part of ensuring automated verification exists.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Secrets created manually via kubectl | FOUND-05 | Cannot automate without exposing credentials in Git | Follow secrets-README.md instructions, verify all secrets listed exist |
| Secret keys present with correct names | FOUND-06 | Sensitive data cannot be read in automated tests | `kubectl get secret <name> -n firecrawl -o jsonpath='{.data}' \| jq 'keys'` - verify expected keys present |

*Note: Kubernetes manifests are infrastructure configuration, not application code. Validation happens via kubectl commands checking cluster state, not traditional unit tests.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (validation scripts, secrets documentation)
- [ ] No watch-mode flags (N/A - kubectl commands are one-shot)
- [ ] Feedback latency < 30s (kubectl validation)
- [ ] `nyquist_compliant: true` set in frontmatter (pending Wave 0 completion)

**Approval:** pending (will be approved after Wave 0 completion and first successful validation run)
