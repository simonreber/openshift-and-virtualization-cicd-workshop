# 🚀 OpenShift Pipelines & GitOps Workshop - Still work in progress

> **A hands-on workshop demonstrating Tekton (OpenShift Pipelines) + Pipelines as Code + ArgoCD (OpenShift GitOps) on Red Hat OpenShift.**

---

## 🗺️ Overview

This workshop walks you through building a fully automated CI/CD pipeline on Red Hat OpenShift using:

| Tool | OpenShift Component | Purpose |
|------|-------------------|---------|
| [Tekton](https://tekton.dev/) | OpenShift Pipelines | Build container images via CI |
| [Pipelines as Code](https://pipelinesascode.com/) | OpenShift Pipelines (PaC) | Trigger pipelines from GitHub events |
| [ArgoCD](https://argo-cd.readthedocs.io/) | OpenShift GitOps | Continuous Delivery / GitOps |
| [Helm](https://helm.sh/) | - | Kubernetes manifest templating |
| [Hugo](https://gohugo.io/) | - | Static site generator (our app) |
| [Quay.io](https://quay.io/) | - | Container image registry |

### Architecture Diagram

```
GitHub Push/Tag
      │
      ▼
┌─────────────────────────────────┐
│  Pipelines as Code (PaC)        │
│  Webhook → Trigger Pipeline     │
└───────────────┬─────────────────┘
                │
                ▼
┌─────────────────────────────────┐
│  Tekton Pipeline                │
│  1. Clone repo                  │
│  2. Build Hugo site             │
│  3. Build & push image → Quay   │
│  4. Update Helm values (tag)    │
└───────────────┬─────────────────┘
                │  (git commit to values)
                ▼
┌─────────────────────────────────┐
│  ArgoCD (OpenShift GitOps)      │
│  Watches git repo               │
│  Detects new image tag          │
│  Deploys via Helm to:           │
│   • workshop-dev   (branch: main)│
│   • workshop-test  (tag: v*-rc*) │
│   • workshop-prod  (tag: v*.*.*)  │
└─────────────────────────────────┘
```

### Promotion Flow

```
main branch  ──────►  workshop-dev   (auto, every commit)
     │
     ▼  git tag v1.0.0-rc1
     └──────────────────►  workshop-test  (auto, rc tags)
                 │
                 ▼  git tag v1.0.0
                 └────────────────►  workshop-prod  (auto, release tags)
```

---

## 📋 Prerequisites

- Red Hat OpenShift cluster (4.12+)
- OpenShift Pipelines operator installed
- OpenShift GitOps operator installed
- `oc` CLI configured and logged in
- `git` CLI
- GitHub account + repository (fork this repo)
- Quay.io account (or any OCI registry)

### Verify operators are installed

```bash
oc get csv -n openshift-operators | grep -E "pipelines|gitops"
```

You should see both operators in `Succeeded` state.

---

## 🏗️ Workshop Steps

### Step 1 — Fork & Clone this Repository

```bash
# Fork on GitHub first, then:
git clone https://github.com/YOUR_ORG/YOUR_FORK.git
cd YOUR_FORK
```

Set environment variables used throughout the workshop:

```bash
export GITHUB_ORG="your-github-org"
export GITHUB_REPO="your-repo-name"
export QUAY_ORG="your-quay-org"
export QUAY_REPO="workshop-app"
export OCP_DOMAIN=$(oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}')
echo "OCP Domain: $OCP_DOMAIN"
```

---

### Step 2 — Create Namespaces

```bash
oc apply -f tekton/namespaces.yaml
```

Verify:

```bash
oc get namespaces | grep workshop
```

Expected:
```
workshop-dev    Active
workshop-test   Active
workshop-prod   Active
workshop-ci     Active
```

---

### Step 3 — Configure Quay.io Credentials

Create a robot account in Quay.io with write access to your repository, then:

```bash
# Create pull secret for all namespaces
for NS in workshop-dev workshop-test workshop-prod workshop-ci; do
  oc create secret docker-registry quay-credentials \
    --docker-server=quay.io \
    --docker-username="YOUR_QUAY_ROBOT" \
    --docker-password="YOUR_QUAY_TOKEN" \
    -n $NS

  oc secrets link default quay-credentials --for=pull -n $NS
  oc secrets link pipeline quay-credentials -n $NS 2>/dev/null || true
done
```

---

### Step 4 — Configure GitHub Credentials (for PaC)

Create a GitHub Personal Access Token (PAT) with `repo` and `admin:repo_hook` scopes:

```bash
oc create secret generic github-token \
  --from-literal=token=YOUR_GITHUB_PAT \
  -n workshop-ci
```

---

### Step 5 — Install Tekton Resources

Apply all Tekton manifests:

```bash
# ServiceAccount, RBAC
oc apply -f tekton/rbac.yaml

# Persistent Volume Claim for workspace
oc apply -f tekton/pvc.yaml

# Pipeline Tasks
oc apply -f tekton/tasks/

# The Pipeline itself
oc apply -f tekton/pipeline.yaml
```

Verify:

```bash
oc get pipeline -n workshop-ci
oc get tasks -n workshop-ci
```

---

### Step 6 — Configure Pipelines as Code

Apply the PaC repository configuration (connects GitHub webhook):

```bash
# Update the repository URL in the manifest first
sed -i "s|YOUR_GITHUB_ORG|$GITHUB_ORG|g" tekton/pac/repository.yaml
sed -i "s|YOUR_GITHUB_REPO|$GITHUB_REPO|g" tekton/pac/repository.yaml

oc apply -f tekton/pac/
```

Get the webhook URL to configure in GitHub:

```bash
oc get route -n pipelines-as-code pipelines-as-code-controller \
  -o jsonpath='{.spec.host}'
```

In GitHub → Settings → Webhooks → Add webhook:
- **Payload URL**: `https://<route-host>`
- **Content type**: `application/json`
- **Events**: Push events, Pull request events
- **Secret**: same value as in `tekton/pac/repository.yaml`

The PaC pipeline definition lives in `.tekton/` directory of this repo — it is automatically picked up.

---

### Step 7 — Configure ArgoCD

```bash
# Apply ArgoCD projects
oc apply -f argocd/appproject.yaml

# Apply ArgoCD Applications (dev, test, prod)
# Update image repo references first
sed -i "s|YOUR_QUAY_ORG|$QUAY_ORG|g" argocd/applications/*.yaml
sed -i "s|YOUR_GITHUB_ORG|$GITHUB_ORG|g" argocd/applications/*.yaml
sed -i "s|YOUR_GITHUB_REPO|$GITHUB_REPO|g" argocd/applications/*.yaml

oc apply -f argocd/applications/
```

Open the ArgoCD UI:

```bash
echo "https://$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}')"

# Get initial admin password
oc extract secret/openshift-gitops-cluster -n openshift-gitops --to=- 2>/dev/null | grep password
```

---

### Step 8 — Trigger Your First Build

Commit and push a change:

```bash
echo "# Test" >> page/content/posts/test.md
git add .
git commit -m "feat: trigger first pipeline run"
git push origin main
```

Watch the pipeline run:

```bash
# List pipeline runs
oc get pipelineruns -n workshop-ci --watch
```

Or open the OpenShift Console → Pipelines → workshop-ci namespace.

---

### Step 9 — Promote to Test Environment

```bash
git tag v1.0.0-rc1
git push origin v1.0.0-rc1
```

Watch the pipeline run for the `rc` tag — it will deploy to `workshop-test`.

---

### Step 10 — Promote to Production

```bash
git tag v1.0.0
git push origin v1.0.0
```

The pipeline runs, image is tagged `v1.0.0`, ArgoCD detects the new tag in the Helm values and deploys to `workshop-prod`.

---

### Step 11 — Access the Application

```bash
# Dev
echo "http://$(oc get route workshop-app -n workshop-dev -o jsonpath='{.spec.host}')"

# Test
echo "http://$(oc get route workshop-app -n workshop-test -o jsonpath='{.spec.host}')"

# Prod
echo "http://$(oc get route workshop-app -n workshop-prod -o jsonpath='{.spec.host}')"
```

---

## 📁 Repository Structure

```
.
├── README.md                    # This file (also rendered in the Hugo app)
├── .tekton/                     # PaC pipeline definitions (auto-picked up)
│   └── pipeline.yaml
├── tekton/                      # Tekton manifests to apply manually
│   ├── namespaces.yaml
│   ├── rbac.yaml
│   ├── pvc.yaml
│   ├── pipeline.yaml
│   ├── tasks/
│   │   ├── build-hugo.yaml
│   │   ├── buildah.yaml
│   │   └── update-helm-values.yaml
│   └── pac/
│       └── repository.yaml
├── argocd/                      # ArgoCD manifests
│   ├── appproject.yaml
│   └── applications/
│       ├── workshop-dev.yaml
│       ├── workshop-test.yaml
│       └── workshop-prod.yaml
├── helm/                        # Helm chart for the application
│   └── workshop-app/
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── values-dev.yaml
│       ├── values-test.yaml
│       ├── values-prod.yaml
│       └── templates/
│           ├── deployment.yaml
│           ├── service.yaml
│           └── route.yaml
├── virt/                        # OpenShift Virtualization manifests
│   ├── namespace.yaml
│   ├── rbac.yaml
│   ├── kickstart-server.yaml    # Deployment + Service + Route
│   ├── kickstart/
│   │   ├── centos10-workshop.ks # CentOS Stream 10 kickstart file
│   │   └── Dockerfile           # httpd container serving the KS file
│   ├── vm/
│   │   ├── virtualmachine.yaml          # VM (install phase)
│   │   ├── virtualmachine-postinstall.yaml  # VM (post-install)
│   │   ├── kickstart-configmap.yaml     # kickstart URL config
│   │   └── network.yaml                 # SSH NodePort service
│   └── argocd/
│       ├── appproject.yaml
│       └── applications/
│           ├── kickstart-server.yaml
│           └── centos-workshop-vm.yaml
└── page/                        # Hugo site source
    ├── config.toml
    ├── content/
    │   └── posts/               # Workshop modules 01-11 (Markdown)
    ├── themes/terminal/         # Custom dark terminal theme
    └── static/                  # CSS + JS
```

---

## 🔧 Troubleshooting

### Pipeline not triggering
```bash
# Check PaC controller logs
oc logs -n pipelines-as-code deployment/pipelines-as-code-controller -f

# Verify repository resource
oc get repository -n workshop-ci
```

### ArgoCD not syncing
```bash
# Check application status
oc get application -n openshift-gitops

# Force sync
oc patch application workshop-app-dev -n openshift-gitops \
  --type merge -p '{"operation": {"initiatedBy": {"username": "admin"}, "sync": {}}}'
```

### Image pull errors
```bash
# Verify secret is linked
oc get secrets -n workshop-dev | grep quay
oc describe sa default -n workshop-dev
```

---

## 📚 References

- [Tekton Documentation](https://tekton.dev/docs/)
- [Pipelines as Code](https://pipelinesascode.com/docs/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [OpenShift Pipelines](https://docs.openshift.com/container-platform/latest/cicd/pipelines/understanding-openshift-pipelines.html)
- [OpenShift GitOps](https://docs.openshift.com/container-platform/latest/cicd/gitops/understanding-openshift-gitops.html)
- [Hugo Documentation](https://gohugo.io/documentation/)

---

## 🖥️ Part 2 — OpenShift Virtualization

> Prerequisite: Part 1 complete (Namespaces, Tekton, ArgoCD configured and working).

### What's Added

| Resource | Path | Description |
|----------|------|-------------|
| Kickstart file | `virt/kickstart/centos10-workshop.ks` | CentOS Stream 10 unattended install |
| Kickstart Dockerfile | `virt/kickstart/Dockerfile` | httpd container serving the KS file |
| Kickstart server | `virt/kickstart-server.yaml` | Deployment + Service + Route (HTTP) |
| VirtualMachine | `virt/vm/virtualmachine.yaml` | KubeVirt VM booting from ISO + blank disk |
| Post-install VM | `virt/vm/virtualmachine-postinstall.yaml` | VM spec after OS install (disk only) |
| ArgoCD AppProject | `virt/argocd/appproject.yaml` | Scopes virt apps to workshop-virt |
| ArgoCD Applications | `virt/argocd/applications/` | kickstart-server + centos-workshop-vm |

### Virt Quick Start

```bash
# 1 — Namespace + RBAC
oc apply -f virt/namespace.yaml && oc apply -f virt/rbac.yaml

# 2 — Build & push kickstart server image
cd virt/kickstart
podman build -t quay.io/${QUAY_ORG}/kickstart-server:latest .
podman push quay.io/${QUAY_ORG}/kickstart-server:latest && cd ../..

# 3 — Deploy kickstart server via ArgoCD
sed -i "s|YOUR_QUAY_ORG|${QUAY_ORG}|g" virt/kickstart-server.yaml
for f in virt/argocd/appproject.yaml virt/argocd/applications/*.yaml; do
  sed -i -e "s|YOUR_GITHUB_ORG|${GITHUB_ORG}|g" \
         -e "s|YOUR_GITHUB_REPO|${GITHUB_REPO}|g" "$f"
done
oc apply -f virt/argocd/appproject.yaml
oc apply -f virt/argocd/applications/kickstart-server.yaml

# 4 — Verify HTTP kickstart access
curl -f http://$(oc get route kickstart-server -n workshop-virt \
  -o jsonpath='{.spec.host}')/centos10-workshop.ks | head -3

# 5 — Set cluster domain in ConfigMap + deploy VM
CLUSTER_DOMAIN=$(oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}')
sed -i "s|YOUR_CLUSTER_DOMAIN|${CLUSTER_DOMAIN}|g" virt/vm/kickstart-configmap.yaml
git add . && git commit -m "chore: set cluster domain" && git push origin main
oc apply -f virt/argocd/applications/centos-workshop-vm.yaml

# 6 — Watch DataVolume import (ISO ~800 MB)
oc get datavolumes -n workshop-virt --watch

# 7 — Boot VM, pass kickstart at Anaconda prompt
virtctl console centos-workshop -n workshop-virt
# At boot menu → Tab → append:
# inst.ks=http://kickstart-server-workshop-virt.apps.${CLUSTER_DOMAIN}/centos10-workshop.ks

# 8 — After install completes, switch to post-install manifest
cp virt/vm/virtualmachine-postinstall.yaml virt/vm/virtualmachine.yaml
git add virt/vm/virtualmachine.yaml
git commit -m "virt: post-install boot from disk"
git push origin main

# 9 — Connect
virtctl ssh root@centos-workshop -n workshop-virt  # password: workshop123!
```

### Virt References

- [OpenShift Virtualization Docs](https://docs.openshift.com/container-platform/latest/virt/about_virt/about-virt.html)
- [KubeVirt User Guide](https://kubevirt.io/user-guide/)
- [CDI DataVolume Docs](https://github.com/kubevirt/containerized-data-importer/blob/main/doc/datavolumes.md)
- [CentOS Stream 10 Mirror](https://mirror.stream.centos.org/10-stream/)
- [Kickstart Syntax Reference](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/performing_an_advanced_rhel_9_installation/kickstart-commands-and-options-reference_installing-rhel-as-an-experienced-user)
