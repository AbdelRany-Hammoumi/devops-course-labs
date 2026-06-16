# Challenge — Build Your Observability Stack (Full-Day Hands-On)

> **Format**: pairs (teams of 2). If the headcount is odd, one team of 3.
> You are a dev + platform duo: by the end of the day your app runs on a cluster
> that watches it, and you demo the whole thing live. Everything you need is in the
> lab READMEs linked below — work through them at your own pace.

---

## The mission

A fictional company is about to ship a service to Kubernetes and is flying blind:
no metrics, no dashboards, no alerts. **Your duo's job: ship the app AND the eyes that watch it.**

You split the work into two roles:

| Role | Owner | What they build | Primary lab |
|------|-------|-----------------|-------------|
| 🛠️ **The App** | one person | An instrumented service: RED metrics, structured JSON logs, exposed `/metrics` | [`observability/lab03-instrumenting-services`](./lab03-instrumenting-services/README.md) |
| 📡 **The Stack** | the other person | The observability platform on kind: Prometheus + Grafana + Alertmanager, scraping + dashboards + alerts | [`k8s-operations/lab06-monitoring-stack`](../k8s-operations/lab06-monitoring-stack/README.md) |

The point of the day: **make them meet.** The Stack must scrape The App, dashboard
its metrics, and alert on its errors. That handoff — dev ships a service, platform
makes it observable — is exactly what happens on a real team.

> **Team of 3?** The third person owns a **specialization track** (logs or traces, see
> Part 3) and starts it as soon as the App is on the Stack — or pair-programs with
> whoever is behind.

By the end of the day you will have:

1. An instrumented app running on a cluster.
2. A metrics stack scraping it, with a custom dashboard and a firing alert **on your app**.
3. (If time / trio) one deeper pillar — logs or traces.
4. A 5-7 minute demo where **both** of you present your half and the handoff between them.

You work **autonomously** from the lab READMEs. The instructor circulates to unblock
you — raise your hand at each checkpoint, or whenever you're stuck for more than 10 minutes.

---

## Ground rules

- **Split, don't silo.** You own a half each, but check in often — your halves must connect.
  When one of you is blocked, pair up until it's unblocked.
- **One cluster per duo.** The Stack person owns it; the App person deploys onto it at integration time.
- **Stuck > 10 min?** Check the README's Validation section first, then ask your partner, then raise your hand.
- **Done early?** There's always more — see [Going Further](#going-further). Nobody sits idle.

---

## Part 1 — Build in parallel · ~2h15

Both roles work at the same time. You don't block each other — sync at Checkpoint 1.

### 🛠️ The App — `lab03-instrumenting-services`
1. Read the Flask starter and its five `# TODO` markers.
2. Add the **Counter** + **Histogram** (RED metrics), expose **`/metrics`**.
3. Switch the logs to **structured JSON** with a `request_id`.
4. Build the image and `kind load` it.
> You can write and build all of this **before** the cluster is ready — you only need
> the Stack at deploy time. Don't wait on your partner to start.

### 📡 The Stack — `lab06-monitoring-stack`
1. Install `kube-prometheus-stack` via Helm.
2. Reach the Grafana, Prometheus and Alertmanager UIs.
3. Use the lab's **sample app** to verify scraping works end-to-end: ServiceMonitor → target **UP** → PromQL returns data.
4. Build a first **custom dashboard** (Rate / Errors / Duration) against the sample app.
> Getting the sample app scraped proves your half works **before** your partner's app
> arrives. You'll point the same machinery at the real app in Part 2.

### ✅ Checkpoint 1 — "Stack is up, App is built"
Raise your hand when: **Stack** has Grafana open + a sample target **UP** in Prometheus,
**and** App has the instrumented image built and `kind load`ed. (Recall: the
`release: monitoring` label is what makes the operator discover a ServiceMonitor.)

---

## Part 2 — Integration: make them meet · ~1h

This is the heart of the day. Do it **together.**

1. **Deploy** the App onto the Stack's cluster (`kubectl apply` the App's manifests).
2. **Discover it** — the App's Service + ServiceMonitor (with the `release: monitoring` label)
   must show the App's target **UP** in Prometheus → Status → Targets.
3. **Dashboard it** — the Stack person builds (or retargets) a dashboard showing the App's
   own RED metrics: request rate, error ratio, p99 latency.
4. **Alert on it** — a PrometheusRule that fires on the App's error rate. Generate some
   traffic / errors against the App and watch it go `Pending → Firing`.

### ✅ Checkpoint 2 — "The App is observed"
Raise your hand when: your **own app's** metrics are live in a Grafana dashboard **and**
an alert is **Firing** on your app's error rate. This is the minimum bar for the demo.

---

## Part 3 — Add a pillar (trio's job, or together if time) · ~45-60 min

Add **one** deeper capability. For a trio, this is the third person's track from the start.

| Track | Lab | You'll be able to… |
|-------|-----|--------------------|
| 🪵 **Logs** | [`k8s-operations/lab07-loki-logs`](../k8s-operations/lab07-loki-logs/README.md) | Centralize logs with Loki, query LogQL from Grafana, jump from a metric spike to the App's log lines that caused it |
| 🔍 **Traces** | [`observability/lab02-traces`](./lab02-traces/README.md) | Install Grafana Tempo, deploy an OTel-instrumented app, read a distributed trace tree, run TraceQL |

> **How to choose**: Logs pairs most naturally with your instrumented app (you already
> emit structured JSON — now centralize it). Traces is the most visual for the demo.

### ✅ Checkpoint 3 — "Third pillar working"
Raise your hand when your chosen track hits its README's main Validation step
(your App's logs queryable in Grafana, or a trace tree visible in Tempo).

---

## Part 4 — Demo · last ~75 min

Each duo presents live. **5-7 minutes**, then 2-3 minutes of questions from the room.
No slides — drive the live UIs. **Both of you speak**: App owner presents the app half,
Stack owner presents the platform half, and together you show the handoff.

### What to show
1. **The App** (App owner) — the instrumented endpoint, the metrics it exposes, the structured logs.
2. **The Stack** (Stack owner) — what's running (`kubectl get pods -n monitoring`), the Targets page proving your app is scraped.
3. **The dashboard** — walk one panel, explain the PromQL behind it.
4. **An alert firing** — on your app, show it in Prometheus/Alertmanager, explain the rule.
5. **(If done) the third pillar** — a LogQL query on your app's logs, or a trace tree.
6. **One thing that broke** — what went wrong at the handoff and how you fixed it.
   (This is often the most useful 60 seconds of the demo.)

### Demo rubric (how you're assessed)

| Criterion | What "good" looks like |
|-----------|------------------------|
| **It works** | App running, scraped by the Stack, UIs reachable, no hand-waving |
| **The handoff** | You can explain how the Stack discovers and scrapes the App (the ServiceMonitor + label) |
| **Understanding** | Each owner explains *why*, not just *what* — what does this PromQL compute? why this metric type? |
| **Alerting** | An alert that fires on the App for a real condition, with a sensible threshold |
| **Third pillar** | Logs or traces working on your own app — a LogQL query on your logs, or a trace tree in Tempo |
| **Teamwork** | Both speak, each owns their half, neither is a passenger |
| **Communication** | Clear, honest (including what broke), within time |

---

## Going Further

Finished integration with time to spare? Pick from:

- **Add the other pillar** — do both logs and traces.
- **Three-pillar correlation** — wire the `trace_id` so you can click from a metric exemplar
  → a trace → its log lines, all for your own app. This is the holy-grail demo.
- **A real business metric** — add an app-specific counter (e.g. `orders_placed_total`) and
  dashboard it alongside the RED metrics.
- **Each lab's own "Going Further" section** — Thanos long-term storage, tail-sampling, …
- **Break each other's stacks** — swap clusters with another duo, introduce a failure
  (scale the App to 0, push a bad image), and see whose alerts catch it first.

---

## Quick reference

```bash
# Cluster healthy?
kubectl get nodes
kubectl get pods -A | grep -v Running | grep -v Completed   # should be ~empty

# The monitoring stack
kubectl get pods -n monitoring

# Load the App's image into kind (App owner, at integration time)
docker build -t <app>:dev .
kind load docker-image <app>:dev

# Reach the UIs (one per terminal, or background with &)
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-alertmanager 9093:9093
```

Grafana login: `admin` / `admin` (lab default).

The #1 integration gotcha: a ServiceMonitor without the `release: monitoring` label is
silently ignored by the operator — your app's target never appears. Check that first.
