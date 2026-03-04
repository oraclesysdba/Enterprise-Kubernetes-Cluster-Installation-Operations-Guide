#!/bin/bash
###############################################################################
# Enterprise Kubernetes - Containerd Installation
# Run on ALL nodes (master + workers)
###############################################################################
set -euo pipefail

echo "=============================================="
echo "  K8s Enterprise - Containerd Installation"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================="

# ─── 1. Remove Old Docker/Containerd Versions ────────────────────────────
echo "[1/5] Removing old container runtime packages..."
sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# ─── 2. Add Docker's Official GPG Key & Repository ───────────────────────
echo "[2/5] Adding Docker repository..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -qq

# ─── 3. Install Containerd ───────────────────────────────────────────────
echo "[3/5] Installing containerd.io..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq containerd.io

# ─── 4. Configure Containerd with SystemdCgroup ─────────────────────────
echo "[4/5] Configuring containerd for Kubernetes..."
sudo mkdir -p /etc/containerd

# Generate default config and modify for K8s
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null

# Enable SystemdCgroup (CRITICAL for K8s)
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Pin the sandbox (pause) image to match K8s version
sudo sed -i 's|sandbox_image = "registry.k8s.io/pause:.*"|sandbox_image = "registry.k8s.io/pause:3.10"|g' /etc/containerd/config.toml

# ─── 5. Restart & Enable Containerd ─────────────────────────────────────
echo "[5/5] Starting containerd service..."
sudo systemctl daemon-reload
sudo systemctl restart containerd
sudo systemctl enable containerd

# Verify containerd is running
if sudo systemctl is-active --quiet containerd; then
    echo "  ✓ Containerd is running"
    echo "  Version: $(containerd --version)"
else
    echo "ERROR: Containerd failed to start!"
    sudo systemctl status containerd --no-pager
    exit 1
fi

echo ""
echo "=============================================="
echo "  ✓ Containerd installation completed"
echo "=============================================="
echo ""
