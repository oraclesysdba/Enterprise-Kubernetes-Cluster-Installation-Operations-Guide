#!/bin/bash
###############################################################################
# Enterprise Kubernetes - Master Node Initialization
# Run ONLY on the control plane node (192.168.56.103)
###############################################################################
set -euo pipefail

MASTER_IP="192.168.56.103"
POD_CIDR="10.244.0.0/16"
SERVICE_CIDR="10.96.0.0/12"
K8S_VERSION="1.32.0"

echo "=============================================="
echo "  K8s Enterprise - Master Node Initialization"
echo "  Master IP: ${MASTER_IP}"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================="

# ─── 1. Pre-flight Check ────────────────────────────────────────────────
echo "[1/6] Running pre-flight checks..."

# --- 1a. Clean up any previous installation ---
MANIFESTS_EXIST=false
for f in /etc/kubernetes/manifests/kube-apiserver.yaml \
         /etc/kubernetes/manifests/kube-controller-manager.yaml \
         /etc/kubernetes/manifests/kube-scheduler.yaml \
         /etc/kubernetes/manifests/etcd.yaml; do
    if [ -f "$f" ]; then
        MANIFESTS_EXIST=true
        break
    fi
done

if kubectl cluster-info &>/dev/null || [ "$MANIFESTS_EXIST" = true ]; then
    echo "  ⚠ Previous Kubernetes installation detected — cleaning up..."
    sudo kubeadm reset -f --cri-socket unix:///var/run/containerd/containerd.sock 2>/dev/null || true
    sudo rm -rf /etc/kubernetes /var/lib/etcd /var/lib/kubelet
    sudo rm -rf $HOME/.kube/config
    echo "  ✓ Previous installation cleaned up"
fi

# --- 1b. Ensure swap is disabled (survives reboot) ---
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
echo "  ✓ Kernel modules (overlay, br_netfilter) loaded"

# --- 1d. Ensure sysctl settings are applied ---
NEED_SYSCTL=false
[ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" != "1" ] && NEED_SYSCTL=true
[ "$(cat /proc/sys/net/bridge/bridge-nf-call-iptables 2>/dev/null)" != "1" ] && NEED_SYSCTL=true
if [ "$NEED_SYSCTL" = true ]; then
    echo "  ⚠ Applying required sysctl settings..."
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

# Verify SystemdCgroup is enabled
if grep -q 'SystemdCgroup = false' /etc/containerd/config.toml 2>/dev/null; then
    echo "  ⚠ Fixing containerd SystemdCgroup setting..."
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
    sudo systemctl restart containerd
fi

# Ensure sandbox image is set correctly
if ! grep -q 'sandbox_image = "registry.k8s.io/pause:3.10"' /etc/containerd/config.toml 2>/dev/null; then
    echo "  ⚠ Fixing containerd sandbox image..."
    sudo sed -i 's|sandbox_image = "registry.k8s.io/pause:.*"|sandbox_image = "registry.k8s.io/pause:3.10"|g' /etc/containerd/config.toml
    sudo systemctl restart containerd
fi
echo "  ✓ Containerd is healthy (SystemdCgroup=true, pause:3.10)"

echo "  ✓ All pre-flight checks passed"

# ─── 2. Pull Required Images ────────────────────────────────────────────
echo "[2/6] Pre-pulling Kubernetes images..."
sudo kubeadm config images pull --kubernetes-version=${K8S_VERSION} 2>/dev/null || \
sudo kubeadm config images pull 2>/dev/null || true

# ─── 3. Initialize Kubernetes Cluster ────────────────────────────────────
echo "[3/6] Initializing Kubernetes cluster..."
sudo kubeadm init \
    --apiserver-advertise-address=${MASTER_IP} \
    --pod-network-cidr=${POD_CIDR} \
    --service-cidr=${SERVICE_CIDR} \
    --node-name=k8s-master \
    --upload-certs \
    --v=5 2>&1 | tee /tmp/kubeadm-init.log

# Check if init was successful
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "ERROR: kubeadm init failed! Check /tmp/kubeadm-init.log"
    exit 1
fi

# ─── 4. Configure kubectl for Current User ──────────────────────────────
echo "[4/6] Configuring kubectl..."
mkdir -p $HOME/.kube
sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
export KUBECONFIG=$HOME/.kube/config

# Also set it up for root (useful for troubleshooting)
sudo mkdir -p /root/.kube
sudo cp -f /etc/kubernetes/admin.conf /root/.kube/config

echo "  ✓ kubectl configured for user: $(whoami)"

# ─── 5. Save Join Command ───────────────────────────────────────────────
echo "[5/6] Saving worker join command..."
JOIN_CMD=$(kubeadm token create --print-join-command 2>/dev/null)
echo "#!/bin/bash" > /tmp/k8s-join-command.sh
echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')" >> /tmp/k8s-join-command.sh
echo "# This token expires in 24 hours" >> /tmp/k8s-join-command.sh
echo "sudo ${JOIN_CMD}" >> /tmp/k8s-join-command.sh
chmod +x /tmp/k8s-join-command.sh
echo "  ✓ Join command saved to /tmp/k8s-join-command.sh"

# ─── 6. Verify Cluster Status ───────────────────────────────────────────
echo "[6/6] Verifying cluster status..."
echo ""
echo "  Cluster Info:"
kubectl cluster-info 2>/dev/null || echo "  Waiting for API server..."
echo ""
echo "  Node Status:"
kubectl get nodes -o wide 2>/dev/null || true
echo ""
echo "  System Pods:"
kubectl get pods -n kube-system 2>/dev/null || true

echo ""
echo "=============================================="
echo "  ✓ Master node initialized successfully!"
echo ""
echo "  Join Command (for worker nodes):"
echo "  ${JOIN_CMD}"
echo ""
echo "  NOTE: Install a CNI plugin before adding"
echo "  worker nodes for full functionality."
echo "=============================================="
echo ""
