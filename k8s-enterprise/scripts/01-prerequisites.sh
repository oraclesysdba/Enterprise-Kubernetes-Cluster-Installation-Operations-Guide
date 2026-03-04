#!/bin/bash
###############################################################################
# Enterprise Kubernetes - Prerequisites Setup
# Run on ALL nodes (master + workers)
# Tested on Ubuntu 22.04 / 24.04 LTS
###############################################################################
set -euo pipefail

MASTER_IP="192.168.56.103"
WORKER1_IP="192.168.56.104"

echo "=============================================="
echo "  K8s Enterprise - Prerequisites Setup"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================="

# ─── 1. System Update ──────────────────────────────────────────────────────
echo "[1/8] Updating system packages..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq

# ─── 2. Install Required Packages ──────────────────────────────────────────
echo "[2/8] Installing required dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    socat \
    conntrack \
    ipset \
    jq \
    bash-completion \
    net-tools \
    wget \
    nfs-common \
    open-iscsi \
    chrony

# ─── 3. Time Synchronization (Critical for K8s certs & tokens) ────────────
echo "[3/8] Configuring time synchronization..."
sudo systemctl enable chrony
sudo systemctl start chrony
# Force immediate sync
sudo chronyc makestep > /dev/null 2>&1 || true
sudo timedatectl set-ntp true 2>/dev/null || true
echo "  ✓ Time synchronized: $(date '+%Y-%m-%d %H:%M:%S %Z')"

# ─── 4. Disable Swap (Required by Kubernetes) ─────────────────────────────
echo "[4/8] Disabling swap..."
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
# Verify swap is off
if [ "$(swapon --show | wc -l)" -gt 0 ]; then
    echo "ERROR: Swap is still enabled!"
    exit 1
fi
echo "  ✓ Swap disabled successfully"

# ─── 5. Load Required Kernel Modules ──────────────────────────────────────
echo "[5/8] Loading kernel modules..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf > /dev/null
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Verify modules
if lsmod | grep -q overlay && lsmod | grep -q br_netfilter; then
    echo "  ✓ Kernel modules loaded successfully"
else
    echo "ERROR: Failed to load kernel modules!"
    exit 1
fi

# ─── 6. Configure Sysctl Parameters ──────────────────────────────────────
echo "[6/8] Configuring sysctl parameters for Kubernetes..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf > /dev/null
# Kubernetes required sysctl params
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1

# Performance tuning for enterprise workloads
net.core.somaxconn                  = 32768
net.ipv4.tcp_max_syn_backlog        = 32768
net.core.netdev_max_backlog         = 5000
net.ipv4.tcp_keepalive_time         = 600
net.ipv4.tcp_keepalive_intvl        = 30
net.ipv4.tcp_keepalive_probes       = 10
vm.max_map_count                    = 262144
fs.inotify.max_user_watches         = 524288
fs.inotify.max_user_instances       = 512
EOF

sudo sysctl --system > /dev/null 2>&1
echo "  ✓ Sysctl parameters configured"

# ─── 7. Configure /etc/hosts ──────────────────────────────────────────────
echo "[7/8] Configuring /etc/hosts..."
# Remove any existing k8s entries
sudo sed -i '/k8s-master/d' /etc/hosts
sudo sed -i '/k8s-worker1/d' /etc/hosts

# Add cluster host entries
cat <<EOF | sudo tee -a /etc/hosts > /dev/null

# Kubernetes Cluster Nodes
${MASTER_IP}  k8s-master
${WORKER1_IP} k8s-worker1
EOF
echo "  ✓ /etc/hosts configured"

# ─── 8. Configure Firewall (if UFW is active) ─────────────────────────────
echo "[8/8] Configuring firewall rules..."
if command -v ufw &> /dev/null && sudo ufw status | grep -q "active"; then
    echo "  UFW is active, adding Kubernetes rules..."
    # Control Plane ports
    sudo ufw allow 6443/tcp comment "K8s API Server"
    sudo ufw allow 2379:2380/tcp comment "etcd"
    sudo ufw allow 10250/tcp comment "Kubelet API"
    sudo ufw allow 10259/tcp comment "kube-scheduler"
    sudo ufw allow 10257/tcp comment "kube-controller-manager"
    # Worker Node ports
    sudo ufw allow 30000:32767/tcp comment "NodePort Services"
    # Calico ports
    sudo ufw allow 179/tcp comment "Calico BGP"
    sudo ufw allow 4789/udp comment "Calico VXLAN"
    sudo ufw allow 5473/tcp comment "Calico Typha"
    sudo ufw reload
    echo "  ✓ Firewall rules configured"
else
    echo "  ✓ UFW not active, skipping firewall configuration"
fi

# ─── 8. Disable AppArmor for containerd (optional, helps avoid issues) ────
echo "[OPTIONAL] Ensuring AppArmor won't interfere..."
if command -v apparmor_parser &> /dev/null; then
    echo "  AppArmor present but leaving default — no changes needed"
fi

echo ""
echo "=============================================="
echo "  ✓ Prerequisites setup completed successfully"
echo "=============================================="
echo ""
