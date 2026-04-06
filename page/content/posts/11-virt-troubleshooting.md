---
title: "11 · Virtualization Troubleshooting & Verification"
description: "Complete verification checklist for the OpenShift Virtualization module, plus common issues and how to fix them."
date: 2024-01-11
weight: 11
tags: ["troubleshooting", "kubevirt", "debug", "verification"]
---

## Full Verification Checklist

Run through this after completing Module 10 to confirm every layer is working correctly.

---

### ✅ Operator Health

```bash
# HyperConverged is Available
oc get hyperconverged kubevirt-hyperconverged -n openshift-cnv \
  -o jsonpath='{.status.conditions[?(@.type=="Available")].status}{"\n"}'
# Expected: True

# All virt-* pods running
oc get pods -n openshift-cnv \
  -l app.kubernetes.io/part-of=hyperconverged-cluster \
  --field-selector=status.phase!=Running

# CDI deployed
oc get cdi cdi -o jsonpath='{.status.phase}{"\n"}'
# Expected: Deployed
```

---

### ✅ Kickstart Server

```bash
# Pod is Running
oc get pods -n workshop-virt -l app=kickstart-server

# Route exists
oc get route kickstart-server -n workshop-virt

# HTTP access works (use http:// not https://)
KS_URL=http://$(oc get route kickstart-server -n workshop-virt \
  -o jsonpath='{.spec.host}')/centos10-workshop.ks

curl -sf "$KS_URL" | head -5
# Expected: first lines of the kickstart file

# Verify plain HTTP (no redirect to HTTPS)
curl -v "$KS_URL" 2>&1 | grep "< HTTP"
# Expected: HTTP/1.1 200 OK
```

---

### ✅ DataVolumes

```bash
# Both DataVolumes are Succeeded
oc get datavolumes -n workshop-virt

# Expected:
# NAME                    PHASE       PROGRESS
# centos-workshop-disk    Succeeded   100.0%
# centos-workshop-iso     Succeeded   100.0%

# Check underlying PVCs
oc get pvc -n workshop-virt
```

---

### ✅ VirtualMachine State

```bash
# VM exists and is Running
oc get vm centos-workshop -n workshop-virt

# VMI exists (= VM is powered on)
oc get vmi centos-workshop -n workshop-virt

# Full VMI status
oc describe vmi centos-workshop -n workshop-virt | tail -30

# VM is Ready
oc get vmi centos-workshop -n workshop-virt \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}{"\n"}'
# Expected: True (after OS install + first boot)
```

---

### ✅ VM Networking

```bash
# VM has an IP address
oc get vmi centos-workshop -n workshop-virt \
  -o jsonpath='{.status.interfaces[0].ipAddress}{"\n"}'

# SSH NodePort service
oc get svc centos-workshop-vm-ssh -n workshop-virt

# Connect via virtctl
virtctl ssh root@centos-workshop -n workshop-virt
# Password: workshop123!
```

---

### ✅ ArgoCD GitOps

```bash
# Both ArgoCD apps are Synced + Healthy
oc get application -n workshop-gitops \
  -l app.kubernetes.io/part-of=workshop-virt

# Expected:
# NAME                   SYNC STATUS   HEALTH STATUS
# kickstart-server       Synced        Healthy
# centos-workshop-vm     Synced        Healthy
```

---

## Common Issues

### DataVolume stuck in `ImportInProgress` for too long

```bash
# Check the CDI importer pod logs
oc logs -n workshop-virt \
  $(oc get pods -n workshop-virt -l app=containerized-data-importer \
    -o jsonpath='{.items[0].metadata.name}') -f
```

Common causes:
- **Slow mirror**: The CentOS Stream 10 ISO is ~800 MB. On slow connections this takes 15–30 min. Be patient.
- **DNS resolution failure**: Check node DNS config.
- **Proxy required**: Set `HTTP_PROXY` / `HTTPS_PROXY` in the CDI config:
  ```bash
  oc edit configmap cdi-proxy-config -n openshift-cnv
  ```
- **Storage not provisioning**: Check `oc get pvc -n workshop-virt`.

---

### VM console shows blank / no output

```bash
# Ensure serial console is enabled in the VM spec
oc get vm centos-workshop -n workshop-virt \
  -o jsonpath='{.spec.template.spec.domain.devices.autoattachSerialConsole}'
# Expected: true

# Check virt-launcher pod logs
oc logs -n workshop-virt \
  $(oc get pods -n workshop-virt -l kubevirt.io/domain=centos-workshop \
    -o jsonpath='{.items[0].metadata.name}') -c compute
```

---

### Anaconda cannot reach the kickstart URL

Inside the Anaconda installer (at the `dracut` / early boot stage):

```bash
# At the Anaconda shell (Ctrl+Alt+F2), test connectivity:
curl -v http://kickstart-server-workshop-virt.apps.YOUR_DOMAIN/centos10-workshop.ks
```

Common causes:
- **Using `https://` instead of `http://`**: Always use plain HTTP for the kickstart URL. OpenShift Routes with `insecureEdgeTerminationPolicy: Allow` serve both but the VM installer should use HTTP.
- **DNS not resolving**: The VM's pod network should resolve `*.apps.*` routes. If not, use the Service's ClusterIP instead (requires the VM to be on the pod network which it is with masquerade).
- **Route not ready**: Check `oc get route kickstart-server -n workshop-virt`.

---

### Kickstart fails at package installation (`url` command error)

The kickstart uses `https://mirror.stream.centos.org` as the install source. If the cluster nodes cannot reach the internet:

```bash
# Option 1: Use a local/internal mirror
# Edit virt/kickstart/centos10-workshop.ks and change:
# url --url="https://your-internal-mirror/centos/10-stream/BaseOS/x86_64/os/"

# Option 2: Attach a full DVD ISO DataVolume and use:
# cdrom
# (remove the url and repo lines from the kickstart)
```

---

### VM won't start after post-install manifest applied

```bash
# Check VM events
oc describe vm centos-workshop -n workshop-virt | grep -A 10 Events

# Check virt-launcher pod
oc get pods -n workshop-virt -l kubevirt.io/domain=centos-workshop
oc logs -n workshop-virt \
  -l kubevirt.io/domain=centos-workshop -c compute --tail=50
```

Common causes:
- DataVolume `centos-workshop-iso` is still referenced but manifest changed — ensure the ISO DataVolume and its PVC still exist (ArgoCD `prune: true` will delete them if the `dataVolumeTemplates` entry is removed).
  ```bash
  # If accidentally pruned, re-create the iso DV only
  oc apply -f virt/vm/virtualmachine.yaml  # re-apply original to recreate
  ```
- VM is locked in a bad state: `virtctl stop centos-workshop -n workshop-virt` then `virtctl start centos-workshop -n workshop-virt`.

---

### ArgoCD shows VM as `OutOfSync` after stopping the VM

This is expected if `selfHeal: false`. The VM's `runStrategy` may drift from Git. Options:

```bash
# Option A: Accept the drift — disable selfHeal (already done)
# Option B: Add ignoreDifferences for runStrategy (already in the Application)

# Option C: Force Git to be truth (re-syncs and starts VM)
oc patch application centos-workshop-vm -n workshop-gitops \
  --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'
```

---

## Useful virtctl Commands

```bash
# Start / stop / restart VM
virtctl start  centos-workshop -n workshop-virt
virtctl stop   centos-workshop -n workshop-virt
virtctl restart centos-workshop -n workshop-virt

# Open serial console
virtctl console centos-workshop -n workshop-virt
# Exit with: Ctrl+]

# SSH into VM
virtctl ssh root@centos-workshop -n workshop-virt

# Expose VM port via NodePort (alternative to Service manifest)
virtctl expose vmi centos-workshop \
  --name=centos-ssh \
  --port=22 \
  --type=NodePort \
  -n workshop-virt

# Live migrate VM to another node (requires RWX storage or live-migration support)
virtctl migrate centos-workshop -n workshop-virt

# Get VM guest OS info
virtctl guestosinfo centos-workshop -n workshop-virt
```

---

## Summary

You have completed the OpenShift Virtualization module of this workshop:

| Component | Status |
|-----------|--------|
| Kickstart file | ✅ Built and served over HTTP |
| Kickstart container | ✅ Deployed via ArgoCD |
| CentOS Stream 10 ISO | ✅ Imported via CDI DataVolume |
| VirtualMachine | ✅ Provisioned via ArgoCD + GitOps |
| OS installation | ✅ Automated via Anaconda + Kickstart |
| SSH access | ✅ Via virtctl or NodePort |
| GitOps management | ✅ VM spec lives in Git, applied by ArgoCD |

The same principles apply at scale: define your VM fleet in Git, let ArgoCD enforce the desired state, and use Tekton to automate image builds for VM base images (e.g. QCOW2 golden images baked with Packer).
