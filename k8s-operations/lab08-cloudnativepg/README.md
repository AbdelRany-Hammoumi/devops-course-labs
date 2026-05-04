# Lab 8 (P3) — CloudNativePG (Postgres Operator)

## Objectives

- Install the CloudNativePG operator via Helm
- Deploy a 3-instance Postgres cluster declaratively
- Connect to the primary and write data
- Demonstrate auto-failover by killing the primary Pod
- Inspect the resources the operator created on your behalf

## Prerequisites

- Lab P3-02 completed; the kind cluster is up
- Helm ≥ 4.1
- ~1 GB free RAM (CNPG + 3 Postgres instances)
- `psql` (or willingness to use `kubectl exec`)

## Duration

~ 30 minutes

## Context

You'll deploy a real Postgres cluster, then use the operator to test failover. The same workflow applies to other stateful operators (Kafka via Strimzi, Redis via OT operator, etc.).

## Starter Files

```
lab08-cloudnativepg/
├── 01-cluster.yaml.TODO       # the Postgres Cluster CR
└── README.md
```

## Instructions

### Step 1 — Install the operator

```bash
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update

helm install cnpg cnpg/cloudnative-pg \
  --namespace cnpg-system --create-namespace \
  --version 0.22.x

kubectl rollout status -n cnpg-system deploy/cnpg-cloudnative-pg --timeout=120s
kubectl get pods -n cnpg-system
# cnpg-cloudnative-pg-xxx-yyy   1/1   Running   (the operator)

kubectl get crd | grep cnpg
# clusters.postgresql.cnpg.io
# backups.postgresql.cnpg.io
# scheduledbackups.postgresql.cnpg.io
# poolers.postgresql.cnpg.io
# imagecatalogs.postgresql.cnpg.io
# clusterimagecatalogs.postgresql.cnpg.io
```

### Step 2 — Author a Postgres Cluster

Author `01-cluster.yaml`:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg
  namespace: default
spec:
  instances: 3                                   # 1 primary + 2 hot-standby
  imageName: ghcr.io/cloudnative-pg/postgresql:17.2
  storage:
    size: 1Gi
    storageClass: standard
  postgresql:
    parameters:
      max_connections: "100"
      shared_buffers: "128MB"
  bootstrap:
    initdb:
      database: app
      owner: app
  resources:
    requests: { cpu: 100m, memory: 256Mi }
    limits:   { cpu: 500m, memory: 512Mi }
```

```bash
kubectl apply -f 01-cluster.yaml

# Wait for the cluster to come up (~3 minutes for 3 instances)
kubectl get cluster pg -w
# pg   3m   3   3   Cluster in healthy state   pg-1
# Ctrl-C when ready
```

### Step 3 — Inspect what the operator built

```bash
kubectl get all,pvc,secret -l cnpg.io/cluster=pg
```

You'll see:
- 3 Pods (`pg-1`, `pg-2`, `pg-3`)
- 4 Services: `pg-r`, `pg-ro`, `pg-rw`, `pg-rw-r`
- 3 PVCs (per-instance storage)
- Secrets: `pg-app`, `pg-superuser`, `pg-replication`, `pg-ca`, `pg-server`, `pg-replication`

```bash
# Find the current primary
kubectl get cluster pg -o jsonpath='{.status.currentPrimary}{"\n"}'
# pg-1

# All Service endpoints
kubectl get svc -l cnpg.io/cluster=pg
```

The 4 Services:
- `pg-rw` → primary (writes go here)
- `pg-ro` → replicas (read-only)
- `pg-r` → any instance
- `pg-rw-r` → replication endpoint (used by replicas)

### Step 4 — Connect and write data

Get the app credentials from the Secret:

```bash
PGPASSWORD=$(kubectl get secret pg-app -o jsonpath='{.data.password}' | base64 -d)
echo "App password: $PGPASSWORD"
```

Connect via the primary Service:

```bash
kubectl run psql --rm -it --image=postgres:17-alpine --restart=Never --env="PGPASSWORD=$PGPASSWORD" -- \
  psql -h pg-rw -U app -d app
```

Inside `psql`:

```sql
CREATE TABLE notes (id serial PRIMARY KEY, body text, ts timestamptz DEFAULT now());
INSERT INTO notes (body) VALUES ('persistence works'), ('cnpg is cool');
SELECT * FROM notes;
\q
```

Try connecting to the read-only Service:

```bash
kubectl run psql --rm -it --image=postgres:17-alpine --restart=Never --env="PGPASSWORD=$PGPASSWORD" -- \
  psql -h pg-ro -U app -d app -c "SELECT * FROM notes;"
# Returns the same rows — replicated within milliseconds

kubectl run psql --rm -it --image=postgres:17-alpine --restart=Never --env="PGPASSWORD=$PGPASSWORD" -- \
  psql -h pg-ro -U app -d app -c "INSERT INTO notes (body) VALUES ('try-on-replica');"
# ERROR: cannot execute INSERT in a read-only transaction
```

The `pg-ro` Service correctly serves read-only traffic.

### Step 5 — Failover demonstration

```bash
# Note current primary
kubectl get cluster pg -o jsonpath='{.status.currentPrimary}{"\n"}'

# Watch the cluster status in another terminal
kubectl get cluster pg -w &

# Kill the primary
kubectl delete pod pg-1

# Within ~10–30 seconds, the operator promotes a replica
# Watch the status field flip:
#   "Switchover in progress" → "Cluster in healthy state"
#   currentPrimary changes from pg-1 → pg-2 (or pg-3)

kill %1
kubectl get cluster pg -o jsonpath='{.status.currentPrimary}{"\n"}'
# pg-2
```

A new replica `pg-1` will be re-cloned in the background:

```bash
kubectl get pods -l cnpg.io/cluster=pg
# pg-1   1/1   Running   (re-bootstrapped from pg-2 via pg_basebackup)
# pg-2   1/1   Running   ← new primary
# pg-3   1/1   Running
```

### Step 6 — Verify data survived

```bash
kubectl run psql --rm -it --image=postgres:17-alpine --restart=Never --env="PGPASSWORD=$PGPASSWORD" -- \
  psql -h pg-rw -U app -d app -c "SELECT * FROM notes;"
# All 2 rows present — failover preserved committed data
```

### Step 7 — Use the cnpg kubectl plugin (optional)

```bash
# Install the plugin
kubectl krew install cnpg

# Status
kubectl cnpg status pg

# Manual switchover (graceful, planned)
kubectl cnpg promote pg pg-3        # promote pg-3 to primary

# Backup (requires storage backend config — skip if not configured)
# kubectl cnpg backup pg

# Logs
kubectl cnpg logs cluster pg
```

The plugin gives a richer status view than `kubectl get cluster -o yaml`.

### Step 8 — Cleanup

```bash
kubectl delete -f 01-cluster.yaml
# The operator deletes Pods + Services. PVCs by default linger.

kubectl delete pvc -l cnpg.io/cluster=pg

helm uninstall cnpg -n cnpg-system
kubectl delete namespace cnpg-system

# CRDs survive helm uninstall — remove if cleaning up entirely:
kubectl delete crd \
  clusters.postgresql.cnpg.io \
  backups.postgresql.cnpg.io \
  scheduledbackups.postgresql.cnpg.io \
  poolers.postgresql.cnpg.io \
  imagecatalogs.postgresql.cnpg.io \
  clusterimagecatalogs.postgresql.cnpg.io 2>/dev/null
```

## Validation

```bash
helm list -n cnpg-system 2>&1 | grep -q cnpg && echo "WARN: cnpg still installed" || echo "[ok] cnpg gone"
kubectl get cluster pg 2>&1 | grep -q "no resources\|NotFound" && echo "[ok] cluster gone"
kubectl get pvc -l cnpg.io/cluster=pg 2>&1 | head -2
```

## Going Further (optional)

- Configure backups: deploy MinIO via Helm, configure `spec.backup.barmanObjectStore` on the Cluster CR. Trigger `kubectl cnpg backup pg`.
- Try point-in-time recovery: take a backup, drop a table, restore from backup with a target time.
- Set up a connection pool with `kind: Pooler` (PgBouncer-based, also a CNPG CRD).
- Read the operator's logs during a failover: `kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg -f` while killing the primary.
- Compare with the alternative — Zalando postgres-operator. Same domain, different design.
- Inspect the Postgres metrics exposed by CNPG (it exposes a `/metrics` endpoint per Pod). Add a ServiceMonitor (lab 06).
