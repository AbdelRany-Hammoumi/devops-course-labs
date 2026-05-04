# Lab 7 (P3) — Centralized Logs with Loki

## Objectives

- Install the loki-stack (Loki + Promtail) via Helm
- Wire Loki as a Grafana data source (alongside Prometheus from lab 06)
- Query logs with LogQL from Grafana Explore
- Generate log lines from a sample app and find them in Loki
- Author a log-based alert via PrometheusRule (fed by recording-from-Loki) — or via Loki Ruler

## Prerequisites

- Lab P3-06 completed; the kube-prometheus-stack is installed in `monitoring` namespace
- Helm ≥ 4.1
- ~1 GB free RAM for Loki + Promtail

## Duration

~ 25 minutes

## Context

You'll add the logs pillar to the cluster's observability. By the end you'll be able to switch from a metric spike in Grafana to the log lines that caused it, in one click.

## Starter Files

```
lab07-loki-logs/
├── 01-loki-values.yaml         # provided — Helm values for loki-stack
├── 02-noisy-app.yaml.TODO      # an app that emits varied log lines
└── README.md
```

## Instructions

### Step 1 — Install loki-stack

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install logging grafana/loki-stack \
  --namespace logging --create-namespace \
  --version 2.x.x \
  -f 01-loki-values.yaml

kubectl rollout status -n logging statefulset/logging-loki --timeout=120s
kubectl get pods -n logging
# logging-loki-0                  1/1   Running    (the Loki single-binary)
# logging-promtail-aaa-bbb        1/1   Running    (one per Node)
# logging-promtail-ccc-ddd        1/1   Running
# logging-promtail-eee-fff        1/1   Running
```

Verify Loki accepts writes:

```bash
kubectl port-forward -n logging svc/logging-loki 3100:3100 &
sleep 1
curl -s "http://localhost:3100/loki/api/v1/labels" | head
# Should return JSON with: namespace, pod, container, app, ...
kill %1
```

### Step 2 — Add Loki as a Grafana data source

Patch the existing Grafana via the chart values. Or via the UI for speed:

In Grafana (port-forward as in lab 06):
1. Connections → Data sources → Add new
2. Pick **Loki**
3. URL: `http://logging-loki.logging.svc.cluster.local:3100`
4. Click **Save & test**. Expect: "Data source connected and labels found."

### Step 3 — Deploy a noisy app

Author `02-noisy-app.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: noisy
  labels: { app: noisy }
spec:
  replicas: 1
  selector:
    matchLabels: { app: noisy }
  template:
    metadata:
      labels: { app: noisy }
    spec:
      containers:
        - name: noisy
          image: busybox:1.37
          command:
            - sh
            - -c
            - |
              i=0
              while :; do
                i=$((i+1))
                if [ $((i % 7)) -eq 0 ]; then
                  echo "{\"level\":\"error\",\"msg\":\"db timeout\",\"i\":$i}"
                elif [ $((i % 3)) -eq 0 ]; then
                  echo "{\"level\":\"warn\",\"msg\":\"cache miss\",\"i\":$i}"
                else
                  echo "{\"level\":\"info\",\"msg\":\"request handled\",\"i\":$i}"
                fi
                sleep 1
              done
```

```bash
kubectl apply -f 02-noisy-app.yaml
kubectl wait --for=condition=Available deploy/noisy --timeout=60s
kubectl logs -l app=noisy --tail=10
```

You should see structured JSON log lines mixing info / warn / error levels.

### Step 4 — Query logs via Grafana Explore

In Grafana → **Explore** (compass icon):
1. Pick the **Loki** data source
2. Type a query and Run:

```logql
{app="noisy"}
```

You'll see a histogram + recent log lines. Click any line to expand the structured fields.

Try filters:

```logql
# Just the errors
{app="noisy"} |= "error"

# JSON-parse and filter on level
{app="noisy"} | json | level="warn"

# Aggregate: error rate per minute
sum(rate({app="noisy"} |= "error" [1m]))

# Compare with all log lines
sum(rate({app="noisy"}[1m]))
```

The aggregation queries return time-series metrics derived from logs — chartable like Prometheus data.

### Step 5 — Pivot from metrics to logs

In Grafana Explore (Prometheus data source):

```promql
sum by (pod) (rate(prometheus_http_requests_total[1m]))
```

Hover the chart → "Show context menu" → "Log for this metric" (or use the **Split** view to put both side by side).

For real apps with both Prometheus metrics AND Loki logs, the pivot is one click.

### Step 6 — Author a log-based alert

Author a PrometheusRule that uses LogQL via the Loki Ruler is one way. The simpler portable approach: use a **recording rule** that queries Loki and emits a metric, then alert on the metric.

For this lab, use a Loki AlertingRule directly:

```yaml
apiVersion: loki.grafana.com/v1
kind: AlertingRule
metadata:
  name: noisy-errors
  namespace: logging
spec:
  tenantID: ""
  groups:
    - name: noisy.rules
      interval: 30s
      rules:
        - alert: NoisyErrorRateHigh
          expr: |
            sum(rate({app="noisy"} |= "error" [1m])) > 0.1
          for: 1m
          labels:
            severity: warning
          annotations:
            summary: "noisy app has > 1 error/10s"
```

> Note: the `loki.grafana.com/v1 AlertingRule` CRD requires the Loki Ruler enabled in values. With the loki-stack chart in this lab, the Ruler is bundled but not always enabled. For learning, just verify the LogQL expression in Grafana Explore — that's enough to internalize the pattern.

```bash
# Verify the expression in Grafana → Explore (Loki):
sum(rate({app="noisy"} |= "error" [1m]))
# > 0.1 most of the time given our app's pattern (every 7th line is an error)
```

### Step 7 — Cleanup

```bash
kubectl delete -f 02-noisy-app.yaml --ignore-not-found
helm uninstall logging -n logging
kubectl delete namespace logging
```

If you don't want to keep monitoring stack either:

```bash
helm uninstall monitoring -n monitoring
kubectl delete namespace monitoring
```

## Validation

```bash
helm list -n logging 2>&1 | grep -q logging \
  && echo "WARN: loki still installed" \
  || echo "[ok] loki gone"
kubectl get deploy noisy 2>&1 | grep -q NotFound && echo "[ok] noisy app gone"
```

## Going Further (optional)

- Switch the agent from Promtail to **Grafana Alloy**: `helm install alloy grafana/alloy ...`. Compare configs.
- Read kubelet logs from Loki: they're already shipped (Promtail picks up `/var/log/`).
- Author a Grafana dashboard with a metric panel + a logs panel for `noisy`. Set the same time range.
- Configure S3-compatible storage: stand up MinIO + reconfigure Loki via values.
- Use `| pattern` in LogQL: extract fields from non-JSON logs (e.g. `<_> level=<level> msg=<_>`).
- Look at `kube-prometheus-stack` Grafana dashboards: many have a "logs" sub-panel that auto-queries Loki when set up.
