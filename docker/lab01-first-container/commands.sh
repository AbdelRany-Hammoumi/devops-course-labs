#!/usr/bin/env bash
# Lab 1 — First Container
# Replace each TODO with the correct command, then run them one by one.
# Do NOT execute this script directly — run each block manually so you can
# observe the output of each step.

set -euo pipefail

# Step 1 — Verify Docker is running
# TODO: print client and server versions
# Hint: docker version

# Step 2 — Pull the nginx:1.27-alpine image
# TODO

# Step 3 — Run the image in detached mode, name the container "lab01"
# TODO

# Step 4 — List running containers, then extract the IP address and host PID
# TODO: docker ps
# TODO: docker inspect -f '{{.NetworkSettings.IPAddress}}' lab01
# TODO: docker inspect -f '{{.State.Pid}}' lab01

# Step 5 — Exec into the container with an interactive shell
# Run manually:
#   docker exec -it lab01 sh
# Inside the container, run:  ps aux ; hostname ; cat /etc/os-release ; exit

# Step 6 — Observe namespace isolation
# TODO: on Linux/WSL2:  ps aux | grep nginx
# TODO: on macOS:       docker top lab01

# Step 7 — Clean up
# TODO: stop the container
# TODO: remove the container
# TODO: remove the image
