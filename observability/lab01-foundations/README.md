# Lab 1 (Observability) — Foundations: Three Pillars, Tooling, RED/USE

## Objectives

- Classify a stream of real-world signals into the three pillars (metrics, logs, traces).
- For a set of operational scenarios, pick which pillar to interrogate first and which tool.
- Design a minimum useful observability plan for a small service using RED + USE.
- Sketch the Build–Measure–Learn loop for a real-world feature.

## Prerequisites

- Chapter `observability/01-foundations` covered (vocabulary, three pillars, RED/USE, BML loop).
- A pen and paper. No `kubectl` for this lab.

## Duration

~ 25 minutes (paper exercise — concepts before code).

## Context

This is a **paper exercise**. The hands-on stack (Prometheus, Grafana, Loki) arrives in `k8s-operations/lab06` and `lab07`. Before installing anything, you'll think through what you would even *want* to observe and why.

## Instructions

### Step 1 — Classify the signals (8 min)

For each signal below, decide which pillar it most naturally belongs to: **M** (metrics), **L** (logs), **T** (traces). Some are debatable — write the reasoning, not just the letter.

| # | Signal |
|---|--------|
| 1 | `http_requests_total{service="api",status="500"}` value `34219` |
| 2 | `2026-05-25T08:12:43Z ERROR api request_id=4f7e err="pg: deadlock"` |
| 3 | Span tree: `api → orders → payments(120ms) → db(95ms)` |
| 4 | `node_filesystem_avail_bytes{mountpoint="/"}` value `2.1e9` |
| 5 | `kubectl logs deploy/web -f` output |
| 6 | A flame graph showing CPU time per function for one request |
| 7 | Number of active WebSocket connections, sampled every 15 s |
| 8 | A list of every SQL query executed during a single user checkout, in order |
| 9 | Counter of how many SQL queries that checkout performed |
| 10 | An alert that fires when error rate exceeds 5% for 5 min |
| 11 | A line in `audit.log`: `user=alice action=DELETE resource=pod/db-0 at=...` |
| 12 | `histogram_quantile(0.99, sum(rate(latency_bucket[5m])) by (le))` |

For 4–5 of them, note: **why** that pillar? What would the other two pillars give you instead?

### Step 2 — Scenario triage (7 min)

For each scenario, pick the **first pillar you query** and the **tool** you would reach for. One sentence why.

| # | Scenario |
|---|----------|
| A | Customers report the checkout page is slow this morning, but no alert has fired. |
| B | One specific Pod has restarted 12 times in the last hour. You need to know what it printed before each crash. |
| C | The team wants a dashboard showing nightly batch job duration over the last 30 days. |
| D | A microservice migration shipped yesterday; today's p99 latency on the user-facing API doubled. You need to find which downstream call got slower. |
| E | Auditors are asking who deleted a Kubernetes Secret last Tuesday at 14:32 UTC. |
| F | A new feature seems to use 3× more CPU than expected. You need to know which code paths burn the CPU. |

### Step 3 — Instrument a small service with RED + USE (8 min)

Pick **one** of the services below (or one you know):

- A simple URL shortener (HTTP API + Postgres).
- A queue worker that consumes RabbitMQ messages and writes to S3.
- A WebSocket server pushing live notifications to mobile clients.

On paper, fill the table:

| Layer | Method | Signals to emit |
|-------|--------|-----------------|
| API endpoints (or queue consume calls) | **RED** | Rate ⇒ ?<br>Errors ⇒ ?<br>Duration ⇒ ? |
| Critical resource #1 (DB / queue / connection pool) | **USE** | Utilization ⇒ ?<br>Saturation ⇒ ?<br>Errors ⇒ ? |
| Critical resource #2 (CPU / memory / disk) | **USE** | Utilization ⇒ ?<br>Saturation ⇒ ?<br>Errors ⇒ ? |

For each signal, write the **metric name** you would expose (e.g. `http_requests_total{route,method,status}`), or the **log shape** (JSON fields), or the **trace span** name.

### Step 4 — Sketch the Build–Measure–Learn loop (2 min)

Pick a feature you've shipped (or would ship). On paper, complete:

- **Build** — what change did you ship?
- **Measure** — which 1 or 2 signals would tell you the change had its intended effect (or didn't)?
- **Learn** — what decision would each measurement outcome trigger?

Keep it short — the point is the loop, not the feature.

## Validation

Compare your answers with the solution sheet (your instructor has it). For Step 1, expect to disagree with the solution on 2-3 borderline items — that's the point of writing the reasoning. For Step 2, the scenario triage answers are tighter; if you're far off on more than two, re-read the incident narrative slide.

For Steps 3 and 4, there is no single right answer — the lab is correct if your signals are **actionable** (you would know what to do if they fired) and **non-overlapping** (no two signals tell you the same thing).

## Going Further

- Read Tom Wilkie's RED method blog: [grafana.com/blog/red-method](https://grafana.com/blog/2018/08/02/the-red-method-how-to-instrument-your-services/)
- Read Brendan Gregg's USE method: [brendangregg.com/usemethod.html](https://brendangregg.com/usemethod.html)
- Read the Google SRE book chapters on SLOs and error budgets: [sre.google/sre-book/service-level-objectives/](https://sre.google/sre-book/service-level-objectives/)
- For a deeper dive on traces and OpenTelemetry: [opentelemetry.io/docs/concepts/](https://opentelemetry.io/docs/concepts/)
