---
title: "02 · Namespaces & RBAC"
description: "Create the four namespaces and configure the service accounts and role bindings that Tekton and ArgoCD need."
date: 2024-01-02
weight: 2
tags: ["openshift", "rbac", "namespaces"]
---

## Overview

We use four namespaces in this workshop:

| Namespace | Purpose |
|-----------|---------|
| `workshop-ci` | Tekton PipelineRuns and their workloads run here |
| `workshop-dev` | Application deployed from every push to `main` |
| `workshop-test` | Application deployed when a `v*-rc*` tag is pushed |
| `workshop-prod` | Application deployed when a `v*.*.*` release tag is pushed |

ArgoCD lives in its own `workshop-gitops` namespace (installed by the operator) and needs `admin`-level access to the three application namespaces.

---

## Step 1 — Create the Namespaces

```bash
oc apply -f tekton/namespaces.yaml
```

Verify:

```bash
oc get namespaces | grep workshop
```

```
workshop-ci     Active
workshop-dev    Active
workshop-test   Active
workshop-prod   Active
```

---

## Step 2 — Apply RBAC

```bash
oc apply -f tekton/rbac.yaml
```

This manifest creates:

- A `pipeline` **ServiceAccount** in `workshop-ci` (used by all PipelineRuns)
- `RoleBinding` giving that SA `edit` rights in `workshop-ci` (so it can create TaskRuns, update PVCs, etc.)
- `RoleBinding` giving the ArgoCD application controller `admin` rights in `workshop-dev`, `workshop-test`, and `workshop-prod`

Verify the service account exists:

```bash
oc get sa pipeline -n workshop-ci
```

Verify ArgoCD role bindings:

```bash
oc get rolebindings -n workshop-dev | grep gitops
oc get rolebindings -n workshop-test | grep gitops
oc get rolebindings -n workshop-prod | grep gitops
```

---

## Step 3 — Configure Registry Credentials

### 3a — Create a Quay Robot Account

1. Log in to [quay.io](https://quay.io)
2. Navigate to your organisation → **Robot Accounts** → **Create Robot Account**
3. Name it `workshop_push`
4. Grant it **Write** permissions on your `workshop-app` repository
5. Copy the robot username (format: `ORG+workshop_push`) and token

### 3b — Create the pull/push secret

```bash
for NS in workshop-ci workshop-dev workshop-test workshop-prod; do
  oc create secret docker-registry quay-credentials \
    --docker-server=quay.io \
    --docker-username="${QUAY_ORG}+workshop_push" \
    --docker-password="YOUR_ROBOT_TOKEN" \
    -n $NS

  # Allow the default SA to pull images
  oc secrets link default quay-credentials --for=pull -n $NS

  # Allow the pipeline SA to push (only needed in workshop-ci)
  if [ "$NS" = "workshop-ci" ]; then
    oc secrets link pipeline quay-credentials -n $NS
  fi
done
```

Verify:

```bash
oc get secrets -n workshop-ci | grep quay
oc describe sa pipeline -n workshop-ci | grep quay
```

---

## Step 4 — Configure GitHub Credentials

The Tekton `update-helm-values` task commits the new image tag back to the repo. It needs a GitHub PAT.

### Create the PAT

1. GitHub → **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)**
2. **Generate new token (classic)**
3. Scopes: ✅ `repo` (full) — this covers push access and webhook management
4. Copy the token

### Create the secret

```bash
oc create secret generic github-token \
  --from-literal=token=ghp_YOUR_TOKEN_HERE \
  -n workshop-ci
```

Verify:

```bash
oc get secret github-token -n workshop-ci
```

---

## Step 5 — Create the Pipeline Workspace PVC

```bash
oc apply -f tekton/pvc.yaml
```

Verify it is bound (this may take a few seconds on a freshly provisioned cluster):

```bash
oc get pvc workshop-pipeline-pvc -n workshop-ci
```

```
NAME                     STATUS   VOLUME   CAPACITY   ACCESS MODES
workshop-pipeline-pvc    Bound    ...      1Gi        RWO
```

> 💡 If the PVC stays in `Pending`, check that a default `StorageClass` is available:
> ```bash
> oc get storageclass
> ```

---

## Summary

At the end of this module you have:

- ✅ Four namespaces created and labelled
- ✅ `pipeline` ServiceAccount with appropriate RBAC
- ✅ ArgoCD controller authorised to deploy into dev/test/prod
- ✅ Quay credentials available in all namespaces
- ✅ GitHub PAT stored as a secret in `workshop-ci`
- ✅ Pipeline workspace PVC ready

Continue to **[Module 03 → Tekton Tasks & Pipeline](/posts/03-tekton-pipeline/)**.
