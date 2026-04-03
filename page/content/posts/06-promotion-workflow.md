---
title: "06 · Promotion Workflow"
description: "Promote your application from Dev to Test to Production using git tags — fully automated."
date: 2024-01-06
weight: 6
tags: ["promotion", "gitops", "git-tags", "release"]
---

## The Promotion Model

This workshop uses **Git tags as the promotion mechanism**. There are no manual `oc` commands to move an image between environments — you simply tag a commit in Git and the pipeline does the rest.

```
Commit to main
      │  (automatic)
      ▼
 workshop-dev  ←── latest main build

      │  git tag v1.0.0-rc1
      ▼
 workshop-test ←── rc build deployed

      │  git tag v1.0.0
      ▼
 workshop-prod ←── release build deployed
```

Each environment tracks a different Helm values file. When Tekton updates that values file with the new image tag, ArgoCD detects the change and deploys automatically.

---

## Step 1 — Verify Dev is Running

After Module 04, every push to `main` triggers a build and deploys to dev. Confirm:

```bash
# Check pipeline ran successfully
oc get pipelineruns -n workshop-ci \
  --sort-by=.metadata.creationTimestamp | tail -3

# Check ArgoCD synced
oc get application workshop-app-dev -n openshift-gitops \
  -o jsonpath='{.status.sync.status}{"\n"}'

# Check pod is running
oc get pods -n workshop-dev

# Get the dev URL
echo "http://$(oc get route workshop-app \
  -n workshop-dev \
  -o jsonpath='{.spec.host}')"
```

Open the URL in your browser — you should see the workshop Hugo site! 🎉

---

## Step 2 — Promote to Test (Release Candidate)

Make a small change to the site content:

```bash
# Edit a page
echo "
> This is a test promotion." >> page/content/posts/01-overview.md

git add .
git commit -m "docs: add test note to overview"
git push origin main
```

Wait for the dev pipeline to succeed, then tag a release candidate:

```bash
git tag v1.0.0-rc1
git push origin v1.0.0-rc1
```

This triggers the `workshop-build-rc` PipelineRun defined in `.tekton/pipeline.yaml`:

```bash
# Watch for the rc pipeline run
oc get pipelineruns -n workshop-ci --watch
```

The pipeline will:
1. Clone the repo at tag `v1.0.0-rc1`
2. Build the Hugo site
3. Build and push image tagged `v1.0.0-rc1` to Quay
4. Update `helm/workshop-app/values-test.yaml` with `tag: "v1.0.0-rc1"`
5. Commit and push → ArgoCD syncs → `workshop-test` updated

Verify test deployment:

```bash
oc get application workshop-app-test -n openshift-gitops \
  -o jsonpath='{.status.sync.status}{"\n"}'

echo "http://$(oc get route workshop-app \
  -n workshop-test \
  -o jsonpath='{.spec.host}')"
```

---

## Step 3 — Promote to Production

After testing looks good, create the release tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

This triggers `workshop-build-release`, which:
1. Builds the image tagged `v1.0.0`
2. Updates `helm/workshop-app/values-prod.yaml`
3. ArgoCD deploys to `workshop-prod`

```bash
# Watch the release pipeline
oc get pipelineruns -n workshop-ci --watch

# Verify prod
oc get application workshop-app-prod -n openshift-gitops \
  -o jsonpath='{.status.sync.status}{"\n"}'

echo "http://$(oc get route workshop-app \
  -n workshop-prod \
  -o jsonpath='{.spec.host}')"
```

---

## What's Different Per Environment

| | Dev | Test | Prod |
|--|-----|------|------|
| **Replicas** | 1 | 1 | 2 |
| **Image tag** | git SHA | `v*-rc*` tag | `v*.*.*` tag |
| **TLS** | off | off | edge termination |
| **Resources** | minimal | minimal | higher limits |
| **Trigger** | push to `main` | `v*-rc*` tag | `v*.*.*` tag |

---

## Tagging Conventions

| Pattern | Example | Environment |
|---------|---------|-------------|
| (any commit to main) | — | dev |
| `v{major}.{minor}.{patch}-rc{n}` | `v1.2.0-rc1` | test |
| `v{major}.{minor}.{patch}` | `v1.2.0` | prod |

---

## Rolling Back

### Dev — push a revert commit
```bash
git revert HEAD --no-edit
git push origin main
```

### Test or Prod — re-tag a previous commit
```bash
# Find the good commit
git log --oneline -10

# Move the tag to a previous commit
git tag -d v1.0.0-rc2
git push origin :refs/tags/v1.0.0-rc2
git tag v1.0.0-rc2 <good-commit-sha>
git push origin v1.0.0-rc2
```

### ArgoCD rollback (emergency)
```bash
# Roll back to the previous ArgoCD revision (does NOT change Git)
argocd app rollback workshop-app-prod
```

> ⚠️ An ArgoCD rollback that conflicts with Git state will be reverted by ArgoCD's self-heal. For a persistent rollback, revert in Git.

---

## Summary

You now have a fully automated promotion pipeline:

- ✅ `git push main` → dev deployed automatically
- ✅ `git tag v*-rc*` → test deployed automatically
- ✅ `git tag v*.*.*` → prod deployed automatically
- ✅ All environments accessible via OpenShift Routes
- ✅ Rollback possible via git revert or ArgoCD UI

Continue to **[Module 07 · Troubleshooting & Tips](/posts/07-troubleshooting/)**.
