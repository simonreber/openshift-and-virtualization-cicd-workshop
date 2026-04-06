---
title: "10 · Virtual Machine Provisioning"
description: "Deploy a CentOS Stream 10 Virtual Machine on OpenShift Virtualization using ArgoCD. Boot from ISO, install via kickstart, verify the running VM."
date: 2024-01-10
weight: 10
tags: ["virtualmachine", "kubevirt", "argocd", "centos", "datavolume"]
---

## What We're Doing

We will create a `VirtualMachine` resource in Git and let ArgoCD sync it to the cluster. OpenShift Virtualization will:

1. Trigger CDI to download the CentOS Stream 10 boot ISO into a DataVolume (PVC)
2. Create a blank 20 GiB DataVolume for the OS installation target
3. Start the VM — it boots from the ISO
4. We pass the kickstart URL at the boot prompt
5. Anaconda installs CentOS unattended to `/dev/vda`
6. VM reboots into the installed OS
7. We apply the post-install manifest (removes CDROM, disk-only boot)

---

## Step 1 — Apply the VM ArgoCD Application

```bash
# Update placeholders
sed -e "s|YOUR_GITHUB_ORG|${GITHUB_ORG}|g" \
    -e "s|YOUR_GITHUB_REPO|${GITHUB_REPO}|g" \
    virt/argocd/applications/centos-workshop-vm.yaml | oc apply -f -
```

ArgoCD will now sync the contents of `virt/vm/` to `workshop-virt`.

```bash
oc get application centos-workshop-vm -n workshop-gitops --watch
```

---

## Step 2 — Watch DataVolume Import Progress

CDI starts downloading the CentOS Stream 10 boot ISO immediately. This can take several minutes depending on your cluster's internet connection.

```bash
# Watch both DataVolumes
oc get datavolumes -n workshop-virt --watch
```

Expected progression:

```
NAME                    PHASE       PROGRESS   RESTARTS   AGE
centos-workshop-disk    Succeeded   100.0%     0          2m
centos-workshop-iso     ImportInProgress  45.2%   0       3m
...
centos-workshop-iso     Succeeded   100.0%     0          8m
```

You can also watch the CDI importer pod:

```bash
oc get pods -n workshop-virt | grep importer
oc logs -n workshop-virt -l app=containerized-data-importer -f
```

---

## Step 3 — Verify the VM is Created

Once both DataVolumes are `Succeeded`, the VM starts automatically:

```bash
oc get vm -n workshop-virt
oc get vmi -n workshop-virt   # VirtualMachineInstance = running VM
```

```
NAME               AGE   STATUS    READY
centos-workshop    5m    Running   False
```

`READY: False` is expected — the OS is not installed yet.

---

## Step 4 — Open the VM Console

```bash
virtctl console centos-workshop -n workshop-virt
```

You should see the CentOS Stream 10 Anaconda boot menu.

> 💡 If the console shows a blank screen, press **Enter** to activate it. The serial console (`ttyS0`) is used.

---

## Step 5 — Pass the Kickstart URL to Anaconda

At the **CentOS Stream 10** boot menu:

**BIOS (q35 machine — our setup):**

1. Highlight **"Install CentOS Stream 10"**
2. Press **`Tab`** to edit the kernel command line
3. At the `boot:` prompt you will see existing args. Append a space then:
   ```
   inst.ks=http://kickstart-server-workshop-virt.apps.YOUR_CLUSTER_DOMAIN/centos10-workshop.ks
   ```
   Get the exact URL:
   ```bash
   oc get configmap centos-workshop-kickstart-args \
     -n workshop-virt \
     -o jsonpath='{.data.kickstart-url}'
   ```
4. Press **`Enter`**

Anaconda will start, print:

```
* Fetching kickstart from http://...
* Running pre-installation scripts
* Starting installation
```

---

## Step 6 — Watch the Installation

Keep the console open and watch Anaconda work through the kickstart:

```bash
# Keep the virtctl console open
virtctl console centos-workshop -n workshop-virt
```

You will see output like:

```
Starting installation process
Configuring storage...
  Creating xfs filesystem on /dev/vda3 for /
  Creating xfs filesystem on /dev/vda1 for /boot
Installing bootloader...
Package installation:
  Installing: kernel
  Installing: bash
  ...
Running post-installation scripts
Installation complete. Rebooting.
```

Total time: approximately **10–20 minutes** depending on mirror speed.

---

## Step 7 — Verify Successful Boot (First Login)

After reboot, the console will show the CentOS login prompt:

```
centos-workshop login:
```

Log in:

```
Username: root
Password: workshop123!
```

You should see the workshop MOTD banner, then verify:

```bash
# Inside the VM
hostname
cat /etc/os-release | grep PRETTY_NAME
lsblk
ip addr
systemctl status sshd
```

Expected:

```
centos-workshop
PRETTY_NAME="CentOS Stream 10"
NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
vda    252:0    0   20G  0 disk
├─vda1 252:1    0    1G  0 part /boot
├─vda2 252:2    0    2G  0 part [SWAP]
└─vda3 252:3    0   17G  0 part /
```

---

## Step 8 — Apply the Post-Install Manifest

The installation is complete. Now commit the post-install manifest to Git so ArgoCD manages the VM without the CDROM:

```bash
# Replace the main VM manifest with the post-install version
cp virt/vm/virtualmachine-postinstall.yaml virt/vm/virtualmachine.yaml

# Stage and commit
git add virt/vm/virtualmachine.yaml
git commit -m "virt: switch centos-workshop to post-install (disk-only boot)"
git push origin main
```

ArgoCD detects the change and applies the updated `VirtualMachine` spec. The VM will restart (if `runStrategy: RerunOnFailure` re-triggers it) and boot from the disk.

Watch ArgoCD sync:

```bash
oc get application centos-workshop-vm -n workshop-gitops
oc get vm -n workshop-virt --watch
```

---

## Step 9 — Access the VM via SSH

```bash
# Get the NodePort for SSH
SSH_PORT=$(oc get svc centos-workshop-vm-ssh -n workshop-virt \
  -o jsonpath='{.spec.ports[0].nodePort}')

# Get a node IP
NODE_IP=$(oc get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

ssh root@${NODE_IP} -p ${SSH_PORT}
# Password: workshop123!
```

Or use `virtctl` (preferred — no NodePort needed):

```bash
virtctl ssh root@centos-workshop -n workshop-virt
```

---

## Step 10 — Verify GitOps is Managing the VM

Make a change in Git to prove ArgoCD controls the VM:

```bash
# Change the VM to have 6 GiB RAM (edit virt/vm/virtualmachine.yaml)
sed -i 's/guest: 4Gi/guest: 6Gi/' virt/vm/virtualmachine.yaml
git add virt/vm/virtualmachine.yaml
git commit -m "virt: increase centos-workshop RAM to 6 GiB"
git push origin main
```

Watch ArgoCD sync the change:

```bash
oc get application centos-workshop-vm -n workshop-gitops --watch
```

After sync, verify inside the VM:

```bash
virtctl ssh root@centos-workshop -n workshop-virt
# Inside VM:
free -h
```

---

## Summary

- ✅ VirtualMachine deployed to `workshop-virt` via ArgoCD
- ✅ CDI downloaded the CentOS Stream 10 boot ISO automatically
- ✅ Anaconda fetched and applied the kickstart file over HTTP
- ✅ CentOS Stream 10 installed unattended to a blank DataVolume
- ✅ VM boots from disk after install (CDROM removed via Git commit)
- ✅ VM is SSH-accessible and managed by ArgoCD

Continue to **[Module 11 → Troubleshooting Virtualization](/posts/11-virt-troubleshooting/)**.
