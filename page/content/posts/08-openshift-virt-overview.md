---
title: "08 · OpenShift Virtualization Overview"
description: "Introduction to OpenShift Virtualization (KubeVirt): concepts, architecture, and how VMs become first-class Kubernetes citizens."
date: 2024-01-08
weight: 8
tags: ["virtualization", "kubevirt", "openshift-virt"]
---

## What Is OpenShift Virtualization?

**OpenShift Virtualization** (based on the upstream [KubeVirt](https://kubevirt.io/) project) extends OpenShift so that **Virtual Machines are first-class Kubernetes resources** — managed the same way as Pods, Deployments, and Services.

Under the hood, each VM runs inside a Pod via a `virt-launcher` container that starts QEMU/KVM on the host. This gives you:

- Near-bare-metal VM performance via KVM hardware acceleration
- Kubernetes scheduling, networking, and storage for VMs
- GitOps (ArgoCD), CI/CD (Tekton), and observability applied to VMs
- Live migration between nodes (maintenance without downtime)
- A clear path to consolidate legacy VM workloads onto OpenShift

---

## Key CRDs Introduced by KubeVirt

| CRD | Group | Description |
|-----|-------|-------------|
| `VirtualMachine` | `kubevirt.io` | Persistent VM spec (like a Deployment — desired state) |
| `VirtualMachineInstance` | `kubevirt.io` | Running VM instance (like a Pod — ephemeral) |
| `DataVolume` | `cdi.kubevirt.io` | Automates PVC creation + disk image import |
| `NetworkAttachmentDefinition` | `k8s.cni.cncf.io` | Defines secondary networks (Multus) |

---

## Architecture

```
oc apply -f virtualmachine.yaml
          │
          ▼
   virt-controller (watches VirtualMachine CRDs)
          │
          │  creates
          ▼
   virt-launcher Pod (per VMI)
          │
          │  starts
          ▼
   QEMU/KVM process
          │
          │  backed by
          ├──▶ DataVolume → PVC → Storage (Ceph/ODF etc.)
          └──▶ Pod network / Multus bridge → VMs NIC
```

### Containerized Data Importer (CDI)

CDI is the component that handles disk import. When you create a `DataVolume` with a `source.http.url`, CDI:

1. Creates a PVC of the requested size
2. Spins up an importer Pod that downloads the image (ISO, QCOW2, RAW)
3. Writes it into the PVC
4. Marks the DataVolume as `Succeeded`
5. KubeVirt then starts the VM using that PVC as the disk

---

## Our Workshop Goal

In this module we will:

1. **Build and deploy a kickstart HTTP server** — serves the CentOS Stream 10 unattended install config over plain HTTP
2. **Create a Virtual Machine** using OpenShift Virtualization that boots from the CentOS Stream 10 installer ISO
3. **Pass the kickstart URL** to Anaconda so the OS installs unattended
4. **Manage everything with ArgoCD** — the kickstart server, the VM definition, and the post-install state all live in Git

This demonstrates that infrastructure (VMs) can be managed with the same GitOps tools as applications.

---

## Prerequisites for This Module

- Modules 01–07 complete (ArgoCD is configured)
- OpenShift Virtualization operator installed and `HyperConverged` CR is `Available`

Verify:

```bash
# Check HyperConverged CR status
oc get hyperconverged kubevirt-hyperconverged \
  -n openshift-cnv \
  -o jsonpath='{.status.conditions[?(@.type=="Available")].status}{"\n"}'
# Expected: True

# Check virt-* pods are running
oc get pods -n openshift-cnv | grep -E "virt-(controller|api|handler|operator)"

# Check CDI is ready
oc get cdi cdi -o jsonpath='{.status.phase}{"\n"}'
# Expected: Deployed
```

---

## Required Tool: virtctl

`virtctl` is the KubeVirt CLI companion to `oc`. Install it:

```bash
# Get the version matching your cluster
VIRT_VERSION=$(oc get csv -n openshift-cnv \
  -o jsonpath='{.items[0].spec.version}')

# Download from the cluster itself (always version-matched)
oc get consoleclidownloads virtctl-clidownloads \
  -o jsonpath='{.spec.links[0].href}'

# Or download directly
curl -L -o virtctl \
  "https://github.com/kubevirt/kubevirt/releases/download/v${VIRT_VERSION}/virtctl-v${VIRT_VERSION}-linux-amd64"
chmod +x virtctl
sudo mv virtctl /usr/local/bin/
```

Verify:

```bash
virtctl version
```

---

## Storage Considerations

The VM needs a **`StorageClass` that supports `ReadWriteOnce`**. On ODF/Ceph clusters the default virtualization storage class is `ocs-storagecluster-ceph-rbd-virtualization`. On other clusters check:

```bash
oc get storageclass
```

The DataVolumes in this workshop request `ReadWriteOnce`. If your cluster requires a specific StorageClass, update `virt/vm/virtualmachine.yaml` to add `storageClassName: <your-class>` in the DataVolume storage spec.

Continue to **[Module 09 → Kickstart Server](/posts/09-kickstart-server/)**.
