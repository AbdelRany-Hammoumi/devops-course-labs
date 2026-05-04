# Lab 4 — Dockerfile Basics

## Objectives

- Write a Dockerfile from scratch for a small Python web service
- Build, tag, and run the resulting image
- Add a `.dockerignore` and observe its effect on context size
- Optimize the layer order to keep the cache warm during development
- Run the container as a non-root user

## Prerequisites

- Lab 03 completed
- Docker Engine ≥ 29.4
- A free TCP port `8080` on the host

## Duration

~ 30 minutes

## Context

You will containerize a tiny Flask app that exposes one endpoint. The starter app is provided. Your job is to author the Dockerfile that turns it into a working image.

## Starter Code

The `app/` directory contains:

- `app/main.py` — a 10-line Flask app
- `app/requirements.txt` — one dependency (Flask)

```python
# app/main.py
from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.get("/")
def hello():
    return jsonify(message="hello from container", host=os.uname().nodename)

@app.get("/health")
def health():
    return jsonify(status="ok"), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
```

## Instructions

### Step 1 — Write the first Dockerfile

Create a file named `Dockerfile` (no extension) at the lab root with the following layout:

```dockerfile
# 1. base image
FROM python:3.12-alpine

# 2. workdir
WORKDIR /app

# 3. install dependencies (cache-friendly: copy lockfile first)
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 4. copy app code
COPY app/ .

# 5. document the port
EXPOSE 8080

# 6. run as non-root
RUN adduser -D -u 1000 appuser
USER appuser

# 7. start command (exec form — handles SIGTERM properly)
CMD ["python", "main.py"]
```

### Step 2 — Build, tag, run

```bash
docker build -t hello-flask:0.1.0 .
docker images hello-flask
```

Tag the image with a second name:

```bash
docker tag hello-flask:0.1.0 hello-flask:latest
docker images hello-flask
```

Run the container:

```bash
docker run -d --name flask -p 8080:8080 hello-flask:0.1.0
curl http://localhost:8080/
curl http://localhost:8080/health
```

### Step 3 — Verify the non-root user

```bash
docker exec flask id
# Expected: uid=1000(appuser) gid=1000(appuser) ...

docker exec flask whoami
# appuser
```

### Step 4 — Add a `.dockerignore`

Create `.dockerignore` at the project root:

```
__pycache__
*.pyc
.venv
.env
.git
.github
*.log
README.md
```

Rebuild and observe the "Sending build context to Docker daemon" message gets smaller:

```bash
docker build -t hello-flask:0.2.0 .
```

### Step 5 — Watch the layer cache

Modify `app/main.py` (e.g. change the message string), then rebuild:

```bash
docker build -t hello-flask:0.2.1 .
```

You should see most layers report `CACHED` and only the `COPY app/ .` and downstream layers re-execute. Build time: a few seconds.

Now modify `app/requirements.txt` (add a comment line) and rebuild:

```bash
docker build -t hello-flask:0.2.2 .
```

This time the `RUN pip install` and everything below it re-executes. Slower — that's the trade-off that motivates the cache-friendly ordering.

### Step 6 — Replace the running container with the new build

```bash
docker rm -f flask
docker run -d --name flask -p 8080:8080 hello-flask:0.2.2
curl http://localhost:8080/
```

### Step 7 — Inspect history and labels

```bash
docker history hello-flask:0.2.2
docker inspect -f '{{.Config.User}}' hello-flask:0.2.2     # → 1000 or appuser
docker inspect -f '{{.Config.ExposedPorts}}' hello-flask:0.2.2  # → map[8080/tcp:{}]
docker inspect -f '{{.Config.Cmd}}' hello-flask:0.2.2      # → [python main.py]
```

### Step 8 — Clean up

```bash
docker rm -f flask
docker rmi hello-flask:0.1.0 hello-flask:0.2.0 hello-flask:0.2.1 hello-flask:0.2.2 hello-flask:latest
docker image prune -f
```

## Validation

```bash
docker images hello-flask --format '{{.Repository}}:{{.Tag}}'
```
Expected: empty.

```bash
docker ps -a --filter name=flask --format '{{.Names}}'
```
Expected: empty.

## Going Further (optional)

- Pin the Python base by digest. Use `docker inspect -f '{{index .RepoDigests 0}}'` after a pull, then update the FROM line.
- Add a `HEALTHCHECK` instruction. Run the container and watch `docker ps` show `(healthy)` after a few seconds.
- Add an `ENV LOG_LEVEL=info` and read it from the Python app via `os.environ.get("LOG_LEVEL")`.
- Switch the FROM to `gcr.io/distroless/python3-debian12`. What breaks? (Hint: no shell.) How would you debug it?
