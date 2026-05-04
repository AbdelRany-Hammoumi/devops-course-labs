# Lab 1 — First Container

## Objectives

- Pull a Docker image from Docker Hub
- Run a container in detached mode
- Inspect a running container with `docker ps` and `docker inspect`
- Execute a command inside a running container
- Observe PID namespace isolation between host and container
- Clean up containers and images

## Prerequisites

- Docker Engine ≥ 29.4 (see `setup/README.md`)
- A terminal: macOS Terminal / iTerm2, Linux shell, or WSL2 on Windows
- Internet access to pull images from Docker Hub

## Duration

~ 20 minutes

## Context

You have just learned that a container is a **process** isolated by Linux namespaces and controlled by cgroups. This lab makes that tangible: you will start a container, look inside it, and confirm that its PID namespace is different from the host's.

## Instructions

### Step 1 — Verify Docker is running

```bash
docker version
```

You should see both **Client** and **Server** sections. If the server section shows an error, the Docker daemon is not running.

### Step 2 — Pull an image

```bash
docker pull nginx:1.27-alpine
```

This downloads the image layers from Docker Hub and stores them in your local image cache. Each layer is fetched separately — note the lines like `Pull complete`.

Confirm the image is now local:

```bash
docker images nginx
```

### Step 3 — Run a container

```bash
docker run -d --name lab01 nginx:1.27-alpine
```

Flags:
- `-d` — detached mode (the container runs in the background)
- `--name lab01` — assigns a human-readable name

List running containers:

```bash
docker ps
```

You should see `lab01` with status `Up X seconds`.

### Step 4 — Inspect the container

```bash
docker inspect lab01
```

This prints a large JSON object. Skim it and locate the fields:
- `State.Status` — should be `running`
- `State.Pid` — the PID of the container's main process **on the host**
- `NetworkSettings.IPAddress` — the container's IP inside the Docker bridge network

To extract just one field with the Go template engine built into `docker`:

```bash
docker inspect -f '{{.NetworkSettings.IPAddress}}' lab01
docker inspect -f '{{.State.Pid}}' lab01
```

Take note of `State.Pid` — you will use it in step 6.

### Step 5 — Exec into the container

```bash
docker exec -it lab01 sh
```

> The image is Alpine-based and does not ship `bash`. Use `sh`.

You are now inside the container. Run:

```sh
ps aux
hostname
cat /etc/os-release
```

You should see only the nginx processes, with **PID 1** being `nginx: master process`. The hostname is the container ID. The OS reports as Alpine Linux.

Exit the container shell with `exit` or `Ctrl-D`. The container itself keeps running.

### Step 6 — Observe namespace isolation

Back on the host, find the same nginx process:

```bash
# Linux / WSL2
ps aux | grep nginx

# macOS (Docker Desktop) — the host can't see container processes directly
docker top lab01
```

Compare the PID you see on the host with PID 1 you saw inside the container. **Same process, two different namespaces.**

### Step 7 — Clean up

```bash
docker stop lab01
docker rm lab01
docker rmi nginx:1.27-alpine
```

## Validation

Run these two commands and confirm:

```bash
docker ps -a --filter name=lab01 --format '{{.Names}}'
```
Expected output: empty (no line printed) — the container was removed.

```bash
docker images nginx --format '{{.Repository}}:{{.Tag}}'
```
Expected output: empty — the image was removed.

## Going Further (optional)

- Run with a memory limit and watch what happens:
  ```bash
  docker run --rm --memory=64m nginx:1.27-alpine
  ```
  Try `--memory=4m`. Why does the container fail to start?
- Use `docker stats lab01` (while the container is running) to see live CPU and memory usage.
- Compare images by inspecting their layers:
  ```bash
  docker history nginx:1.27-alpine
  ```
- Try `docker run --rm hello-world` and trace the six steps you saw on the slides.
