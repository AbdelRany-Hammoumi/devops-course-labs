#!/usr/bin/env bash
# Lab 8 — Registries
# Replace each TODO with the correct command.

set -euo pipefail

# Step 1 — Run a local registry on port 5000
# TODO: docker run -d --name registry -p 5000:5000 -v reg-data:/var/lib/registry registry:3
# TODO: curl http://localhost:5000/v2/

# Step 2 — Tag and push alpine:3.20 to the local registry
# TODO: docker pull alpine:3.20
# TODO: docker tag alpine:3.20 localhost:5000/my-alpine:3.20
# TODO: docker tag alpine:3.20 localhost:5000/my-alpine:latest
# TODO: docker push localhost:5000/my-alpine:3.20
# TODO: docker push localhost:5000/my-alpine:latest

# Step 3 — Browse the registry HTTP API
# TODO: curl /v2/_catalog
# TODO: curl /v2/my-alpine/tags/list
# TODO: curl /v2/my-alpine/manifests/3.20

# Step 4 — Round-trip pull from the local registry
# TODO: docker rmi localhost:5000/my-alpine:3.20 localhost:5000/my-alpine:latest
# TODO: docker pull localhost:5000/my-alpine:3.20
# TODO: docker run --rm localhost:5000/my-alpine:3.20 echo "from local registry"

# Step 5 — Apply production-style tags (semver + sha + env)
# TODO: tag with 0.1.0, 0.1, sha-<short>, dev
# TODO: docker push --all-tags localhost:5000/my-alpine
# TODO: verify all tags resolve to the same Docker-Content-Digest

# Step 6 — Add basic auth (optional)
# TODO: stop the registry
# TODO: generate htpasswd via httpd:2.4 image
# TODO: re-run the registry with REGISTRY_AUTH=htpasswd
# TODO: docker login localhost:5000 -u alice
# TODO: pull/push with auth, then docker logout

# Step 7 — Clean up
# TODO: docker rm -f registry ; docker volume rm reg-data
# TODO: remove all localhost:5000/* images, alpine:3.20
# TODO: rm -rf /tmp/lab08-auth
