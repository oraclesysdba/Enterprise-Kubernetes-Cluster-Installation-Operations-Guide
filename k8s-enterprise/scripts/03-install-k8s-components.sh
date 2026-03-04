#!/bin/bash
###############################################################################
# Enterprise Kubernetes - K8s Components Installation
# Run on ALL nodes (master + workers)
# Installs: kubeadm, kubelet, kubectl v1.32
###############################################################################
set -euo pipefail

K8S_VERSION="1.32"

echo "=============================================="
echo "  K8s Enterprise - Components Installation"
echo "  Kubernetes Version: v${K8S_VERSION}"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================="

# ─── 1. Add Kubernetes APT Repository ───────────────────────────────────
echo "[1/4] Adding Kubernetes v${K8S_VERSION} repository..."
sudo mkdir -p /etc/apt/keyrings

curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" | \
    sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg --yes

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" | \
    sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

sudo apt-get update -qq

# ─── 2. Install kubeadm, kubelet, kubectl ────────────────────────────────
echo "[2/4] Installing kubeadm, kubelet, kubectl..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq kubelet kubeadm kubectl

# ─── 3. Hold Packages (Prevent Unintended Upgrades) ─────────────────────
echo "[3/4] Holding Kubernetes packages..."
sudo apt-mark hold kubelet kubeadm kubectl

# ─── 4. Enable kubelet Service ──────────────────────────────────────────
echo "[4/4] Enabling kubelet service..."
sudo systemctl enable kubelet

# ─── Verify Installation ────────────────────────────────────────────────
echo ""
echo "  Installed versions:"
echo "  kubeadm: $(kubeadm version -o short 2>/dev/null || echo 'pending init')"
echo "  kubelet: $(kubelet --version 2>/dev/null || echo 'pending')"
echo "  kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1)"

# ─── Enable kubectl Bash Completion ─────────────────────────────────────
echo ""
echo "  Setting up kubectl bash completion..."
kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null 2>&1 || true
echo 'alias k=kubectl' >> ~/.bashrc 2>/dev/null || true
echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc 2>/dev/null || true

echo ""
echo "=============================================="
echo "  ✓ Kubernetes components installed"
echo "=============================================="
echo ""
