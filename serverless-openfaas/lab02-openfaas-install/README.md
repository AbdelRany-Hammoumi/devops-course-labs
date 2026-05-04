# Lab 2 (P4) — OpenFaaS Install

## Objectives

- Install OpenFaaS via Helm with explicit basic-auth
- Login with `faas-cli`
- Deploy `figlet` from the function store
- Invoke it synchronously and asynchronously
- Reach the OpenFaaS UI and tour the Functions list

## Prerequisites

- Lab P3-02 completed; the kind cluster is up
- Helm ≥ 4.1, kubectl ≥ 1.35
- `faas-cli` ≥ 0.18 (`brew install faas-cli` or [installation guide](https://docs.openfaas.com/cli/install/))

## Duration

~ 25 minutes

## Context

You'll bring up the FaaS control plane on your existing kind cluster. By the end you'll have a function deployed and reachable.

## Instructions

### Step 1 — Create namespaces and credentials

```bash
helm repo add openfaas https://openfaas.github.io/faas-netes/
helm repo update

kubectl create ns openfaas
kubectl create ns openfaas-fn

PASSWORD=$(head -c 12 /dev/urandom | shasum | cut -d' ' -f1)
kubectl -n openfaas create secret generic basic-auth \
  --from-literal=basic-auth-user=admin \
  --from-literal=basic-auth-password="$PASSWORD"
echo "OpenFaaS admin password: $PASSWORD"
# SAVE THIS — you'll need it for login
```

### Step 2 — Install OpenFaaS

```bash
helm install openfaas openfaas/openfaas \
  --namespace openfaas \
  --version 14.x.x \
  --set functionNamespace=openfaas-fn \
  --set generateBasicAuth=false

kubectl rollout status -n openfaas deploy/gateway --timeout=180s
kubectl get pods -n openfaas
```

You should see ~6-7 Pods Running (gateway, alertmanager, basic-auth-plugin, nats, prometheus, queue-worker).

### Step 3 — Port-forward and login

```bash
kubectl port-forward -n openfaas svc/gateway 8080:8080 &
sleep 2

echo "$PASSWORD" | faas-cli login \
  --gateway http://localhost:8080 \
  --username admin --password-stdin
# Calling the OpenFaaS server to validate the credentials...
# WARNING! Communication is not secure, please consider using HTTPS. Letsencrypt.org offers free SSL/TLS certificates.
# credentials saved for admin http://localhost:8080
```

Verify:

```bash
faas-cli list
# Function   Invocations   Replicas
# (empty for now)
```

### Step 4 — Deploy figlet from the store

```bash
faas-cli store list | head -10
# NAME                  DESCRIPTION
# nodeinfo              Get info about the underlying node
# figlet                Generate ASCII logos with the figlet CLI
# ...

faas-cli store deploy figlet

# Wait for the Pod
kubectl get pods -n openfaas-fn -l faas_function=figlet
sleep 5

faas-cli list
# Function   Invocations   Replicas
# figlet     0             1
```

### Step 5 — Invoke synchronously

```bash
echo "Hello OpenFaaS" | faas-cli invoke figlet
#  _   _      _ _         ___                   _____ _    _    ____
# | | | | ___| | | ___   / _ \ _ __   ___ _ __ |  ___|  __|  __/ ___|
# ...

# Or via curl
curl -d "lab02 ok" http://localhost:8080/function/figlet

# Verify metrics updated
faas-cli list
# figlet   2   1            ← invocation count
```

### Step 6 — Invoke asynchronously

```bash
curl -i -d "async hello" http://localhost:8080/async-function/figlet
# HTTP/1.1 202 Accepted
# X-Call-Id: <uuid>
# (empty body — fire-and-forget)
```

Watch the queue worker process it:

```bash
kubectl logs -n openfaas -l app=queue-worker --tail=10
# ... [#1] Received on [faas-request]: 'subject:..., reply:..., data:[11]'
# ... Status: 200 (...)
```

### Step 7 — Tour the UI

Open http://localhost:8080 in a browser.
- Username: `admin`
- Password: from step 1

What to look at:
- **Functions list** — figlet shows up
- Click figlet → see invocations, logs, replicas
- Use the "Invoke" panel: paste text, see the response

### Step 8 — Inspect the underlying K8s resources

```bash
kubectl get all -n openfaas-fn
# deployment.apps/figlet      1/1
# replicaset.apps/figlet-...  1/1
# pod/figlet-...              1/1
# service/figlet              ClusterIP
```

A function = a Deployment + Service. No CRDs, no operator. Standard K8s.

```bash
kubectl describe deploy -n openfaas-fn figlet | head -30
# Image:          ghcr.io/openfaas/figlet:latest
# Port:           8080
# Liveness probe: /_/health  (handled by the OpenFaaS watchdog)
# Readiness probe: /_/ready
```

### Step 9 — Cleanup

```bash
faas-cli remove figlet
kubectl get all -n openfaas-fn      # empty

# Logout (clears ~/.openfaas/config.yml)
faas-cli logout --gateway http://localhost:8080

# kill port-forwards
pkill -f "kubectl port-forward" 2>/dev/null

# Keep OpenFaaS installed for ch03 onwards
# (If you want to fully tear down: helm uninstall openfaas -n openfaas; kubectl delete ns openfaas openfaas-fn)
```

## Validation

```bash
helm list -n openfaas | grep -q openfaas && echo "[ok] OpenFaaS installed (keep for next labs)"
kubectl get pods -n openfaas-fn 2>&1 | head -3
```

## Going Further (optional)

- Deploy 3 more functions from the store. Compare cold-start times.
- Set up a Traefik IngressRoute (lab P3-03) to expose the gateway at `faas.localtest.me`. Login through that hostname.
- Read OpenFaaS metrics in your Grafana (P3 lab 06): the gateway exposes `gateway_function_invocation_total`. Query it.
- Set up Prometheus scraping for OpenFaaS by adding a ServiceMonitor selecting the gateway and prometheus Services.
- Tweak `gateway.upstreamTimeout` via `helm upgrade` to allow longer function timeouts.
- Browse the public Function Store JSON: https://github.com/openfaas/store/blob/master/store.json
