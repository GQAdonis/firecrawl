---
phase: 1
slug: cicd-pipeline-foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-27
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bash + GitHub Actions (workflow validation) |
| **Config file** | .github/workflows/ci-build-deploy.yml |
| **Quick run command** | N/A (CI workflow only) |
| **Full suite command** | `act push -j build-push-update` (local testing with nektos/act) |
| **Estimated runtime** | ~180 seconds |

---

## Sampling Rate

- **After every task commit:** N/A (workflow is the deliverable, not code with traditional tests)
- **After every plan wave:** Manual validation - trigger workflow, verify all requirements pass
- **Before `/gsd:verify-work`:** Full integration test (see Phase gate below)
- **Max feedback latency:** 180 seconds (workflow runtime)

**Phase gate full integration test:**
1. Push test change to `apps/api/`
2. Verify workflow completes successfully
3. Verify both images appear in GCR with correct SHA tags
4. Verify `kustomization.yaml` updated and committed
5. Verify only 1 workflow run (no loop from manifest commit)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 1-01-01 | 01 | 1 | CI-02 | integration | `docker build -f apps/ui/ingestion-ui/Dockerfile .` | ❌ W0 | ⬜ pending |
| 1-01-02 | 01 | 1 | CI-06 | integration | `kustomize build k8s/base` | ❌ W0 | ⬜ pending |
| 1-02-01 | 02 | 2 | CI-01 | integration | Push test commit, verify via `gh run list` | ❌ W0 | ⬜ pending |
| 1-02-01 | 02 | 2 | CI-03 | integration | Inspect tags via `gcloud container images list-tags` | ❌ W0 | ⬜ pending |
| 1-02-01 | 02 | 2 | CI-04 | integration | `gcloud container images list --repository=gcr.io/prometheus-461323` | ❌ W0 | ⬜ pending |
| 1-02-01 | 02 | 2 | CI-05 | integration | Check workflow logs for verification step success | ❌ W0 | ⬜ pending |
| 1-02-01 | 02 | 2 | CI-06 | integration | `git diff HEAD~1 -- k8s/base/kustomization.yaml` (verify image update) | ❌ W0 | ⬜ pending |
| 1-02-01 | 02 | 2 | CI-07 | integration | `git log -1 --pretty=%B \| grep '\[skip ci\]'` | ❌ W0 | ⬜ pending |
| 1-02-02 | 02 | 2 | CI-08 | integration | Check workflow logs for WIF authentication step | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Workload Identity Federation provider and service account setup in GCP
- [ ] Repository secrets configuration: `WIF_PROVIDER`, `WIF_SERVICE_ACCOUNT`
- [ ] k8s/base/ directory structure with initial kustomization.yaml (created by Plan 01)
- [ ] apps/ui/ingestion-ui/Dockerfile creation (created by Plan 01)
- [ ] Local testing capability via nektos/act (optional but recommended)

*Note: Plans 01 and 02 create the k8s/ structure and Dockerfile. WIF setup and secrets configuration are manual prerequisites before Plan 02 execution (checkpoint:human-action).*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Workflow triggers on main push | CI-01 | Requires actual GitHub event | Push test commit to main, verify via `gh run list --limit 1` |
| Images appear in GCR | CI-04 | Requires GCP API access and successful build | After workflow: `gcloud container images list --repository=gcr.io/prometheus-461323` |
| Workflow doesn't re-trigger | CI-07 | Requires observing GitHub Actions behavior | After manifest commit: wait 2 min, verify no new run with `gh run list --limit 2` |
| WIF authentication succeeds | CI-08 | Requires GCP IAM validation | Check workflow logs for google-github-actions/auth step success |

*Note: CI/CD workflows are inherently integration tests. Unit testing is not applicable. Validation happens by executing the workflow and verifying outcomes.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify (N/A - only 4 tasks total)
- [ ] Wave 0 covers all MISSING references (WIF setup, secrets, local testing tools)
- [ ] No watch-mode flags (N/A - CI workflow has natural triggers)
- [ ] Feedback latency < 180s (workflow runtime)
- [ ] `nyquist_compliant: true` set in frontmatter (pending Wave 0 completion)

**Approval:** pending (will be approved after Wave 0 completion and first successful workflow run)
