# Lab 7 (P4) — Knative Survey + Decision Exercise

## Objectives

- Read a Knative Service CR and trace what it would deploy
- Compare it to the equivalent OpenFaaS function
- Sketch the architecture for a hypothetical workload
- Make a FaaS-platform decision for 5 real-world scenarios

## Prerequisites

- All previous P4 chapters reviewed
- Pen + paper or a digital diagramming tool

## Duration

~ 15 minutes

## Context

This is a paper exercise, like lab 01. By now you have hands-on with OpenFaaS — today you compare and decide.

## Instructions

### Step 1 — Read a Knative Service

Study this Knative Service CR (provided here, no need to deploy):

```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: hello
  namespace: default
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/min-scale: "0"
        autoscaling.knative.dev/max-scale: "20"
        autoscaling.knative.dev/target: "100"     # 100 concurrent reqs/replica
    spec:
      containers:
        - image: ghcr.io/myorg/hello:1.2.0
          env:
            - name: TARGET
              value: World
          resources:
            requests: { cpu: 100m, memory: 128Mi }
            limits:   { cpu: 500m, memory: 256Mi }
  traffic:
    - revisionName: hello-00001
      percent: 90
    - revisionName: hello-00002
      percent: 10
      tag: canary
```

Answer (on paper):
1. How many K8s resources would Knative create from this CR?
2. What URL would route to the canary revision specifically?
3. Where does scale-to-zero happen here?
4. If the canary fails, how do you roll back?

### Step 2 — Equivalent OpenFaaS function

Sketch (on paper) the equivalent OpenFaaS setup for the same `hello` workload, including:
- `stack.yml` for the function
- Annotations / labels for scaling (min/max)
- How would you do canary in OpenFaaS? (Hint: you'd need a separate deployment + a Traefik IngressRoute with weighted backends, or Argo Rollouts.)

Compare:
- Knative: 1 CR, traffic split native
- OpenFaaS: stack.yml + extra tooling for traffic split

### Step 3 — Architecture sketches

Sketch each on paper:

1. **Webhook receiver** (low-volume): Cloud Lambda
2. **Image-resize pipeline** (medium-volume, async): OpenFaaS chain (lab P4-05)
3. **Public REST API with strict latency**: Knative (warm pool) OR plain Deployment
4. **Edge compute** (sub-100ms global): Cloudflare Workers
5. **Long-running ETL** (30 min, complex DAG): Argo Workflows + K8s Jobs (NOT FaaS)

For each: 5 lines of pseudocode + a one-line architecture diagram.

### Step 4 — Decision Matrix

For each scenario in step 3, fill a table:

| Scenario | Platform | Why | Cost rough estimate |
|----------|----------|-----|---------------------|
| Webhook | Lambda | Free tier covers it | $0 / mo |
| Image pipeline | OpenFaaS | Already on K8s; async fan-out | Cluster $$ amortized |
| Public REST API | Plain Deployment | Cold-start kills latency | Cluster $$ amortized |
| Edge compute | Workers | Sub-10ms cold start | $5/mo for low traffic |
| Long ETL | Argo Workflows | DAG + retries needed | Cluster $$ amortized |

### Step 5 — Pick your future stack

In one paragraph, write down:
- What FaaS platform you'd pick for your next project
- Why
- One trade-off you accept

Examples:
- "OpenFaaS on existing K8s — simple, owns the operational story, good cost model since cluster is paid for. Trade-off: no scale-to-zero in OSS."
- "AWS Lambda — already on AWS, low traffic, free tier. Trade-off: vendor lock-in."
- "Knative — need traffic splitting and gradual rollouts. Trade-off: ~3x more control-plane Pods to manage."

### Step 6 — Optional: install Knative locally

Ambitious: try `knative quickstart` to install Knative on a kind cluster. Deploy the equivalent of `hello`. Compare the experience with OpenFaaS.

```bash
kn quickstart kind                      # creates a separate kind cluster with Knative
kn service create hello --image ghcr.io/knative-samples/helloworld-go --env TARGET=World
kn service list
```

This is out-of-scope for the lab, but worth experiencing.

## Validation

This lab is paper-based. Self-check:
- ✅ You can read a Knative Service CR
- ✅ You have a coherent answer for each step 3 scenario
- ✅ You can articulate when Knative beats OpenFaaS and vice versa

## Going Further (optional)

- Read the Knative Eventing docs: https://knative.dev/docs/eventing/
- Read the CloudEvents spec: https://cloudevents.io/
- Try Cloudflare Workers free tier: https://workers.cloudflare.com/
- Read the CNCF Serverless WG whitepapers
- Look at Fermyon Spin: a Wasm-first FaaS framework. Compare cold-start with OpenFaaS.
