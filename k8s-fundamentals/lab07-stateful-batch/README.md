# Lab 7 — StatefulSets, DaemonSets, Jobs, CronJobs

## Objectives

- Deploy a StatefulSet with per-replica PVCs and observe ordered scaling
- Resolve per-Pod DNS via a headless Service
- Deploy a DaemonSet that runs on every Node (control-plane + workers)
- Run a Job to completion and read its logs
- Schedule a CronJob and observe each run as a separate Job

## Prerequisites

- Lab 06 completed; the kind cluster is up
- No leftover Pods/PVCs/Deployments from previous labs (`kubectl get all,pvc`)

## Duration

~ 30 minutes

## Context

You'll author one manifest per controller type. Each demonstrates a different lifecycle pattern.

## Starter Files

```
lab07-stateful-batch/
├── 01-statefulset.yaml.TODO
├── 02-daemonset.yaml.TODO
├── 03-job.yaml.TODO
├── 04-cronjob.yaml.TODO
└── README.md
```

## Instructions

### Step 1 — A StatefulSet with per-Pod PVC

Author `01-statefulset.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
  labels: { app: web }
spec:
  clusterIP: None                       # headless — required for StatefulSet DNS
  selector: { app: web }
  ports:
    - port: 80
      targetPort: 80
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web
spec:
  serviceName: web                      # must match the headless Service above
  replicas: 3
  selector:
    matchLabels: { app: web }
  template:
    metadata:
      labels: { app: web }
    spec:
      containers:
        - name: nginx
          image: nginx:1.27-alpine
          ports: [{ containerPort: 80 }]
          volumeMounts:
            - name: data
              mountPath: /usr/share/nginx/html
          lifecycle:
            postStart:
              exec:
                command:
                  - sh
                  - -c
                  - "echo '<h1>I am '$HOSTNAME'</h1>' > /usr/share/nginx/html/index.html"
  volumeClaimTemplates:
    - metadata: { name: data }
      spec:
        accessModes: [ReadWriteOnce]
        storageClassName: standard
        resources:
          requests: { storage: 256Mi }
```

```bash
kubectl apply -f 01-statefulset.yaml
kubectl get statefulset,pvc -l app=web
kubectl get pods -l app=web -w
# Watch: web-0 created → Ready → web-1 created → Ready → web-2 created → Ready
```

Once all 3 are Ready, verify:

```bash
kubectl get pods -l app=web
# web-0   1/1   Running
# web-1   1/1   Running
# web-2   1/1   Running

kubectl get pvc -l app=web
# data-web-0   Bound
# data-web-1   Bound
# data-web-2   Bound
```

### Step 2 — Test per-Pod DNS

```bash
kubectl run dnstest --rm -it --image=alpine:3.20 -- sh
```

Inside:

```sh
# Each Pod has its own A record
nslookup web-0.web.default.svc.cluster.local
nslookup web-1.web.default.svc.cluster.local

# The headless Service returns all Pod IPs
nslookup web

# Each Pod serves its own content
wget -qO- http://web-0.web/
wget -qO- http://web-1.web/
wget -qO- http://web-2.web/
exit
```

You should see `<h1>I am web-0</h1>`, `web-1`, `web-2` respectively.

### Step 3 — Scale and observe ordering

```bash
kubectl scale statefulset/web --replicas=4
kubectl get pods -l app=web -w
# web-3 created last; ordered, after web-0/1/2 are all Ready
```

```bash
kubectl scale statefulset/web --replicas=2
kubectl get pods -l app=web -w
# web-3 terminates first, then web-2 — reverse order
```

```bash
kubectl get pvc -l app=web
# All 4 PVCs still present (data-web-0..3) — survived the scale-down
```

By default, PVCs survive StatefulSet scaling. Useful for "scale back up later"; can leak storage if not cleaned up.

### Step 4 — A DaemonSet

Author `02-daemonset.yaml`:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-info
spec:
  selector:
    matchLabels: { app: node-info }
  template:
    metadata:
      labels: { app: node-info }
    spec:
      tolerations:
        - operator: Exists                  # tolerate every taint, including control-plane
      containers:
        - name: info
          image: busybox:1.37
          command:
            - sh
            - -c
            - |
              while true; do
                echo "[$(date)] running on $(hostname) — Node: $NODE_NAME"
                sleep 30
              done
          env:
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
```

```bash
kubectl apply -f 02-daemonset.yaml
kubectl get daemonset node-info
# DESIRED  CURRENT  READY  ...  NODE SELECTOR  AGE
# 3        3        3      ...                  10s

kubectl get pods -l app=node-info -o wide
# 3 Pods — one on the control-plane Node and one on each worker
```

Watch one Pod's output:

```bash
POD=$(kubectl get pods -l app=node-info -o jsonpath='{.items[0].metadata.name}')
kubectl logs -f $POD --tail=2
# Ctrl-C to detach
```

Without `tolerations: [{operator: Exists}]`, the DaemonSet would skip the control-plane Node (which has a NoSchedule taint).

### Step 5 — A Job

Author `03-job.yaml`:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: pi-calc
spec:
  backoffLimit: 3
  parallelism: 2
  completions: 4
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: pi
          image: perl:5.40-slim
          command:
            - perl
            - -Mbignum=bpi
            - -wle
            - "print bpi(200)"
```

```bash
kubectl apply -f 03-job.yaml
kubectl get job pi-calc -w
# COMPLETIONS  DURATION  AGE
# 0/4          5s        5s
# 2/4          (parallelism kicks in)
# 4/4          completed

kubectl get pods -l job-name=pi-calc
kubectl logs job/pi-calc            # logs from one Pod
```

Note: 2 Pods run in parallel; once a Pod completes, the next is scheduled until 4 successes total.

### Step 6 — A CronJob

Author `04-cronjob.yaml`:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: heartbeat
spec:
  schedule: "*/1 * * * *"               # every minute (for the lab — never use in prod)
  timeZone: "UTC"
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 1
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      backoffLimit: 1
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: hb
              image: busybox:1.37
              command: ["sh", "-c", "echo \"[$(date)] heartbeat from $HOSTNAME\""]
```

```bash
kubectl apply -f 04-cronjob.yaml
kubectl get cronjob heartbeat
# SCHEDULE      SUSPEND   ACTIVE   LAST SCHEDULE
# */1 * * * *   False     0        <none>          (waiting)
```

Wait ~2 minutes:

```bash
kubectl get jobs            # 1 or 2 Jobs created (depending on timing)
kubectl get pods -l app.kubernetes.io/managed-by=cronjob-controller
```

```bash
# Trigger a manual run (1.21+)
kubectl create job --from=cronjob/heartbeat manual-run

# Suspend the CronJob (stop further scheduling)
kubectl patch cronjob heartbeat -p '{"spec":{"suspend":true}}'

# Read logs from one of the runs
LATEST=$(kubectl get jobs -l app=heartbeat,parent=heartbeat \
  --sort-by='.metadata.creationTimestamp' -o jsonpath='{.items[-1].metadata.name}')
kubectl logs job/$LATEST 2>/dev/null \
  || kubectl logs $(kubectl get pods -l job-name=$LATEST -o name | head -1)
```

The `successfulJobsHistoryLimit: 2` means only the 2 most recent successful Jobs survive — the rest auto-delete.

### Step 7 — Clean up

```bash
# StatefulSet (PVCs survive — explicit cleanup)
kubectl delete statefulset web
kubectl delete service web
kubectl delete pvc -l app=web

# DaemonSet
kubectl delete daemonset node-info

# Job
kubectl delete job pi-calc

# CronJob and any leftover Jobs/Pods
kubectl delete cronjob heartbeat
kubectl delete job -l parent=heartbeat 2>/dev/null

kubectl get all,pvc -l app=web
kubectl get all -l app=node-info
```

## Validation

```bash
kubectl get statefulset,daemonset,job,cronjob 2>&1 | tail -5
kubectl get pvc 2>&1 | tail -5
```
Expected: empty (or just system stuff in `kube-system`).

## Going Further (optional)

- Use `persistentVolumeClaimRetentionPolicy: { whenDeleted: Delete, whenScaled: Delete }` (1.27+) on the StatefulSet. Re-run the scale exercise; observe PVCs disappear with the Pods.
- Add `partition: 2` to the StatefulSet's `updateStrategy.rollingUpdate`. Bump the image. Confirm only `web-2` updates; the others stay on the old image.
- Author an Indexed Job (`completionMode: Indexed`) with 5 completions. Each Pod gets a `JOB_COMPLETION_INDEX` env. Print it from the container.
- Set `concurrencyPolicy: Replace` on the CronJob and add `sleep 90` to the heartbeat command. Observe what happens at the next-minute boundary.
- Use `kubectl explain cronjob.spec` to discover one field you haven't used yet.
- Add a `nodeSelector: { "kubernetes.io/os": linux }` to the DaemonSet template — verify it still lands on every (Linux) Node.
