---
title: "04 · Pipelines as Code"
description: "Configure Pipelines as Code to automatically trigger the Tekton pipeline from GitHub push and tag events."
date: 2024-01-04
weight: 4
tags: ["pac", "pipelines-as-code", "github", "webhook"]
---

## What Is Pipelines as Code?

**Pipelines as Code (PaC)** is the bridge between your Git repository and Tekton. Instead of configuring webhooks and TriggerTemplates manually, PaC:

1. Reads pipeline definitions directly from the **`.tekton/` directory** in your repository
2. Listens to GitHub (or GitLab / Bitbucket) webhook events
3. Creates a `PipelineRun` automatically when an event matches the annotations in your pipeline file

This means your pipeline definition is **version-controlled alongside your application code** — no more config drift between what's in Git and what's deployed on the cluster.

---

## How PaC Works

```
.tekton/pipeline.yaml          (in your GitHub repo)
     │
     │  annotations:
     │    on-event: "[push]"
     │    on-target-branch: "[main, refs/tags/v*]"
     │
     ▼
PaC Controller (running in pipelines-as-code namespace)
     │
     │  GitHub webhook → match event → instantiate PipelineRun
     ▼
PipelineRun created in workshop-ci
     │
     │  Reports status back to GitHub commit/PR as a check
     ▼
GitHub commit shows ✅ or ❌
```

PaC also posts the pipeline status as a **GitHub commit check** — you get native CI feedback directly on your commits and pull requests.

---

## Step 1 — Generate a Webhook Secret

```bash
WEBHOOK_SECRET=$(openssl rand -hex 20)
echo "Webhook secret: $WEBHOOK_SECRET"
# Save this — you'll need it in GitHub too

# Create the secret on the cluster
oc create secret generic github-webhook-secret \
  --from-literal=secret="$WEBHOOK_SECRET" \
  -n workshop-ci
```

---

## Step 2 — Apply the PaC Repository Resource

The `Repository` CRD tells PaC which GitHub repository to watch and where to find the credentials.

```bash
# Substitute your values
sed -e "s|YOUR_GITHUB_ORG|${GITHUB_ORG}|g" \
    -e "s|YOUR_GITHUB_REPO|${GITHUB_REPO}|g" \
    tekton/pac/repository.yaml | oc apply -f -
```

Verify:

```bash
oc get repository -n workshop-ci
```

```
NAME           URL                                             SUCCEEDED
workshop-app   https://github.com/your-org/your-repo          True
```

---

## Step 3 — Get the Webhook Endpoint

```bash
PAC_ROUTE=$(oc get route -n pipelines-as-code \
  pipelines-as-code-controller \
  -o jsonpath='{.spec.host}')
echo "Webhook URL: https://${PAC_ROUTE}"
```

---

## Step 4 — Configure the GitHub Webhook

1. Open your GitHub repository → **Settings** → **Webhooks** → **Add webhook**
2. Fill in:
   - **Payload URL**: `https://<PAC_ROUTE>` (from previous step)
   - **Content type**: `application/json`
   - **Secret**: the `$WEBHOOK_SECRET` value from Step 1
   - **Which events?** → select **Let me select individual events**:
     - ✅ Push
     - ✅ Pull requests
3. Click **Add webhook**

GitHub will send a ping event — you should see a green ✅ tick next to the webhook.

> 💡 If the webhook shows an error, check the PaC controller logs:
> ```bash
> oc logs -n pipelines-as-code \
>   deployment/pipelines-as-code-controller -f
> ```

---

## Step 5 — Update the PipelineRun Template

The `.tekton/pipeline.yaml` file needs your Quay organisation substituted:

```bash
sed -i "s|YOUR_QUAY_ORG|${QUAY_ORG}|g" .tekton/pipeline.yaml

git add .tekton/pipeline.yaml
git commit -m "chore: set quay org in pac pipeline template"
git push origin main
```

---

## Step 6 — Verify the First Auto-Triggered Run

After pushing the commit above, PaC should detect the push and create a PipelineRun:

```bash
# Watch for the PipelineRun to appear
oc get pipelineruns -n workshop-ci --watch
```

You should also see a **pending → running → succeeded** check on your GitHub commit.

To view logs:

```bash
# Using tkn (if installed)
tkn pipelinerun logs -n workshop-ci --last -f

# Using oc
LAST_PR=$(oc get pipelinerun -n workshop-ci \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1].metadata.name}')
oc logs -n workshop-ci -l \
  tekton.dev/pipelineRun=$LAST_PR --all-containers -f
```

---

## Understanding the PaC Annotations

The annotations in `.tekton/pipeline.yaml` control what triggers a PipelineRun:

```yaml
# Trigger only on push events (not pull_request, etc.)
pipelinesascode.tekton.dev/on-event: "[push]"

# Target: main branch AND any v* tag
pipelinesascode.tekton.dev/on-target-branch: "[main, refs/tags/v*]"

# Prune old runs — keep max 5
pipelinesascode.tekton.dev/max-keep-runs: "5"
```

We have **three separate PipelineRun definitions** in `.tekton/pipeline.yaml`:

| PipelineRun | Branch filter | Helm values file | Environment |
|-------------|--------------|-----------------|-------------|
| `workshop-build` | `main` | `values-dev.yaml` | dev |
| `workshop-build-rc` | `refs/tags/v*-rc*` | `values-test.yaml` | test |
| `workshop-build-release` | `refs/tags/v*.*.*` | `values-prod.yaml` | prod |

---

## Summary

- ✅ PaC `Repository` resource configured
- ✅ GitHub webhook set up and verified
- ✅ First automated PipelineRun triggered by git push
- ✅ Pipeline status visible as a GitHub commit check

Continue to **[Module 05 → ArgoCD & GitOps](/posts/05-argocd-gitops/)**.
