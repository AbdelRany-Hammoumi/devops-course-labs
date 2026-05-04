# Lab 5 — ConfigMaps and Secrets

## Objectives

- Create a ConfigMap from literals AND from a manifest
- Mount it as environment variables and as files
- Update a ConfigMap and observe the difference between env-var and volume consumption
- Create a Secret and prove that base64 ≠ encryption
- Use the immutable + name-bump pattern for safe rollouts

## Prerequisites

- Lab 04 completed; the kind cluster is up
- No leftover Deployments or Services from earlier labs (`kubectl get all`)

## Duration

~ 20 minutes

## Context

You'll progressively wire up an nginx Pod with externalized config and secret material. Each step shows one consumption pattern.

## Starter Files

```
lab05-config-secrets/
├── 01-configmap.yaml.TODO
├── 02-pod-env.yaml.TODO
├── 03-pod-volume.yaml.TODO
├── 04-secret.yaml.TODO
├── 05-pod-secret.yaml.TODO
└── README.md
```

## Instructions

### Step 1 — Author a ConfigMap

Author `01-configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  LOG_LEVEL: info
  GREETING: "hello from configmap"
  index.html: |
    <!doctype html>
    <html>
      <head><title>Lab05</title></head>
      <body>
        <h1>Served from a ConfigMap-mounted file</h1>
      </body>
    </html>
```

```bash
kubectl apply -f 01-configmap.yaml
kubectl get configmap app-config -o yaml | head -25
kubectl describe configmap app-config
```

Compare with the imperative form:

```bash
kubectl create configmap app-config-imp \
  --from-literal=LOG_LEVEL=info \
  --from-literal=GREETING="hello via CLI" \
  --dry-run=client -o yaml
```

Note `--dry-run=client -o yaml` — it prints the manifest without applying. Useful for converting imperative commands to GitOps-friendly YAML.

### Step 2 — Consume as env vars

Author `02-pod-env.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: env-demo
  labels: { app: env-demo }
spec:
  containers:
    - name: web
      image: nginx:1.27-alpine
      env:
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: LOG_LEVEL
        - name: CUSTOM_GREETING
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: GREETING
      ports: [{ containerPort: 80 }]
```

```bash
kubectl apply -f 02-pod-env.yaml
kubectl wait --for=condition=Ready pod/env-demo --timeout=30s
kubectl exec env-demo -- printenv LOG_LEVEL CUSTOM_GREETING
```

Expected:
```
LOG_LEVEL=info
CUSTOM_GREETING=hello from configmap
```

### Step 3 — Consume as a mounted volume

Author `03-pod-volume.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: volume-demo
  labels: { app: volume-demo }
spec:
  containers:
    - name: web
      image: nginx:1.27-alpine
      ports: [{ containerPort: 80 }]
      volumeMounts:
        - name: web-content
          mountPath: /usr/share/nginx/html
  volumes:
    - name: web-content
      configMap:
        name: app-config
        items:
          - key: index.html
            path: index.html
```

```bash
kubectl apply -f 03-pod-volume.yaml
kubectl wait --for=condition=Ready pod/volume-demo --timeout=30s

kubectl port-forward pod/volume-demo 8080:80 &
sleep 1
curl -s http://localhost:8080/ | head -8
kill %1
```

You should see the HTML from the ConfigMap.

### Step 4 — Update behavior: env vs volume

Edit the ConfigMap:

```bash
kubectl patch configmap app-config -p '{"data":{"GREETING":"updated message"}}'
```

Check the env-var Pod:

```bash
kubectl exec env-demo -- printenv CUSTOM_GREETING
# Still: "hello from configmap"  ← env vars are static, set at Pod creation
```

Check the volume Pod (within ~60s for the kubelet to sync):

```bash
sleep 70
kubectl exec volume-demo -- cat /usr/share/nginx/html/index.html | grep -i served
# Will eventually reflect the updated content (we didn't update index.html, but if you did, it would propagate)
```

Update the actual mounted file:

```bash
kubectl patch configmap app-config --type merge -p '
{
  "data": {
    "index.html": "<h1>UPDATED HTML</h1>"
  }
}'

# Wait up to ~60s for the kubelet sync
sleep 70
kubectl exec volume-demo -- cat /usr/share/nginx/html/index.html
# <h1>UPDATED HTML</h1>
```

To pick up env-var changes, restart the Pod:

```bash
kubectl delete pod env-demo
kubectl apply -f 02-pod-env.yaml
kubectl wait --for=condition=Ready pod/env-demo --timeout=30s
kubectl exec env-demo -- printenv CUSTOM_GREETING
# updated message
```

### Step 5 — Create a Secret

Author `04-secret.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
type: Opaque
stringData:                                     # plain text — kubectl base64-encodes on apply
  username: postgres
  password: super-secret-123
```

```bash
kubectl apply -f 04-secret.yaml
kubectl get secret db-credentials -o yaml
```

Note that the YAML now shows **base64-encoded** values under `data:` (the API server converted `stringData` → `data`).

### Step 6 — Prove base64 ≠ encryption

```bash
kubectl get secret db-credentials -o jsonpath='{.data.password}' | base64 -d
# super-secret-123
```

Anyone with read RBAC on Secrets sees the value in plaintext (after base64 decode). Drive home: **K8s Secrets are NOT encrypted by default.**

In a managed cluster (EKS, GKE, AKS), etcd encryption is usually on. In self-managed kind/kubeadm clusters, it's **off** unless explicitly configured.

### Step 7 — Mount the Secret

Author `05-pod-secret.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secret-demo
  labels: { app: secret-demo }
spec:
  containers:
    - name: web
      image: nginx:1.27-alpine
      env:
        - name: DB_USERNAME
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: username
      volumeMounts:
        - name: secrets
          mountPath: /etc/secrets
          readOnly: true
  volumes:
    - name: secrets
      secret:
        secretName: db-credentials
```

```bash
kubectl apply -f 05-pod-secret.yaml
kubectl wait --for=condition=Ready pod/secret-demo --timeout=30s

kubectl exec secret-demo -- printenv DB_USERNAME
# postgres

kubectl exec secret-demo -- ls /etc/secrets
# password  username

kubectl exec secret-demo -- cat /etc/secrets/password
# super-secret-123
```

The mount is on **tmpfs** (RAM only). Verify on the Node:

```bash
kubectl exec secret-demo -- mount | grep /etc/secrets
# tmpfs on /etc/secrets type tmpfs (ro,relatime,size=...)
```

### Step 8 — Immutable ConfigMap pattern

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-v2
immutable: true
data:
  LOG_LEVEL: debug
EOF

# Try to edit it — rejected
kubectl patch configmap app-config-v2 -p '{"data":{"LOG_LEVEL":"info"}}' \
  || echo "[expected] cannot patch immutable ConfigMap"
```

The flow with hashed names: `app-config-<hash>` → bump the name in the Pod template → triggers a rollout automatically.

### Step 9 — Clean up

```bash
kubectl delete pod env-demo volume-demo secret-demo
kubectl delete configmap app-config app-config-v2
kubectl delete secret db-credentials
kubectl get configmap,secret,pod 2>&1 | head
```

The cluster stays up.

## Validation

```bash
kubectl get pod env-demo volume-demo secret-demo 2>&1 | grep -q NotFound && echo "[ok] pods gone"
kubectl get configmap app-config 2>&1 | grep -q NotFound && echo "[ok] configmap gone"
kubectl get secret db-credentials 2>&1 | grep -q NotFound && echo "[ok] secret gone"
```

## Going Further (optional)

- Replace your `env:` block with `envFrom: [{ configMapRef: { name: app-config } }]`. What happens to the `index.html` key (it tries to become an env var `index.html`)? Why is `envFrom` risky?
- Use `kubectl create secret docker-registry` to create an `imagePullSecret`. Reference it in a Pod spec via `imagePullSecrets:`. Pull a private image (or fake one).
- Mount only one key from a Secret using `items:` (like the ConfigMap volume in step 3).
- Generate a hashed ConfigMap name with kubectl: `kubectl create cm app-config-$(date +%s) --from-literal=KEY=value --dry-run=client -o yaml`.
- Read about External Secrets Operator (https://external-secrets.io/) — what's the operator's CRD called? How would you wire it to Vault or AWS Secrets Manager?
