---
title: "01 · Overview & Prerequisites"
description: "What we're building, why it matters, and what you need before starting."
date: 2024-01-01
weight: 1
tags: ["intro", "prerequisites", "openshift"]
---

## What Are We Building?

This workshop walks you through a complete, production-style CI/CD pipeline running entirely on **Red Hat OpenShift**. By the end you will have:

- A **Tekton** pipeline that builds a Hugo static site into a container image and pushes it to **Quay.io**
- **Pipelines as Code** automatically triggering that pipeline from GitHub pushes and tags
- **ArgoCD** watching the Git repository and deploying to three isolated namespaces
- A **promotion workflow** — `git push` → dev, `git tag v*-rc*` → test, `git tag v*.*.*` → prod

Everything is driven by Git events. No manual `kubectl apply`, no CI server to babysit.

---

## Architecture at a Glance

```
GitHub Repo
    │
    │  push / tag event
    ▼
Pipelines as Code (PaC)
    │  webhook trigger (future: PaC)
    │  creates PipelineRun
    ▼
Tekton Pipeline (workshop-ci namespace)
    ├── git-clone    — fetch source
    ├── build-hugo   — compile Hugo site
    ├── buildah      — build & push OCI image → quay.io
    └── update-helm  — commit new tag to helm/values-*.yaml
                              │
                              │ git commit detected
                              ▼
                        ArgoCD (workshop-gitops)
                              │
                    ┌─────────┼──────────┐
                    ▼         ▼          ▼
               workshop-dev  workshop-test  workshop-prod
               (main push)  (rc tag)       (release tag)
```

---

## Component Glossary

| Term | What it is |
|------|-----------|
| **Tekton** | Cloud-native CI framework; pipelines are Kubernetes CRDs |
| **PipelineRun** | Manual trigger via `oc create -f tekton/pipelineruns/` |
| **ArgoCD** | GitOps CD tool; continuously reconciles cluster state with Git |
| **Helm** | Kubernetes package manager; templates our manifests |
| **Hugo** | Fast static site generator written in Go |
| **Quay.io** | Red Hat's container image registry |
| **OpenShift Route** | OpenShift-native HTTP/HTTPS ingress resource |

---

## Prerequisites

### Cluster access

```bash
# Verify you are logged in
oc whoami
oc cluster-info

# Check OpenShift version (4.12+ recommended)
oc version
```

### Operators installed

```bash
oc get csv -n openshift-operators \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.phase' \
  | grep -E "pipelines|gitops"
```

Expected output:
```
openshift-pipelines-operator-rh.v1.x.x   Succeeded
workshop-gitops-operator.v1.x.x          Succeeded
```

If missing, install from **OperatorHub** in the OpenShift Console, or:

```bash
# OpenShift Pipelines
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-pipelines-operator-rh
  namespace: openshift-operators
spec:
  channel: latest
  name: openshift-pipelines-operator-rh
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# OpenShift GitOps
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: workshop-gitops-operator
  namespace: openshift-operators
spec:
  channel: latest
  name: workshop-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

Wait for both to reach `Succeeded`:

```bash
watch oc get csv -n openshift-operators | grep -E "pipelines|gitops"
```

### Tools on your workstation

| Tool | Purpose | Install |
|------|---------|---------|
| `oc` | OpenShift CLI | [mirror.openshift.com](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/) |
| `git` | Version control | system package manager |
| `helm` (optional) | Local chart testing | [helm.sh/docs/intro/install](https://helm.sh/docs/intro/install/) |

### Accounts

- **GitHub** — Fork this repository; create a Personal Access Token with `repo` + `admin:repo_hook` scopes
- **Quay.io** — Create a free account; create an image repository and a robot account with write access

---

## Fork the Repository

```bash
# 1. Fork on GitHub (via UI), then clone your fork
git clone https://github.com/YOUR_ORG/YOUR_FORK.git
cd YOUR_FORK

# 2. Set convenience variables (used throughout all modules)
export GITHUB_ORG="your-github-org"
export GITHUB_REPO="your-repo-name"
export QUAY_ORG="your-quay-org"
export QUAY_REPO="workshop-app"
export OCP_DOMAIN=$(oc get ingress.config.openshift.io cluster \
  -o jsonpath='{.spec.domain}')

echo "Cluster domain: $OCP_DOMAIN"
```

> 💡 **Tip:** Add those exports to your shell profile or a `.envrc` file so they survive terminal restarts.

---

## What's Next?

Move on to **[Module 02 → Namespaces & RBAC](/posts/02-namespaces-rbac/)** to create the namespaces and wire up the necessary permissions.
