# Challenge — Build Your Observability Stack (Full-Day Hands-On)

> **Format**: teams of 2-3. You are the SRE team for the day. By 17:00 your team
> demos a working observability stack to the room. Everything you need is in the
> lab READMEs linked below — work through them at your own pace.

---

## The mission

A fictional company runs a Kubernetes cluster and is flying blind: no dashboards,
no alerts, no way to debug an incident. **Your team's job: give them eyes.**

By the end of the day you will have:

1. A running metrics stack (Prometheus + Grafana + Alertmanager).
2. A custom dashboard and a working alert.
3. **One** deeper capability of your choice (logs, traces, or app instrumentation).
4. A 5-7 minute demo showing it all live.

You work **autonomously** from the lab READMEs. The instructor circulates to unblock
you — raise your hand at each checkpoint, or whenever you're stuck for more than 10 minutes.

---

## Teams & ground rules

- **Teams of 2-3.** Pair-driving encouraged: one types, one reads the README, swap often.
- **One cluster per team is enough** — work on whichever machine has a healthy kind cluster.
- **Stuck > 10 min?** Check the README's Validation section first, then ask a neighbour, then raise your hand.
- **Done early?** There's always more — see [Going Further](#going-further). Nobody sits idle.

---

## Part 1 — Core mission (everyone) · ~2h15

Stand up the canonical Kubernetes metrics stack and prove it works end-to-end.

**Lab**: [`k8s-operations/lab06-monitoring-stack`](../k8s-operations/lab06-monitoring-stack/README.md)

What you'll do:
1. Install `kube-prometheus-stack` via Helm.
2. Reach the Grafana, Prometheus and Alertmanager UIs.
3. Deploy a sample app, author a **ServiceMonitor**, verify the target appears in Prometheus.
4. Write a few **PromQL** queries against the scraped metrics.
5. Build a **custom Grafana dashboard** (at least: a Rate panel, an Errors panel, a Duration/p99 panel).
6. Define a **PrometheusRule** alert and watch it transition `Pending → Firing`.

### ✅ Checkpoint 1 — "Grafana is up"
Raise your hand when: Grafana opens, and Prometheus → Status → Targets shows your
sample app's ServiceMonitor as **UP**. (Recall: the `release: monitoring` label is
what makes the operator discover your ServiceMonitor.)

### ✅ Checkpoint 2 — "Alert fired"
Raise your hand when: your custom dashboard shows live data **and** your alert is
**Firing** in the Prometheus Alerts tab. This is the minimum bar for the demo.

---

## Part 2 — Specialization track (pick ONE) · ~1h30

Each team picks **one** track. Different teams pick different tracks → the demos at
the end of the day cover the whole observability story, not the same lab eight times.

| Track | Lab | You'll be able to… |
|-------|-----|--------------------|
| 🪵 **Logs** | [`k8s-operations/lab07-loki-logs`](../k8s-operations/lab07-loki-logs/README.md) | Centralize logs with Loki, query LogQL from Grafana, jump from a metric spike to the log lines that caused it |
| 🔍 **Traces** | [`observability/lab02-traces`](./lab02-traces/README.md) | Install Grafana Tempo, deploy an OTel-instrumented app, read a distributed trace tree, run TraceQL |
| 🛠️ **Instrumentation** | [`observability/lab03-instrumenting-services`](./lab03-instrumenting-services/README.md) | Instrument a Flask app from scratch — RED metrics, structured JSON logs, ship a dashboard + alert as code |

> **How to choose**: Logs is the gentlest (least new infra). Traces is the most
> visual (the trace tree wows in a demo). Instrumentation is the most hands-on-code
> (best if your team likes writing Python).

### ✅ Checkpoint 3 — "Bonus working"
Raise your hand when your chosen track hits its README's main Validation step
(logs queryable in Grafana / a trace tree visible in Tempo / your Flask app's
metrics scraped and its alert firing).

---

## Part 3 — Demos · last ~75 min

Each team presents its stack live. **5-7 minutes per team.** No slides — drive the
live UIs. Then 2-3 minutes of questions from the room.

### What to show
1. **The stack** — what's running (`kubectl get pods -n monitoring`).
2. **A dashboard** — walk one panel, explain the PromQL behind it.
3. **An alert firing** — show it in Prometheus/Alertmanager, explain the rule.
4. **Your specialization** — the one thing your track unlocked (a LogQL query, a
   trace tree, your instrumented endpoint).
5. **One thing that broke** — what went wrong and how you fixed it. (This is often
   the most useful 60 seconds of the demo.)

### Demo rubric (how you're assessed)

| Criterion | What "good" looks like |
|-----------|------------------------|
| **Working stack** | Pods running, UIs reachable, no hand-waving |
| **Understanding** | You can explain *why*, not just *what* — what does this PromQL actually compute? |
| **Alerting** | An alert that fires for a real condition, with a sensible threshold |
| **Specialization depth** | Your chosen track is genuinely working, not half-done |
| **Communication** | Clear, honest (including what broke), within time |

---

## Going Further

Finished the core mission and your track with time to spare? Pick from:

- **Second track** — do another specialization lab from Part 2.
- **Each lab's own "Going Further" section** — every lab README ends with stretch goals
  (long-term storage with Thanos, tail-sampling for traces, custom business metrics, …).
- **Three-pillar correlation** — if your team did metrics + logs + traces, wire the
  `trace_id` so you can click from a metric exemplar → a trace → its log lines. This is
  the holy grail demo.
- **Break each other's stacks** — swap clusters with another team, introduce a failure
  (scale a Deployment to 0, push a bad image), and see whose alerts catch it first.

---

## Quick reference

```bash
# Cluster healthy?
kubectl get nodes
kubectl get pods -A | grep -v Running | grep -v Completed   # should be ~empty

# The monitoring stack
kubectl get pods -n monitoring

# Reach the UIs (one per terminal, or background with &)
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-alertmanager 9093:9093
```

Grafana login: `admin` / `admin` (lab default).

Stuck on Helm or Ingress concepts? They're in the `k8s-operations` chapter labs you've
already touched — the monitoring lab assumes only that the cluster is up.
