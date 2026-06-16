# DevOps Course — Labs

Hands-on labs for the DevOps course covering **Docker**, **Kubernetes Fundamentals**, **Kubernetes Operations**, **Serverless (OpenFaaS)**, and **Observability**.

Each lab is a short, self-contained exercise: a `README.md` with objectives, step-by-step instructions, validation, and a "Going further" section. Minimal starter files (`# TODO` markers) accompany the README where relevant.

## How to use

1. Read your session's chapter (slides) — your instructor will share the deck or its PDF.
2. Open the matching lab folder under the right pillar.
3. Follow the README, run the commands, validate as you go.
4. Solutions stay in the instructor's private repo — try first, ask second.

## Layout

```
docker/                  P1 — Docker fundamentals
k8s-fundamentals/        P2 — Kubernetes fundamentals
k8s-operations/          P3 — Kubernetes platform & operations
serverless-openfaas/     P4 — Serverless with OpenFaaS
observability/           P5 — Observability (metrics, logs, traces)
setup/                   shared cluster setup (kind config, setup checks)
```

Each pillar holds `labNN-<slug>/` directories. Lab numbers track the chapter that introduces the concept.

The `observability/` pillar also ships a full-day team challenge handout —
`challenge-observability-day.md` (and `.fr.md`) — that chains the monitoring, logs, and
tracing labs into a paired dev-and-platform exercise with a final demo.

## Prerequisites

A working local toolchain (May 2026):

- **Docker** ≥ 29.4
- **kind** ≥ 0.31
- **kubectl** ≥ 1.35
- **Helm** ≥ 4.1
- **faas-cli** ≥ 0.18  *(P4 only)*
- **Git**, **make**, a recent shell (bash/zsh)

The labs are tested on macOS, Linux, and WSL2. No cloud account is required.

## Cluster bootstrap

The shared `setup/kind-cluster.yaml` defines a 1 control-plane + 2 worker cluster with port mappings for ingress (80/443):

```bash
kind create cluster --name devops-course --config setup/kind-cluster.yaml
kubectl get nodes
```

Reset between labs:

```bash
kind delete cluster --name devops-course
```

## Conventions

- All commands and YAML are in **English**.
- Instructions assume the cluster `devops-course` is running unless stated otherwise.
- Examples use `localhost:5000` for a local registry — see `docker/lab08-registries`.
- Ingress examples assume **Traefik v3** (ingress-nginx is retired since 2026-03-24).

## License

Lab content is provided for educational use within the course. See each pillar's instructor for redistribution terms.
