# Lab 2 — Running Containers

## Objectives

- Run a containerized HTTP service in detached mode with port mapping
- Inspect its state, configuration, and live logs
- Exec into the container to read configuration and trigger an action
- Practice the stop / start / restart / rm lifecycle
- Use restart policies and clean up disk usage

## Prerequisites

- Lab 01 completed
- Docker Engine ≥ 29.4
- A free TCP port `8080` on the host (the lab uses it for port mapping)
- `curl` available locally

## Duration

~ 30 minutes

## Context

You are running a containerized web service. Throughout the lab you will treat the container as a real process: query it, observe it, intervene, restart it, and remove it cleanly.

## Instructions

### Step 1 — Run the service

Start an `nginx:1.27-alpine` container in detached mode, named `webapp`, exposing the container's port 80 on host port 8080. Apply a sensible restart policy.

```bash
docker run -d \
  --name webapp \
  -p 8080:80 \
  --restart=unless-stopped \
  nginx:1.27-alpine
```

Verify with:

```bash
docker ps
curl -I http://localhost:8080
```

Expected: HTTP/1.1 200 OK from nginx.

### Step 2 — Inspect the container

Use `docker inspect` (with `-f` Go templates) to extract:

```bash
docker inspect -f '{{.State.Status}}'             webapp   # → running
docker inspect -f '{{.State.Pid}}'                webapp   # → host PID
docker inspect -f '{{.NetworkSettings.IPAddress}}' webapp  # → bridge IP
docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' webapp  # → unless-stopped
```

### Step 3 — Generate traffic and read logs

Hit the service a few times, then read the logs:

```bash
curl http://localhost:8080
curl http://localhost:8080/does-not-exist
curl http://localhost:8080
```

```bash
docker logs webapp                # full history
docker logs --tail 5 webapp       # last 5 entries
docker logs --since 1m webapp     # last minute
```

In a separate terminal, follow logs in real time:

```bash
docker logs -f webapp
```

Generate one more request from the first terminal — you should see it appear instantly in the follower. `Ctrl-C` detaches.

### Step 4 — Exec inside the container

Open an interactive shell:

```bash
docker exec -it webapp sh
```

Inside the container, run:

```sh
ls /etc/nginx/conf.d
cat /etc/nginx/conf.d/default.conf | head -20
nginx -v
exit
```

Then run a one-shot command without opening a shell:

```bash
docker exec webapp nginx -t
```

Expected: `nginx: configuration file /etc/nginx/nginx.conf test is successful`.

### Step 5 — Lifecycle

Stop the container gracefully:

```bash
docker stop webapp
docker ps -a --filter name=webapp
# → Exited (0) X seconds ago
```

Start it again — same name, same config:

```bash
docker start webapp
curl -I http://localhost:8080  # still 200 OK
```

Force-restart (stop + start):

```bash
docker restart webapp
```

Now simulate a problem with `docker kill`:

```bash
docker kill webapp
docker ps -a --filter name=webapp
# → Exited (137) X seconds ago    ← 137 = 128 + 9 (SIGKILL)
```

The restart policy `unless-stopped` will not auto-restart after a manual `kill`, but it WILL restart after an unexpected crash. You can prove this by killing the container's main process from the host — out of scope for this lab.

### Step 6 — Clean up

Remove the container and its image:

```bash
docker rm -f webapp
docker container prune        # shows nothing — confirm with y
docker rmi nginx:1.27-alpine
docker system df              # check disk usage after cleanup
```

## Validation

```bash
docker ps -a --filter name=webapp --format '{{.Names}}'
```
Expected output: empty (no `webapp` container).

```bash
docker images nginx --format '{{.Repository}}:{{.Tag}}'
```
Expected output: empty.

```bash
curl -sI http://localhost:8080 | head -1 || echo "port 8080 free"
```
Expected: `port 8080 free` (or a connection refused).

## Going Further (optional)

- Run two containers (`webapp1`, `webapp2`) on different host ports (8080, 8081). Use `docker ps --format` to display both side by side.
- Run a stateful container (e.g. `redis:7-alpine`), exec into it, run `redis-cli SET hello world`, restart the container, and confirm the data is **lost** (no volume — chapter 06).
- Try a custom signal: `docker kill -s SIGTERM webapp`. What exit code do you observe? Why is it different from `docker stop`?
- Use `docker logs --details` to see the metadata Docker attaches to log lines. Compare with `docker inspect -f '{{.LogPath}}' webapp` and `cat` that file (Linux only).
