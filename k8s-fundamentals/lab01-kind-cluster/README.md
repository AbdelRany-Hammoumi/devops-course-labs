# Lab 1 — Your First kind Cluster

## Objectives

- Create a 3-node kind cluster (1 control-plane + 2 workers) using the project's standard config
- Inspect the control-plane components and the Nodes
- Deploy a Pod imperatively and observe the path through scheduler → kubelet → containerd
- Inspect the cluster state via the API server (kubectl + raw API calls)
- Tear down the cluster cleanly

## Prerequisites

- Docker Engine ≥ 29.4 running
- `kind` ≥ 0.31 installed (`brew install kind` / [installation guide](https://kind.sigs.k8s.io/docs/user/quick-start/#installation))
- `kubectl` ≥ 1.35 installed (`brew install kubectl` / [installation guide](https://kubernetes.io/docs/tasks/tools/))
- `jq` available (`brew install jq` or apt/dnf equivalent)
- 4 GB free RAM, 8 GB free disk

## Duration

~ 30 minutes

## Context

You will spin up the cluster every other lab in P2/P3/P4 will use. The setup file lives in `setup/kind-cluster.yaml` at the labs repo root and provides a 1 control-plane + 2 worker Node topology with port mappings for ingress (used in later labs).

## Instructions

### Step 1 — Verify your tools

```bash
docker version
kind version          # ≥ 0.31
kubectl version --client    # ≥ 1.35
```

If any tool is missing, install it before proceeding (see Prerequisites).

### Step 2 — Create the cluster

From the labs repo root:

```bash
kind create cluster --config setup/kind-cluster.yaml
```

This takes ~60 seconds. kind:
1. Pulls `kindest/node:v1.35.0` (a Docker image containing a full K8s Node)
2. Starts 3 containers acting as Nodes
3. Bootstraps the control plane (apiserver, etcd, scheduler, controller-manager)
4. Joins the workers
5. Installs CoreDNS and kube-proxy
6. Writes credentials into `~/.kube/config` and switches your context

Verify:

```bash
kind get clusters
kubectl config current-context        # → kind-devops-course
kubectl cluster-info
```

### Step 3 — Inspect the Nodes

```bash
kubectl get nodes
# NAME                          STATUS   ROLES           AGE   VERSION
# devops-course-control-plane   Ready    control-plane   90s   v1.35.0
# devops-course-worker          Ready    <none>          70s   v1.35.0
# devops-course-worker2         Ready    <none>          70s   v1.35.0

kubectl get nodes -o wide
kubectl describe node devops-course-control-plane | head -50
```

Notice in `describe`:
- **Conditions**: `Ready=True`, `MemoryPressure=False`, etc.
- **Capacity / Allocatable**: how much CPU + memory the Node advertises
- **Taints**: control-plane is tainted `node-role.kubernetes.io/control-plane:NoSchedule` (workloads stay off it by default)

### Step 4 — Inspect the control plane Pods

The control plane runs as static Pods inside the control-plane Node:

```bash
kubectl get pods -n kube-system -o wide
# kube-apiserver-devops-course-control-plane          1/1  Running
# kube-controller-manager-devops-course-control-plane 1/1  Running
# etcd-devops-course-control-plane                    1/1  Running
# kube-scheduler-devops-course-control-plane          1/1  Running
# kube-proxy-xxx (one per Node, DaemonSet)
# coredns-xxx (Deployment)
# ...
```

Look at the API server's args:

```bash
kubectl get pod -n kube-system kube-apiserver-devops-course-control-plane -o yaml \
  | grep -A40 'spec:' | head -50
```

You'll see `--etcd-servers=https://127.0.0.1:2379`, the bound port, the cert paths.

### Step 5 — Get a shell on a Node

kind Nodes are Docker containers. Drop into one:

```bash
docker exec -it devops-course-control-plane bash
```

Inside the Node:

```bash
ls /etc/kubernetes/manifests/        # static Pod manifests for the control plane
ps -ef | grep -E 'kubelet|containerd|etcd' | head
crictl ps                            # CRI client — what containerd is running
exit
```

`crictl` is the kubelet's-eye view of containers. Compare with `kubectl get pods -n kube-system`.

### Step 6 — Deploy a Pod and trace the path

```bash
kubectl run hello --image=nginx:1.27-alpine --port=80
kubectl get pod hello -o wide
kubectl describe pod hello | tail -20      # Events show: Scheduled → Pulled → Created → Started
```

The Events section is the chapter's diagram, played out:
- `Scheduled` — the scheduler chose a Node
- `Pulling` / `Pulled` — kubelet asked containerd to fetch the image
- `Created` / `Started` — containerd reported the container running

Hit the Pod via port-forward:

```bash
kubectl port-forward pod/hello 8080:80 &
sleep 1
curl -sI http://localhost:8080
kill %1
```

### Step 7 — Read state from the raw API

```bash
# Open a tunnel to the API server through kubectl
kubectl proxy --port=8001 &
sleep 1

# Pure HTTP/JSON — same data kubectl uses
curl -s http://localhost:8001/api/v1/namespaces/default/pods/hello | jq '.metadata.name, .status.phase, .spec.nodeName'

curl -s http://localhost:8001/api | jq
curl -s http://localhost:8001/apis/apps/v1 | jq '.resources[] | select(.kind=="Deployment")'

kill %1
```

This proves the chapter's claim: kubectl is just a JSON HTTP client.

### Step 8 — Clean up the Pod (keep the cluster)

```bash
kubectl delete pod hello
kubectl get pods
```

The cluster stays. We'll reuse it in lab02.

## Validation

```bash
kind get clusters | grep devops-course
```
Expected: `devops-course` listed.

```bash
kubectl get nodes --no-headers | wc -l
```
Expected: `3`.

```bash
kubectl get pods -n kube-system --field-selector=status.phase=Running --no-headers | wc -l
```
Expected: `≥ 8` (apiserver, controller-manager, scheduler, etcd, 3× kube-proxy, 2× coredns, etc.).

```bash
kubectl get pod hello 2>&1 | grep -q "NotFound" && echo "[ok] test pod cleaned up"
```

## Going Further (optional)

- Add a third worker node to your cluster (edit `setup/kind-cluster.yaml`, recreate). Confirm a `kubectl run` schedules to it.
- Use `kubectl get --raw '/metrics'` against the API server to see Prometheus metrics.
- `kubectl get events --sort-by='.lastTimestamp' -A` — the cluster's audit-style log of state transitions.
- `kubectl auth can-i --list` — print everything your current user can do (interesting on a multi-tenant cluster).
- Inspect a Node's taints: `kubectl get node <name> -o jsonpath='{.spec.taints}'`. Why is the control-plane tainted? Try removing the taint and re-deploying — does scheduling change?
- Tear down completely: `kind delete cluster --name devops-course`. Note: every other P2/P3 lab assumes the cluster exists. Don't tear down between labs unless asked.
