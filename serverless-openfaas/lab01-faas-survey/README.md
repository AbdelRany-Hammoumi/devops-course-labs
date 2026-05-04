# Lab 1 (P4) — FaaS Architecture Survey

## Objectives

- Sketch the architecture of three FaaS platforms side-by-side
- Pick a use case and propose the right FaaS (or no FaaS at all)
- Estimate the cost of one workload on cloud Lambda vs OpenFaaS-on-K8s
- Identify which functions in a real backend are "FaaS-shaped"

## Prerequisites

- Pillar 3 completed
- A pen and paper (or a digital diagramming tool)

## Duration

~ 20 minutes

## Context

This is a paper exercise — no `kubectl` until lab 02. You'll think through architecture decisions before deploying anything.

## Instructions

### Step 1 — Sketch the three architectures

On paper, draw three side-by-side diagrams:

1. **AWS Lambda + API Gateway**
   - Client → API Gateway → Lambda → DynamoDB
   - Note: where does scale-to-zero happen? Where does the cold-start tax apply?

2. **OpenFaaS on Kubernetes**
   - Client → Traefik Ingress → OpenFaaS Gateway → Function Pod (replicas) → external DB
   - Note: which components run always-on?

3. **Knative Serving on Kubernetes**
   - Client → Knative Activator → Knative Service (Pods) → external DB
   - Note: what's the Activator's role?

In each, mark:
- ✅ Stateless components
- ⚠ Stateful components
- 💰 Components you pay for when idle

### Step 2 — Pick a workload

Choose ONE of these scenarios. Document on paper:

| Scenario | Description |
|----------|-------------|
| A | Webhook receiver: GitHub → resize image → upload to S3. ~100 events/day. |
| B | Public API: REST endpoints for a SaaS, ~10 req/s sustained, p99 < 100 ms required |
| C | Cron job: nightly report aggregation, runs 30 min, ~1 GB peak memory |
| D | Real-time dashboard: WebSocket-fed price feed for traders |
| E | Internal admin tool: 5 endpoints, used by ~20 employees during business hours |

For your scenario, answer:
1. Which of the three FaaS architectures fits? Or is FaaS the wrong choice entirely?
2. What's the dominant constraint (latency, cost, scale, complexity)?
3. What would your alternative non-FaaS architecture look like?

### Step 3 — Cost estimation

Pick scenario A (webhook, 100 events/day, 200 ms each, 256 MB).

Compute monthly cost on:
- **AWS Lambda**: 100 × 30 = 3,000 invocations/mo. Lambda free tier covers it. Real cost ≈ $0/mo.
- **OpenFaaS on a $30 / mo VPS** running just for this webhook → $30 / mo.
- **OpenFaaS on existing K8s cluster** (already paying $400 / mo for cluster) → marginal cost ≈ $0/mo.

Now scale up: what about 1M invocations / day, 200 ms each, 256 MB?
- **Lambda**: ~$5,000 / mo (compute) + ~$1,000 / mo (API Gateway).
- **OpenFaaS on a $400 / mo cluster**: $400/mo (if cluster has the headroom).

Crossover point: somewhere between 100k and 1M invocations / day. Below: Lambda. Above: OpenFaaS amortizes well.

### Step 4 — Audit a real backend

Pick a side-project or a system you know well. List 5-10 endpoints / jobs. For each:

| Endpoint / Job | FaaS-shaped? | Why? |
|----------------|--------------|------|
| `POST /webhooks/stripe` | ✅ | Sporadic, stateless, async |
| `GET /api/dashboard` | ❌ | Latency-sensitive, sustained traffic |
| `POST /uploads/process` | ✅ | Triggered by upload, async |
| Nightly cron `cleanup-old-data` | ✅ | Scheduled, batch |
| `GET /api/users/:id` | Maybe | If high-traffic, no; if internal-admin, yes |

Most real systems have ~30 % FaaS-shaped work. The rest stays as Deployments.

### Step 5 — Decide

For each FaaS-shaped item from step 4, decide:
- Cloud (Lambda / Cloud Functions / Workers): when?
- OpenFaaS on existing K8s: when?
- Knative Serving: when?

Write down a one-line rationale per item.

## Validation

This lab is paper-based. Self-check:
- ✅ You can sketch the three FaaS architectures from memory
- ✅ You can identify FaaS vs non-FaaS workloads
- ✅ You have a rough cost intuition (low traffic → cloud; high traffic → self-hosted on existing K8s)

## Going Further (optional)

- Read the Wardley map for FaaS: where is it on the evolution curve in 2026?
- Pick one cloud FaaS and read its limits page: max execution time, max memory, max payload size, runtime versions.
- Compare AWS Lambda's cold-start vs Cloudflare Workers' V8 isolate cold-start (~200 ms vs ~5 ms). What architectural choices enable that?
- Read the OpenFaaS architecture doc: https://docs.openfaas.com/architecture/stack/
- Sketch how you'd run OpenFaaS in a cluster you already have monitoring (Prometheus from P3) wired into.
