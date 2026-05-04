#!/usr/bin/env bash
# Lab 3 — Images and Layers
# Replace each TODO with the correct command, then run them block by block.

set -euo pipefail

# Step 1 — Pull two images sharing the Alpine base; observe "Already exists"
# TODO: docker pull alpine:3.20
# TODO: docker pull nginx:1.27-alpine
# TODO: docker images --format ...

# Step 2 — Inspect history
# TODO: docker history nginx:1.27-alpine
# TODO: print the 5 largest layers by size

# Step 3 — Compare three base images
# TODO: pull alpine:3.20, debian:12-slim, gcr.io/distroless/static-debian12
# TODO: list with sizes
# Try a `docker run` on each — observe which fails and why.

# Step 4 — Tag vs digest
# TODO: docker inspect -f '{{index .RepoDigests 0}}' nginx:1.27-alpine
# TODO: pull the same image by its digest
# TODO: confirm the image IDs match

# Step 5 — Multi-platform manifest
# TODO: docker manifest inspect nginx:1.27-alpine

# Step 6 — Disk usage and cleanup
# TODO: docker system df
# TODO: docker images --filter dangling=true
# TODO: docker image prune -a
