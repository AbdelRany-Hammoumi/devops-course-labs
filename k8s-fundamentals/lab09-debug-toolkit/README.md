# Lab 9 — kubectl Debug Toolkit

## Objectives

- Diagnose three intentionally-broken Pods with describe + logs + events
- Use exec to verify behavior from inside a running container
- Use port-forward to reach a Service from your laptop
- Use `kubectl debug` to attach an ephemeral container to a distroless Pod
- Extract resource fields with jsonpath / Go templates

## Prerequisites

- Lab 08 completed; the kind cluster is up
- All previous-lab resources cleaned up (`kubectl get all,pvc -A | grep -v kube-`)
- Optional: `metrics-server` installed for the `kubectl top` exercise

## Duration

~ 20 minutes

## Context

You're on call. Three Pods are broken in different ways. You need to diagnose each one without `exec`-ing first — exhaust the cheap commands.

## Starter Files

```
lab09-debug-toolkit/
├── 01-broken-image.yaml          # provided — broken Pod #1
├── 02-broken-probe.yaml          # provided — broken Pod #2
├── 03-broken-config.yaml         # provided — broken Pod #3
├── 04-distroless.yaml            # provided — distroless Pod for kubectl debug
└── README.md
```

## Instructions

### Step 1 — Install metrics-server (optional)

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/components.yaml

# kind needs --kubelet-insecure-tls — patch the deployment
kubectl patch -n kube-system deployment metrics-server --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

kubectl rollout status -n kube-system deployment/metrics-server --timeout=90s
kubectl top nodes
```

If you skip this, the `kubectl top` step at the end won't work — everything else will.

### Step 2 — Pod #1: ImagePullBackOff

```bash
kubectl apply -f 01-broken-image.yaml
kubectl get pod broken-image
# broken-image   0/1   ErrImagePull   0   10s
```

Diagnose without exec or guessing:

```bash
kubectl describe pod broken-image | tail -20
# Events should mention: "Failed to pull image", "manifest unknown" or similar
kubectl get events --field-selector involvedObject.name=broken-image --sort-by='.lastTimestamp'
```

What's the issue? Look at the image tag in the YAML.

Fix in place:
```bash
kubectl set image pod/broken-image web=nginx:1.27-alpine
```

Wait — you can't update Pod images directly via kubectl set image (Pod is immutable except a few fields). The correct fix:

```bash
kubectl delete pod broken-image
# Then edit the YAML to use a real tag (nginx:1.27-alpine) and re-apply.
```

### Step 3 — Pod #2: CrashLoopBackOff

```bash
kubectl apply -f 02-broken-probe.yaml
sleep 20
kubectl get pod broken-probe
# broken-probe   0/1   CrashLoopBackOff   3 (10s ago)   45s
```

Diagnose:

```bash
kubectl describe pod broken-probe | tail -20
# Events: Liveness probe failed: HTTP probe failed with statuscode: 404

kubectl logs broken-probe                   # might be empty or short
kubectl logs broken-probe --previous        # KEY — logs from the killed instance
```

The probe hits `/non-existent`; nginx returns 404; kubelet kills and restarts. Fix the probe path in the manifest:

```bash
# Edit 02-broken-probe.yaml — change /non-existent to /
kubectl delete pod broken-probe
kubectl apply -f 02-broken-probe.yaml
kubectl wait --for=condition=Ready pod/broken-probe --timeout=30s
```

### Step 4 — Pod #3: Pending forever

```bash
kubectl apply -f 03-broken-config.yaml
sleep 5
kubectl get pod broken-config
# broken-config   0/1   Pending   0   10s
```

Diagnose:

```bash
kubectl describe pod broken-config | tail -15
# Events: 0/3 nodes are available: ... insufficient cpu, ...
# OR: configmap "missing-config" not found
```

What's wrong? Look at the manifest's resources.requests.cpu (4 cores per Pod is more than any kind Node).

Fix:
```bash
# Edit 03-broken-config.yaml — drop requests.cpu to 100m
kubectl delete pod broken-config
kubectl apply -f 03-broken-config.yaml
kubectl wait --for=condition=Ready pod/broken-config --timeout=30s
```

### Step 5 — Pod #4: Distroless, no shell

```bash
kubectl apply -f 04-distroless.yaml
kubectl wait --for=condition=Ready pod/distroless --timeout=30s

# Try to exec in
kubectl exec -it distroless -- sh
# Error: exec: "sh": executable file not found in $PATH
```

Use `kubectl debug` instead:

```bash
kubectl debug -it distroless --image=busybox:1.37 --target=app --share-processes
# You're now in a busybox shell, with `--share-processes` letting you see distroless's processes
```

Inside:

```sh
ps aux                # see the distroless app's process
ls /proc/1/root/      # peek at the distroless filesystem (limited)
exit
```

The ephemeral container is gone after exit; the original Pod is unchanged.

### Step 6 — port-forward + service exec

Apply a small Deployment + Service:

```bash
kubectl create deployment web --image=nginx:1.27-alpine --replicas=2
kubectl expose deployment web --port=80
kubectl wait --for=condition=Available deployment/web --timeout=60s
```

Reach the Service from your laptop:

```bash
kubectl port-forward svc/web 8080:80 &
sleep 1
curl -sI http://localhost:8080
kill %1
```

Run a one-shot from inside the cluster (without leaving kubectl):

```bash
kubectl run curl-test --rm -it --image=alpine:3.20 --restart=Never -- sh -c "wget -qO- http://web/ | head -3"
```

### Step 7 — jsonpath / templates / top

```bash
# Names + nodes
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\n"}{end}'

# Restart counts (find chronic crashers)
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\t"}{.status.containerStatuses[0].restartCount}{"\n"}{end}' \
  | sort -k2 -nr | head -5

# Internal IPs of Nodes
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}'

# Resource usage (needs metrics-server from step 1)
kubectl top pods --sort-by=memory 2>/dev/null \
  || echo "metrics-server not installed — skip"
```

### Step 8 — Clean up

```bash
kubectl delete pod broken-image broken-probe broken-config distroless --ignore-not-found
kubectl delete deployment web --ignore-not-found
kubectl delete svc web --ignore-not-found
```

## Validation

```bash
kubectl get pods --no-headers | wc -l
```
Expected: `0` (or just system stuff if you're in a non-default namespace).

## Going Further (optional)

- Install `stern` (`brew install stern`) and try `stern .` in a busy namespace. Compare with `kubectl logs -l app=web`.
- Install krew + `kubectl tree`: `kubectl krew install tree`. Then `kubectl tree deployment web` shows the ownership graph (Deployment → RS → Pods).
- Create a debug copy of an existing Pod: `kubectl debug <pod> -it --image=nicolaka/netshoot --copy-to=<pod>-debug --share-processes`. The original keeps running.
- Use `kubectl get events -w` while you `kubectl apply` a Deployment — watch the events flow.
- Run `kubectl auth can-i --list` for your current user. Then for a SA. Compare.
