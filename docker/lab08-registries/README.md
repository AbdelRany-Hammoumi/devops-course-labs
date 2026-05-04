# Lab 8 — Registries

## Objectives

- Run a local OCI-compliant registry (no signup, no rate limits)
- Tag and push an image with multiple production-style tags
- Pull from the local registry and verify byte-equivalence with the source
- Browse the registry's HTTP API to inspect catalog and manifests
- Add basic-auth to the registry

## Prerequisites

- Lab 03 completed
- Docker Engine ≥ 29.4
- Free TCP port `5000` (or substitute another)
- `curl` available

## Duration

~ 20 minutes

## Context

You will run the reference OCI registry implementation locally. It speaks the same API as Docker Hub, ghcr.io, and every other registry — so the workflow you learn here transfers directly.

## Instructions

### Step 1 — Run a local registry

```bash
docker run -d \
  --name registry \
  -p 5000:5000 \
  -v reg-data:/var/lib/registry \
  registry:3
```

Verify it's up:

```bash
curl -fsS http://localhost:5000/v2/
# Returns {} on success — that's the OCI v2 root endpoint.
```

### Step 2 — Tag and push

We'll re-publish a public image into the local registry.

```bash
docker pull alpine:3.20

docker tag alpine:3.20 localhost:5000/my-alpine:3.20
docker tag alpine:3.20 localhost:5000/my-alpine:latest

docker images localhost:5000/my-alpine
```

Push:

```bash
docker push localhost:5000/my-alpine:3.20
docker push localhost:5000/my-alpine:latest
```

### Step 3 — Browse the registry catalog

The OCI distribution spec exposes an HTTP API. Use `curl` against it:

```bash
# List repositories
curl -s http://localhost:5000/v2/_catalog | jq
# {"repositories": ["my-alpine"]}

# List tags for a repo
curl -s http://localhost:5000/v2/my-alpine/tags/list | jq
# {"name": "my-alpine", "tags": ["3.20", "latest"]}

# Read the manifest for a tag
curl -sH 'Accept: application/vnd.oci.image.manifest.v1+json' \
  http://localhost:5000/v2/my-alpine/manifests/3.20 | jq | head -30
```

### Step 4 — Pull from the local registry

To prove the round-trip works, remove the local images and pull them back:

```bash
docker rmi localhost:5000/my-alpine:3.20 localhost:5000/my-alpine:latest

docker pull localhost:5000/my-alpine:3.20
docker run --rm localhost:5000/my-alpine:3.20 echo "from local registry"
```

### Step 5 — Tag with production-style names

Apply the semver + SHA pattern:

```bash
SHA=$(echo "lab08-fake-commit" | sha256sum | cut -c1-7)

docker tag alpine:3.20 localhost:5000/my-alpine:0.1.0
docker tag alpine:3.20 localhost:5000/my-alpine:0.1
docker tag alpine:3.20 localhost:5000/my-alpine:sha-$SHA
docker tag alpine:3.20 localhost:5000/my-alpine:dev

docker push --all-tags localhost:5000/my-alpine

curl -s http://localhost:5000/v2/my-alpine/tags/list | jq
# tags: ["0.1", "0.1.0", "3.20", "dev", "latest", "sha-..."]
```

All these tags point to the same digest — proven by inspecting the manifest digest header:

```bash
for tag in 0.1.0 0.1 latest dev sha-$SHA; do
  digest=$(curl -sI \
    -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
    http://localhost:5000/v2/my-alpine/manifests/$tag \
    | awk -F': ' '/Docker-Content-Digest/ {print $2}' | tr -d '\r')
  echo "$tag → $digest"
done
```

All lines should print the same digest.

### Step 6 — Add basic auth (optional but worth doing once)

Stop the open registry:

```bash
docker rm -f registry
```

Create an htpasswd file:

```bash
mkdir -p /tmp/lab08-auth
docker run --rm --entrypoint htpasswd httpd:2.4 -Bbn alice secret123 > /tmp/lab08-auth/htpasswd
cat /tmp/lab08-auth/htpasswd
```

Run the registry with basic auth:

```bash
docker run -d \
  --name registry \
  -p 5000:5000 \
  -v reg-data:/var/lib/registry \
  -v /tmp/lab08-auth:/auth \
  -e REGISTRY_AUTH=htpasswd \
  -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
  -e "REGISTRY_AUTH_HTPASSWD_REALM=Lab Registry" \
  registry:3
```

Try unauthenticated access — it fails:

```bash
curl -i http://localhost:5000/v2/_catalog
# HTTP/1.1 401 Unauthorized
```

Authenticate:

```bash
echo "secret123" | docker login localhost:5000 -u alice --password-stdin
```

Now `docker pull localhost:5000/my-alpine:3.20` works again. Inspect the credentials:

```bash
cat ~/.docker/config.json | jq '.auths'
# { "localhost:5000": { "auth": "..." } }
```

Logout when done:

```bash
docker logout localhost:5000
```

### Step 7 — Clean up

```bash
docker rm -f registry
docker volume rm reg-data
docker rmi $(docker images localhost:5000/my-alpine -q) 2>/dev/null
docker rmi alpine:3.20
rm -rf /tmp/lab08-auth
```

## Validation

```bash
docker ps -a --filter name=registry --format '{{.Names}}'
```
Expected: empty.

```bash
docker images --filter reference='localhost:5000/*' --format '{{.Repository}}:{{.Tag}}'
```
Expected: empty.

```bash
docker volume ls --filter name=reg-data --format '{{.Name}}'
```
Expected: empty.

## Going Further (optional)

- Configure your daemon to use the local registry as a pull-through cache for Docker Hub:
  ```bash
  docker run -d --name cache -p 5001:5000 \
    -e REGISTRY_PROXY_REMOTEURL=https://registry-1.docker.io \
    registry:3
  ```
  Add `"registry-mirrors": ["http://localhost:5001"]` to `/etc/docker/daemon.json` (Docker Desktop: Settings → Docker Engine), restart, then `docker pull alpine:3.20` and observe the cache populate.
- Set up TLS on the registry with a self-signed cert. Docker refuses HTTP for non-localhost addresses by default — add the registry to `insecure-registries` in `daemon.json`, or generate a TLS cert and configure the registry to use it.
- Use `crane` (`brew install crane`) to copy an image between two registries without round-tripping through the local daemon:
  ```bash
  crane copy nginx:1.27-alpine localhost:5000/nginx:1.27-alpine
  ```
- Sign your image with `cosign` against the local registry:
  ```bash
  cosign generate-key-pair
  cosign sign --key cosign.key localhost:5000/my-alpine:3.20
  cosign verify --key cosign.pub localhost:5000/my-alpine:3.20
  ```
