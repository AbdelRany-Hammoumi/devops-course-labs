# Lab 5 — Multi-Stage Builds and BuildKit

## Objectives

- Containerize a Go HTTP service with a single-stage Dockerfile and observe its size
- Refactor to multi-stage; reduce the image to <10 MB
- Use a BuildKit cache mount to speed up rebuilds
- Scan the final image with Trivy
- Run the container with hardened runtime flags

## Prerequisites

- Lab 04 completed
- Docker Engine ≥ 29.4 (BuildKit on by default)
- A free TCP port `8080`
- Optional but recommended: `trivy` (`brew install trivy` or [installation guide](https://aquasecurity.github.io/trivy/latest/getting-started/installation/))

## Duration

~ 30 minutes

## Context

The starter is a tiny Go HTTP service that responds with a greeting. You will go through three iterations of the Dockerfile and measure each one.

## Starter Code

```
lab05-multi-stage/
├── go.mod
├── cmd/
│   └── server/
│       └── main.go
└── README.md
```

```go
// cmd/server/main.go (provided)
package main

import (
    "fmt"
    "log"
    "net/http"
    "os"
)

func main() {
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        host, _ := os.Hostname()
        fmt.Fprintf(w, `{"message":"hello from container","host":%q}`+"\n", host)
    })
    http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
        w.Write([]byte(`{"status":"ok"}`))
    })
    log.Println("listening on :8080")
    log.Fatal(http.ListenAndServe(":8080", nil))
}
```

## Instructions

### Step 1 — Single-stage build (the bloated version)

Create `Dockerfile.v1`:

```dockerfile
FROM golang:1.23-alpine
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
RUN go build -o /app/server ./cmd/server
EXPOSE 8080
CMD ["/app/server"]
```

Build and measure:

```bash
docker build -f Dockerfile.v1 -t hello-go:v1 .
docker images hello-go:v1 --format '{{.Repository}}:{{.Tag}}\t{{.Size}}'
```

Expected size: **~700 MB**.

Run and verify:

```bash
docker run -d --rm --name hello -p 8080:8080 hello-go:v1
curl http://localhost:8080/
docker stop hello
```

### Step 2 — Multi-stage refactor

Create `Dockerfile.v2`:

```dockerfile
# Stage 1: builder
FROM golang:1.23-alpine AS builder
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/server ./cmd/server

# Stage 2: runtime
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /out/server /server
EXPOSE 8080
USER nonroot
ENTRYPOINT ["/server"]
```

```bash
docker build -f Dockerfile.v2 -t hello-go:v2 .
docker images hello-go --format '{{.Repository}}:{{.Tag}}\t{{.Size}}'
```

Expected sizes:
```
hello-go:v1   ~700 MB
hello-go:v2   ~8–12 MB
```

Verify the runtime image still works:

```bash
docker run -d --rm --name hello -p 8080:8080 hello-go:v2
curl http://localhost:8080/
curl http://localhost:8080/health
docker stop hello
```

### Step 3 — Add BuildKit cache mounts

Create `Dockerfile.v3`:

```dockerfile
# syntax=docker/dockerfile:1
FROM golang:1.23-alpine AS builder
WORKDIR /src
COPY go.mod ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download
COPY . .
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/server ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /out/server /server
EXPOSE 8080
USER nonroot
ENTRYPOINT ["/server"]
```

Build twice and time it:

```bash
time docker build -f Dockerfile.v3 -t hello-go:v3 --no-cache .   # first build, populates cache
echo "// noop" >> cmd/server/main.go
time docker build -f Dockerfile.v3 -t hello-go:v3 .              # second build, uses cache
```

The second build should be noticeably faster — the Go module download and build cache are reused.

### Step 4 — Scan with Trivy (if installed)

```bash
trivy image hello-go:v3
```

Expected: very few or zero CVEs (distroless static + Go binary has minimal attack surface).

For comparison:

```bash
trivy image hello-go:v1   # full Go toolchain on Alpine — usually a handful of CVEs
```

If Trivy is not installed, use `docker scout cves hello-go:v3` (built into modern Docker) as a fallback.

### Step 5 — Hardened runtime

Run the container with strict isolation:

```bash
docker run -d --rm \
  --name hello \
  -p 8080:8080 \
  --read-only \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  --user 65532 \
  hello-go:v3

curl http://localhost:8080/
docker stop hello
```

Verify it still works. Then break it deliberately:

```bash
docker run --rm --read-only --cap-drop=ALL hello-go:v3 sh
# Expected: ENTRYPOINT runs the server. The --read-only and cap-drop have no observable effect for this app — it doesn't write or escalate.
```

### Step 6 — Multi-platform build (optional, requires buildx)

```bash
docker buildx ls
# If you don't see a multi-platform builder, create one:
docker buildx create --name multi --use --bootstrap

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t hello-go:multiarch \
  -f Dockerfile.v3 \
  --load=false \
  .
```

`--load=false` is needed because the local daemon can't store multi-arch images. In real CI you'd add `--push` and a registry tag.

### Step 7 — Clean up

```bash
docker rmi hello-go:v1 hello-go:v2 hello-go:v3 hello-go:multiarch 2>/dev/null
docker buildx rm multi 2>/dev/null
docker image prune -f
```

## Validation

```bash
docker images hello-go --format '{{.Repository}}:{{.Tag}}'
```
Expected: empty.

```bash
ls Dockerfile.v*
```
You should have authored at least `Dockerfile.v1`, `Dockerfile.v2`, `Dockerfile.v3`. Compare them with `diff` — the changes are surgical.

## Going Further (optional)

- Add a third stage `debug` based on `debian:12-slim` that includes the binary plus `curl`, `bash`, and `strace`. Build it with `--target debug`.
- Use BuildKit secrets to pass a fake "private registry token" (just to see the syntax — no actual private access needed).
- Build the v3 image with `--cache-to=type=local,dest=/tmp/cache --cache-from=type=local,src=/tmp/cache` and verify cache reuse from disk.
- Add a `HEALTHCHECK` to v3 — it requires an HTTP client. Hint: distroless has none. Either include a tiny health-check binary or skip distroless for this exercise.
- Run `docker buildx imagetools inspect ghcr.io/distroless/static-debian12` to read the upstream multi-platform manifest.
