#!/bin/bash
###############################################################################
# Enterprise Kubernetes - Worker Node Join
# Run ONLY on worker nodes
# This script is a wrapper — the actual join command is retrieved from master
###############################################################################
set -euo pipefail

MASTER_IP="192.168.56.103"
MASTER_USER="k8s"

echo "=============================================="
echo "  K8s Enterprise - Worker Node Join"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================="

# The join command will be provided as argument or fetched
if [ $# -ge 1 ]; then
    JOIN_CMD="$*"
    echo "  Using provided join command..."
else
    echo "  ERROR: No join command provided!"
    echo "  Usage: $0 <full kubeadm join command>"
    echo ""
    echo "  Get the join command from the master node:"
    echo "  ssh ${MASTER_USER}@${MASTER_IP} 'cat /tmp/k8s-join-command.sh'"
    exit 1
fi

# ─── 1. Pre-flight Check ────────────────────────────────────────────────
echo "[1/3] Running pre-flight checks..."

# --- 1a. Clean up any previous join ---
if [ -f /etc/kubernetes/kubelet.conf ]; then
    echo "  ⚠ Previous cluster join detected — cleaning up..."
    sudo kubeadm reset -f --cri-socket unix:///var/run/containerd/containerd.sock 2>/dev/null || true
    sudo rm -rf /etc/kubernetes /var/lib/kubelet
    echo "  ✓ Previous join cleaned up"
fi

# --- 1b. Ensure swap is disabled ---
if [ "$(swapon --show | wc -l)" -gt 0 ]; then
    echo "  ⚠ Swap is enabled — disabling..."
    sudo swapoff -a
    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    echo "  ✓ Swap disabled"
else
    echo "  ✓ Swap is already disabled"
fi

# --- 1c. Ensure kernel modules are loaded ---
for mod in overlay br_netfilter; do
    if ! lsmod | grep -q "^${mod}"; then
        echo "  ⚠ Loading kernel module: ${mod}"
        sudo modprobe ${mod}
    fi
done
echo "  ✓ Kernel modules loaded"

# --- 1d. Ensure sysctl settings ---
NEED_SYSCTL=false
[ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" != "1" ] && NEED_SYSCTL=true
[ "$(cat /proc/sys/net/bridge/bridge-nf-call-iptables 2>/dev/null)" != "1" ] && NEED_SYSCTL=true
if [ "$NEED_SYSCTL" = true ]; then
    echo "  ⚠ Applying sysctl settings..."
    sudo sysctl -w net.bridge.bridge-nf-call-iptables=1 > /dev/null
    sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=1 > /dev/null
    sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null
fi
echo "  ✓ Sysctl parameters verified"

# --- 1e. Ensure containerd is running with SystemdCgroup ---
if ! sudo systemctl is-active --quiet containerd; then
    echo "  ⚠ Containerd not running — starting..."
    sudo systemctl start containerd
fi
if grep -q 'SystemdCgroup = false' /etc/containerd/config.toml 2>/dev/null; then
    echo "  ⚠ Fixing containerd SystemdCgroup..."
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
    sudo systemctl restart containerd
fi
echo "  ✓ Containerd is healthy"

echo "  ✓ All pre-flight checks passed"

# ─── 2. Execute Join Command ────────────────────────────────────────────
echo "[2/3] Joining cluster..."
echo "  Command: ${JOIN_CMD}"
sudo ${JOIN_CMD} --node-name=k8s-worker1

# ─── 3. Verify Join ─────────────────────────────────────────────────────
echo "[3/3] Verifying join..."
sleep 5

if sudo systemctl is-active --quiet kubelet; then
    echo "  ✓ Kubelet is running"
else
    echo "  WARNING: Kubelet may still be starting up..."
    sudo systemctl status kubelet --no-pager || true
fi

echo ""
echo "=============================================="
echo "  ✓ Worker node joined successfully!"
echo ""
echo "  Run on master to verify:"
echo "  kubectl get nodes -o wide"
echo "=============================================="
echo ""
