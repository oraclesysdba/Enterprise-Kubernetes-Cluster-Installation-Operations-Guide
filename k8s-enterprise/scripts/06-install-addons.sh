#!/bin/bash
###############################################################################
# Enterprise Kubernetes - Add-ons Installation
# Run ONLY on the master/control-plane node
# Installs: Calico CNI, MetalLB, Metrics Server, Dashboard, RBAC, Net Policies
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"

echo "=============================================="
echo "  K8s Enterprise - Add-ons Installation"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================="

# ─── 1. Install Calico CNI ──────────────────────────────────────────────
echo "[1/6] Installing Calico CNI..."
echo "  Deploying Calico operator..."
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/tigera-operator.yaml 2>/dev/null || \
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/tigera-operator.yaml

echo "  Applying Calico custom resources..."
kubectl apply -f ${MANIFESTS_DIR}/calico.yaml

echo "  Waiting for Calico pods to be ready (timeout: 180s)..."
kubectl wait --for=condition=Ready pods -l k8s-app=calico-node -n calico-system --timeout=180s 2>/dev/null || \
    echo "  NOTE: Calico pods may still be initializing..."

echo "  ✓ Calico CNI deployed"

# ─── 2. Install Metrics Server ──────────────────────────────────────────
echo "[2/6] Installing Metrics Server..."
kubectl apply -f ${MANIFESTS_DIR}/metrics-server.yaml
echo "  ✓ Metrics Server deployed"

# ─── 3. Install MetalLB ─────────────────────────────────────────────────
echo "[3/6] Installing MetalLB..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

echo "  Waiting for MetalLB controller to be ready..."
kubectl wait --for=condition=Ready pods -l app=metallb -n metallb-system --timeout=120s 2>/dev/null || \
    echo "  NOTE: MetalLB pods may still be initializing..."

sleep 10
echo "  Applying MetalLB configuration..."
kubectl apply -f ${MANIFESTS_DIR}/metallb-config.yaml
echo "  ✓ MetalLB deployed"

# ─── 4. Install Kubernetes Dashboard ────────────────────────────────────
echo "[4/6] Installing Kubernetes Dashboard..."
kubectl apply -f ${MANIFESTS_DIR}/dashboard/dashboard-deploy.yaml
kubectl apply -f ${MANIFESTS_DIR}/dashboard/dashboard-admin.yaml

echo "  ✓ Kubernetes Dashboard deployed"

# ─── 5. Apply RBAC Policies ─────────────────────────────────────────────
echo "[5/6] Applying RBAC policies..."
kubectl apply -f ${MANIFESTS_DIR}/rbac/cluster-roles.yaml
kubectl apply -f ${MANIFESTS_DIR}/rbac/namespace-policies.yaml
echo "  ✓ RBAC policies applied"

# ─── 6. Apply Network Policies ──────────────────────────────────────────
echo "[6/6] Applying Network Policies..."
kubectl apply -f ${MANIFESTS_DIR}/network-policies/default-deny.yaml
kubectl apply -f ${MANIFESTS_DIR}/network-policies/allow-dns.yaml
echo "  ✓ Network policies applied"

# ─── Summary ────────────────────────────────────────────────────────────
echo ""
echo "=============================================="
echo "  ✓ All enterprise add-ons installed!"
echo "=============================================="
echo ""
echo "  Components Deployed:"
echo "  ├── Calico CNI v3.28.0"
echo "  ├── MetalLB v0.14.8"
echo "  ├── Metrics Server"
echo "  ├── Kubernetes Dashboard"
echo "  ├── Enterprise RBAC Policies"
echo "  └── Network Policies (default-deny)"
echo ""

# Dashboard access info
echo "  ─── Dashboard Access ───"
echo "  Get NodePort:"
echo "    kubectl get svc -n kubernetes-dashboard"
echo ""
echo "  Get Admin Token:"
echo "    kubectl -n kubernetes-dashboard create token dashboard-admin"
echo ""
echo "  Access URL:"
echo "    https://<NODE_IP>:<NODE_PORT>"
echo ""

# Cluster overview
echo "  ─── Cluster Status ───"
kubectl get nodes -o wide
echo ""
kubectl get pods -A --field-selector status.phase!=Running 2>/dev/null || echo "  All pods running!"
echo ""
