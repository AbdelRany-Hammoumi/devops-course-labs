# Lab 3 — Deployments and Rolling Updates

## Objectives

- Author a Deployment manifest for a 3-replica nginx workload
- Scale up and down imperatively and declaratively
- Trigger a rolling update and observe the surge / unavailable behavior
- Simulate a broken release and roll back
- Switch between RollingUpdate and Recreate strategies

## Prerequisites

- Lab 02 completed; the kind cluster `devops-course` is up
- All lab02 Pods cleaned up (`kubectl get pods` shows nothing in `default`)

## Duration

~ 30 minutes

## Context

You will work through the full Deployment lifecycle: create, scale, update, fail, rollback. The example uses nginx so you can swap the tag and observe the rolling behavior.

## Starter Files

```
lab03-deployment-rollout/
├── 01-deployment.yaml.TODO
├── 02-recreate.yaml.TODO
└── README.md
```

## Instructions

### Step 1 — Author the Deployment

Author `01-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  labels: { app: web }
spec:
  replicas: 3
  selector:
    matchLabels: { app: web }
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels: { app: web }
    spec:
      containers:
        - name: web
          image: nginx:1.27-alpine
          ports:
            - containerPort: 80
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits:   { cpu: 200m, memory: 128Mi }
          readinessProbe:
            httpGet: { path: /, port: 80 }
            periodSeconds: 5
          livenessProbe:
            httpGet: { path: /, port: 80 }
            periodSeconds: 10
```

`maxSurge: 1, maxUnavailable: 0` = strict zero-downtime: at any point you have ≥ replicas alive.

```bash
kubectl apply -f 01-deployment.yaml
kubectl get deployment,replicaset,pods -l app=web
```

Confirm 3 Pods are Running, all on the `web-<hash>` ReplicaSet.

### Step 2 — Scale

```bash
# Imperative
kubectl scale deployment/web --replicas=5
kubectl get pods -l app=web -w        # 2 new Pods come up; Ctrl-C when 5/5

# Declarative (preferred)
# Edit 01-deployment.yaml: replicas: 4
kubectl apply -f 01-deployment.yaml
kubectl get pods -l app=web           # 1 Pod terminates → back to 4
```

Set replicas back to 3 in the YAML and apply.

### Step 3 — Trigger a rolling update

Bump the image:

```bash
kubectl set image deployment/web web=nginx:1.28-alpine
```

Watch:

```bash
kubectl rollout status deployment/web
kubectl get pods -l app=web -w        # surge: 4 Pods briefly; old terminates as new becomes ready
kubectl get rs -l app=web             # two ReplicaSets — old (replicas=0) + new (replicas=3)
```

Inspect history:

```bash
kubectl rollout history deployment/web
kubectl annotate deployment/web kubernetes.io/change-cause="bump nginx 1.27 → 1.28"
```

Trigger one more rollout for a meaningful history:

```bash
kubectl set image deployment/web web=nginx:1.29-alpine
kubectl annotate deployment/web kubernetes.io/change-cause="bump nginx 1.28 → 1.29"
kubectl rollout history deployment/web
```

### Step 4 — Simulate a broken release

Push a bad image:

```bash
kubectl set image deployment/web web=nginx:does-not-exist
kubectl rollout status deployment/web --timeout=30s
# Eventually: error: deployment "web" exceeded its progress deadline
```

```bash
kubectl get pods -l app=web
# Some Pods stuck in ImagePullBackOff — note maxUnavailable: 0 protected the live ones
```

Real production behavior: the running 1.29 Pods are still serving traffic; the new bad ReplicaSet is stuck.

### Step 5 — Rollback

```bash
kubectl rollout undo deployment/web
kubectl rollout status deployment/web
kubectl get pods -l app=web        # back to 3 Running, all on a recent good RS
kubectl rollout history deployment/web
```

Note: K8s detects rollback as a NEW revision (not "go back to 2"). The undo creates revision 5 = template of revision 3.

### Step 6 — Try Recreate strategy

Author `02-recreate.yaml` based on `01-deployment.yaml` but change:

```yaml
spec:
  strategy:
    type: Recreate
```

(No `rollingUpdate:` block under Recreate.)

Apply:

```bash
kubectl apply -f 02-recreate.yaml
kubectl set image deployment/web web=nginx:1.28-alpine

# Watch: ALL 3 old Pods terminate first, THEN 3 new Pods start
kubectl get pods -l app=web -w
```

The downtime is real — for ~5–15 seconds, no Pod is Available. Use this strategy only when forced to.

Switch back to RollingUpdate:

```bash
kubectl apply -f 01-deployment.yaml
```

### Step 7 — Force-restart without changing the spec

```bash
kubectl rollout restart deployment/web
kubectl rollout status deployment/web
```

The `rollout restart` command rotates Pods one by one (RollingUpdate-style) without changing the Pod template. Useful for picking up updated ConfigMaps, recycling memory, refreshing certs.

### Step 8 — Clean up

```bash
kubectl delete deployment web
kubectl get pods -l app=web        # gone
```

Cluster stays.

## Validation

```bash
kubectl get deployment web 2>&1 | grep -q "NotFound" && echo "[ok] deployment removed"
kubectl get pods -l app=web --no-headers 2>&1 | grep -q . && echo "FAIL: pods linger" || echo "[ok] no pods left"
```

## Going Further (optional)

- Set `progressDeadlineSeconds: 60` on the Deployment. Push a bad image. Confirm `kubectl rollout status` errors out at 60s instead of waiting indefinitely.
- Author an HPA on the Deployment (`kubectl autoscale deployment/web --min=3 --max=10 --cpu-percent=70`). Verify with `kubectl get hpa`.
- Set `revisionHistoryLimit: 2` on the Deployment. Trigger 4 rollouts. Confirm only 2 old ReplicaSets survive.
- Use `kubectl explain deployment.spec` to discover one Deployment field you haven't used yet (e.g. `paused`, `minReadySeconds`).
- Read the full Pod template hash for one of your Pods (`kubectl get pod -o jsonpath='{.metadata.labels.pod-template-hash}'`) and find the matching ReplicaSet.
