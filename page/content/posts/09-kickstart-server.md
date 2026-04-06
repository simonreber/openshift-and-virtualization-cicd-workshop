---
title: "09 · Kickstart Server"
description: "Build the CentOS Stream 10 kickstart file, package it into a container image, and deploy it as an HTTP server on OpenShift via ArgoCD."
date: 2024-01-09
weight: 9
tags: ["kickstart", "anaconda", "centos", "httpd"]
---

## What Is a Kickstart File?

A **Kickstart file** is a plain-text answer file for Red Hat's Anaconda installer. Instead of clicking through installation screens, Anaconda reads the kickstart file and performs a fully automated, unattended installation.

Our kickstart (`virt/kickstart/centos10-workshop.ks`) configures:

- **Installation source**: CentOS Stream 10 mirror over HTTPS
- **Network**: DHCP on the first active interface
- **Disk**: `/dev/vda` — simple flat layout (no LVM)
  - `/boot` — 1 GiB XFS
  - `swap` — 2 GiB
  - `/`    — remainder XFS (grows to fill disk)
- **Packages**: Minimal environment + SSH + Cockpit + useful tools
- **Post-install**: SSH enabled, root login allowed, workshop MOTD

---

## Step 1 — Review the Kickstart File

```bash
cat virt/kickstart/centos10-workshop.ks
```

Key sections to notice:

```bash
# Installation source — CentOS Stream 10 BaseOS mirror
url --url="https://mirror.stream.centos.org/10-stream/BaseOS/x86_64/os/"

# DHCP network
network --bootproto=dhcp --device=link --activate --onboot=on

# Target disk — /dev/vda (VirtIO disk inside the VM)
ignoredisk --only-use=vda
clearpart --all --initlabel --drives=vda

# Simple flat partitioning
part /boot --fstype=xfs  --size=1024  --ondisk=vda
part swap  --fstype=swap --size=2048  --ondisk=vda
part /     --fstype=xfs  --size=1     --grow  --ondisk=vda
```

> 💡 The root password in the kickstart (`workshop123!`) is for the workshop only. Change it before using in any real environment. The encrypted hash is pre-computed — to generate your own:
> ```bash
> python3 -c "import crypt; print(crypt.crypt('yourpassword', crypt.mksalt(crypt.METHOD_SHA512)))"
> ```

---

## Step 2 — Create the workshop-virt Namespace

```bash
oc apply -f virt/namespace.yaml
oc apply -f virt/rbac.yaml
```

Add the Quay pull secret to `workshop-virt`:

```bash
oc create secret docker-registry quay-credentials \
  --docker-server=quay.io \
  --docker-username="${QUAY_ORG}+workshop_push" \
  --docker-password="YOUR_ROBOT_TOKEN" \
  -n workshop-virt

oc secrets link default quay-credentials --for=pull -n workshop-virt
```

---

## Step 3 — Build the Kickstart Server Image

The kickstart file is embedded directly into a container image based on `quay.io/hummingbird/httpd`. This means the file is always available as long as the container is running — no external file shares needed.

```bash
cd virt/kickstart

# Build the image (using Buildah or Docker)
podman build -t quay.io/${QUAY_ORG}/kickstart-server:latest .

# Push to Quay
podman push quay.io/${QUAY_ORG}/kickstart-server:latest
```

Or trigger it via a Tekton task (reuse the `buildah-build-push` task from the CI module):

```bash
oc create -f - <<EOF
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  generateName: build-kickstart-server-
  namespace: workshop-ci
spec:
  taskRef:
    kind: Task
    name: buildah-build-push
  params:
    - name: IMAGE
      value: quay.io/${QUAY_ORG}/kickstart-server:latest
    - name: DOCKERFILE
      value: virt/kickstart/Dockerfile
    - name: CONTEXT
      value: virt/kickstart
  workspaces:
    - name: source
      persistentVolumeClaim:
        claimName: workshop-pipeline-pvc
    - name: dockerconfig
      secret:
        secretName: quay-credentials
EOF

oc get taskruns -n workshop-ci --watch
```

---

## Step 4 — Update the Kickstart Server Manifest

Substitute your Quay org in `virt/kickstart-server.yaml`:

```bash
sed -i "s|YOUR_QUAY_ORG|${QUAY_ORG}|g" virt/kickstart-server.yaml

git add virt/kickstart-server.yaml
git commit -m "chore: set quay org for kickstart server image"
git push origin main
```

---

## Step 5 — Deploy via ArgoCD

Apply the ArgoCD AppProject and Application for the kickstart server:

```bash
# Update placeholders
sed -e "s|YOUR_GITHUB_ORG|${GITHUB_ORG}|g" \
    -e "s|YOUR_GITHUB_REPO|${GITHUB_REPO}|g" \
    virt/argocd/appproject.yaml | oc apply -f -

sed -e "s|YOUR_GITHUB_ORG|${GITHUB_ORG}|g" \
    -e "s|YOUR_GITHUB_REPO|${GITHUB_REPO}|g" \
    virt/argocd/applications/kickstart-server.yaml | oc apply -f -
```

Watch ArgoCD sync:

```bash
oc get application kickstart-server -n workshop-gitops --watch
```

Verify the deployment is running:

```bash
oc get pods -n workshop-virt
oc get route kickstart-server -n workshop-virt
```

---

## Step 6 — Verify the Kickstart File is Reachable

```bash
# Get the kickstart server URL
KS_URL=$(oc get route kickstart-server -n workshop-virt \
  -o jsonpath='http://{.spec.host}/centos10-workshop.ks')

echo "Kickstart URL: $KS_URL"

# Test plain HTTP access (what the VM installer will use)
curl -f "$KS_URL" | head -20
```

Expected output: the first lines of the kickstart file.

```
# =============================================================================
# CentOS Stream 10 — Automated Kickstart Installation
...
```

> ⚠️ **Always use the `http://` URL** when passing to Anaconda. The `https://` URL requires TLS verification which may fail inside the Anaconda installer if the OpenShift cluster's CA is not trusted.

---

## Step 7 — Update the ConfigMap with the Real URL

Now that you have the real kickstart URL, update the ConfigMap:

```bash
CLUSTER_DOMAIN=$(oc get ingress.config.openshift.io cluster \
  -o jsonpath='{.spec.domain}')

KS_HOST="kickstart-server-workshop-virt.${CLUSTER_DOMAIN}"

sed -i "s|YOUR_CLUSTER_DOMAIN|${CLUSTER_DOMAIN}|g" \
  virt/vm/kickstart-configmap.yaml

git add virt/vm/kickstart-configmap.yaml
git commit -m "chore: set kickstart URL for cluster ${CLUSTER_DOMAIN}"
git push origin main
```

---

## Summary

- ✅ Kickstart file written for CentOS Stream 10 with DHCP + simple disk layout
- ✅ Kickstart server image built and pushed to Quay
- ✅ Kickstart server deployed to `workshop-virt` via ArgoCD
- ✅ Kickstart file reachable via plain HTTP Route
- ✅ ConfigMap updated with the real URL

Continue to **[Module 10 → Virtual Machine Provisioning](/posts/10-virtual-machine/)**.
