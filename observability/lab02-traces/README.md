# Lab 2 (Observability) — Distributed Tracing with Tempo and OpenTelemetry

## Objectives

- Install **Grafana Tempo** on a kind cluster via Helm and wire it as a Grafana data source.
- Deploy the **Jaeger HotROD** demo app (multi-service, OTel-instrumented) and ship its traces to Tempo over OTLP.
- Read a real trace tree in Grafana Explore — find the slow span, the failed span, the long DB span.
- Run a few **TraceQL** queries.
- Follow the **metric → trace → logs** correlation chain (bonus, requires the Prom + Loki labs already done).

## Prerequisites

- Lab `k8s-operations/lab06-monitoring-stack` completed — Grafana + Prometheus are already running in the `monitoring` namespace.
- (Optional, for the correlation bonus) Lab `k8s-operations/lab07-loki-logs` completed.
- A running **kind** cluster (`kind 0.31.0`, `kindest/node:v1.35.0`) with at least 4 GB free RAM.
- `helm 4.1.3`, `kubectl 1.35`.

## Duration

~ 30 minutes.

## Context

You will install Tempo in monolithic mode (single binary, fine for labs), deploy the **HotROD** demo app from the Jaeger project (a tiny taxi-booking app with 4 internal services, instrumented with OpenTelemetry), and explore the resulting traces in Grafana.

You will NOT write instrumentation code in this lab — that's the next chapter. Here the focus is on the **operator** side: install the backend, point the app at it, read what comes out.

## Instructions

### Step 1 — Install Tempo

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install tempo grafana/tempo \
  --namespace observability --create-namespace \
  --set tempo.storage.trace.backend=local

kubectl rollout status -n observability statefulset/tempo --timeout=180s
kubectl get pods -n observability
# tempo-0   1/1   Running
```

Tempo exposes two ports:

- `4317/tcp` — OTLP gRPC (apps send traces here)
- `3100/tcp` — HTTP API (Grafana queries here)

### Step 2 — Register Tempo as a Grafana data source

```bash
kubectl apply -f manifests/tempo-datasource.yaml
```

The Grafana sidecar (installed in lab06) auto-discovers the ConfigMap thanks to the `grafana_datasource: "1"` label and reloads its config within ~30 s.

Verify in Grafana UI (`kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80`, then visit `http://localhost:3000`):

- Connections → Data sources → `Tempo` is listed.
- Click `Save & test` → expect "Data source connected and ready".

### Step 3 — Deploy the HotROD demo

```bash
kubectl apply -f manifests/hotrod.yaml
kubectl rollout status -n observability deploy/hotrod --timeout=120s
```

The Deployment runs `jaegertracing/example-hotrod` with the OTLP exporter pointed at Tempo:

```text
--otel-exporter=otlp
--otel-exporter-endpoint=http://tempo.observability:4317
--otel-exporter-insecure
```

Expose the HotROD UI:

```bash
kubectl port-forward -n observability svc/hotrod 8080:8080
# open http://localhost:8080
```

### Step 4 — Generate traces

In the HotROD UI, click any of the four customer buttons (`Rachel's Floor`, `Trom Chocolatier`, ...). Each click simulates "book a ride" and triggers an internal request graph: `frontend → customer → driver → route`.

Click a button ~10 times. The page shows latency in ms next to each request.

Alternative: a curl loop (drives traffic without a browser):

```bash
for i in {1..30}; do
  curl -s "http://localhost:8080/dispatch?customer=$((RANDOM % 4 + 123))" > /dev/null
  sleep 0.5
done
```

### Step 5 — Explore traces in Grafana

In Grafana → **Explore** → switch the data source to **Tempo**.

Two ways to find a trace:

**(a) From a trace_id printed in the HotROD UI**:
- In HotROD, each booking shows a `Trace` link with an ID.
- Paste the ID into Grafana Explore's `Trace ID` input → see the trace tree.

**(b) Via TraceQL** (no copy-paste needed):

```text
{ resource.service.name = "frontend" }
```

→ Returns the latest matching traces. Click any row to see the tree.

You should see something like:

```text
frontend          HTTP GET /dispatch         220ms
├── customer      GET /customer              45ms
├── driver        gRPC FindNearest          60ms
│   └── redis     redis::Set                12ms
├── driver        gRPC GetDriver (×10)      40-90ms each
└── route         HTTP GET /route (×10)     20-60ms each
```

Identify:

- The **longest span** — which service?
- Any **error span** (red marker) — what attribute tells you it failed?
- The **fan-out** pattern — `driver.GetDriver` is called 10× in parallel.

### Step 6 — TraceQL queries

Try each of these and read what comes back:

```text
# All HotROD traces
{ resource.service.name =~ "frontend|customer|driver|route" }

# Slow dispatches (> 500ms)
{ resource.service.name = "frontend" && span.http.target = "/dispatch" && duration > 500ms }

# Driver gRPC calls only
{ resource.service.name = "driver" && span.rpc.system = "grpc" }

# Aggregate: how many traces per service in the last 5 min
{ } | count() by (resource.service.name)
```

For each query, note **how many traces** matched and **what you would do next** if you were debugging.

### Step 7 (Bonus) — Three-pillar correlation

Only if you have completed lab06 (Prom) AND lab07 (Loki):

- In Grafana → Explore → Prometheus → query `up{job=~"hotrod.*"}` (or any metric exposed by HotROD).
- Switch data source to Loki → query `{namespace="observability"} |= "trace_id"` → click a log line → if Loki is configured with the `derivedFields` block from lab07, a `Tempo` button appears next to the `trace_id` value.
- Click it → land directly on the matching trace.

If you don't yet have the Loki derived-fields config, that's fine — note what would need to be added.

## Validation

- `kubectl get pods -n observability` shows `tempo-0` and `hotrod-...` both `Running`.
- In Grafana, the **Tempo** data source is connected and returns traces.
- At least one trace shows a tree of `frontend → customer/driver/route` spans.
- A TraceQL query like `{ duration > 500ms }` returns results.
- You can articulate, in one sentence: "In the trace I clicked, the bottleneck was the X span in service Y because it took Zms."

## Going Further

- Switch Tempo from `local` to S3-compatible storage (MinIO running in the cluster). Production patterns require object storage.
- Add the **OpenTelemetry Collector** between HotROD and Tempo — configure tail-sampling (keep all errors + 5% random). See the collector config in the slides.
- Instrument a service you wrote yourself with `opentelemetry-instrument` (auto-instrumentation) and ship to the same Tempo. That's chapter 03 of this pillar.
- Read the Tempo TraceQL docs: [grafana.com/docs/tempo/latest/traceql/](https://grafana.com/docs/tempo/latest/traceql/)
- Read the OpenTelemetry concepts: [opentelemetry.io/docs/concepts/](https://opentelemetry.io/docs/concepts/)

## Cleanup

```bash
kubectl delete -f manifests/
helm uninstall tempo -n observability
kubectl delete namespace observability
```
