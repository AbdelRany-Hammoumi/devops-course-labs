#!/usr/bin/env bash
# Lab 1 (P2) — Your First kind Cluster
# Replace each TODO with the right command, then run blocks manually.

set -euo pipefail

# Step 1 — Verify tools
# TODO: docker version ; kind version ; kubectl version --client

# Step 2 — Create the cluster from the standard config
# TODO: kind create cluster --config setup/kind-cluster.yaml
# TODO: kind get clusters
# TODO: kubectl cluster-info

# Step 3 — Inspect Nodes
# TODO: kubectl get nodes -o wide
# TODO: kubectl describe node <control-plane-name>

# Step 4 — Inspect control-plane Pods
# TODO: kubectl get pods -n kube-system -o wide
# TODO: read kube-apiserver Pod spec with kubectl get -o yaml

# Step 5 — Shell into a Node, see crictl ps and the static manifests
# TODO: docker exec -it devops-course-control-plane bash
# Inside: ls /etc/kubernetes/manifests/ ; crictl ps ; exit

# Step 6 — Deploy a Pod, trace events
# TODO: kubectl run hello --image=nginx:1.27-alpine --port=80
# TODO: kubectl describe pod hello | tail -20

# Step 7 — Talk to the raw API
# TODO: kubectl proxy --port=8001 &
# TODO: curl /api/v1/namespaces/default/pods/hello

# Step 8 — Cleanup the Pod (keep the cluster running for next labs)
# TODO: kubectl delete pod hello
