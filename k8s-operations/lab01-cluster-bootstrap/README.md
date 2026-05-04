# Lab 1 (P3) — Cluster Bootstrap

## Objectives

- Tear down and recreate the kind cluster with a custom config
- Inspect the kind cluster through the lens of a "real" kubeadm install
- Read the static-Pod manifests on the control-plane Node
- Compare the kind topology with what kubeadm would produce
- Try a kubeadm init `--dry-run` (no actual install)

## Prerequisites

- Pillar 2 complete; the kind cluster `devops-course` is up (or torn down — we'll recreate)
- kind ≥ 0.31, kubectl ≥ 1.35, Docker ≥ 29.4

## Duration

~ 30 minutes

## Context

You've used the kind cluster for all of P2. Today, you peek under the hood: the same K8s components a kubeadm install would create, but inside Docker containers. By the end you should be able to read any kubeadm-bootstrapped cluster's structure.

## Starter Files

```
lab01-cluster-bootstrap/
├── kind-cluster.yaml        # provided — the standard cluster config (same as setup/kind-cluster.yaml)
└── README.md
```

## Instructions

### Step 1 — Inspect the existing cluster (or skip to step 2)

```bash
kind get clusters
kubectl get nodes -o wide
kubectl get pods -n kube-system -o wide
```

Note:
- 3 Nodes (1 CP + 2 workers)
- Control-plane Node has the `node-role.kubernetes.io/control-plane:NoSchedule` taint
- `kube-system` runs apiserver, etcd, scheduler, controller-manager, kube-proxy (DaemonSet), CoreDNS, kindnet (CNI)

### Step 2 — Tear down and recreate

```bash
kind delete cluster --name devops-course
kind get clusters    # empty

cat kind-cluster.yaml
kind create cluster --config kind-cluster.yaml
```

The recreate takes ~60 s. kind logs the steps:
```
✓ Ensuring node image (kindest/node:v1.35.0)
✓ Preparing nodes 📦 📦 📦
✓ Writing configuration 📜
✓ Starting control-plane 🕹️
✓ Installing CNI 🔌
✓ Installing StorageClass 💾
✓ Joining worker nodes 🚜
```

These are exactly the steps a kubeadm install does (one machine at a time instead of three Docker containers).

### Step 3 — Read the control-plane Node from the inside

```bash
docker exec -it devops-course-control-plane bash
```

Inside the Node container:

```bash
# Static Pod manifests — the kubelet starts these directly, before the apiserver is up
ls /etc/kubernetes/manifests/
cat /etc/kubernetes/manifests/kube-apiserver.yaml | head -30

# kubelet config
cat /var/lib/kubelet/config.yaml | head -20

# Container runtime — what's actually running
crictl ps | head -10

# Cluster certificates
ls /etc/kubernetes/pki/ | head -10

exit
```

Static Pods are the bootstrap trick: the apiserver starts before there's anywhere to register Pods. The kubelet reads `/etc/kubernetes/manifests/`, runs the YAMLs as Pods, and the apiserver is the result.

### Step 4 — kubeconfig from inside the cluster

The kubelet has its own kubeconfig:

```bash
docker exec devops-course-control-plane cat /etc/kubernetes/kubelet.conf | head -15
```

This file is what every Node uses to talk back to the apiserver. Compare with your `~/.kube/config`.

### Step 5 — Worker Node join (the kubeadm equivalent)

```bash
# What command would join a new worker?
docker exec devops-course-control-plane kubeadm token create --print-join-command
```

You'll get something like:
```
kubeadm join 192.168.X.X:6443 --token abcdef.0123456789abcdef \
  --discovery-token-ca-cert-hash sha256:e2e1d8f9b3c8...
```

This is the literal command you'd paste into a Node's terminal in a real kubeadm install.

### Step 6 — kubeadm init `--dry-run` (no actual install)

> Skip if you don't have a Linux VM handy — this step is informational.

On a fresh Linux VM with `kubeadm` + `kubelet` installed:

```bash
sudo kubeadm init --dry-run --pod-network-cidr=10.244.0.0/16 2>&1 | head -40
```

`--dry-run` runs the validation steps without modifying anything. You see the certs, the config, the static-Pod manifests it would write — without touching `/etc/kubernetes/`.

### Step 7 — Inspect the existing CNI

kind installs `kindnet` (its own minimal CNI). For production: Calico or Cilium.

```bash
kubectl get daemonset -n kube-system kindnet
kubectl get pod -n kube-system -l app=kindnet -o wide

# Show what kindnet does — read its CNI config
docker exec devops-course-worker cat /etc/cni/net.d/10-kindnet.conflist | head -20
```

A real cluster might have:
```bash
kubectl get daemonset -n kube-system calico-node    # Calico
kubectl get daemonset -n kube-system cilium         # Cilium
```

### Step 8 — Identify the StorageClass and CNI

```bash
kubectl get storageclass
kubectl get pods -n local-path-storage              # local-path-provisioner

kubectl describe node devops-course-worker | head -30
# Look for: Allocatable, System Info (kernel, container runtime version)
```

### Step 9 — Lightweight comparison: what would change?

| Aspect | kind (now) | kubeadm + Calico (production-ish) |
|--------|------------|------------------------------------|
| Nodes | 3 Docker containers | 3+ VMs / bare-metal |
| CNI | kindnet | Calico / Cilium |
| StorageClass | local-path | EBS / PD / Ceph / etc. |
| Ingress | Nothing | Traefik (chapter 03) |
| Monitoring | Nothing | kube-prometheus-stack (chapter 06) |
| HA control plane | 1 CP Node | 3 CP Nodes + load balancer |

The kind cluster is a fair model of what a single-CP kubeadm install gives you, minus the production add-ons. Pillar 3 layers them on.

### Step 10 — Verify the cluster is healthy

```bash
kubectl get nodes
kubectl get pods -A
kubectl wait --for=condition=Ready --all nodes --timeout=60s
```

All Nodes should be `Ready`; all kube-system Pods Running.

The cluster stays up — every other P3 lab assumes it.

## Validation

```bash
[ "$(kubectl get nodes --no-headers | wc -l | tr -d ' ')" = "3" ] && echo "[ok] 3 Nodes Ready"
kubectl get sc standard >/dev/null 2>&1 && echo "[ok] standard SC present"
kubectl get ds -n kube-system kindnet >/dev/null 2>&1 && echo "[ok] kindnet (CNI) running"
kubectl get pods -n kube-system --field-selector=status.phase=Running --no-headers | wc -l
# Expect ≥ 8
```

## Going Further (optional)

- Edit `kind-cluster.yaml` to use 4 worker Nodes. Recreate. Confirm `kubectl get nodes` shows 5 Nodes.
- Try `kind create cluster --image kindest/node:v1.34.0` — different K8s minor. Compare `kubectl get nodes -o wide` between v1.34 and v1.35 clusters.
- Use `--feature-gates=` in the kind config to enable an alpha feature (e.g. `MemoryQoS=true`).
- Read `kubeadm config print init-defaults` to see the full kubeadm init configuration. Compare with kind's hardcoded approach.
- Replace kindnet with Calico: delete kindnet (`kubectl delete ds -n kube-system kindnet`) and apply the Calico manifest. (Hard — only attempt if curious.)
