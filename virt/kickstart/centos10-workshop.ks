# =============================================================================
# CentOS Stream 10 — Automated Kickstart Installation
# Served via HTTP from the kickstart-server container in workshop-virt namespace
# Used by: OpenShift Virtualization VM network boot (PXE → Anaconda → kickstart)
#
# Installation source: CentOS Stream 10 mirror
# Network: DHCP (assigned by OpenShift pod network / bridge)
# Disk layout: Single disk, simple partitioning (no LVM for workshop simplicity)
# =============================================================================

# ── Installation method ───────────────────────────────────────────────────
# Use network installation from the official CentOS Stream 10 mirror
url --url="https://mirror.stream.centos.org/10-stream/BaseOS/x86_64/os/"

# Additional repositories
repo --name="AppStream" --baseurl="https://mirror.stream.centos.org/10-stream/AppStream/x86_64/os/"
repo --name="extras-common" --baseurl="https://mirror.stream.centos.org/SIGs/10-stream/extras/x86_64/extras-common/"

# ── Installation mode ─────────────────────────────────────────────────────
text
skipx
reboot

# ── Locale & keyboard ─────────────────────────────────────────────────────
lang en_US.UTF-8
keyboard --vckeymap=us --xlayouts='us'
timezone UTC --utc

# ── Network ───────────────────────────────────────────────────────────────
# DHCP on first active interface — KubeVirt VM gets IP from the pod network
# or bridge network depending on the NAD configuration
network --bootproto=dhcp --device=link --activate --onboot=on --hostname=centos-workshop

# ── Security ──────────────────────────────────────────────────────────────
selinux --enforcing
firewall --enabled --service=ssh

# ── Root password ─────────────────────────────────────────────────────────
# Password: <to-be-defined>
# Generated with: python3 -c "import crypt; print(crypt.crypt('<to-be-defined>', crypt.mksalt(crypt.METHOD_SHA512)))"
# Replace with your own hash in production!
rootpw --iscrypted <to-be-added-here>

# ── System services ───────────────────────────────────────────────────────
services --enabled=sshd,chronyd
services --disabled=kdump

# ── Kdump ─────────────────────────────────────────────────────────────────
%addon com_redhat_kdump --disable
%end

# ── Disk configuration ────────────────────────────────────────────────────
# Target the first VirtIO disk (/dev/vda) which is the blank DataVolume
# For virtio disks, the device will appear as /dev/vda inside the VM
ignoredisk --only-use=vda

# Clear the master boot record and all existing partitions
zerombr
clearpart --all --initlabel --drives=vda

# Bootloader
bootloader --append="console=tty0 console=ttyS0,115200n8 net.ifnames=0 biosdevname=0" \
           --location=mbr \
           --boot-drive=vda

# ── Partition layout ──────────────────────────────────────────────────────
# Simple flat layout — no LVM — keeps things easy to reason about in a workshop
#
# /boot   — 1 GiB  ext4
# /       — grows to fill remaining space  xfs
# swap    — 2 GiB
#
part /boot --fstype=xfs  --size=1024  --ondisk=vda
part swap  --fstype=swap --size=2048  --ondisk=vda
part /     --fstype=xfs  --size=1     --grow  --ondisk=vda

# ── Package selection ─────────────────────────────────────────────────────
%packages --ignoremissing
@^minimal-environment
@core
chrony
curl
wget
git
vim-minimal
bash-completion
openssh-server
openssh-clients
cockpit
cockpit-system
python3
python3-pip
# Cloud tools useful for a workshop VM
cloud-utils-growpart
# Remove unnecessary packages
-iwl*firmware
-fprintd
-fprintd-pam
-intltool
%end

# ── Post-install configuration ────────────────────────────────────────────
%post --log=/root/ks-post.log

echo "=== Workshop VM Post-Installation ==="

# ── SSH hardening
sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

# ── Set up root .ssh directory (add your public key here for key-based auth)
mkdir -p /root/.ssh
chmod 700 /root/.ssh
# Uncomment and add your key:
# echo "ssh-ed25519 AAAA... your-key" >> /root/.ssh/authorized_keys
# chmod 600 /root/.ssh/authorized_keys

# ── Workshop banner
cat > /etc/motd << 'MOTDBANNER'

  ██████╗ ███████╗███╗   ██╗████████╗ ██████╗ ███████╗
 ██╔════╝ ██╔════╝████╗  ██║╚══██╔══╝██╔═══██╗██╔════╝
 ██║      █████╗  ██╔██╗ ██║   ██║   ██║   ██║███████╗
 ██║      ██╔══╝  ██║╚██╗██║   ██║   ██║   ██║╚════██║
 ╚██████╗ ███████╗██║ ╚████║   ██║   ╚██████╔╝███████║
  ╚═════╝ ╚══════╝╚═╝  ╚═══╝   ╚═╝    ╚═════╝ ╚══════╝

  OpenShift Virtualization Workshop VM
  CentOS Stream 10 — Installed via Kickstart over HTTP
  Managed by ArgoCD (OpenShift GitOps)

MOTDBANNER

# ── Hostname from DHCP (will be set by NetworkManager)
echo "centos-workshop" > /etc/hostname

# ── Enable cockpit for web console access
systemctl enable cockpit.socket

# ── Disable IPv6 if not needed (simplifies workshop networking)
# echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.d/99-workshop.conf

# ── Set timezone
timedatectl set-timezone UTC 2>/dev/null || true

echo "=== Post-installation complete ==="
%end
