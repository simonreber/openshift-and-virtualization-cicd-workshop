---
title: "04 · Triggering Pipelines"
description: "Trigger Tekton PipelineRuns manually using oc create, understand the pipeline flow, and promote builds across environments."
date: 2024-01-04
weight: 4
tags: ["tekton", "pipelinerun", "ci", "trigger"]
---

## Why Manual Triggers?

This workshop triggers Tekton pipelines **manually** using `oc create -f`. This is an intentional choice:

- Zero additional setup (no webhooks, no tokens, no GitHub App registration)
- Transparent — you see exactly what parameters are passed
- Easy to debug — the PipelineRun YAML is fully readable
- Identical to what an automated trigger would create under the hood

Automated triggering via **Pipelines as Code** will be covered in a future module once the core workflow is solid.

---

## The PipelineRun Templates

Three PipelineRun templates live in `tekton/pipelineruns/`:

| File | Environment | Git revision | Helm values file |
|------|-------------|-------------|-----------------|
| `run-dev.yaml` | `workshop-dev` | `main` | `values-dev.yaml` |
| `run-test.yaml` | `workshop-test` | `v*-rc*` tag | `values-test.yaml` |
| `run-prod.yaml` | `workshop-prod` | `v*.*.*` tag | `values-prod.yaml` |

Each file contains all parameters pre-filled by `setup.sh`. You `oc create -f` them directly.

---

## Step 1 — Trigger a Dev Build

```bash
oc create -f tekton/pipelineruns/run-dev.yaml
```

Watch it run:

```bash
# Quick status view
oc get pipelineruns -n workshop-ci

# Live watch
oc get pipelineruns -n workshop-ci --watch

# Full log stream (tkn CLI)
tkn pipelinerun logs -n workshop-ci --last -f

# Full log stream (oc only)
oc logs -n workshop-ci \
  -l tekton.dev/pipeline=workshop-build-pipeline \
  --all-containers --prefix -f
```

Each stage maps to a Tekton Task running as a Pod:

```
workshop-dev-xxxxx-clone-xxxxx        ← git-clone task
workshop-dev-xxxxx-build-hugo-xxxxx   ← build-hugo task
workshop-dev-xxxxx-build-push-xxxxx   ← buildah task
workshop-dev-xxxxx-update-image-xxxxx ← update-helm-values task
```

---

## Step 2 — Verify the Build Succeeded

```bash
oc get pipelineruns -n workshop-ci \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[0].reason,TIME:.status.completionTime'
```

Expected:

```
NAME                STATUS      TIME
workshop-dev-xxxxx  Succeeded   2024-01-01T12:00:00Z
```

---

## Step 3 — Confirm ArgoCD Deployed the New Image

Once the PipelineRun succeeds, the `update-helm-values` task commits a new `image.tag` to `helm/workshop-app/values-dev.yaml`. ArgoCD detects this within ~3 minutes and deploys.

```bash
# Check ArgoCD sync status
oc get application workshop-app-dev -n workshop-gitops

# Watch the rollout in the dev namespace
oc rollout status deployment/workshop-app -n workshop-dev

# Get the running image tag
oc get deployment workshop-app -n workshop-dev \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

---

## Step 4 — Promote to Test

When you are happy with dev, create a release candidate tag and trigger the test pipeline:

```bash
# Tag the commit
git tag v1.0.0-rc1
git push origin v1.0.0-rc1

# Trigger the test pipeline with the rc tag
RC_TAG=v1.0.0-rc1
sed -e "s|v1.0.0-rc1|${RC_TAG}|g" \
    tekton/pipelineruns/run-test.yaml | oc create -f -

# Watch
oc get pipelineruns -n workshop-ci --watch
```

ArgoCD syncs `values-test.yaml` → deploys `v1.0.0-rc1` to `workshop-test`.

---

## Step 5 — Promote to Production

After test validation:

```bash
git tag v1.0.0
git push origin v1.0.0

RELEASE_TAG=v1.0.0
sed -e "s|v1.0.0|${RELEASE_TAG}|g" \
    tekton/pipelineruns/run-prod.yaml | oc create -f -

oc get pipelineruns -n workshop-ci --watch
```

ArgoCD syncs `values-prod.yaml` → deploys `v1.0.0` to `workshop-prod`.

---

## Re-running a PipelineRun

Because PipelineRuns are immutable once created, to re-run you always `oc create` a new one. The `generateName` field ensures each run gets a unique name:

```bash
# Re-trigger dev (new PipelineRun every time)
oc create -f tekton/pipelineruns/run-dev.yaml
```

Old runs are automatically pruned by Tekton once the count exceeds the configured limit.

---

## Useful Commands

```bash
# List all PipelineRuns
oc get pipelineruns -n workshop-ci

# Delete all completed/failed runs
oc delete pipelineruns -n workshop-ci \
  --field-selector=status.conditions[0].reason=Failed

# Describe a specific run (events, parameters, workspace bindings)
oc describe pipelinerun <name> -n workshop-ci

# TaskRun view (individual steps)
oc get taskruns -n workshop-ci \
  -l tekton.dev/pipelineRun=<pipelinerun-name>
```

---

## Summary

- ✅ PipelineRun templates pre-filled by `setup.sh` for dev, test, and prod
- ✅ Dev build triggered with a single `oc create -f`
- ✅ ArgoCD automatically deploys after each successful build
- ✅ Promotion to test and prod via git tags + `oc create -f`

Continue to **[Module 05 → ArgoCD & GitOps](/posts/05-argocd-gitops/)**.
