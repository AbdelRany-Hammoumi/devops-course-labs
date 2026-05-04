# Lab 3 — Images and Layers

## Objectives

- Pull images and observe the layer-caching behavior
- Use `docker history` and `docker inspect` to read an image's structure
- Compare three base images of different sizes (alpine, debian-slim, distroless)
- Pull an image by digest and verify byte-level immutability
- Practice cleanup of dangling and unused images

## Prerequisites

- Lab 02 completed
- Docker Engine ≥ 29.4
- ~500 MB free disk for image pulls
- Internet access

## Duration

~ 25 minutes

## Context

Images are the unit you ship across teams, registries, and CI. Understanding their structure — layers, digests, base choice — is the difference between a 700 MB image that crawls on every deploy and a 30 MB image that pulls in seconds.

## Instructions

### Step 1 — Pull and observe layer caching

Pull two images that share the Alpine base:

```bash
docker pull alpine:3.20
docker pull nginx:1.27-alpine
```

Watch the second pull. The Alpine base layer should be reported as `Already exists` because it was downloaded with the first pull.

```bash
docker images --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}'
```

### Step 2 — Read an image's history

```bash
docker history nginx:1.27-alpine
docker history --no-trunc nginx:1.27-alpine | head -20
```

Note:
- The bottom-most line is the base layer (from `ADD alpine-minirootfs...`).
- The `<missing>` ID for intermediate layers is normal.
- Lines with `0B` are metadata-only steps (CMD, ENV, EXPOSE).

Find the layer that contributed the most size:

```bash
docker history --format '{{.Size}}\t{{.CreatedBy}}' nginx:1.27-alpine | sort -hr | head -5
```

### Step 3 — Compare three base images

Pull three different base images:

```bash
docker pull alpine:3.20
docker pull debian:12-slim
docker pull gcr.io/distroless/static-debian12
```

List them with size:

```bash
docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' \
  alpine debian gcr.io/distroless/static-debian12
```

Expected order (smallest → largest): `distroless/static` < `alpine` < `debian:12-slim`.

Try `docker run --rm` on each:

```bash
docker run --rm alpine:3.20 echo "hello from alpine"
docker run --rm debian:12-slim echo "hello from debian"
docker run --rm gcr.io/distroless/static-debian12 echo "hello"  # this WILL fail — why?
```

The distroless run fails because the image has no shell (`echo` is a shell builtin). Distroless images can only run pre-compiled binaries.

### Step 4 — Tag vs digest

Find the digest of an image you have:

```bash
docker pull nginx:1.27-alpine
docker inspect -f '{{index .RepoDigests 0}}' nginx:1.27-alpine
# nginx@sha256:e2e1d8f9b3c8...
```

Pull the same image by digest:

```bash
docker pull nginx@sha256:<the-digest-you-just-saw>
docker images --digests | grep nginx
```

Both `nginx:1.27-alpine` and `nginx@sha256:...` should now point to the **same image ID** — they are aliases.

### Step 5 — The OCI manifest

Inspect a multi-platform manifest:

```bash
docker manifest inspect nginx:1.27-alpine | head -40
```

Note the `manifests` array — each entry is a per-architecture manifest. Your local pull picked the one matching your CPU.

To force a specific platform:

```bash
docker pull --platform linux/amd64 alpine:3.20
docker pull --platform linux/arm64 alpine:3.20
```

(On macOS Apple Silicon, you will see emulation warnings on the amd64 pull — expected.)

### Step 6 — Disk usage and cleanup

```bash
docker system df
docker system df -v | head -30
```

Find dangling images:

```bash
docker images --filter "dangling=true"
```

Clean up unused images (keep the running ones):

```bash
docker image prune -a
# Confirm with 'y' — review what's about to be deleted first
```

Final disk check:

```bash
docker system df
```

## Validation

After the cleanup step:

```bash
docker images --filter "dangling=true" --format '{{.ID}}'
```
Expected: empty.

```bash
docker images --format '{{.Repository}}:{{.Tag}}' | sort -u | wc -l
```
Expected: only the images you explicitly want kept (depends on your environment — at most 4–5 if you followed the lab cleanly).

## Going Further (optional)

- Build a "scratch" image from a Go static binary in <2 MB. Compare with the same binary on alpine.
- Use `dive` (`brew install dive`) to explore an image layer-by-layer interactively. Find files that exist in lower layers but are shadowed by higher ones.
- Pull the same `nginx:1.27-alpine` tag on two laptops and compare the digest — they must be identical.
- Use `skopeo inspect docker://nginx:1.27-alpine` (if installed) to read the manifest without pulling the image.
