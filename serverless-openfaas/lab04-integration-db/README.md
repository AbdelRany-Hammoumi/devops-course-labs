# Lab 4 (P4) — Function Talks to Postgres

## Objectives

- Deploy a Postgres cluster (or reuse from lab P3-08)
- Author a function that lists rows from a `notes` table
- Mount the DB credentials as a Secret file
- Verify the connection at scale (raw socket test, then function load)
- Observe DB connection counts during a load test

## Prerequisites

- OpenFaaS installed (lab P4-02)
- CloudNativePG installed + a running `pg` cluster (lab P3-08; if uninstalled, redo)
- Local registry running on `:5000`

## Duration

~ 25 minutes

## Context

You'll wire a function to a real database. Pattern transfers to any DB / cache / KV store.

## Instructions

### Step 1 — Ensure Postgres is running

```bash
kubectl get cluster -A
# default   pg   3   3   Cluster in healthy state   pg-1
```

If absent: redo P3-08's setup (install CNPG operator + apply the Cluster CR).

Pre-populate the `notes` table:

```bash
PGPASSWORD=$(kubectl get secret pg-app -o jsonpath='{.data.password}' | base64 -d)

kubectl run psql --rm -it --image=postgres:17-alpine --restart=Never \
  --env="PGPASSWORD=$PGPASSWORD" -- \
  psql -h pg-rw -U app -d app -c "
    CREATE TABLE IF NOT EXISTS notes (id serial PRIMARY KEY, body text, ts timestamptz DEFAULT now());
    INSERT INTO notes (body) VALUES ('first'), ('second'), ('third');
  "
```

### Step 2 — Mount the Postgres credentials

Copy the `pg-app` Secret into `openfaas-fn` (cross-namespace Secret access isn't direct in K8s):

```bash
PG_USER=$(kubectl get secret pg-app -o jsonpath='{.data.username}' | base64 -d)
PG_PASS=$(kubectl get secret pg-app -o jsonpath='{.data.password}' | base64 -d)

kubectl -n openfaas-fn create secret generic db-username --from-literal=db-username="$PG_USER" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n openfaas-fn create secret generic db-password --from-literal=db-password="$PG_PASS" --dry-run=client -o yaml | kubectl apply -f -
```

> Production: use the External Secrets Operator (P2 ch05) to sync from a vault. For the lab: copy via kubectl.

### Step 3 — Author the function

```bash
mkdir lab04 && cd lab04
faas-cli template store pull python3-http
faas-cli new --lang python3-http notes-list
```

Replace `notes-list/handler.py`:

```python
import json
import os
import psycopg

DB_HOST = os.environ.get("DB_HOST", "pg-rw.default.svc.cluster.local")
DB_NAME = os.environ.get("DB_NAME", "app")

# Connection reused across invocations within ONE replica
_conn = None


def _get_conn():
    global _conn
    if _conn is None or _conn.closed:
        with open("/var/openfaas/secrets/db-username") as f:
            user = f.read().strip()
        with open("/var/openfaas/secrets/db-password") as f:
            pwd = f.read().strip()
        _conn = psycopg.connect(
            host=DB_HOST,
            dbname=DB_NAME,
            user=user,
            password=pwd,
            connect_timeout=5,
        )
    return _conn


def handle(event, context):
    try:
        conn = _get_conn()
        with conn.cursor() as cur:
            cur.execute("SELECT id, body FROM notes ORDER BY id DESC LIMIT 10")
            rows = cur.fetchall()
        body = json.dumps([{"id": r[0], "body": r[1]} for r in rows])
        return {"statusCode": 200, "body": body, "headers": {"Content-Type": "application/json"}}
    except Exception as e:
        return {"statusCode": 500, "body": f"db error: {e}", "headers": {"Content-Type": "text/plain"}}
```

`notes-list/requirements.txt`:

```
psycopg[binary]==3.2.3
```

### Step 4 — Author the stack.yml

```yaml
version: 1.0
provider:
  name: openfaas
  gateway: http://localhost:8080
functions:
  notes-list:
    lang: python3-http
    handler: ./notes-list
    image: registry:5000/notes-list:0.1.0
    environment:
      DB_HOST: pg-rw.default.svc.cluster.local
      DB_NAME: app
    secrets:
      - db-username
      - db-password
    labels:
      com.openfaas.scale.min: "1"
      com.openfaas.scale.max: "5"
```

### Step 5 — Deploy and invoke

```bash
faas-cli up -f stack.yml

# Invoke
curl -s http://localhost:8080/function/notes-list | jq
# [
#   {"id": 3, "body": "third"},
#   {"id": 2, "body": "second"},
#   {"id": 1, "body": "first"}
# ]
```

### Step 6 — Verify connection reuse

```bash
# Tail the gateway logs to see invocation timing
faas-cli logs notes-list &

# Hit the function 5 times rapidly
for i in $(seq 1 5); do
  time curl -s http://localhost:8080/function/notes-list > /dev/null
done

# kill log stream
kill %1
```

The first request takes ~50-200 ms (DB connection setup). Subsequent ones < 30 ms (reused connection within the same replica).

### Step 7 — Observe DB connection counts

```bash
# In one terminal: watch active connections
kubectl exec -it pg-1 -- psql -U app -d app -c "
  SELECT pid, application_name, client_addr, state, backend_start
  FROM pg_stat_activity
  WHERE datname='app' AND application_name != 'psql'
"
```

Run a simple load test:

```bash
# Hammer the function
for i in $(seq 1 50); do
  curl -s http://localhost:8080/function/notes-list > /dev/null &
done
wait

# Re-run the pg_stat_activity query — see how many connections OpenFaaS replicas hold
```

With 1 replica + connection reuse: 1 connection. Scale up replicas:

```bash
kubectl -n openfaas-fn scale deploy/notes-list --replicas=5
sleep 5
```

Re-run the load test. Expect ~5 active connections (one per replica).

### Step 8 — Cleanup

```bash
faas-cli remove notes-list
kubectl -n openfaas-fn delete secret db-username db-password
```

## Validation

```bash
faas-cli list 2>&1 | grep -q notes-list && echo "WARN: function still deployed" || echo "[ok] removed"
```

## Going Further (optional)

- Install a `Pooler` (PgBouncer) via CloudNativePG: `kind: Pooler`. Point the function at the pooler instead of `pg-rw`.
- Run the load test with `wrk` or `vegeta` for higher concurrency. Watch DB connection limits.
- Add `prometheus.io/scrape: "true"` and a `psycopg_connection_total` counter exposed by the function. Build a Grafana panel.
- Replace Postgres with Redis (deploy via Helm). Re-do the function for a key-value lookup.
- Add a write path: a second function `notes-create` that INSERTs. Use Read-Only Service `pg-ro` for reads, primary for writes.
- Migrate the secret-copy step to External Secrets Operator (sync from a Vault).
