# Enterprise Kubernetes Cluster — Complete Installation & Operations Guide

> **Full documentation of every process, step, and component in this enterprise K8s setup.**

---

## 📐 Architecture Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                    KUBERNETES CLUSTER v1.32                       │
│                                                                  │
│  ┌─────────────────────┐        ┌─────────────────────┐         │
│  │   MASTER (Control)  │        │   WORKER Node        │         │
│  │   k8s-master        │◄──────►│   k8s-worker1        │         │
│  │   192.168.56.103    │  Join  │   192.168.56.104     │         │
│  │                     │        │                      │         │
│  │  • API Server       │        │  • kubelet           │         │
│  │  • etcd             │        │  • kube-proxy        │         │
│  │  • Scheduler        │        │  • Flannel CNI       │         │
│  │  • Controller Mgr   │        │  • MetalLB Speaker   │         │
│  │  • Flannel CNI      │        │                      │         │
│  │  • MetalLB          │        │                      │         │
│  │  • Metrics Server   │        │                      │         │
│  │  • Dashboard        │        │                      │         │
│  └─────────────────────┘        └─────────────────────┘         │
│                                                                  │
│  Pod CIDR:     10.244.0.0/16    (Flannel overlay network)        │
│  Service CIDR: 10.96.0.0/12     (ClusterIP range)                │
│  LB Pool:      192.168.56.200-220 (MetalLB L2 mode)             │
└──────────────────────────────────────────────────────────────────┘
```

| Component          | Details                               |
|--------------------|---------------------------------------|
| **Platform**       | Kubernetes v1.32 on Ubuntu 22.04/24.04|
| **Control Plane**  | k8s-master (192.168.56.103)           |
| **Worker Node**    | k8s-worker1 (192.168.56.104)          |
| **Container Runtime** | containerd (with SystemdCgroup)    |
| **CNI Plugin**     | Flannel (VXLAN overlay)               |
| **Load Balancer**  | MetalLB v0.14.8 (Layer 2 mode)       |
| **Monitoring**     | Metrics Server v0.7.2                 |
| **Dashboard**      | Kubernetes Dashboard v2.7.0           |
| **SSH User**       | `k8s` (password: `neptune`)           |

---

## 📂 Directory Structure

```
k8s-enterprise/
├── deploy.ps1                            # Windows PowerShell automated deployment
│                                         #   → Runs ALL steps via SSH from Windows
│                                         #   → Copies files, installs, inits, joins
│
├── scripts/                              # Shell scripts (run on Linux nodes)
│   ├── 01-prerequisites.sh               # [ALL NODES] System prep & dependencies
│   ├── 02-install-containerd.sh          # [ALL NODES] Container runtime setup
│   ├── 03-install-k8s-components.sh      # [ALL NODES] kubeadm/kubelet/kubectl
│   ├── 04-init-master.sh                 # [MASTER]    Initialize control plane
│   ├── 05-join-worker.sh                 # [WORKER]    Join cluster
│   └── 06-install-addons.sh              # [MASTER]    Enterprise add-ons
│
├── manifests/                            # Kubernetes YAML manifests
│   ├── calico.yaml                       # Calico CNI config (unused if Flannel active)
│   ├── metallb-config.yaml               # MetalLB IP pool & L2 advertisement
│   ├── metrics-server.yaml               # Metrics Server deployment
│   ├── dashboard/
│   │   ├── dashboard-deploy.yaml         # Dashboard deployment + NodePort service
│   │   └── dashboard-admin.yaml          # Admin service account & RBAC binding
│   ├── rbac/
│   │   ├── cluster-roles.yaml            # Enterprise RBAC roles (4 roles)
│   │   └── namespace-policies.yaml       # Namespace quotas & limit ranges
│   └── network-policies/
│       ├── default-deny.yaml             # Zero-trust: deny all ingress/egress
│       └── allow-dns.yaml                # Allow DNS egress (kube-dns/CoreDNS)
│
├── configs/
│   ├── kubeadm-config.yaml               # Custom kubeadm configuration
│   └── sysctl-k8s.conf                   # Kernel parameters reference
│
└── README.md                             # This file
```

---

## 🚀 Deployment Methods

### Option A: Automated from Windows (Recommended)

The `deploy.ps1` PowerShell script runs **everything** from your Windows machine via SSH:

```powershell
# From the k8s-enterprise directory:
.\deploy.ps1
```

**What it does (8 phases):**

| Phase | Action | Target |
|-------|--------|--------|
| 1 | Copy `k8s-enterprise/` files to both nodes via SCP | Master + Worker |
| 2 | Run `01-prerequisites.sh` | Master + Worker |
| 3 | Run `02-install-containerd.sh` | Master + Worker |
| 4 | Run `03-install-k8s-components.sh` | Master + Worker |
| 5 | Run `04-init-master.sh` | Master only |
| 6 | Retrieve join command, run `05-join-worker.sh` | Worker only |
| 7 | Run `06-install-addons.sh` | Master only |
| 8 | Verify cluster status & print dashboard token | Master |

> **Note:** You'll be prompted for the SSH password (`neptune`) multiple times.

---

### Option B: Manual Step-by-Step (SSH into each node)

Follow the steps below in order.

---

## 📋 Step-by-Step Process (Complete Details)

---

### STEP 1: Prerequisites — `01-prerequisites.sh`

**Run on:** ALL nodes (master + worker)
**Purpose:** Prepare the OS for Kubernetes installation

```bash
# SSH into each node and run:
cd ~/k8s-enterprise/scripts
bash 01-prerequisites.sh
```

**What this script does (8 sub-steps):**

| # | Sub-step | Purpose | Details |
|---|----------|---------|---------|
| 1 | System Update | Ensure latest packages | `apt-get update && upgrade` |
| 2 | Install Dependencies | Required tools for K8s | `apt-transport-https, curl, socat, conntrack, ipset, jq, chrony, nfs-common, open-iscsi` |
| 3 | Time Sync (Chrony) | **Critical** — K8s certs & tokens need synced clocks | Starts chrony, forces immediate sync via `chronyc makestep` |
| 4 | Disable Swap | **Required by Kubernetes** — kubelet won't start with swap on | `swapoff -a` + comments out swap in `/etc/fstab` (persists across reboot) |
| 5 | Load Kernel Modules | Required for container networking | Loads `overlay` (for overlayFS) and `br_netfilter` (for iptables bridge traffic) |
| 6 | Sysctl Parameters | Network forwarding & tuning | Enables `ip_forward`, `bridge-nf-call-iptables`; also enterprise tuning: TCP keepalive, somaxconn, inotify limits |
| 7 | Configure `/etc/hosts` | Name resolution within cluster | Adds `k8s-master` → `192.168.56.103` and `k8s-worker1` → `192.168.56.104` |
| 8 | Firewall Rules (if UFW active) | Open required K8s ports | API Server (6443), etcd (2379-2380), Kubelet (10250), NodePort range (30000-32767) |

**Key sysctl settings explained:**

```
net.bridge.bridge-nf-call-iptables  = 1   # Allow iptables to see bridged traffic
net.bridge.bridge-nf-call-ip6tables = 1   # Same for IPv6
net.ipv4.ip_forward                 = 1   # Allow packet forwarding (required for pods)
net.core.somaxconn                  = 32768 # Max socket backlog (high-traffic apps)
vm.max_map_count                    = 262144 # Required for Elasticsearch/JVM apps
fs.inotify.max_user_watches         = 524288 # File watchers (for large projects)
```

---

### STEP 2: Install Containerd — `02-install-containerd.sh`

**Run on:** ALL nodes (master + worker)
**Purpose:** Install and configure the container runtime

```bash
bash 02-install-containerd.sh
```

**What this script does (5 sub-steps):**

| # | Sub-step | Purpose | Details |
|---|----------|---------|---------|
| 1 | Remove old packages | Clean slate | Removes any old docker/containerd/runc packages |
| 2 | Add Docker repo | Get latest containerd | Adds Docker's official GPG key and APT repository |
| 3 | Install containerd.io | Container runtime | Installs containerd from Docker's repo (latest stable) |
| 4 | Configure containerd | K8s compatibility | Sets `SystemdCgroup = true` (**critical**) and pins `pause:3.10` image |
| 5 | Start & enable | Ensure service runs | `systemctl restart containerd && systemctl enable containerd` |

**Why `SystemdCgroup = true`?**
> Kubernetes v1.22+ requires the container runtime to use systemd as the cgroup driver. Without this, pods will fail to start with container runtime errors.

**Why pin `pause:3.10`?**
> The pause container is the "sandbox" for every pod. Pinning it avoids image pull failures from version mismatches.

---

### STEP 3: Install K8s Components — `03-install-k8s-components.sh`

**Run on:** ALL nodes (master + worker)
**Purpose:** Install kubeadm, kubelet, and kubectl

```bash
bash 03-install-k8s-components.sh
```

**What this script does (4 sub-steps):**

| # | Sub-step | Purpose | Details |
|---|----------|---------|---------|
| 1 | Add K8s APT repo | v1.32 stable repo | Adds `pkgs.k8s.io` with GPG key |
| 2 | Install packages | Core K8s tools | `kubeadm` (cluster setup), `kubelet` (node agent), `kubectl` (CLI) |
| 3 | Hold packages | Prevent accidental upgrades | `apt-mark hold kubelet kubeadm kubectl` |
| 4 | Enable kubelet | Ensure service starts at boot | `systemctl enable kubelet` (won't run until init/join) |

**What each component does:**

- **kubeadm** — Bootstraps the cluster (init master, join workers)
- **kubelet** — Node agent that runs pods; talks to the API server
- **kubectl** — CLI tool to interact with the cluster

**Bonus:** Sets up bash completion and `k` alias for `kubectl`.

---

### STEP 4: Initialize Master — `04-init-master.sh`

**Run on:** MASTER node only (192.168.56.103)
**Purpose:** Bootstrap the Kubernetes control plane

```bash
bash 04-init-master.sh
```

**What this script does (6 sub-steps):**

| # | Sub-step | Purpose | Details |
|---|----------|---------|---------|
| 1 | Pre-flight checks | Safe to init | Cleans any previous install, verifies swap off, kernel modules, sysctl, containerd health |
| 2 | Pre-pull images | Faster init | Downloads K8s images before init to avoid timeout |
| 3 | `kubeadm init` | **Creates the cluster** | Initializes etcd, API server, controller manager, scheduler |
| 4 | Configure kubectl | CLI access | Copies admin config to `~/.kube/config` |
| 5 | Save join command | For worker nodes | Generates `kubeadm token` and saves to `/tmp/k8s-join-command.sh` |
| 6 | Verify | Confirm health | Shows `kubectl cluster-info`, node status, system pods |

**`kubeadm init` parameters:**

```bash
kubeadm init \
    --apiserver-advertise-address=192.168.56.103  # Master IP for API server
    --pod-network-cidr=10.244.0.0/16              # Pod network range (Flannel default)
    --service-cidr=10.96.0.0/12                   # ClusterIP service range
    --node-name=k8s-master                        # Explicit node name
    --upload-certs                                # Upload certs for HA (future use)
```

**After this step:**
- The control plane is running (API Server, etcd, Scheduler, Controller Manager)
- kubelet and kube-proxy are running
- CoreDNS pods are deployed
- A join command is saved at `/tmp/k8s-join-command.sh`
- **CNI is NOT yet installed** — nodes will show `NotReady` until Step 6

---

### STEP 5: Join Worker — `05-join-worker.sh`

**Run on:** WORKER node only (192.168.56.104)
**Purpose:** Join the worker node to the cluster

```bash
# First, get the join command from master:
ssh k8s@192.168.56.103 'cat /tmp/k8s-join-command.sh'

# Then run on worker (replace <command> with actual join command):
bash 05-join-worker.sh <kubeadm join command>
```

**What this script does (3 sub-steps):**

| # | Sub-step | Purpose | Details |
|---|----------|---------|---------|
| 1 | Pre-flight checks | Safe to join | Cleans any previous join, verifies swap/modules/sysctl/containerd |
| 2 | Execute join | **Joins the cluster** | Runs `kubeadm join` with `--node-name=k8s-worker1` |
| 3 | Verify join | Confirm kubelet running | Checks `systemctl is-active kubelet` |

**What happens during join:**
1. Worker contacts the API server at `192.168.56.103:6443`
2. Worker validates the token and CA cert hash
3. kubelet is configured to talk to the master
4. kube-proxy is deployed on the worker
5. Node appears in `kubectl get nodes` (will be `NotReady` until CNI starts)

---

### STEP 6: Install Enterprise Add-ons — `06-install-addons.sh`

**Run on:** MASTER node only
**Purpose:** Install CNI, load balancer, monitoring, dashboard, security policies

```bash
bash 06-install-addons.sh
```

**What this script does (6 sub-steps):**

#### [1/6] CNI Plugin Check

- **Detects** if Flannel is already running (installed during init)
- **Skips Calico** if Flannel is present (avoids dual-CNI conflict)
- If neither CNI exists, installs Calico v3.28.0 via Tigera operator

> **Why CNI is needed:** Without a CNI plugin, pods can't communicate across nodes. The CNI creates the overlay network (10.244.0.0/16) that connects all pods.

#### [2/6] Metrics Server

- Deploys Metrics Server v0.7.2 from `manifests/metrics-server.yaml`
- **Purpose:** Provides CPU/memory metrics for `kubectl top nodes/pods` and Horizontal Pod Autoscaler (HPA)
- Uses `--kubelet-insecure-tls` flag (required for self-signed kubelet certs in this setup)

#### [3/6] MetalLB Load Balancer

- Installs MetalLB v0.14.8 (native manifest from GitHub)
- **Waits for CRDs** to be established (`IPAddressPool`, `L2Advertisement`)
- **Waits for controller & speaker pods** to become `Ready`
- **Applies config** with retry loop (up to 10 attempts, 15s apart)

**MetalLB Configuration** (`manifests/metallb-config.yaml`):
```yaml
# IPAddressPool: 192.168.56.200 - 192.168.56.220
#   → MetalLB assigns IPs from this range to LoadBalancer services
#   → These IPs must be in the same L2 network as your nodes
#
# L2Advertisement:
#   → Uses ARP/NDP to announce IPs on the local network
#   → Speaker pods respond to ARP requests for assigned IPs
```

**Why MetalLB?**
> In bare-metal clusters (no cloud provider), `Service type: LoadBalancer` stays in `Pending` forever. MetalLB provides real external IPs.

#### [4/6] Kubernetes Dashboard

- Deploys from `manifests/dashboard/dashboard-deploy.yaml`
- Creates admin service account from `manifests/dashboard/dashboard-admin.yaml`
- **Access:** `https://192.168.56.103:30443`

#### [5/6] RBAC Policies

From `manifests/rbac/cluster-roles.yaml`:

| Role | Access Level |
|------|-------------|
| `enterprise-cluster-viewer` | Read-only access to all cluster resources |
| `enterprise-cluster-developer` | Full workload access (pods, deployments, services), limited cluster access |
| `enterprise-cluster-operator` | Broad access to all resources except RBAC modification |
| `enterprise-security-auditor` | Read access to security-related resources (RBAC, network policies, certs) |

From `manifests/rbac/namespace-policies.yaml`:
- **Resource Quotas** — CPU/memory limits per namespace (production, staging, development)
- **Limit Ranges** — Default container resource requests/limits

#### [6/6] Network Policies

- **`default-deny.yaml`** — Zero-trust baseline: deny ALL ingress/egress in `production` and `staging` namespaces
- **`allow-dns.yaml`** — Allows egress to `kube-dns` (CoreDNS) on port 53 so pods can resolve DNS

---

## 🔐 Post-Installation

### Access the Kubernetes Dashboard

```bash
# 1. Open in browser (accept self-signed cert warning):
#    https://192.168.56.103:30443

# 2. Get admin token:
kubectl -n kubernetes-dashboard create token dashboard-admin

# 3. Copy the token → Paste into the login field → Click "Sign in"
```

If `dashboard-admin` doesn't exist:
```bash
kubectl -n kubernetes-dashboard create serviceaccount dashboard-admin
kubectl create clusterrolebinding dashboard-admin \
    --clusterrole=cluster-admin \
    --serviceaccount=kubernetes-dashboard:dashboard-admin
```

### Verify Cluster Health

```bash
# Check node status (both should be Ready)
kubectl get nodes -o wide

# Check all pods across all namespaces
kubectl get pods -A

# Check resource usage (requires Metrics Server)
kubectl top nodes
kubectl top pods -A

# Cluster info
kubectl cluster-info

# Component statuses
kubectl get componentstatuses
```

### Use MetalLB LoadBalancer

```bash
# Example: expose a deployment with an external IP
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --type=LoadBalancer --port=80

# Check the assigned external IP (from 192.168.56.200-220 range)
kubectl get svc nginx
# NAME    TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)
# nginx   LoadBalancer   10.96.x.x      192.168.56.200   80:3xxxx/TCP
```

---

## ⚠️ Common Issues & Troubleshooting

### Issue: Nodes show `NotReady`

**Cause:** CNI plugin not installed or not running.

```bash
# Check if Flannel pods are running
kubectl get pods -n kube-flannel

# If not running, apply Flannel manually:
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

### Issue: MetalLB webhook `connection refused`

**Cause:** MetalLB controller/speaker pods aren't ready when config is applied.

```bash
# Check MetalLB pod status
kubectl get pods -n metallb-system

# Wait for pods to be ready, then re-apply config
kubectl wait --for=condition=Ready pods -l component=controller -n metallb-system --timeout=180s
kubectl apply -f ~/k8s-enterprise/manifests/metallb-config.yaml
```

### Issue: Pods stuck in `Pending`

**Cause:** Control-plane taint preventing scheduling (especially on single-node setups).

```bash
# Check taints on nodes
kubectl describe node k8s-master | grep -A5 Taints

# Remove the NoSchedule taint to allow workloads on master:
kubectl taint nodes k8s-master node-role.kubernetes.io/control-plane:NoSchedule-
```

### Issue: `annotations too long` error during Calico install

**Cause:** The Calico operator CRD exceeds the 262KB annotation limit for `kubectl apply`.

```bash
# Use server-side apply instead:
kubectl apply --server-side --force-conflicts -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/tigera-operator.yaml
```

### Issue: Container images not pulling

```bash
# Check pod events
kubectl describe pod <pod-name> -n <namespace> | tail -20

# Check containerd is running
sudo systemctl status containerd

# Manually pull an image to test
sudo ctr image pull docker.io/library/nginx:latest
```

### General Debugging Commands

```bash
# Check kubelet logs (most issues show here)
sudo journalctl -u kubelet -f --no-pager -n 50

# Check containerd logs
sudo journalctl -u containerd -f --no-pager -n 50

# Check API server logs
kubectl logs -n kube-system kube-apiserver-k8s-master

# Check events in a namespace
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Nuclear option: Reset and start over
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d /var/lib/etcd /var/lib/kubelet $HOME/.kube
```

---

## 🔒 Security Features Deployed

| Feature | Status | Details |
|---------|--------|---------|
| Zero-Trust Network Policies | ✅ | Default deny ingress/egress on `production` & `staging` namespaces |
| Resource Quotas | ✅ | CPU/memory limits per namespace |
| Limit Ranges | ✅ | Default container resource constraints |
| RBAC | ✅ | 4 enterprise roles (viewer, developer, operator, auditor) |
| Admission Controllers | ✅ | NodeRestriction, ResourceQuota, LimitRanger |
| Containerd SystemdCgroup | ✅ | Proper cgroup driver for K8s |
| Package Hold | ✅ | Prevents accidental K8s version upgrade |
| Swap Disabled | ✅ | Required by kubelet, persists across reboot |
| Time Synchronization | ✅ | Chrony NTP for cert/token validity |

---

## 📊 Network Configuration Summary

```
Physical Network:  192.168.56.0/24   (VirtualBox host-only or equivalent)
  ├── k8s-master:    192.168.56.103
  ├── k8s-worker1:   192.168.56.104
  └── MetalLB Pool:  192.168.56.200 - 192.168.56.220

Pod Network:       10.244.0.0/16     (Flannel VXLAN overlay)
  ├── Node 1 pods:   10.244.0.0/24
  └── Node 2 pods:   10.244.1.0/24

Service Network:   10.96.0.0/12      (ClusterIP virtual IPs)
  └── CoreDNS:       10.96.0.10

Dashboard:         https://192.168.56.103:30443
API Server:        https://192.168.56.103:6443
```

---

## 🔄 Day-2 Operations

### Scale the Cluster (Add More Workers)

```bash
# On master: generate a new join token
kubeadm token create --print-join-command

# On new worker: run prerequisites, containerd, k8s components, then join
bash 01-prerequisites.sh
bash 02-install-containerd.sh
bash 03-install-k8s-components.sh
bash 05-join-worker.sh <join command>
```

### Renew Certificates (Auto-renew on kubeadm upgrade)

```bash
# Check certificate expiration
sudo kubeadm certs check-expiration

# Renew all certificates
sudo kubeadm certs renew all
```

### Backup etcd

```bash
ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup.db \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key
```

---

*Last updated: 2026-03-04 | Kubernetes v1.32 | Ubuntu 22.04/24.04 LTS*
