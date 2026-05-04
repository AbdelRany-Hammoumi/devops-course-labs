# Lab 4 — Services and Discovery

## Objectives

- Deploy a 3-replica web Deployment and front it with a ClusterIP Service
- Resolve the Service by DNS from another Pod
- Observe EndpointSlice updates as Pods are added/removed
- Expose the same Deployment with NodePort
- Create a Headless Service and observe per-Pod DNS resolution
- Diagnose a "Service has no Endpoints" misconfiguration

## Prerequisites

- Lab 03 completed; the kind cluster `devops-course` is up
- No leftover `web` Deployment from previous labs (`kubectl delete deployment web --ignore-not-found`)

## Duration

~ 30 minutes

## Context

Services are the contract between Pods. Every microservice setup on K8s relies on them. This lab walks through every Service flavor with a real Deployment behind each.

## Starter Files

```
lab04-services-discovery/
├── 01-deployment.yaml         # provided — same as lab03 baseline
├── 02-clusterip.yaml.TODO
├── 03-nodeport.yaml.TODO
├── 04-headless.yaml.TODO
└── README.md
```

## Instructions

### Step 1 — Deploy the web Deployment

Apply the provided `01-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  labels: { app: web }
spec:
  replicas: 3
  selector:
    matchLabels: { app: web }
  template:
    metadata:
      labels: { app: web }
    spec:
      containers:
        - name: web
          image: nginx:1.27-alpine
          ports: [{ containerPort: 80 }]
          readinessProbe:
            httpGet: { path: /, port: 80 }
            periodSeconds: 5
```

```bash
kubectl apply -f 01-deployment.yaml
kubectl wait --for=condition=Available --timeout=60s deployment/web
kubectl get pods -l app=web -o wide
```

### Step 2 — Author a ClusterIP Service

Author `02-clusterip.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  type: ClusterIP
  selector:
    app: web
  ports:
    - name: http
      port: 80
      targetPort: 80
```

```bash
kubectl apply -f 02-clusterip.yaml
kubectl get svc web
# NAME   TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
# web    ClusterIP   10.96.X.Y      <none>        80/TCP    3s
```

Inspect the EndpointSlice:

```bash
kubectl get endpointslices -l kubernetes.io/service-name=web
kubectl describe endpointslice -l kubernetes.io/service-name=web | head -30
```

You should see 3 endpoint entries — one per Pod, all `Ready=true`.

### Step 3 — Reach the Service by DNS

Run a one-shot client Pod:

```bash
kubectl run dnstest --rm -it --image=alpine:3.20 -- sh
```

Inside:

```sh
# Short name (works because we're in the same namespace)
wget -qO- http://web/ | head -5

# Fully qualified
nslookup web.default.svc.cluster.local

# Hit the ClusterIP directly
CIP=$(getent hosts web | awk '{print $1}'); echo "$CIP"; wget -qO- "http://$CIP/" | head -3

exit
```

The DNS lookup returns the ClusterIP. The wget goes through the ClusterIP, which kube-proxy NATs to one of the 3 Pods.

### Step 4 — Watch EndpointSlices update during scale

In one terminal, watch:

```bash
kubectl get endpointslices -l kubernetes.io/service-name=web -w
```

In another terminal:

```bash
kubectl scale deployment/web --replicas=5
# Two more endpoints appear in the slice

kubectl scale deployment/web --replicas=2
# Three endpoints disappear
```

Then trigger a rolling update:

```bash
kubectl set image deployment/web web=nginx:1.28-alpine
# Watch endpoints flip as new Pods come Ready and old Pods are evicted
```

Stop the watcher (Ctrl-C) when the rollout finishes.

### Step 5 — NodePort

Author `03-nodeport.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-np
spec:
  type: NodePort
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080
```

```bash
kubectl apply -f 03-nodeport.yaml
kubectl get svc web-np
# NAME     TYPE       CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE
# web-np   NodePort   10.96.X.Z     <none>        80:30080/TCP   3s
```

The kind cluster's nodes are Docker containers. Reach the NodePort by:

```bash
# Find a Node's container IP
docker inspect devops-course-worker -f '{{ .NetworkSettings.Networks.kind.IPAddress }}'
NODE_IP=$(docker inspect devops-course-worker -f '{{ .NetworkSettings.Networks.kind.IPAddress }}')
docker run --rm --network kind alpine:3.20 wget -qO- "http://$NODE_IP:30080/" | head -3
```

(On a real Node, this would be the Node's public IP. Inside kind, we hop through the Docker `kind` network.)

### Step 6 — Headless Service

Author `04-headless.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-headless
spec:
  clusterIP: None                # ← headless
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 80
```

```bash
kubectl apply -f 04-headless.yaml
kubectl get svc web-headless
# CLUSTER-IP shows "None"
```

Resolve from a client Pod:

```bash
kubectl run dnstest --rm -it --image=alpine:3.20 -- sh
```

Inside:

```sh
nslookup web-headless
# Server:  10.96.0.10
# Address: 10.96.0.10:53
# Name: web-headless.default.svc.cluster.local
# Address: 10.244.X.X    ← Pod 1
# Address: 10.244.Y.Y    ← Pod 2
# Address: 10.244.Z.Z    ← Pod N

# Multiple A records — one per Ready Pod, no virtual IP
exit
```

This is what StatefulSets use for stable per-Pod addressing.

### Step 7 — A broken Service (debug exercise)

Apply this intentionally-broken Service:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: broken
spec:
  selector:
    app: web-typo            # ← no Pod has this label
  ports:
    - port: 80
EOF
```

```bash
kubectl get svc broken
# CLUSTER-IP allocated as expected

kubectl describe svc broken
# Endpoints:  <none>      ← red flag
```

```bash
kubectl get endpointslices -l kubernetes.io/service-name=broken
# No endpoints (or zero-endpoint slice)
```

Diagnosis: selector doesn't match any Ready Pod's labels. Fix would be to change `app: web-typo` to `app: web` (or fix the Pod labels).

Clean up:

```bash
kubectl delete svc broken
```

### Step 8 — Clean up

```bash
kubectl delete svc web web-np web-headless
kubectl delete deployment web
kubectl get svc,deploy,po -l app=web 2>&1 | head
```

The kind cluster stays up.

## Validation

```bash
kubectl get svc web web-np web-headless 2>&1 | grep -q "NotFound" && echo "[ok] Services gone"
kubectl get deployment web 2>&1 | grep -q "NotFound" && echo "[ok] Deployment gone"
```

## Going Further (optional)

- Add `sessionAffinity: ClientIP` to the ClusterIP Service. Verify with multiple curls from the same client Pod that you keep hitting the same backend (nginx hostname header trick).
- Author a multi-port Service (port 80 + a fake metrics port 9090). Hit each port individually.
- Use `kubectl run client --image=nicolaka/netshoot --rm -it -- bash` to get a debug Pod with `dig`, `nc`, `tcpdump`. Inspect SRV records: `dig SRV _http._tcp.web.default.svc.cluster.local`.
- Try an `ExternalName` Service pointing at `example.com`. From a Pod, resolve it and confirm the CNAME chain.
- Deploy a second Deployment + Service in a different namespace. Reach it from `default` using the FQDN form.
