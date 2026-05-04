#!/usr/bin/env bash
# Lab 2 — Running Containers
# Replace each TODO with the correct command, then run them block by block.

set -euo pipefail

# Step 1 — Run nginx:1.27-alpine detached, named "webapp",
#          publishing host:8080 → container:80, restart=unless-stopped.
# TODO

# Step 2 — Inspect status, host PID, IP, restart policy with docker inspect -f '{{...}}'
# TODO: status
# TODO: pid
# TODO: ip
# TODO: restart policy

# Step 3 — Generate traffic, then read logs.
# TODO: hit / and /does-not-exist with curl
# TODO: docker logs (tail / since / -t)
# Run the follower in a second terminal:
#   docker logs -f webapp

# Step 4 — Interactive shell inside the container, plus a one-shot command.
# Run manually:
#   docker exec -it webapp sh
#   inside: ls /etc/nginx/conf.d ; cat /etc/nginx/conf.d/default.conf ; nginx -v ; exit
# TODO: docker exec webapp nginx -t

# Step 5 — Lifecycle: stop, start, restart, kill — observe exit codes.
# TODO: stop
# TODO: ps -a --filter name=webapp
# TODO: start, then curl
# TODO: restart
# TODO: kill, then check exit code is 137

# Step 6 — Clean up
# TODO: docker rm -f webapp
# TODO: docker rmi nginx:1.27-alpine
# TODO: docker system df
