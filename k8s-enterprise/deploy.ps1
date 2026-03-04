###############################################################################
# Enterprise Kubernetes - Automated Deployment Script
# Deploys K8s cluster on Ubuntu nodes from Windows via SSH
# 
# Usage: .\deploy.ps1
# Prerequisites: OpenSSH client on Windows
###############################################################################

$ErrorActionPreference = "Continue"

# ─── Configuration ──────────────────────────────────────────────────────
$MASTER_IP   = "192.168.56.103"
$WORKER_IP   = "192.168.56.104"
$SSH_USER    = "k8s"
$SSH_PASS    = "neptune"
$REMOTE_DIR  = "/home/k8s/k8s-enterprise"
$LOCAL_DIR   = $PSScriptRoot

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  Enterprise Kubernetes - Automated Deployment"     -ForegroundColor Cyan
Write-Host "  Master: $MASTER_IP  |  Worker: $WORKER_IP"       -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"       -ForegroundColor Gray
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# ─── Helper: Run SSH command on remote node ─────────────────────────────
function Invoke-RemoteSSH {
    param(
        [string]$NodeIP,
        [string]$Command,
        [string]$StepName
    )
    Write-Host "  [$StepName] Running on $NodeIP..." -ForegroundColor Yellow
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 "${SSH_USER}@${NodeIP}" $Command
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [ERROR] Command failed on $NodeIP (exit code: $LASTEXITCODE)" -ForegroundColor Red
        return $false
    }
    Write-Host "  [OK] $StepName completed on $NodeIP" -ForegroundColor Green
    return $true
}

# ─── Helper: SCP files to remote node ──────────────────────────────────
function Send-FilesToNode {
    param(
        [string]$NodeIP,
        [string]$StepName
    )
    Write-Host "  [$StepName] Copying files to $NodeIP..." -ForegroundColor Yellow
    Write-Host "  >> Enter password '$SSH_PASS' when prompted <<" -ForegroundColor Magenta
    scp -o StrictHostKeyChecking=no -r "$LOCAL_DIR" "${SSH_USER}@${NodeIP}:/home/${SSH_USER}/"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [ERROR] SCP failed to $NodeIP" -ForegroundColor Red
        return $false
    }
    Write-Host "  [OK] Files copied to $NodeIP" -ForegroundColor Green
    return $true
}

# ═══════════════════════════════════════════════════════════════════════
#  PHASE 1: Copy files to both nodes
# ═══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "══════ PHASE 1: Copy Files to Nodes ══════" -ForegroundColor Cyan
Write-Host ""

Write-Host "Copying k8s-enterprise to MASTER ($MASTER_IP)..." -ForegroundColor White
Send-FilesToNode -NodeIP $MASTER_IP -StepName "SCP-Master"

Write-Host ""
Write-Host "Copying k8s-enterprise to WORKER ($WORKER_IP)..." -ForegroundColor White
Send-FilesToNode -NodeIP $WORKER_IP -StepName "SCP-Worker"

# ═══════════════════════════════════════════════════════════════════════
#  PHASE 2: Run prerequisites on BOTH nodes
# ═══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "══════ PHASE 2: Prerequisites (Both Nodes) ══════" -ForegroundColor Cyan
Write-Host ""
Write-Host ">> Enter password '$SSH_PASS' when prompted for each node <<" -ForegroundColor Magenta
Write-Host ""

Write-Host "─── Master Node ($MASTER_IP) ───" -ForegroundColor White
Invoke-RemoteSSH -NodeIP $MASTER_IP -StepName "Prerequisites" `
    -Command "chmod +x ${REMOTE_DIR}/scripts/*.sh && cd ${REMOTE_DIR} && echo '$SSH_PASS' | sudo -S bash scripts/01-prerequisites.sh"

Write-Host ""
Write-Host "─── Worker Node ($WORKER_IP) ───" -ForegroundColor White
Invoke-RemoteSSH -NodeIP $WORKER_IP -StepName "Prerequisites" `
    -Command "chmod +x ${REMOTE_DIR}/scripts/*.sh && cd ${REMOTE_DIR} && echo '$SSH_PASS' | sudo -S bash scripts/01-prerequisites.sh"

# ═══════════════════════════════════════════════════════════════════════
#  PHASE 3: Install Containerd on BOTH nodes
# ═══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "══════ PHASE 3: Containerd (Both Nodes) ══════" -ForegroundColor Cyan
Write-Host ""

Invoke-RemoteSSH -NodeIP $MASTER_IP -StepName "Containerd" `
    -Command "cd ${REMOTE_DIR} && echo '$SSH_PASS' | sudo -S bash scripts/02-install-containerd.sh"

Write-Host ""
Invoke-RemoteSSH -NodeIP $WORKER_IP -StepName "Containerd" `
    -Command "cd ${REMOTE_DIR} && echo '$SSH_PASS' | sudo -S bash scripts/02-install-containerd.sh"

# ═══════════════════════════════════════════════════════════════════════
#  PHASE 4: Install K8s Components on BOTH nodes
# ═══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "══════ PHASE 4: K8s Components (Both Nodes) ══════" -ForegroundColor Cyan
Write-Host ""

Invoke-RemoteSSH -NodeIP $MASTER_IP -StepName "K8s-Components" `
    -Command "cd ${REMOTE_DIR} && echo '$SSH_PASS' | sudo -S bash scripts/03-install-k8s-components.sh"

Write-Host ""
Invoke-RemoteSSH -NodeIP $WORKER_IP -StepName "K8s-Components" `
    -Command "cd ${REMOTE_DIR} && echo '$SSH_PASS' | sudo -S bash scripts/03-install-k8s-components.sh"

# ═══════════════════════════════════════════════════════════════════════
#  PHASE 5: Initialize Master Node
# ═══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "══════ PHASE 5: Initialize Master Node ══════" -ForegroundColor Cyan
Write-Host ""

Invoke-RemoteSSH -NodeIP $MASTER_IP -StepName "Master-Init" `
    -Command "cd ${REMOTE_DIR} && echo '$SSH_PASS' | sudo -S bash scripts/04-init-master.sh"

# ═══════════════════════════════════════════════════════════════════════
#  PHASE 6: Get Join Command and Join Worker
# ═══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "══════ PHASE 6: Join Worker Node ══════" -ForegroundColor Cyan
Write-Host ""

Write-Host "  Retrieving join command from master..." -ForegroundColor Yellow
$JOIN_CMD = ssh -o StrictHostKeyChecking=no "${SSH_USER}@${MASTER_IP}" "cat /tmp/k8s-join-command.sh | grep 'kubeadm join'"

if ($JOIN_CMD) {
    Write-Host "  Join command: $JOIN_CMD" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Joining worker to cluster..." -ForegroundColor Yellow
    Invoke-RemoteSSH -NodeIP $WORKER_IP -StepName "Worker-Join" `
        -Command "echo '$SSH_PASS' | sudo -S $JOIN_CMD --node-name=k8s-worker1"
} else {
    Write-Host "  [ERROR] Could not retrieve join command!" -ForegroundColor Red
    Write-Host "  Manually run on master: kubeadm token create --print-join-command" -ForegroundColor Yellow
}

# ═══════════════════════════════════════════════════════════════════════
#  PHASE 7: Install Enterprise Add-ons
# ═══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "══════ PHASE 7: Enterprise Add-ons ══════" -ForegroundColor Cyan
Write-Host ""

# Wait for nodes to be ready
Write-Host "  Waiting 30s for nodes to stabilize..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

Invoke-RemoteSSH -NodeIP $MASTER_IP -StepName "Add-ons" `
    -Command "cd ${REMOTE_DIR} && bash scripts/06-install-addons.sh"

# ═══════════════════════════════════════════════════════════════════════
#  PHASE 8: Verify Cluster
# ═══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "══════ PHASE 8: Cluster Verification ══════" -ForegroundColor Cyan
Write-Host ""

Start-Sleep -Seconds 15

Write-Host "─── Node Status ───" -ForegroundColor White
ssh -o StrictHostKeyChecking=no "${SSH_USER}@${MASTER_IP}" "kubectl get nodes -o wide"

Write-Host ""
Write-Host "─── All Pods ───" -ForegroundColor White
ssh -o StrictHostKeyChecking=no "${SSH_USER}@${MASTER_IP}" "kubectl get pods -A"

Write-Host ""
Write-Host "─── Cluster Info ───" -ForegroundColor White
ssh -o StrictHostKeyChecking=no "${SSH_USER}@${MASTER_IP}" "kubectl cluster-info"

# ═══════════════════════════════════════════════════════════════════════
#  Dashboard Token
# ═══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "══════ Dashboard Access ══════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Dashboard URL: https://${MASTER_IP}:30443" -ForegroundColor Green
Write-Host ""
Write-Host "  Getting admin token..." -ForegroundColor Yellow
ssh -o StrictHostKeyChecking=no "${SSH_USER}@${MASTER_IP}" "kubectl -n kubernetes-dashboard create token dashboard-admin 2>/dev/null || kubectl -n kubernetes-dashboard get secret dashboard-admin-token -o jsonpath='{.data.token}' | base64 -d"

Write-Host ""
Write-Host ""
Write-Host "==================================================" -ForegroundColor Green
Write-Host "  ✓ Enterprise Kubernetes Deployment Complete!"    -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green
Write-Host ""
