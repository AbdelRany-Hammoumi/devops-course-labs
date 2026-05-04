# Lab 4 (P3) — MetalLB on kind

## Objectives

- Install MetalLB via Helm
- Discover the kind Docker network's subnet and pick an unused range
- Configure an `IPAddressPool` + `L2Advertisement`
- Deploy a `LoadBalancer` Service and watch the EXTERNAL-IP get assigned
- Reach the LB IP from a Docker container on the same network

## Prerequisites

- Lab P3-02 completed; the kind cluster is up
- Helm ≥ 4.1
- The Traefik install from lab 03 can stay or be removed — irrelevant to this lab

## Duration

~ 15 minutes

## Context

You'll close the `EXTERNAL-IP <pending>` gap on a kind cluster. The pattern is identical on bare metal — only the IP range source changes.

## Starter Files

```
lab04-metallb/
├── 01-pool.yaml.TODO
└── README.md
```

## Instructions

### Step 1 — Install MetalLB

```bash
helm repo add metallb https://metallb.github.io/metallb
helm repo update

helm install metallb metallb/metallb \
  --namespace metallb-system --create-namespace \
  --version 0.14.x

kubectl rollout status -n metallb-system deploy/metallb-controller --timeout=120s
kubectl get pods -n metallb-system
# 1 controller + 3 speakers (one per Node — DaemonSet)
```

Verify the CRDs are installed:

```bash
kubectl get crd | grep metallb
# bgppeers.metallb.io
# ipaddresspools.metallb.io
# l2advertisements.metallb.io
# bgpadvertisements.metallb.io
# bfdprofiles.metallb.io
# communities.metallb.io
```

### Step 2 — Find the kind Docker network subnet

```bash
docker network inspect kind \
  -f '{{ (index .IPAM.Config 0).Subnet }}'
# 172.18.0.0/16     ← typical
```

The Nodes have IPs at the low end (172.18.0.2..0.5). Pick a high range that won't collide with anything else:

```bash
# Recommended: 172.18.255.200-172.18.255.250 (well outside the Node + DHCP range)
```

### Step 3 — Configure the IP pool

Author `01-pool.yaml`:

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lab-pool
  namespace: metallb-system
spec:
  addresses:
    - 172.18.255.200-172.18.255.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: lab-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - lab-pool
```

```bash
kubectl apply -f 01-pool.yaml
kubectl get ipaddresspool,l2advertisement -n metallb-system
```

### Step 4 — Create a LoadBalancer Service

```bash
kubectl create deployment web --image=nginx:1.27-alpine --replicas=2
kubectl expose deployment web --type=LoadBalancer --port=80

kubectl get svc web -w
# Watch EXTERNAL-IP transition from <pending> to 172.18.255.200
# Ctrl-C when assigned
```

```bash
kubectl describe svc web | grep -A2 -i events
# Should show: AssignedIP   ipv4 = "172.18.255.200..."
```

### Step 5 — Reach the LB IP

The LB IP is on the kind Docker network, not your host. Reach it from a Docker container on the same network:

```bash
LB_IP=$(kubectl get svc web -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "LB IP: $LB_IP"

docker run --rm --network kind alpine:3.20 wget -qO- "http://$LB_IP/" | head -3
# <!DOCTYPE html>
# <html>
# <head>
```

### Step 6 — Allocate a second LB IP and observe the pool

```bash
kubectl create deployment api --image=hashicorp/http-echo:1.0 -- -text="hello api"
kubectl expose deployment api --type=LoadBalancer --port=80 --target-port=5678

kubectl get svc
# Both web and api have EXTERNAL-IPs — different addresses from the pool
```

Try to allocate more than the pool can provide (it has 51 IPs; create lots of services for fun):

```bash
for i in $(seq 1 5); do
  kubectl create deployment "test$i" --image=nginx:1.27-alpine --replicas=1
  kubectl expose deployment "test$i" --type=LoadBalancer --port=80
done

kubectl get svc | grep LoadBalancer
```

All should bind successfully. To exhaust the pool you'd need to create > 51 LBs.

### Step 7 — Cleanup

```bash
kubectl delete deployment web api test1 test2 test3 test4 test5 --ignore-not-found
kubectl delete svc web api test1 test2 test3 test4 test5 --ignore-not-found

kubectl delete -f 01-pool.yaml
helm uninstall metallb -n metallb-system
kubectl delete namespace metallb-system
```

## Validation

```bash
kubectl get svc -A | grep -q LoadBalancer && echo "WARN: LB svc lingers" || echo "[ok] no LB svc"
helm list -n metallb-system 2>&1 | grep -q metallb \
  && echo "WARN: metallb still installed" \
  || echo "[ok] metallb gone"
```

## Going Further (optional)

- Add a second `IPAddressPool` and use the `metallb.io/address-pool` annotation on a Service to pick which pool to draw from.
- Patch the L2Advertisement with `nodeSelectors:` to restrict which Nodes can announce the IPs.
- Set `metallb.io/loadBalancerIPs` annotation on a Service to request a specific IP from the pool.
- Read the Cilium docs on LB IPAM and compare the YAML — same pattern, different controller.
- Try `metallb.io/address-pool: nonexistent` on a Service — what status / event does it get?
