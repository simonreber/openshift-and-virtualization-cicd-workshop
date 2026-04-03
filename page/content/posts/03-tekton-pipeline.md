---
title: "03 · Tekton Tasks & Pipeline"
description: "Install the Tekton Tasks and Pipeline that build the Hugo site, create a container image, and update the Helm values."
date: 2024-01-03
weight: 3
tags: ["tekton", "pipeline", "buildah", "hugo"]
---

## What Is Tekton?

**Tekton** is a cloud-native, Kubernetes-native CI framework. Everything in Tekton is a CRD:

| CRD | Purpose |
|-----|---------|
| `Task` | Reusable, parameterised unit of work (one or more container steps) |
| `Pipeline` | Ordered graph of Tasks; shares workspaces and passes results between steps |
| `PipelineRun` | Instantiates a Pipeline with concrete parameter values |
| `TaskRun` | Instantiates a single Task (created automatically by a Pipeline) |

Tekton Tasks run as plain Kubernetes Pods — no special agents, no persistent build servers.

---

## Our Pipeline

The `workshop-build-pipeline` runs four sequential tasks:

```
clone ──▶ build-hugo ──▶ buildah-build-push ──▶ update-helm-values
```

### Task breakdown

**`git-clone`** (cluster task from OpenShift Pipelines)
: Clones the repository at the specified revision into the shared workspace.

**`build-hugo`** (custom, `tekton/tasks/build-hugo.yaml`)
: Runs `hugo --minify` inside `page/` using the `quay.io/sreber84/hugo:latest` image.
Output lands in `page/public/`.

**`buildah-build-push`** (custom, `tekton/tasks/buildah.yaml`)
: Calls Buildah to build the `Dockerfile` (which copies the Hugo output into the httpd image) and pushes the image to Quay.

**`update-helm-values`** (custom, `tekton/tasks/update-helm-values.yaml`)
: Uses `sed` to rewrite the `tag:` line in the target Helm values file, commits, and pushes.
ArgoCD detects the change and starts a sync automatically.

---

## Step 1 — Apply the Custom Tasks

```bash
oc apply -f tekton/tasks/
```

Verify:

```bash
oc get tasks -n workshop-ci
```

```
NAME                   AGE
build-hugo             5s
buildah-build-push     5s
update-helm-values     5s
```

---

## Step 2 — Apply the Pipeline

```bash
oc apply -f tekton/pipeline.yaml
```

Verify:

```bash
oc get pipeline -n workshop-ci
```

```
NAME                      AGE
workshop-build-pipeline   3s
```

Inspect the pipeline graph (requires `tkn` CLI or OpenShift Console):

```bash
# Using oc describe
oc describe pipeline workshop-build-pipeline -n workshop-ci
```

Or open the **OpenShift Console** → **Pipelines** → `workshop-ci` → `workshop-build-pipeline` to see the visual graph.

---

## Step 3 — Run the Pipeline Manually (optional smoke test)

Before wiring up the webhook, you can trigger a PipelineRun manually to check everything works:

```bash
oc create -f - <<EOF
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: workshop-smoke-test-
  namespace: workshop-ci
spec:
  pipelineRef:
    name: workshop-build-pipeline
  params:
    - name: git-url
      value: "https://github.com/${GITHUB_ORG}/${GITHUB_REPO}"
    - name: git-revision
      value: main
    - name: image-registry
      value: quay.io
    - name: image-repo
      value: "${QUAY_ORG}/workshop-app"
    - name: image-tag
      value: smoke-test
    - name: github-repo-url
      value: "https://github.com/${GITHUB_ORG}/${GITHUB_REPO}"
    - name: helm-values-file
      value: helm/workshop-app/values-dev.yaml
    - name: helm-values-file-branch
      value: main
  workspaces:
    - name: shared-workspace
      persistentVolumeClaim:
        claimName: workshop-pipeline-pvc
    - name: quay-credentials
      secret:
        secretName: quay-credentials
    - name: github-token
      secret:
        secretName: github-token
EOF
```

Watch progress:

```bash
# Stream logs (requires tkn CLI)
tkn pipelinerun logs -n workshop-ci -f --last

# Or using oc
oc get pipelineruns -n workshop-ci --watch
```

Each TaskRun becomes a Pod — you can also watch the pods:

```bash
oc get pods -n workshop-ci --watch
```

Expected final state:

```
workshop-smoke-test-xxxxx   Succeeded
```

---

## Tekton Tips

### Viewing TaskRun logs

```bash
# List TaskRuns for last PipelineRun
oc get taskruns -n workshop-ci \
  -l tekton.dev/pipelineRun=$(oc get pr -n workshop-ci \
    --sort-by=.metadata.creationTimestamp -o name | tail -1 | cut -d/ -f2)
```

### Retrying a failed task

```bash
# Delete and re-create the PipelineRun with the same params
# (Tekton PipelineRuns are immutable once created)
oc delete pipelinerun -n workshop-ci -l tekton.dev/pipeline=workshop-build-pipeline
```

### Workspace persistence

The `workshop-pipeline-pvc` PVC is `ReadWriteOnce` — only one PipelineRun can use it at a time. For parallel builds, switch to an `emptyDir` workspace or a `ReadWriteMany` storage class.

---

## Summary

- ✅ Three custom Tasks installed in `workshop-ci`
- ✅ `workshop-build-pipeline` installed
- ✅ Optional smoke-test PipelineRun verifies end-to-end image build

Continue to **[Module 04 → Pipelines as Code](/posts/04-pipelines-as-code/)**.
