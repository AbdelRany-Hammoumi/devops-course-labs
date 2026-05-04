#!/usr/bin/env bash
# Lab 6 — Volumes and Networks
# Replace each TODO with the correct command.

set -euo pipefail

# Step 1 — Create a network and a named volume
# TODO: docker network create app-net
# TODO: docker volume create pgdata

# Step 2 — Run postgres:17-alpine on app-net with the pgdata volume
# TODO: docker run -d --name db --network app-net -v pgdata:/var/lib/postgresql/data -e POSTGRES_PASSWORD=secret -e POSTGRES_DB=lab postgres:17-alpine
# TODO: docker logs db | tail
# TODO: docker exec db pg_isready -U postgres

# Step 3 — Insert data
# TODO: psql -c "CREATE TABLE notes ..."

# Step 4 — Destroy the container, recreate, verify data still there
# TODO: docker rm -f db
# TODO: re-run the same docker run from step 2
# TODO: psql -c "SELECT * FROM notes"

# Step 5 — Run a client on the same network, query by hostname "db"
# TODO: docker run --rm --network app-net -e PGPASSWORD=secret postgres:17-alpine psql -h db ...

# Step 6 — Inspect
# TODO: docker network inspect app-net

# Step 7 — Bind-mount workflow
# TODO: create /tmp/lab06-site/index.html on host
# TODO: docker run -d --name web --network app-net -p 8080:80 -v /tmp/lab06-site:/usr/share/nginx/html:ro nginx:1.27-alpine
# TODO: curl localhost:8080
# TODO: edit the file on host, curl again, see change

# Step 8 — Clean up
# TODO: docker rm -f db web
# TODO: docker volume rm pgdata
# TODO: docker network rm app-net
# TODO: rm -rf /tmp/lab06-site
