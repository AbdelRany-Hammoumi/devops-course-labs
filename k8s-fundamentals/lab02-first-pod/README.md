# Lab 2 — Your First Pod

## Objectives

- Author a Pod manifest from scratch and apply it
- Add liveness/readiness probes and watch them gate the Pod's status
- Add resource requests and limits and observe the QoS class
- Add an init container that gates Pod startup
- Add a native sidecar (K8s 1.29+) that ships logs from a shared volume
- Trigger a CrashLoopBackOff and read the logs

## Prerequisites

- Lab 01 completed; the kind cluster `devops-course` is up
- `kubectl` configured (current context = `kind-devops-course`)

## Duration

~ 30 minutes

## Context

You will progressively build a multi-container Pod in five iterations. Each step adds one feature and proves it works.

## Starter Files

```
lab02-first-pod/
├── 01-bare-pod.yaml.TODO
├── 02-with-probes.yaml.TODO
├── 03-with-resources.yaml.TODO
├── 04-with-init.yaml.TODO
├── 05-with-sidecar.yaml.TODO
└── README.md
```

Each `.yaml.TODO` is a stub; you'll author the contents and rename it to `.yaml` before applying.

## Instructions

### Step 1 — A bare Pod

Author `01-bare-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: hello
  labels: { app: hello }
spec:
  containers:
    - name: web
      image: nginx:1.27-alpine
      ports:
        - containerPort: 80
```

```bash
kubectl apply -f 01-bare-pod.yaml
kubectl get pods -w        # watch the phase transition (Ctrl-C when Running)
kubectl describe pod hello | tail -15
```

The Events section shows: `Scheduled` → `Pulling` → `Pulled` → `Created` → `Started`.

```bash
kubectl port-forward pod/hello 8080:80 &
sleep 1
curl -sI http://localhost:8080
kill %1
kubectl delete pod hello
```

### Step 2 — Add probes

Author `02-with-probes.yaml` (build on step 1):

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: hello
  labels: { app: hello }
spec:
  containers:
    - name: web
      image: nginx:1.27-alpine
      ports: [{ containerPort: 80 }]
      readinessProbe:
        httpGet: { path: /, port: 80 }
        periodSeconds: 5
      livenessProbe:
        httpGet: { path: /, port: 80 }
        periodSeconds: 10
        failureThreshold: 3
      startupProbe:
        httpGet: { path: /, port: 80 }
        failureThreshold: 30
        periodSeconds: 2
```

```bash
kubectl apply -f 02-with-probes.yaml
kubectl get pod hello       # READY column should show 1/1 only after readiness passes
kubectl describe pod hello | grep -A2 -i probe
kubectl get pod hello -o jsonpath='{.status.containerStatuses[0].ready}{"\n"}'
```

Trigger a probe failure: stop nginx inside the container.

```bash
kubectl exec hello -- killall nginx
kubectl get events --field-selector involvedObject.name=hello --sort-by='.lastTimestamp' | tail -10
# Expect: liveness probe failed → container killed → restarted
kubectl get pod hello       # RESTARTS counter incremented
kubectl delete pod hello
```

### Step 3 — Add resource requests + limits

Author `03-with-resources.yaml` (extends step 2):

```yaml
apiVersion: v1
kind: Pod
metadata: { name: hello, labels: { app: hello } }
spec:
  containers:
    - name: web
      image: nginx:1.27-alpine
      ports: [{ containerPort: 80 }]
      resources:
        requests:
          cpu: 50m
          memory: 64Mi
        limits:
          cpu: 200m
          memory: 128Mi
      readinessProbe:
        httpGet: { path: /, port: 80 }
      livenessProbe:
        httpGet: { path: /, port: 80 }
```

```bash
kubectl apply -f 03-with-resources.yaml
kubectl get pod hello -o jsonpath='{.status.qosClass}{"\n"}'
# Expected: Burstable (because requests < limits)
```

Try the **Guaranteed** tier — set requests == limits, re-apply, re-check the QoS.

```bash
kubectl delete pod hello
```

### Step 4 — Add an init container

Author `04-with-init.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata: { name: hello, labels: { app: hello } }
spec:
  initContainers:
    - name: prepare
      image: busybox:1.37
      command:
        - sh
        - -c
        - |
          echo "preparing..."
          for i in 1 2 3 4 5; do echo "step $i"; sleep 1; done
          echo "<h1>Initialized at $(date)</h1>" > /work/index.html
      volumeMounts:
        - name: html
          mountPath: /work
  containers:
    - name: web
      image: nginx:1.27-alpine
      ports: [{ containerPort: 80 }]
      volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
  volumes:
    - name: html
      emptyDir: {}
```

```bash
kubectl apply -f 04-with-init.yaml
kubectl get pod hello -w
# Pod stays Init:0/1 → Init:1/1 → PodInitializing → Running
```

```bash
kubectl logs hello -c prepare       # init container's stdout
kubectl port-forward pod/hello 8080:80 &
sleep 1
curl http://localhost:8080            # served from the volume populated by init
kill %1
kubectl delete pod hello
```

### Step 5 — Native sidecar (1.29+)

Author `05-with-sidecar.yaml`. The init+main pattern of step 4 stays; we add a sidecar that tails a log file from a shared volume.

```yaml
apiVersion: v1
kind: Pod
metadata: { name: hello, labels: { app: hello } }
spec:
  initContainers:
    - name: prepare
      image: busybox:1.37
      command: ["sh", "-c", "echo '<h1>hi</h1>' > /work/index.html"]
      volumeMounts:
        - name: html
          mountPath: /work
    - name: log-tail
      image: busybox:1.37
      restartPolicy: Always           # ← native sidecar (1.29+)
      command:
        - sh
        - -c
        - "while true; do echo \"[sidecar] $(date) — heartbeat\"; sleep 5; done"
  containers:
    - name: web
      image: nginx:1.27-alpine
      ports: [{ containerPort: 80 }]
      volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
  volumes:
    - name: html
      emptyDir: {}
```

```bash
kubectl apply -f 05-with-sidecar.yaml
kubectl get pod hello                            # 2/2 ready (web + sidecar)
kubectl logs hello -c log-tail --tail=3
kubectl logs hello -c web
kubectl delete pod hello
```

### Step 6 — Trigger CrashLoopBackOff

Run a Pod that exits immediately:

```bash
kubectl run crashy --image=busybox:1.37 --restart=Never -- sh -c "echo boom; exit 1"
# (Note: --restart=Never creates a Pod with restartPolicy=Never — won't loop.)

# To see CrashLoopBackOff, do this instead:
kubectl run crashy --image=busybox:1.37 --restart=Always -- sh -c "echo boom; exit 1"
```

Wait 30s and observe:

```bash
kubectl get pod crashy
# crashy   0/1   CrashLoopBackOff   3   45s
```

```bash
kubectl logs crashy --previous     # log from the just-crashed instance
kubectl describe pod crashy | tail -15
```

Clean up:

```bash
kubectl delete pod crashy --force --grace-period=0
```

## Validation

```bash
kubectl get pods
```
Expected: empty (no Pods named `hello` or `crashy`).

```bash
kubectl get events --sort-by='.lastTimestamp' | tail -5
```
Expect entries showing the recent Pod lifecycle events.

## Going Further (optional)

- Add a `tcpSocket` probe instead of `httpGet`. What's the behavior difference?
- Set requests too high (`memory: 100Gi`) and apply. What does `kubectl describe` show? (Hint: `Pending` with `0/3 nodes are available`.)
- Mount a `configMap` into a Pod (you'll meet this properly in chapter 05).
- Run `kubectl debug hello -it --image=busybox:1.37 --share-processes --copy-to=hello-debug`. Compare with `kubectl exec`.
- Check the QoS class for a Pod with NO `requests` or `limits` — what tier is it?
