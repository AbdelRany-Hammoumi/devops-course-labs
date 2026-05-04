# Lab 3 (P4) — Your First Function

## Objectives

- Stand up a local Docker registry to use as the image source
- Scaffold a Python function with `faas-cli new --lang python3-http`
- Author the handler (markdown → HTML transformer)
- Build, push, deploy with `faas-cli up`
- Invoke the function and inspect logs

## Prerequisites

- OpenFaaS installed from lab P4-02 (still running)
- `faas-cli` ≥ 0.18 logged in to the gateway
- Free port 5000 for a local registry, free port 8080 (gateway port-forward)

## Duration

~ 30 minutes

## Context

You'll write a small markdown-to-HTML function from scratch. The pattern transfers to any Python (or other-language) function you'll ever write.

## Instructions

### Step 1 — Local registry

(Re-use from P1 ch08 if still running, or start a new one.)

```bash
docker ps --filter name=registry -q || \
  docker run -d --name registry -p 5000:5000 -v reg-data:/var/lib/registry registry:3

curl -fsS http://localhost:5000/v2/
# {} on success
```

Make the local registry reachable from inside the kind cluster:

```bash
# kind connects its containers to the docker network "kind"
docker network connect kind registry 2>/dev/null || true
```

### Step 2 — Scaffold the function

```bash
mkdir lab03 && cd lab03
faas-cli template store pull python3-http
faas-cli new --lang python3-http md2html

ls -R
# stack.yml
# md2html/
#   handler.py
#   requirements.txt
# template/python3-http/...
```

### Step 3 — Author the handler

Replace `md2html/handler.py`:

```python
import markdown


def handle(event, context):
    body = event.body.decode("utf-8") if event.body else ""
    if not body.strip():
        return {
            "statusCode": 400,
            "body": "POST a markdown body to /function/md2html",
            "headers": {"Content-Type": "text/plain"},
        }
    html = markdown.markdown(body)
    return {
        "statusCode": 200,
        "body": html,
        "headers": {"Content-Type": "text/html"},
    }
```

Update `md2html/requirements.txt`:

```
markdown==3.7
```

Edit `stack.yml` to point at the local registry:

```yaml
version: 1.0
provider:
  name: openfaas
  gateway: http://localhost:8080
functions:
  md2html:
    lang: python3-http
    handler: ./md2html
    image: registry:5000/md2html:0.1.0
```

> Why `registry:5000` and not `localhost:5000`?
> The kind Nodes pull from the cluster's Docker network. `localhost` from inside a Node container points to the Node, not your laptop. The `registry` hostname resolves on the kind network thanks to step 1.

### Step 4 — Build, push, deploy

```bash
faas-cli up -f stack.yml
```

You'll see:
1. Docker build of the function image (multi-stage Python build)
2. Push to `registry:5000/md2html:0.1.0`
3. Deploy: 202 Accepted from the gateway

Wait for the function Pod:

```bash
kubectl get pods -n openfaas-fn -l faas_function=md2html
faas-cli list
# md2html   0   1
```

### Step 5 — Invoke

```bash
echo "# Hello, OpenFaaS" | faas-cli invoke md2html
# <h1>Hello, OpenFaaS</h1>

curl -d "## Subtitle\n\nA paragraph with **bold** text." http://localhost:8080/function/md2html
# <h2>Subtitle</h2>
# <p>A paragraph with <strong>bold</strong> text.</p>

# Empty body — should 400
curl -i -d "" http://localhost:8080/function/md2html
# HTTP/1.1 400 Bad Request
# POST a markdown body to /function/md2html
```

### Step 6 — Add an env var + a Secret

Update `stack.yml`:

```yaml
functions:
  md2html:
    lang: python3-http
    handler: ./md2html
    image: registry:5000/md2html:0.2.0   # bump tag
    environment:
      MD_EXTENSIONS: "fenced_code,tables"
    secrets:
      - md-license
```

Update `md2html/handler.py` to use both:

```python
import os
import markdown


def handle(event, context):
    extensions = os.environ.get("MD_EXTENSIONS", "").split(",") if os.environ.get("MD_EXTENSIONS") else []

    license_text = "(no license)"
    license_path = "/var/openfaas/secrets/md-license"
    if os.path.exists(license_path):
        with open(license_path) as f:
            license_text = f.read().strip()

    body = event.body.decode("utf-8") if event.body else ""
    if not body.strip():
        return {"statusCode": 400, "body": "POST markdown body", "headers": {"Content-Type": "text/plain"}}

    html = markdown.markdown(body, extensions=[e for e in extensions if e])
    html += f"<!-- license: {license_text} -->"
    return {"statusCode": 200, "body": html, "headers": {"Content-Type": "text/html"}}
```

Create the Secret:

```bash
kubectl -n openfaas-fn create secret generic md-license \
  --from-literal=md-license="MIT-2026"
```

Re-deploy:

```bash
faas-cli up -f stack.yml

# Test fenced code (extension only works if MD_EXTENSIONS env var is set)
echo '```py
print("hi")
```' | faas-cli invoke md2html
# <pre><code class="language-py">print("hi")
# </code></pre><!-- license: MIT-2026 -->
```

### Step 7 — Watch the logs

```bash
faas-cli logs md2html
# Streams logs from all replicas of md2html
# Ctrl-C to detach
```

In another terminal, invoke a few times. Observe each request appearing in the log stream.

### Step 8 — Cleanup

```bash
faas-cli remove md2html

# Optional: leave OpenFaaS + registry up for next labs
# Or full cleanup:
# docker rm -f registry; docker volume rm reg-data
# helm uninstall openfaas -n openfaas
# kubectl delete ns openfaas openfaas-fn
```

## Validation

```bash
faas-cli list | grep -q md2html && echo "WARN: md2html still deployed" || echo "[ok] md2html removed"
```

## Going Further (optional)

- Switch to Node.js: `faas-cli new --lang node22-http md2html-node` and rewrite the handler with `markdown-it`.
- Add a `readinessProbe` annotation that delays gateway routing until your function is fully warm.
- Build a function in Go: `faas-cli template store pull golang-middleware` + write a Go handler. Compare image size vs Python.
- Use BuildKit secrets to pass an npm token at build time (skipping in stack.yml — chapter docker/05 patterns).
- Add a Prometheus `prometheus.io/scrape: "true"` annotation to your function via `stack.yml`'s `annotations:`. Check Grafana for the function's metrics.
- Multi-function stack: add a second function `qrcode` from the store reference to `stack.yml`. `faas-cli up` should deploy both.
