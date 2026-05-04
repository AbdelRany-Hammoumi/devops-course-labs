# Lab 6 (P3) — Monitoring with kube-prometheus-stack

## Objectives

- Install kube-prometheus-stack via Helm
- Reach the Grafana, Prometheus, and Alertmanager UIs
- Browse pre-built K8s dashboards
- Deploy a small app exposing `/metrics`
- Author a ServiceMonitor and verify the target appears in Prometheus
- Run PromQL queries against the scraped metrics
- Define a PrometheusRule alert and observe it fire

## Prerequisites

- Lab P3-02 completed; the kind cluster is up
- Helm ≥ 4.1
- Patience for the install (~3 minutes; ~8–10 Pods come up)

## Duration

~ 30 minutes

## Context

You'll stand up the canonical K8s observability stack and verify it end-to-end with a sample workload.

## Starter Files

```
lab06-monitoring-stack/
├── 01-app.yaml                    # provided — sample app exposing /metrics
├── 02-servicemonitor.yaml.TODO
├── 03-alert-rule.yaml.TODO
└── README.md
```

## Instructions

### Step 1 — Install the stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --version 65.x.x \
  --set grafana.adminPassword=admin \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false

kubectl rollout status -n monitoring deploy/monitoring-grafana --timeout=180s
kubectl get pods -n monitoring
```

You should see ~10 Pods Running:
- `prometheus-monitoring-...` (the TSDB + scraper)
- `alertmanager-monitoring-...` (alert router)
- `monitoring-grafana-...` (UI)
- `monitoring-kube-prometheus-operator-...`
- `monitoring-kube-state-metrics-...`
- `monitoring-prometheus-node-exporter-...` (1 per Node, DaemonSet)

### Step 2 — Reach the UIs

Open three terminals (or use background port-forwards):

```bash
# Grafana — admin / admin
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80 &
# http://localhost:3000

# Prometheus
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090 &
# http://localhost:9090

# Alertmanager
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-alertmanager 9093:9093 &
# http://localhost:9093
```

In **Grafana** → Dashboards → Browse → "Kubernetes / Compute Resources / Cluster" — see your kind cluster's metrics.

In **Prometheus** → Status → Targets — see all the auto-scraped targets (kubelet, kube-state-metrics, node-exporter, the operator itself, etc).

### Step 3 — Deploy the sample app

`01-app.yaml` (provided):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample
spec:
  replicas: 2
  selector:
    matchLabels: { app: sample }
  template:
    metadata:
      labels: { app: sample }
    spec:
      containers:
        - name: sample
          image: prom/prometheus:v3.0.1
          args:
            - --config.file=/etc/prometheus/prometheus.yml
            - --web.listen-address=:9090
          ports:
            - containerPort: 9090
              name: metrics
---
apiVersion: v1
kind: Service
metadata:
  name: sample
  labels:
    app: sample
spec:
  selector:
    app: sample
  ports:
    - port: 9090
      targetPort: metrics
      name: metrics
```

> The "sample app" here is just Prometheus itself running with default config — easy and exposes `/metrics` like any standard app would. Real apps would expose your business metrics on a similar port.

```bash
kubectl apply -f 01-app.yaml
kubectl wait --for=condition=Available deploy/sample --timeout=60s
kubectl get pod -l app=sample -o wide
```

### Step 4 — Author a ServiceMonitor

Author `02-servicemonitor.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: sample
  labels:
    release: monitoring          # picked up by the operator's selector (chart default)
spec:
  selector:
    matchLabels:
      app: sample
  endpoints:
    - port: metrics
      path: /metrics
      interval: 15s
```

```bash
kubectl apply -f 02-servicemonitor.yaml
kubectl get servicemonitor sample -o yaml
```

Wait ~30 seconds, then in Prometheus UI → Status → Targets → search "sample". You should see `serviceMonitor/default/sample/0` with `STATE: UP`.

### Step 5 — PromQL queries

In Prometheus UI → Graph tab, run:

```promql
# Up status
up{job="sample"}

# Metrics from our sample
prometheus_http_requests_total

# Per-Pod request rate
sum by (pod) (rate(prometheus_http_requests_total[1m]))

# Cluster-wide CPU
sum by (namespace) (rate(container_cpu_usage_seconds_total[5m]))

# Pod restart counts (use kube-state-metrics)
kube_pod_container_status_restarts_total
```

Each query returns a graph or a table — click "Execute" then switch to "Graph" tab to visualize.

### Step 6 — Add a panel to Grafana

In Grafana:

1. **Dashboards → New → New dashboard**
2. **Add visualization**
3. Data source: `Prometheus`
4. Query: `sum by (pod) (rate(prometheus_http_requests_total[1m]))`
5. Title: `sample req/s`
6. **Save dashboard** → name `lab06-custom`

You now have a custom dashboard backed by your scrape data.

### Step 7 — Define an alert

Author `03-alert-rule.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: sample-alerts
  labels:
    release: monitoring
spec:
  groups:
    - name: sample.rules
      rules:
        - alert: SampleAlwaysFiring
          expr: vector(1)            # always 1 → always firing (for the demo)
          for: 30s
          labels:
            severity: warning
            team: lab
          annotations:
            summary: "Lab demo alert (always fires)"
            runbook_url: "https://runbooks.example.com/SampleAlwaysFiring"
```

```bash
kubectl apply -f 03-alert-rule.yaml
sleep 60
```

In Prometheus UI → Alerts → search "Sample" — `SampleAlwaysFiring` should be `FIRING`.

In Alertmanager UI → see the alert in the active list (with default routing).

### Step 8 — Configure a real receiver (optional)

The default Alertmanager config sends to a stub receiver (logs only). For real Slack:

```bash
helm upgrade monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --reuse-values \
  --set "alertmanager.config.receivers[0].name=null"
# (Tweaking AM config via --set is awkward. For real life: a values.yaml file.)
```

For learning: leave the default; see the alert in the Alertmanager UI.

### Step 9 — Cleanup

```bash
kubectl delete -f 03-alert-rule.yaml --ignore-not-found
kubectl delete -f 02-servicemonitor.yaml --ignore-not-found
kubectl delete -f 01-app.yaml --ignore-not-found

# kill port-forwards
kill %1 %2 %3 2>/dev/null

helm uninstall monitoring -n monitoring
kubectl delete namespace monitoring
```

## Validation

```bash
helm list -n monitoring 2>&1 | grep -q monitoring \
  && echo "WARN: stack still installed" \
  || echo "[ok] monitoring gone"
kubectl get servicemonitor sample 2>&1 | grep -q NotFound && echo "[ok] SM gone"
```

## Going Further (optional)

- Trigger a real CPU spike Pod and watch the cluster dashboard's CPU panel. Use `stress` image: `kubectl run cpu-stress --image=progrium/stress -- --cpu 1 --timeout 60s`.
- Author a recording rule (`spec.groups[].rules[]` with `record:` instead of `alert:`). Query the new metric.
- Install `prometheus-adapter` and create an HPA on `prometheus_http_requests_total` (custom-metric scaling).
- Mount a Grafana dashboard via ConfigMap with `grafana_dashboard: "1"` label. Watch it auto-import.
- Hit the Prometheus admin API with `kubectl port-forward + curl /api/v1/series` to enumerate all metric names.
- Read the kube-prometheus-stack default `PrometheusRule` set: `kubectl get prometheusrule -A`. Many production-ready alerts already defined.
