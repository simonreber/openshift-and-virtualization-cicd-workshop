---
title: "05 · ArgoCD & GitOps"
description: "Configure the ArgoCD AppProject and Applications to automatically deploy new images to dev, test, and prod."
date: 2024-01-05
weight: 5
tags: ["argocd", "gitops", "helm", "openshift-gitops"]
---

## What Is ArgoCD?

**ArgoCD** is a declarative GitOps continuous delivery tool for Kubernetes. Instead of pushing manifests to a cluster with `kubectl apply`, you declare the desired state in Git and ArgoCD continuously reconciles the live cluster state to match.

```
Git repo (Helm chart + values)
        │
        │  ArgoCD polls every 3 min
        │  (or webhook for instant sync)
        ▼
  ArgoCD compares
  "desired" (Git) vs "live" (cluster)
        │
        │  Diff detected
        ▼
  ArgoCD syncs ──▶ OpenShift namespace
```

### Key concepts

| Concept | Description |
|---------|-------------|
| **Application** | ArgoCD CRD that maps a Git source to a cluster destination |
| **AppProject** | Scopes what repos and namespaces an Application can use |
| **Sync** | The act of applying Git state to the cluster |
| **Self-heal** | Automatically revert manual cluster changes to match Git |
| **Prune** | Delete resources that exist in cluster but not in Git |

---

## Our GitOps Flow

When Tekton finishes building an image:

1. `update-helm-values` task commits a new `tag:` into `helm/workshop-app/values-dev.yaml` (or test/prod)
2. ArgoCD detects the changed file in Git (within ~3 minutes, or immediately with a webhook)
3. ArgoCD re-renders the Helm chart with the new tag
4. ArgoCD applies the updated `Deployment` to the target namespace
5. OpenShift rolls out the new pod with the new image

---

## Step 1 — Update Manifest Placeholders

```bash
for FILE in argocd/appproject.yaml argocd/applications/*.yaml; do
  sed -i \
    -e "s|YOUR_GITHUB_ORG|${GITHUB_ORG}|g" \
    -e "s|YOUR_GITHUB_REPO|${GITHUB_REPO}|g" \
    -e "s|YOUR_QUAY_ORG|${QUAY_ORG}|g" \
    "$FILE"
done
```

Commit the updated files:

```bash
git add argocd/
git commit -m "chore: configure argocd manifests for ${GITHUB_ORG}/${GITHUB_REPO}"
git push origin main
```

---

## Step 2 — Apply the AppProject

```bash
oc apply -f argocd/appproject.yaml
```

Verify:

```bash
oc get appproject workshop -n openshift-gitops
```

The AppProject restricts ArgoCD to only deploy from your repo and only to the three workshop namespaces — defence in depth.

---

## Step 3 — Apply the ArgoCD Applications

```bash
oc apply -f argocd/applications/
```

Verify:

```bash
oc get applications -n openshift-gitops
```

```
NAME                 SYNC STATUS   HEALTH STATUS
workshop-app-dev     Synced        Healthy
workshop-app-test    Synced        Healthy
workshop-app-prod    Synced        Healthy
```

> The apps may show `OutOfSync` initially if the Helm values reference an image tag that doesn't exist yet. That's normal — the first pipeline run will fix it.

---

## Step 4 — Open the ArgoCD UI

```bash
# Get the ArgoCD URL
echo "https://$(oc get route openshift-gitops-server \
  -n openshift-gitops \
  -o jsonpath='{.spec.host}')"

# Get the initial admin password
oc extract secret/openshift-gitops-cluster \
  -n openshift-gitops \
  --to=- 2>/dev/null
```

Log in as `admin` with the extracted password. You should see three applications.

---

## Step 5 — Grant ArgoCD Access to Your Git Repo

If your fork is **private**, add a deploy key or credentials in ArgoCD:

**ArgoCD UI → Settings → Repositories → Connect Repo**

- **Connection Method**: HTTPS
- **Repository URL**: `https://github.com/YOUR_ORG/YOUR_REPO`
- **Username**: your GitHub username
- **Password**: your GitHub PAT

Or via CLI:

```bash
argocd repo add "https://github.com/${GITHUB_ORG}/${GITHUB_REPO}" \
  --username "${GITHUB_ORG}" \
  --password "ghp_YOUR_TOKEN"
```

---

## Step 6 — Force an Initial Sync

```bash
# Sync all three apps
for APP in workshop-app-dev workshop-app-test workshop-app-prod; do
  oc patch application $APP \
    -n openshift-gitops \
    --type merge \
    -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"syncStrategy":{"hook":{}}}}}'
done
```

Or click **Sync** in the ArgoCD UI.

---

## Understanding Helm in This Workshop

ArgoCD renders the Helm chart at `helm/workshop-app/` using two value files:

```
helm/workshop-app/values.yaml        ← base defaults
helm/workshop-app/values-dev.yaml    ← dev overrides (image tag lives here)
```

The `image.tag` field is what the Tekton pipeline updates:

```yaml
# values-dev.yaml (simplified)
image:
  tag: "abc1234"   # ← updated by pipeline
```

ArgoCD sees this change, re-renders the Deployment template, and applies it.

---

## Useful ArgoCD Commands

```bash
# Get all app statuses
oc get applications -n openshift-gitops -o wide

# Describe an app
oc describe application workshop-app-dev -n openshift-gitops

# Manually sync
oc patch application workshop-app-dev -n openshift-gitops \
  --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'

# Roll back to previous revision
argocd app rollback workshop-app-dev 2   # revision 2
```

---

## Summary

- ✅ `workshop` AppProject scopes ArgoCD to your repo and namespaces
- ✅ Three ArgoCD Applications watch `main` branch, each with different values files
- ✅ ArgoCD automatically syncs when Tekton updates the image tag in Git

Continue to **[Module 06 → Promotion Workflow](/posts/06-promotion-workflow/)**.
