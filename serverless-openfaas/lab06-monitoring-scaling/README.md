# Lab 6 (P4) — Monitoring + Auto-Scaling

## Objectives

- Add a ServiceMonitor so the central Prometheus (P3 lab 06) scrapes OpenFaaS
- Query OpenFaaS metrics in Grafana
- Configure scale labels on a function and observe scaling under load
- Author a PrometheusRule alert on function error rate

## Prerequisites

- OpenFaaS installed (lab P4-02)
- kube-prometheus-stack installed (lab P3-06) — Grafana + Prometheus + Alertmanager in `monitoring`
- Local registry running on `:5000`
- `hey` or `wrk` for load testing (optional; `for ... curl` works)

## Duration

~ 25 minutes

## Context

You'll bring OpenFaaS into the cluster's main observability stack and watch it scale.

## Starter Files

```
lab06-monitoring-scaling/
├── 01-servicemonitor.yaml.TODO
├── 02-burner-function/
│   ├── handler.py
│   └── requirements.txt
├── 02-stack.yml.TODO
├── 03-alert-rule.yaml.TODO
└── README.md
```

## Instructions

### Step 1 — ServiceMonitor for OpenFaaS

Author `01-servicemonitor.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: openfaas-gateway
  namespace: monitoring
  labels:
    release: monitoring
spec:
  namespaceSelector:
    matchNames: [openfaas]
  selector:
    matchLabels:
      app: gateway
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
```

```bash
kubectl apply -f 01-servicemonitor.yaml
```

In Prometheus UI (port-forward `monitoring-kube-prometheus-prometheus`) → Status → Targets → search "openfaas". A green target should appear within ~30 seconds.

Run a query:

```promql
gateway_function_invocation_total
```

Empty initially (no functions deployed yet).

### Step 2 — Deploy a "burner" function

The burner sleeps for a configurable time, simulating load.

`02-burner-function/handler.py`:

```python
import os
import time

SLEEP_MS = int(os.environ.get("SLEEP_MS", "200"))


def handle(event, context):
    time.sleep(SLEEP_MS / 1000.0)
    return {"statusCode": 200, "body": f"slept {SLEEP_MS}ms"}
```

`02-burner-function/requirements.txt`: empty.

`02-stack.yml`:

```yaml
version: 1.0
provider:
  name: openfaas
  gateway: http://localhost:8080
functions:
  burner:
    lang: python3-http
    handler: ./02-burner-function
    image: registry:5000/burner:0.1.0
    environment:
      SLEEP_MS: "200"
    labels:
      com.openfaas.scale.min: "1"
      com.openfaas.scale.max: "10"
      com.openfaas.scale.factor: "30"
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 500m
      memory: 256Mi
```

```bash
faas-cli up -f 02-stack.yml
```

### Step 3 — Generate load

```bash
# Sustained moderate load
for i in $(seq 1 200); do
  curl -s http://localhost:8080/function/burner > /dev/null &
done
wait
```

Or with `hey` (more realistic):
```bash
brew install hey 2>/dev/null
hey -z 30s -c 20 http://localhost:8080/function/burner
```

While the load runs, watch:
```bash
kubectl get pods -n openfaas-fn -l faas_function=burner -w
```

Replicas should grow from 1 toward 10 within ~30-60 seconds. After load stops, they shrink back to 1.

### Step 4 — Query metrics

In Prometheus UI:

```promql
# Invocation rate (per second)
sum(rate(gateway_function_invocation_total{function_name="burner"}[1m]))

# Replica count over time
gateway_service_count{function_name="burner"}

# Latency p95
histogram_quantile(0.95,
  sum by (le) (rate(gateway_functions_seconds_bucket{function_name="burner"}[1m])))
```

Switch to Grafana → Explore → Prometheus → run the same queries → "Add to dashboard" for posterity.

### Step 5 — Authoring an alert

Author `03-alert-rule.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: openfaas-burner-alerts
  namespace: monitoring
  labels:
    release: monitoring
spec:
  groups:
    - name: openfaas.burner
      rules:
        - alert: BurnerLatencyHigh
          expr: |
            histogram_quantile(0.95,
              sum by (le, function_name) (rate(gateway_functions_seconds_bucket[2m])))
              {function_name="burner"} > 0.5
          for: 1m
          labels:
            severity: warning
          annotations:
            summary: "burner p95 latency > 500 ms"
            runbook_url: "https://runbooks/example/burner-latency"
```

```bash
kubectl apply -f 03-alert-rule.yaml
```

To trigger it: bump `SLEEP_MS` to 800:

```bash
sed -i.bak 's/SLEEP_MS: "200"/SLEEP_MS: "800"/' 02-stack.yml
faas-cli up -f 02-stack.yml

# Re-run load
hey -z 30s -c 20 http://localhost:8080/function/burner
```

In Prometheus → Alerts: `BurnerLatencyHigh` should go pending → firing within ~1 minute.

### Step 6 — Tweak resource limits

Reduce CPU limit to make latency spike under load:

```yaml
limits:
  cpu: 100m              # tight
  memory: 256Mi
```

```bash
faas-cli up -f 02-stack.yml
hey -z 30s -c 20 http://localhost:8080/function/burner
# Observe p95 latency rise — CPU throttling
```

This shows resource limits in action: too-tight = latency cliff, too-loose = wasted reservation.

### Step 7 — Cleanup

```bash
kubectl delete -f 03-alert-rule.yaml --ignore-not-found
kubectl delete -f 01-servicemonitor.yaml --ignore-not-found
faas-cli remove burner
```

## Validation

```bash
faas-cli list 2>&1 | grep -q burner && echo "WARN: burner still deployed" || echo "[ok] burner gone"
kubectl get servicemonitor -n monitoring openfaas-gateway 2>&1 | grep -q NotFound && echo "[ok] SM gone"
```

## Going Further (optional)

- Import the community OpenFaaS Grafana dashboards (IDs 3434 + 3435) and customize.
- Add a per-function readinessProbe annotation that delays gateway routing until the function is fully warm.
- Write a recording rule that pre-computes invocation rate per function. Use it in dashboards instead of recomputing.
- Configure Alertmanager (P3 lab 06) routing for `severity=warning` to a different receiver than `severity=critical`.
- For OpenFaaS Pro users: enable scale-to-zero on `burner` via `com.openfaas.scale.zero=true` and observe the cold-start tax.
