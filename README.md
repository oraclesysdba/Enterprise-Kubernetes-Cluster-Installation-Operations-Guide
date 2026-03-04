# Enterprise Kubernetes Cluster — Installation & Operations Guide

## Architecture Overview

| Component | Details |
|-----------|---------|
| **Platform** | Kubernetes v1.32 on Ubuntu |
| **Control Plane** | k8s-master (192.168.56.103) |
| **Worker Node** | k8s-worker1 (192.168.56.104) |
| **Container Runtime** | containerd |
| **CNI Plugin** | Calico v3.28.0 |
| **Load Balancer** | MetalLB v0.14.8 (L2 mode) |
| **Monitoring** | Metrics Server v0.7.2 |
| **Dashboard** | Kubernetes Dashboard v2.7.0 |
| **Pod CIDR** | 10.244.0.0/16 |
| **Service CIDR** | 10.96.0.0/12 |

---

## Directory Structure

```
k8s-enterprise/
├── scripts/                          # Installation scripts
│   ├── 01-prerequisites.sh           # System prerequisites (all nodes)
│   ├── 02-install-containerd.sh      # Containerd runtime (all nodes)
│   ├── 03-install-k8s-components.sh  # kubeadm/kubelet/kubectl (all nodes)
│   ├── 04-init-master.sh             # Master initialization
│   ├── 05-join-worker.sh             # Worker join command
│   └── 06-install-addons.sh          # Enterprise add-ons
├── manifests/                        # Kubernetes YAML manifests
│   ├── calico.yaml                   # Calico CNI configuration
│   ├── metallb-config.yaml           # MetalLB IP pool & L2 ads
│   ├── metrics-server.yaml           # Metrics Server deployment
│   ├── dashboard/
│   │   ├── dashboard-deploy.yaml     # Dashboard deployment
│   │   └── dashboard-admin.yaml      # Admin service account
│   ├── rbac/
│   │   ├── cluster-roles.yaml        # Enterprise RBAC roles
│   │   └── namespace-policies.yaml   # Namespace quotas & limits
│   └── network-policies/
│       ├── default-deny.yaml         # Zero-trust baseline
│       └── allow-dns.yaml            # DNS egress rules
├── configs/
│   ├── kubeadm-config.yaml           # Custom kubeadm config
│   └── sysctl-k8s.conf              # Kernel parameters
└── README.md                         # This file
```

---

## Installation Steps

### Step 1: Prerequisites (Both Nodes)
```bash
# SSH into each node and run:
bash 01-prerequisites.sh
```

### Step 2: Install Containerd (Both Nodes)
```bash
bash 02-install-containerd.sh
```

### Step 3: Install K8s Components (Both Nodes)
```bash
bash 03-install-k8s-components.sh
```

### Step 4: Initialize Master (Node 1 Only)
```bash
bash 04-init-master.sh
```

### Step 5: Join Worker (Node 2 Only)
```bash
# Get join command from master:
cat /tmp/k8s-join-command.sh

# Run on worker:
bash 05-join-worker.sh <join-command>
```

### Step 6: Install Enterprise Add-ons (Master Only)
```bash
bash 06-install-addons.sh
```

---

## Post-Installation

### Access Dashboard
```bash
# URL: https://192.168.56.103:30443

# Get admin token:
kubectl -n kubernetes-dashboard create token dashboard-admin
```

### Verify Cluster
```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl top nodes
kubectl cluster-info
```

### Enterprise RBAC Roles
| Role | Description |
|------|-------------|
| `enterprise-cluster-viewer` | Read-only access to cluster resources |
| `enterprise-cluster-developer` | Full workload access, limited cluster access |
| `enterprise-cluster-operator` | Broad access except RBAC modification |
| `enterprise-security-auditor` | Read access to security resources |

### MetalLB Load Balancer
IP Pool: `192.168.56.200 - 192.168.56.220`
```bash
# Create a LoadBalancer service:
kubectl expose deployment myapp --type=LoadBalancer --port=80
```

---

## Security Features

- ✅ **Zero-Trust Network Policies** — Default deny ingress/egress on prod/staging
- ✅ **Resource Quotas** — CPU/memory limits per namespace
- ✅ **Limit Ranges** — Default container resource constraints
- ✅ **RBAC** — Role-based access for viewer/developer/operator/auditor
- ✅ **Audit Logging** — API server audit logs at `/var/log/kubernetes/audit.log`
- ✅ **Admission Controllers** — NodeRestriction, ResourceQuota, LimitRanger enabled
- ✅ **Profiling Disabled** — API server, controller manager, scheduler

---

## Troubleshooting

```bash
# Check node status
kubectl get nodes -o wide

# Check system pods
kubectl get pods -n kube-system

# Check kubelet logs
sudo journalctl -u kubelet -f

# Check containerd
sudo systemctl status containerd

# Reset and reinitialize (if needed)
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d /var/lib/etcd $HOME/.kube
```
