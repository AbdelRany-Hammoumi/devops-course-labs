# Lab 5 (P4) — Async Chain (Splitter → Enricher → Recorder)

## Objectives

- Author three functions that pass data through a chain
- Use the X-Callback-Url pattern to trigger the next function
- Observe queue-worker activity in OpenFaaS logs
- Demonstrate fan-out from the splitter

## Prerequisites

- OpenFaaS installed (lab P4-02)
- Local registry running on `:5000`

## Duration

~ 25 minutes

## Context

You'll build a tiny pipeline: client posts a JSON list of words; the splitter fans out one async invocation per word to the enricher; the enricher uppercases each word; the recorder logs the final result.

## Architecture

```
client → splitter (sync, 202) → N × async enricher → callback to recorder
```

## Instructions

### Step 1 — Scaffold the three functions

```bash
mkdir lab05 && cd lab05
faas-cli template store pull python3-http
faas-cli new --lang python3-http splitter
faas-cli new --lang python3-http enricher
faas-cli new --lang python3-http recorder
```

### Step 2 — Splitter

`splitter/handler.py`:

```python
import json
import os
import httpx

GATEWAY = os.environ.get("GATEWAY", "http://gateway.openfaas.svc.cluster.local:8080")
RECORDER_URL = f"{GATEWAY}/function/recorder"


def handle(event, context):
    try:
        items = json.loads(event.body or b"[]")
    except json.JSONDecodeError:
        return {"statusCode": 400, "body": "expected JSON list"}

    if not isinstance(items, list):
        return {"statusCode": 400, "body": "expected JSON list"}

    fanout_url = f"{GATEWAY}/async-function/enricher"
    for item in items:
        httpx.post(
            fanout_url,
            content=json.dumps({"raw": item}),
            headers={
                "Content-Type": "application/json",
                "X-Callback-Url": RECORDER_URL,
            },
            timeout=5.0,
        )
    return {
        "statusCode": 202,
        "body": json.dumps({"queued": len(items)}),
        "headers": {"Content-Type": "application/json"},
    }
```

`splitter/requirements.txt`:
```
httpx==0.28.1
```

### Step 3 — Enricher

`enricher/handler.py`:

```python
import json


def handle(event, context):
    try:
        payload = json.loads(event.body)
    except (json.JSONDecodeError, TypeError):
        return {"statusCode": 400, "body": "expected JSON"}

    raw = payload.get("raw", "")
    enriched = {"raw": raw, "upper": raw.upper(), "len": len(raw)}
    return {
        "statusCode": 200,
        "body": json.dumps(enriched),
        "headers": {"Content-Type": "application/json"},
    }
```

`enricher/requirements.txt`: empty (no deps).

### Step 4 — Recorder

`recorder/handler.py`:

```python
import json
import sys


def handle(event, context):
    body = event.body.decode("utf-8") if event.body else ""
    # Log to stdout — visible via faas-cli logs recorder
    print(f"[recorder] received: {body}", file=sys.stdout, flush=True)
    return {"statusCode": 200, "body": "logged"}
```

`recorder/requirements.txt`: empty.

### Step 5 — stack.yml

```yaml
version: 1.0
provider:
  name: openfaas
  gateway: http://localhost:8080

functions:
  splitter:
    lang: python3-http
    handler: ./splitter
    image: registry:5000/splitter:0.1.0
    environment:
      GATEWAY: http://gateway.openfaas.svc.cluster.local:8080
  enricher:
    lang: python3-http
    handler: ./enricher
    image: registry:5000/enricher:0.1.0
  recorder:
    lang: python3-http
    handler: ./recorder
    image: registry:5000/recorder:0.1.0
```

### Step 6 — Deploy

```bash
faas-cli up -f stack.yml
faas-cli list
# splitter   0   1
# enricher   0   1
# recorder   0   1
```

### Step 7 — Tail recorder logs

In one terminal:
```bash
faas-cli logs recorder
```

### Step 8 — Trigger the chain

In another terminal:
```bash
curl -d '["alpha", "beta", "gamma", "delta"]' \
  -H "Content-Type: application/json" \
  http://localhost:8080/function/splitter
# {"queued": 4}
```

In the recorder log stream you should see (within a few seconds):
```
[recorder] received: {"raw": "alpha", "upper": "ALPHA", "len": 5}
[recorder] received: {"raw": "beta", "upper": "BETA", "len": 4}
[recorder] received: {"raw": "gamma", "upper": "GAMMA", "len": 5}
[recorder] received: {"raw": "delta", "upper": "DELTA", "len": 5}
```

The order may vary (queue-worker processes in parallel).

### Step 9 — Watch the queue worker

```bash
kubectl logs -n openfaas -l app=queue-worker --tail=20 -f
```

Each fan-out item produces one log line in the queue worker.

### Step 10 — Larger fan-out

```bash
# Generate a 50-item list
python3 -c "import json; print(json.dumps([f'word{i}' for i in range(50)]))" \
  | curl -d @- -H "Content-Type: application/json" http://localhost:8080/function/splitter

# Watch the queue work through them
kubectl logs -n openfaas -l app=queue-worker --tail=60 -f
```

50 invocations queued. With default `queue-worker` concurrency of 1: serial processing. Scale it up:

```bash
kubectl -n openfaas scale deploy/queue-worker --replicas=5
# Re-trigger; observe parallel processing.
```

### Step 11 — Cleanup

```bash
faas-cli remove -f stack.yml

# Restore queue-worker
kubectl -n openfaas scale deploy/queue-worker --replicas=1
```

## Validation

```bash
faas-cli list 2>&1 | grep -E "splitter|enricher|recorder" && echo "WARN: still deployed" || echo "[ok] all gone"
```

## Going Further (optional)

- Add idempotency: each enriched item carries a UUID; recorder dedup by ID via Redis.
- Replace recorder with a function that writes to Postgres (lab P4-04 pattern).
- Trigger the splitter via a CronJob: deploy openfaas/cron-connector, annotate splitter with `topic: cron-function, schedule: '*/2 * * * *'`. Watch it fire every 2 min.
- Build a fan-in: enricher writes to Redis with `INCR` keyed on a batch ID; a separate "reducer" function aggregates after all items are done.
- Inspect the Argo Workflows alternative: same pipeline as a Workflow CRD with retries + DAG.
