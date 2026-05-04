# Lab 6 — Volumes and Networks

## Objectives

- Run a stateful service (Postgres) with a named volume and verify data persists
- Create a user-defined bridge network and resolve containers by name
- Connect a client container to the same network and query the database
- Use a bind mount for a dev-style hot-reload workflow
- Inspect networks, volumes, and clean up everything

## Prerequisites

- Lab 02 completed
- Docker Engine ≥ 29.4
- Free TCP port `5432` (or skip the host-port mapping)

## Duration

~ 25 minutes

## Context

The chapter showed three ways to mount state and how user-defined networks give containers DNS-by-name. This lab puts both into practice with a real database and a thin client container.

## Instructions

### Step 1 — A network and a volume

```bash
docker network create app-net
docker volume create pgdata

docker network ls
docker volume ls
```

### Step 2 — Run Postgres on the network with a named volume

```bash
docker run -d \
  --name db \
  --network app-net \
  -v pgdata:/var/lib/postgresql/data \
  -e POSTGRES_PASSWORD=secret \
  -e POSTGRES_DB=lab \
  postgres:17-alpine
```

Wait a few seconds for initialization, then verify:

```bash
docker logs db | tail -5
# expect: "database system is ready to accept connections"

docker exec db pg_isready -U postgres
# /var/run/postgresql:5432 - accepting connections
```

### Step 3 — Insert data

```bash
docker exec -it db psql -U postgres -d lab -c "
  CREATE TABLE notes (id serial PRIMARY KEY, body text);
  INSERT INTO notes (body) VALUES ('persistence works');
  SELECT * FROM notes;
"
```

Expected:
```
 id |        body
----+---------------------
  1 | persistence works
```

### Step 4 — Prove persistence

Destroy the container (NOT the volume):

```bash
docker rm -f db
docker volume ls            # pgdata still listed
```

Recreate the container with the same volume:

```bash
docker run -d \
  --name db \
  --network app-net \
  -v pgdata:/var/lib/postgresql/data \
  -e POSTGRES_PASSWORD=secret \
  -e POSTGRES_DB=lab \
  postgres:17-alpine
```

```bash
sleep 3
docker exec db psql -U postgres -d lab -c "SELECT * FROM notes;"
```

The row inserted in step 3 is still there. **Volumes outlive containers.**

### Step 5 — Reach the database from another container by name

Run a client container on the same network. Use the database hostname `db` (the container's name) — Docker resolves it via its embedded DNS:

```bash
docker run --rm --network app-net postgres:17-alpine \
  psql -h db -U postgres -d lab -c "SELECT count(*) FROM notes;" \
  <<< "secret"
```

(The `<<<` heredoc passes the password to psql's prompt.)

Or with `psql`'s env-var auth:

```bash
docker run --rm --network app-net \
  -e PGPASSWORD=secret \
  postgres:17-alpine \
  psql -h db -U postgres -d lab -c "SELECT body FROM notes;"
```

You should see the row from step 3.

### Step 6 — Inspect the network

```bash
docker network inspect app-net
docker network inspect app-net --format '{{range .Containers}}{{.Name}}: {{.IPv4Address}}{{"\n"}}{{end}}'
```

You should see the `db` container listed with its bridge IP.

### Step 7 — A bind-mount dev workflow

Create a small static site on the host:

```bash
mkdir -p /tmp/lab06-site
cat > /tmp/lab06-site/index.html <<'EOF'
<h1>Hello from the host filesystem</h1>
EOF
```

Run nginx with a bind mount pointing at it:

```bash
docker run -d \
  --name web \
  --network app-net \
  -p 8080:80 \
  -v /tmp/lab06-site:/usr/share/nginx/html:ro \
  nginx:1.27-alpine

curl http://localhost:8080/
```

Edit the file on the host; the container sees the change immediately:

```bash
echo "<p>edited at $(date)</p>" >> /tmp/lab06-site/index.html
curl http://localhost:8080/
```

The `:ro` flag mounts read-only — the container cannot modify host files.

### Step 8 — Clean up

```bash
docker rm -f db web
docker volume rm pgdata
docker network rm app-net
rm -rf /tmp/lab06-site
docker volume prune -f
docker network prune -f
```

## Validation

```bash
docker volume ls --filter name=pgdata --format '{{.Name}}'
```
Expected: empty.

```bash
docker network ls --filter name=app-net --format '{{.Name}}'
```
Expected: empty.

```bash
docker ps -a --filter name=db --filter name=web --format '{{.Names}}'
```
Expected: empty.

## Going Further (optional)

- Replace the named volume with a bind mount to a host path (`-v /tmp/lab06-pgdata:/var/lib/postgresql/data`). What permissions issue do you hit on Linux? How does `--user` fix it?
- Run a second Postgres on a **different** user-defined network. Verify the two databases cannot reach each other. Then connect one container to both networks and use it as a bridge.
- Run nginx with `--read-only` and a `tmpfs` for `/var/cache/nginx`. Confirm it still serves the bind-mounted HTML.
- Inspect `/var/lib/docker/volumes/pgdata/_data/` directly (Linux only, `sudo`). Compare the directory tree with what you'd see inside the container at `/var/lib/postgresql/data/`.
- Add a `HEALTHCHECK` to the db using `pg_isready`. Watch `docker ps` show `(healthy)` after a few seconds.
