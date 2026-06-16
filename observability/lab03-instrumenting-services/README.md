# Lab 3 (Observability) — Instrumenting a Python Service End-to-End

## Objectives

- Add **RED metrics** to a starter Flask app using `prometheus_client`.
- Convert the app's logs to **structured JSON** with `request_id` and `trace_id` fields.
- Deploy the app on kind, expose `/metrics`, and wire a **ServiceMonitor** so Prometheus scrapes it.
- Build a **Grafana dashboard** (R / E / D panels) shipped as a ConfigMap.
- Author a **PrometheusRule alert** that fires when the error rate breaches an SLO.

## Prerequisites

- Lab `k8s-operations/lab06-monitoring-stack` completed (kube-prometheus-stack running in `monitoring` namespace).
- (Optional, for trace-context propagation step) Lab `observability/lab02-traces` completed.
- A running **kind** cluster, `docker 29.4.1`, `kubectl 1.35`, `helm 4.1.3`, `python 3.13+` locally (only for testing the starter image).

## Duration

~ 45 minutes.

## Context

You will take the minimal Flask app under [`starter/`](./starter/) — a fake orders service with two endpoints and an intentional ~5% error rate — and turn it into a properly observable production-grade service.

The starter contains all the boilerplate (Flask app, Dockerfile, Kubernetes manifests) but with `# TODO:` markers where you need to add instrumentation. Each TODO has a pointer to the chapter slide that covers it.

## Instructions

### Step 1 — Read the starter (5 min)

```bash
cd starter/
ls
# app.py            <- 4 TODOs, listed at the top of the file
# requirements.txt
# Dockerfile
# manifests/deployment.yaml
# manifests/service.yaml
# manifests/servicemonitor.yaml   <- 1 TODO (the release label)
```

Read `app.py`. Identify the four TODOs. Read the existing endpoint handlers to understand the request flow.

### Step 2 — Add RED metrics (10 min)

In `starter/app.py`, replace the TODO blocks with:

1. **Counter** `http_requests_total{method,route,status}` — incremented in an `@app.after_request` hook.
2. **Histogram** `http_request_duration_seconds{method,route}` — observed in the same hook (use `time.perf_counter()` recorded in `@app.before_request`).
3. **`/metrics` endpoint** — returns `generate_latest()` with the right `CONTENT_TYPE_LATEST` mimetype.

Use `route = request.endpoint` (NOT `request.path`) — see the chapter slide on label hygiene to understand why.

Reasonable histogram buckets for an HTTP API:

```python
buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10)
```

### Step 3 — Switch to structured JSON logs (5 min)

Replace the existing `print(...)` calls with a structured logger:

```python
import logging
from pythonjsonlogger import jsonlogger
handler = logging.StreamHandler()
handler.setFormatter(jsonlogger.JsonFormatter("%(asctime)s %(levelname)s %(name)s %(message)s"))
log = logging.getLogger("orders")
log.addHandler(handler)
log.setLevel("INFO")
```

Log every request with at least these fields: `route`, `status`, `elapsed_ms`, `request_id`. Read the incoming `X-Request-ID` header; generate one if it's missing.

### Step 4 — Build and load the image into kind (5 min)

```bash
docker build -t orders:lab03 ./starter
kind load docker-image orders:lab03
```

If your kind cluster name is non-default:

```bash
kind load docker-image orders:lab03 --name <cluster-name>
```

### Step 5 — Deploy + fix the ServiceMonitor (5 min)

```bash
kubectl create namespace orders
kubectl apply -f starter/manifests/ -n orders
kubectl rollout status -n orders deploy/orders --timeout=60s
```

The deployment will start, but Prometheus will NOT scrape it yet. Open `starter/manifests/servicemonitor.yaml` — find the TODO comment and add the right label so the Prometheus Operator picks it up. (Hint: check what label the operator uses by default — chapter `k8s-operations/06`.)

Reapply:

```bash
kubectl apply -f starter/manifests/servicemonitor.yaml -n orders
```

Verify in the Prometheus UI:

```bash
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
# http://localhost:9090 → Status → Targets → search "orders"
# Expected: 1 endpoint UP
```

### Step 6 — Drive traffic and inspect metrics (5 min)

```bash
kubectl port-forward -n orders svc/orders 8080:80 &

# 100 mixed requests
for i in {1..100}; do
  curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:8080/orders"
done | sort | uniq -c
# Expect ~95 "200" and ~5 "500" (synthetic 5% error rate)
```

In the Prometheus UI, query:

```text
sum by (status) (rate(http_requests_total{namespace="orders"}[1m]))
histogram_quantile(0.99, sum by (le,route) (rate(http_request_duration_seconds_bucket{namespace="orders"}[5m])))
```

You should see counters incrementing in real time.

> **Why `namespace="orders"` and not `app="orders"`?** Your app emits only the labels you
> coded (`method`, `route`, `status`) — it does **not** emit an `app` label. When Prometheus
> scrapes via a ServiceMonitor it adds *target* labels like `namespace`, `service`, `pod`,
> `job` — but **not** the Service's selector labels (those need `spec.targetLabels` on the
> ServiceMonitor). `namespace` is always present, so filtering on `namespace="orders"` works
> out of the box. (Bonus: add `targetLabels: [app]` to your ServiceMonitor and `app="orders"`
> starts working too.)

### Step 7 — Build a Grafana dashboard as ConfigMap (5 min)

In the Grafana UI (lab06 port-forward), build a simple dashboard with three panels:

- **R** — `sum by (route) (rate(http_requests_total{namespace="orders"}[5m]))`
- **E** — `sum by (route) (rate(http_requests_total{namespace="orders", status=~"5.."}[5m])) / sum by (route) (rate(http_requests_total{namespace="orders"}[5m]))`
- **D** — `histogram_quantile(0.99, sum by (le,route) (rate(http_request_duration_seconds_bucket{namespace="orders"}[5m])))`

Then **export** the dashboard JSON: `Share` → `Export` → `Save to file`.

Wrap it in a ConfigMap and apply:

```bash
kubectl create configmap orders-dashboard \
  --from-file=orders.json=./my-exported-dashboard.json \
  -n monitoring \
  --dry-run=client -o yaml | \
  yq eval '.metadata.labels.grafana_dashboard = "1"' - | \
  kubectl apply -f -
```

Within ~30 s, the dashboard reappears in Grafana — now from disk.

### Step 8 — Author an SLO alert (5 min)

Create `starter/manifests/alerts.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: orders-slo
  labels:
    release: monitoring        # same label trick as the ServiceMonitor
spec:
  groups:
    - name: orders.slo
      rules:
        - alert: OrdersHighErrorRate
          expr: |
            sum(rate(http_requests_total{namespace="orders", status=~"5.."}[5m]))
              /
            sum(rate(http_requests_total{namespace="orders"}[5m])) > 0.03
          for: 2m
          labels: { severity: critical }
          annotations:
            summary: "orders: error rate > 3% for 2 min"
            runbook_url: "https://example.com/runbook/orders-high-error-rate"
```

```bash
kubectl apply -f starter/manifests/alerts.yaml -n orders
```

Wait 2 minutes (the `for: 2m` window must elapse) — given the 5% synthetic error rate, the alert should transition `Pending` → `Firing`. Verify in the Prometheus UI: `Alerts` tab.

## Validation

You pass the lab if:

- `/metrics` on the deployed Pod returns Prometheus-format metrics including `http_requests_total` and `http_request_duration_seconds_bucket`.
- The Prometheus Targets page shows the `orders` endpoint as `UP`.
- Your Grafana dashboard renders R / E / D panels with live data.
- `OrdersHighErrorRate` is `Firing` after ~2 minutes of traffic.
- Log lines from the Pod appear in Loki (if lab07 is done) and are queryable as JSON via `{namespace="orders"} | json | request_id != ""`.

## Going Further

- **Add a business KPI metric** — `orders_placed_total{currency}` Counter, incremented in the success path of `POST /orders`. Add it to your dashboard.
- **Wire trace context** — instrument the app with OpenTelemetry auto-instrumentation (`opentelemetry-instrument flask app:app`), point at the Tempo from lab02, and add the `trace_id` field to every log line. Click from a Grafana panel exemplar straight to a trace.
- **Compute an error budget** — `1 − slo_target` as a Grafana single-stat panel that counts down through the month. See the SRE book chapter on error budgets.
- **Add USE metrics** for the connection pool / queue if your app uses one — `db_connections_active`, `db_connection_wait_seconds_bucket`.
- **Repeat the exercise in Go or Node** — same patterns, different SDK. The Prometheus client API is consistent across languages.

## Cleanup

```bash
kubectl delete namespace orders
kubectl delete configmap orders-dashboard -n monitoring
```
