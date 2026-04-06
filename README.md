# 🚀 OpenShift Pipelines & GitOps Workshop

> ⚠️ **WORK IN PROGRESS — Not yet ready for public use.**
> This workshop is actively being developed. Steps may be incomplete, manifests may change without notice, and some sections are still being validated on real clusters. Use at your own risk and expect rough edges.

---

## 🗺️ Overview

A hands-on workshop demonstrating a complete CI/CD and GitOps stack on **Red Hat OpenShift**, covering:

| Part | Focus |
|------|-------|
| **Part 1** | Tekton (OpenShift Pipelines) · ArgoCD (OpenShift GitOps) · Hugo app |
| **Part 2** | OpenShift Virtualization (KubeVirt) · CentOS Stream 10 · Kickstart |

### Technology Stack

| Tool | OpenShift Component | Purpose |
|------|-------------------|---------|
| [Tekton](https://tekton.dev/) | OpenShift Pipelines | Container image CI builds |
| [ArgoCD](https://argo-cd.readthedocs.io/) | OpenShift GitOps | Continuous Delivery / GitOps |
| [Helm](https://helm.sh/) | — | Kubernetes manifest templating |
| [Hugo](https://gohugo.io/) | — | Static site generator (demo app) |
| [Quay.io](https://quay.io/) | — | Container image registry |
| [KubeVirt](https://kubevirt.io/) | OpenShift Virtualization | Virtual machine management |

> **Note on Pipelines as Code:** PaC is **intentionally excluded** from this version. PaC adds significant setup complexity (webhook configuration, GitHub App registration, token management) that makes it difficult to get working quickly. Pipelines are triggered **manually** using `oc create -f`. PaC will be added back in a future iteration once the core workshop flow is stable and validated.

---

## ⚠️ Prerequisites

- Red Hat OpenShift cluster (4.14+)
- **OpenShift Pipelines operator** installed and `Succeeded`
- **OpenShift GitOps operator** installed and `Succeeded` — used only to provision the dedicated instance
- `oc` CLI, logged in as `cluster-admin`
- `git` CLI
- GitHub account + fork of this repository
- Quay.io account with repositories `workshop-app` and `kickstart-server`

### Verify operators

```bash
oc get csv -n openshift-operators \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.phase' \
  | grep -E "pipelines|gitops"
```

Both must show `Succeeded`.

---

## 🔧 Initial Setup — Variables (Run Once)

All placeholder tokens in all manifests are replaced by a single script. **Do this before applying anything to the cluster.**

### Step 1 — Fork and Clone

```bash
git clone https://github.com/YOUR_ORG/YOUR_FORK.git
cd YOUR_FORK
```

### Step 2 — Edit setup.env

```bash
vi setup.env
```

| Variable | Description | Example |
|----------|-------------|---------|
| `GITHUB_ORG` | Your GitHub org or username | `myorg` |
| `GITHUB_REPO` | Your fork repository name | `workshop` |
| `QUAY_ORG` | Your Quay.io org or username | `myquayorg` |
| `OCP_DOMAIN` | Cluster apps domain (auto-detected if blank) | `apps.cluster.example.com` |

### Step 3 — Run setup.sh

```bash
source setup.env
./setup.sh
```

This replaces **all** placeholder tokens in every manifest file simultaneously, verifies nothing is left unresolved, and prints a confirmation. The files modified are:

| File | Tokens replaced |
|------|----------------|
| `gitops/argocd-instance.yaml` | — |
| `argocd/appproject.yaml` | `YOUR_GITHUB_ORG`, `YOUR_GITHUB_REPO` |
| `argocd/applications/workshop-dev.yaml` | `YOUR_GITHUB_ORG`, `YOUR_GITHUB_REPO` |
| `argocd/applications/workshop-test.yaml` | `YOUR_GITHUB_ORG`, `YOUR_GITHUB_REPO` |
| `argocd/applications/workshop-prod.yaml` | `YOUR_GITHUB_ORG`, `YOUR_GITHUB_REPO` |
| `helm/workshop-app/values.yaml` | `YOUR_QUAY_ORG` |
| `tekton/namespaces.yaml` | — |
| `tekton/rbac.yaml` | — |
| `tekton/pipelineruns/run-dev.yaml` | `YOUR_GITHUB_ORG`, `YOUR_GITHUB_REPO`, `YOUR_QUAY_ORG` |
| `tekton/pipelineruns/run-test.yaml` | `YOUR_GITHUB_ORG`, `YOUR_GITHUB_REPO`, `YOUR_QUAY_ORG` |
| `tekton/pipelineruns/run-prod.yaml` | `YOUR_GITHUB_ORG`, `YOUR_GITHUB_REPO`, `YOUR_QUAY_ORG` |
| `virt/argocd/appproject.yaml` | `YOUR_GITHUB_ORG`, `YOUR_GITHUB_REPO` |
| `virt/argocd/applications/kickstart-server.yaml` | `YOUR_GITHUB_ORG`, `YOUR_GITHUB_REPO` |
| `virt/argocd/applications/centos-workshop-vm.yaml` | `YOUR_GITHUB_ORG`, `YOUR_GITHUB_REPO` |
| `virt/kickstart-server.yaml` | `YOUR_QUAY_ORG` |
| `virt/namespace.yaml` | — |
| `virt/rbac.yaml` | — |
| `virt/vm/kickstart-configmap.yaml` | `YOUR_CLUSTER_DOMAIN` |

### Step 4 — Commit the Updated Manifests

```bash
git add -A
git commit -m "chore: apply workshop variables"
git push origin main
```

---

## 📁 Repository Structure

```
.
├── README.md                            # This file
├── setup.env                            # ← EDIT THIS first
├── setup.sh                             # ← RUN THIS second
├── Dockerfile                           # Multi-stage: Hugo build → httpd serve
├── .gitignore
│
├── gitops/                              # Dedicated ArgoCD instance
│   ├── namespace.yaml                   # workshop-gitops namespace
│   ├── argocd-instance.yaml             # ArgoCD CR (operator provisions it)
│   └── rbac.yaml                        # Grant ArgoCD access to all namespaces
│
├── tekton/                              # Tekton CI manifests
│   ├── namespaces.yaml                  # workshop-ci/dev/test/prod namespaces
│   ├── rbac.yaml                        # Pipeline SA + role bindings
│   ├── pvc.yaml                         # Shared workspace PVC
│   ├── pipeline.yaml                    # Pipeline definition
│   ├── tasks/
│   │   ├── build-hugo.yaml
│   │   ├── buildah.yaml
│   │   └── update-helm-values.yaml
│   └── pipelineruns/
│       ├── run-dev.yaml                 # Trigger dev build manually
│       ├── run-test.yaml                # Trigger test (rc) build manually
│       └── run-prod.yaml                # Trigger prod (release) build manually
│
├── argocd/                              # ArgoCD app manifests (Part 1)
│   ├── appproject.yaml
│   └── applications/
│       ├── workshop-dev.yaml
│       ├── workshop-test.yaml
│       └── workshop-prod.yaml
│
├── helm/                                # Helm chart for the Hugo app
│   └── workshop-app/
│       ├── Chart.yaml
│       ├── values.yaml                  # image.repository set by setup.sh
│       ├── values-dev.yaml
│       ├── values-test.yaml
│       ├── values-prod.yaml
│       └── templates/
│           ├── _helpers.tpl
│           ├── deployment.yaml
│           ├── service.yaml
│           └── route.yaml
│
├── virt/                                # OpenShift Virtualization (Part 2)
│   ├── namespace.yaml                   # workshop-virt namespace
│   ├── rbac.yaml                        # ArgoCD access to workshop-virt
│   ├── kickstart-server.yaml            # Deployment + Service + Route
│   ├── kickstart/
│   │   ├── centos10-workshop.ks         # CentOS Stream 10 kickstart file
│   │   └── Dockerfile                   # httpd image serving the KS file
│   ├── vm/
│   │   ├── virtualmachine.yaml              # VM (install phase)
│   │   ├── virtualmachine-postinstall.yaml  # VM (post-install, disk only)
│   │   ├── kickstart-configmap.yaml         # kickstart URL reference
│   │   └── network.yaml                     # SSH NodePort service
│   └── argocd/
│       ├── appproject.yaml
│       └── applications/
│           ├── kickstart-server.yaml
│           └── centos-workshop-vm.yaml
│
└── page/                                # Hugo site source
    ├── config.toml
    ├── content/posts/                   # Workshop modules 01–11 (Markdown)
    ├── themes/terminal/                 # Custom dark terminal theme
    └── static/                          # CSS + JS
```

---

## 🏗️ Part 1 — Tekton CI + ArgoCD GitOps

### Step 5 — Deploy the Dedicated ArgoCD Instance

We use a **dedicated ArgoCD instance** in `workshop-gitops`, not the cluster default `openshift-gitops`. This keeps the workshop self-contained.

```bash
# Create namespace then ArgoCD instance
oc apply -f gitops/namespace.yaml

# Wait for namespace to be active
oc wait --for=jsonpath='{.status.phase}'=Active namespace/workshop-gitops --timeout=30s

# Create the ArgoCD instance (operator provisions it automatically)
oc apply -f gitops/argocd-instance.yaml
```

Wait for all ArgoCD components to be ready (~2–3 minutes):

```bash
oc rollout status deployment/workshop-argocd-server \
  -n workshop-gitops --timeout=5m
oc rollout status deployment/workshop-argocd-repo-server \
  -n workshop-gitops --timeout=5m
oc rollout status statefulset/workshop-argocd-application-controller \
  -n workshop-gitops --timeout=5m
```

Verify and get credentials:

```bash
# Check all pods are Running
oc get pods -n workshop-gitops

# ArgoCD URL
echo "ArgoCD: https://$(oc get route workshop-argocd-server \
  -n workshop-gitops -o jsonpath='{.spec.host}')"

# Initial admin password
oc extract secret/workshop-argocd-cluster \
  -n workshop-gitops --to=- 2>/dev/null
```

### Step 6 — Apply ArgoCD RBAC

```bash
oc apply -f gitops/rbac.yaml
```

Verify:

```bash
oc get rolebindings -A | grep workshop-argocd-admin
```

### Step 7 — Create Namespaces and Tekton RBAC

```bash
oc apply -f tekton/namespaces.yaml
oc apply -f tekton/rbac.yaml
```

Verify:

```bash
oc get namespaces | grep workshop
oc get sa pipeline -n workshop-ci
```

### Step 8 — Configure Quay Registry Credentials

Create a Quay.io robot account with **write** access to both `workshop-app` and `kickstart-server` repositories, then:

```bash
QUAY_ROBOT="YOUR_QUAY_ROBOT_ACCOUNT"    # e.g. myorg+workshop_push
QUAY_TOKEN="YOUR_QUAY_ROBOT_TOKEN"

for NS in workshop-ci workshop-dev workshop-test workshop-prod workshop-virt; do
  oc create secret docker-registry quay-credentials \
    --docker-server=quay.io \
    --docker-username="${QUAY_ROBOT}" \
    --docker-password="${QUAY_TOKEN}" \
    -n ${NS}

  # Allow default SA to pull
  oc secrets link default quay-credentials --for=pull -n ${NS}
done

# Allow pipeline SA to push (workshop-ci only)
oc secrets link pipeline quay-credentials -n workshop-ci
```

Verify:

```bash
oc get secret quay-credentials -n workshop-ci
oc describe sa pipeline -n workshop-ci | grep quay
```

### Step 9 — Configure GitHub Credentials

Create a GitHub Personal Access Token (PAT) with `repo` scope. The `update-helm-values` task uses it to commit the updated image tag back to Git:

```bash
oc create secret generic github-token \
  --from-literal=token=ghp_YOUR_GITHUB_PAT \
  -n workshop-ci
```

### Step 10 — Create Pipeline Workspace PVC

```bash
oc apply -f tekton/pvc.yaml

# Verify it binds
oc get pvc workshop-pipeline-pvc -n workshop-ci
# Expected: STATUS = Bound
```

If it stays in `Pending`, check your default StorageClass:

```bash
oc get storageclass | grep default
```

### Step 11 — Install Tekton Tasks and Pipeline

```bash
oc apply -f tekton/tasks/
oc apply -f tekton/pipeline.yaml
```

Verify:

```bash
oc get tasks -n workshop-ci
oc get pipeline workshop-build-pipeline -n workshop-ci
```

### Step 12 — Trigger the First Dev Build

```bash
oc create -f tekton/pipelineruns/run-dev.yaml
```

Watch progress:

```bash
# PipelineRun status
oc get pipelineruns -n workshop-ci --watch

# Pod-level view
oc get pods -n workshop-ci --watch

# Log streaming (requires tkn CLI)
tkn pipelinerun logs -n workshop-ci --last -f

# Log streaming (oc only)
oc logs -n workshop-ci \
  -l tekton.dev/pipeline=workshop-build-pipeline \
  --all-containers --prefix -f
```

Expected final state: `SUCCEEDED`

### Step 13 — Deploy ArgoCD Applications

```bash
oc apply -f argocd/appproject.yaml
oc apply -f argocd/applications/
```

Verify in ArgoCD UI or:

```bash
oc get applications -n workshop-gitops
```

Expected:

```
NAME                 SYNC STATUS   HEALTH STATUS
workshop-app-dev     Synced        Healthy
workshop-app-test    OutOfSync     Missing      ← normal, no image yet
workshop-app-prod    OutOfSync     Missing      ← normal, no image yet
```

### Step 14 — Access the Dev Application

```bash
DEV_URL=$(oc get route workshop-app -n workshop-dev \
  -o jsonpath='{.spec.host}')
echo "Dev application: http://${DEV_URL}"
```

Open in a browser — you should see the workshop Hugo site. ✅

---

## 🚀 Triggering Builds and Promoting

### Dev — every code change

```bash
oc create -f tekton/pipelineruns/run-dev.yaml
```

### Test — release candidate

```bash
git tag v1.0.0-rc1 && git push origin v1.0.0-rc1

RC_TAG=v1.0.0-rc1
sed -e "s|v1.0.0-rc1|${RC_TAG}|g" \
    tekton/pipelineruns/run-test.yaml | oc create -f -
```

### Production — release

```bash
git tag v1.0.0 && git push origin v1.0.0

RELEASE_TAG=v1.0.0
sed -e "s|v1.0.0|${RELEASE_TAG}|g" \
    tekton/pipelineruns/run-prod.yaml | oc create -f -
```

Once the PipelineRun succeeds, ArgoCD detects the updated image tag in the Helm values file and deploys automatically.

---

## 🖥️ Part 2 — OpenShift Virtualization

> Prerequisite: Part 1 complete. ArgoCD is healthy.

Verify OpenShift Virtualization operator:

```bash
oc get hyperconverged kubevirt-hyperconverged -n openshift-cnv \
  -o jsonpath='{.status.conditions[?(@.type=="Available")].status}{"\n"}'
# Expected: True
```

Install `virtctl`:

```bash
# Download from the cluster (always version-matched)
VIRT_DL=$(oc get consoleclidownload virtctl-clidownloads \
  -o jsonpath='{.spec.links[?(@.text=="Download virtctl for Linux for x86_64")].href}' 2>/dev/null)
curl -L -o virtctl "${VIRT_DL}"
chmod +x virtctl && sudo mv virtctl /usr/local/bin/
virtctl version
```

### Step 15 — Create workshop-virt Namespace

```bash
oc apply -f virt/namespace.yaml
oc apply -f virt/rbac.yaml
```

### Step 16 — Build and Push Kickstart Server Image

```bash
cd virt/kickstart
podman build -t quay.io/${QUAY_ORG}/kickstart-server:latest .
podman push quay.io/${QUAY_ORG}/kickstart-server:latest
cd ../..
```

### Step 17 — Deploy Kickstart Server via ArgoCD

```bash
oc apply -f virt/argocd/appproject.yaml
oc apply -f virt/argocd/applications/kickstart-server.yaml

# Wait for sync and healthy
oc get application kickstart-server -n workshop-gitops --watch
```

Verify:

```bash
oc get pods -n workshop-virt -l app=kickstart-server
oc get route kickstart-server -n workshop-virt

KS_URL=http://$(oc get route kickstart-server -n workshop-virt \
  -o jsonpath='{.spec.host}')/centos10-workshop.ks

curl -f "${KS_URL}" | head -5
# Expected: first lines of the kickstart file
```

> ⚠️ Use `http://` **not** `https://` — Anaconda cannot verify the cluster's TLS certificate.

### Step 18 — Deploy Virtual Machine via ArgoCD

```bash
oc apply -f virt/argocd/applications/centos-workshop-vm.yaml
```

Watch DataVolume import (CDI downloads the ~800 MB CentOS boot ISO):

```bash
oc get datavolumes -n workshop-virt --watch
```

Expected progression:

```
NAME                    PHASE               PROGRESS
centos-workshop-disk    Succeeded           100.0%
centos-workshop-iso     ImportInProgress    23.4%
...
centos-workshop-iso     Succeeded           100.0%
```

### Step 19 — Install the OS via Console

```bash
virtctl console centos-workshop -n workshop-virt
```

At the **CentOS Stream 10** boot menu:

1. Highlight **Install CentOS Stream 10**
2. Press **`Tab`** to edit the kernel command line
3. Append (get exact URL from Step 17 output):
   ```
   inst.ks=http://kickstart-server-workshop-virt.apps.YOUR_DOMAIN/centos10-workshop.ks
   ```
4. Press **`Enter`**

Watch the automated installation. Total time: 10–20 minutes. Exit the console with `Ctrl+]`.

### Step 20 — Switch to Post-Install Manifest

After the VM reboots into the installed OS:

```bash
cp virt/vm/virtualmachine-postinstall.yaml virt/vm/virtualmachine.yaml
git add virt/vm/virtualmachine.yaml
git commit -m "virt: post-install — boot from disk only"
git push origin main
```

ArgoCD syncs the updated spec and removes the ISO from the VM.

### Step 21 — Connect to the VM

```bash
# Preferred: virtctl SSH
virtctl ssh root@centos-workshop -n workshop-virt
# Password: workshop123!

# Alternative: NodePort
SSH_PORT=$(oc get svc centos-workshop-vm-ssh -n workshop-virt \
  -o jsonpath='{.spec.ports[0].nodePort}')
NODE_IP=$(oc get nodes \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
ssh root@${NODE_IP} -p ${SSH_PORT}
```

---

## 🔧 Troubleshooting

### PipelineRun not starting or stuck in Pending

```bash
# Describe the PipelineRun for events
oc describe pipelinerun -n workshop-ci \
  $(oc get pr -n workshop-ci \
    --sort-by=.metadata.creationTimestamp -o name | tail -1 | cut -d/ -f2)

# Check workspace PVC is Bound
oc get pvc workshop-pipeline-pvc -n workshop-ci

# Check pipeline SA has the quay secret linked
oc describe sa pipeline -n workshop-ci
```

### Buildah step fails — permission denied

```bash
# The pipeline SA needs the privileged SCC
oc adm policy add-scc-to-user privileged \
  system:serviceaccount:workshop-ci:pipeline
```

### update-helm-values fails — git push rejected

```bash
# Verify the github-token secret is correct
oc get secret github-token -n workshop-ci -o jsonpath='{.data.token}' \
  | base64 -d | cut -c1-8
# Should show: ghp_XXXX

# Ensure the PAT has 'repo' (write) scope and hasn't expired
```

### ArgoCD Application stuck OutOfSync

```bash
# Force a hard refresh
oc annotate application workshop-app-dev -n workshop-gitops \
  argocd.argoproj.io/refresh=hard

# Force sync
oc patch application workshop-app-dev -n workshop-gitops \
  --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'
```

### ArgoCD cannot reach private Git repository

```bash
ARGOCD_POD=$(oc get pod -n workshop-gitops \
  -l app.kubernetes.io/name=workshop-argocd-server \
  -o jsonpath='{.items[0].metadata.name}')

oc exec -n workshop-gitops ${ARGOCD_POD} -- \
  argocd repo add "https://github.com/${GITHUB_ORG}/${GITHUB_REPO}" \
  --username "${GITHUB_ORG}" \
  --password "ghp_YOUR_PAT" \
  --server localhost:8080 --insecure
```

### DataVolume stuck importing

```bash
# Check CDI importer pod logs
oc logs -n workshop-virt \
  $(oc get pods -n workshop-virt -l app=containerized-data-importer \
    -o jsonpath='{.items[0].metadata.name}') -f
```

### Kickstart URL not reachable from VM

```bash
# Verify plain HTTP works (not HTTPS)
curl -v http://$(oc get route kickstart-server -n workshop-virt \
  -o jsonpath='{.spec.host}')/centos10-workshop.ks 2>&1 | grep "< HTTP"
# Expected: HTTP/1.1 200 OK
```

---

## 📚 References

- [Tekton Documentation](https://tekton.dev/docs/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [OpenShift Pipelines](https://docs.openshift.com/container-platform/latest/cicd/pipelines/understanding-openshift-pipelines.html)
- [OpenShift GitOps](https://docs.openshift.com/container-platform/latest/cicd/gitops/understanding-openshift-gitops.html)
- [OpenShift Virtualization](https://docs.openshift.com/container-platform/latest/virt/about_virt/about-virt.html)
- [KubeVirt User Guide](https://kubevirt.io/user-guide/)
- [CentOS Stream 10 Mirror](https://mirror.stream.centos.org/10-stream/)
- [Hugo Documentation](https://gohugo.io/documentation/)
- [Kickstart Syntax Reference](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/performing_an_advanced_rhel_9_installation/kickstart-commands-and-options-reference_installing-rhel-as-an-experienced-user)
