# Lab 5 (P3) — cert-manager + Self-Signed TLS

## Objectives

- Install cert-manager via Helm
- Author a self-signed root CA via the `selfSigned` issuer
- Author a leaf Certificate signed by that CA
- Serve HTTPS through a Traefik IngressRoute using the auto-generated Secret
- Verify the certificate's expiry and the rotation behavior

## Prerequisites

- Lab P3-03 completed (Traefik installed; if you uninstalled it, redo step 1 of lab 03)
- Helm ≥ 4.1, kubectl ≥ 1.35, openssl
- Free port 80/443 (or use port-forward)

## Duration

~ 25 minutes

## Context

Real production uses Let's Encrypt + ACME. That requires public DNS, which the kind cluster doesn't have. We'll use the **selfSigned + CA pattern** instead — same cert-manager mechanics, no internet required. Migrating to ACME is a one-line ClusterIssuer change.

## Starter Files

```
lab05-cert-manager-tls/
├── 01-issuers.yaml.TODO       # selfSigned + CA ClusterIssuers
├── 02-root-cert.yaml.TODO     # Root CA Certificate
├── 03-leaf-cert.yaml.TODO     # Leaf cert for our domain
├── 04-app.yaml.TODO           # nginx app + IngressRoute using TLS
└── README.md
```

## Instructions

### Step 1 — Verify Traefik is installed

```bash
kubectl get pods -n traefik
kubectl get ingressclass traefik
```

If not, redo step 1 of lab 03.

### Step 2 — Install cert-manager

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --version v1.20.x \
  --set installCRDs=true

kubectl rollout status -n cert-manager deploy/cert-manager --timeout=120s
kubectl get pods -n cert-manager
# 3 Pods: controller, webhook, cainjector
```

Verify the CRDs:

```bash
kubectl get crd | grep cert-manager
# certificaterequests.cert-manager.io
# certificates.cert-manager.io
# challenges.acme.cert-manager.io
# clusterissuers.cert-manager.io
# issuers.cert-manager.io
# orders.acme.cert-manager.io
```

### Step 3 — Two ClusterIssuers (selfSigned + CA)

Author `01-issuers.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: lab-ca
spec:
  ca:
    secretName: root-ca-secret      # filled by step 4 — the root cert
```

```bash
kubectl apply -f 01-issuers.yaml
kubectl get clusterissuer
```

The `lab-ca` issuer is `Not Ready` for now — it depends on a Secret we'll create.

### Step 4 — Mint a root CA Certificate

Author `02-root-cert.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: root-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: lab-root-ca
  secretName: root-ca-secret
  duration: 8760h                  # 1 year
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: selfsigned
    kind: ClusterIssuer
```

```bash
kubectl apply -f 02-root-cert.yaml
kubectl wait --for=condition=Ready certificate/root-ca -n cert-manager --timeout=60s

kubectl get secret root-ca-secret -n cert-manager
kubectl get clusterissuer lab-ca           # should now be Ready=True
```

Behind the scenes:
- selfSigned issuer minted a self-signed cert
- Secret `root-ca-secret` in `cert-manager` namespace
- The `lab-ca` ClusterIssuer reads that Secret as its signing key

### Step 5 — A leaf cert for our app

Author `03-leaf-cert.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: app-tls
  namespace: default
spec:
  secretName: app-tls
  issuerRef:
    name: lab-ca
    kind: ClusterIssuer
  commonName: app.localtest.me
  dnsNames:
    - app.localtest.me
  duration: 720h                     # 30 days
  renewBefore: 240h                  # renew at 20-day mark
```

```bash
kubectl apply -f 03-leaf-cert.yaml
kubectl wait --for=condition=Ready certificate/app-tls --timeout=60s

kubectl describe certificate app-tls
kubectl get secret app-tls -o jsonpath='{.data.tls\.crt}' \
  | base64 -d \
  | openssl x509 -noout -subject -issuer -dates
```

Expected output:

```
subject=CN = app.localtest.me
issuer=CN = lab-root-ca
notBefore=May  4 ...
notAfter=Jun  3 ...           ← 30 days
```

### Step 6 — Wire it into Traefik

Author `04-app.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: app }
spec:
  replicas: 1
  selector: { matchLabels: { app: app } }
  template:
    metadata: { labels: { app: app } }
    spec:
      containers:
        - name: web
          image: hashicorp/http-echo:1.0
          args: ["-text=hello over TLS"]
          ports: [{ containerPort: 5678 }]
---
apiVersion: v1
kind: Service
metadata: { name: app }
spec:
  selector: { app: app }
  ports:
    - port: 80
      targetPort: 5678
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata: { name: app }
spec:
  entryPoints: [websecure]
  routes:
    - match: Host(`app.localtest.me`)
      kind: Rule
      services: [{ name: app, port: 80 }]
  tls:
    secretName: app-tls
```

```bash
kubectl apply -f 04-app.yaml
kubectl wait --for=condition=Available deploy/app --timeout=60s
```

Reach the HTTPS endpoint (use port-forward if NodePort 443 isn't bound):

```bash
kubectl port-forward -n traefik svc/traefik 8443:443 &

# Verify the cert chain (use --cacert to trust our private CA)
kubectl get secret -n cert-manager root-ca-secret -o jsonpath='{.data.tls\.crt}' \
  | base64 -d > /tmp/lab-root-ca.crt

curl -sI --resolve app.localtest.me:8443:127.0.0.1 \
  --cacert /tmp/lab-root-ca.crt \
  https://app.localtest.me:8443/

# Or skip cert verification (not for production):
curl -sI -k --resolve app.localtest.me:8443:127.0.0.1 \
  https://app.localtest.me:8443/
```

You should see `HTTP/2 200`.

```bash
# Without --cacert: certificate not trusted (expected — it's our private CA)
curl -sI --resolve app.localtest.me:8443:127.0.0.1 https://app.localtest.me:8443/
# curl: (60) SSL certificate problem: unable to get local issuer certificate
```

Kill the port-forward when done: `kill %1`.

### Step 7 — Force a renewal (optional)

```bash
# cert-manager exposes a "renew" annotation
kubectl annotate certificate app-tls cert-manager.io/issue-temporary-certificate="true" --overwrite
# ... or use kubectl-cert-manager plugin: kubectl cert-manager renew app-tls

# Watch the Secret get regenerated
kubectl get secret app-tls -o jsonpath='{.metadata.annotations.cert-manager\.io/certificate-name}{"\n"}'
```

In production, cert-manager renews automatically when `now > notAfter - renewBefore`.

### Step 8 — Cleanup

```bash
kubectl delete -f 04-app.yaml --ignore-not-found
kubectl delete -f 03-leaf-cert.yaml --ignore-not-found
kubectl delete -f 02-root-cert.yaml --ignore-not-found
kubectl delete -f 01-issuers.yaml --ignore-not-found

helm uninstall cert-manager -n cert-manager
kubectl delete namespace cert-manager
rm -f /tmp/lab-root-ca.crt
```

## Validation

```bash
helm list -n cert-manager 2>&1 | grep -q cert-manager \
  && echo "WARN: cert-manager still installed" \
  || echo "[ok] cert-manager gone"
kubectl get clusterissuer 2>&1 | grep -qE "selfsigned|lab-ca" \
  && echo "WARN: issuers linger" \
  || echo "[ok] no test issuers"
```

## Going Further (optional)

- Replace the `lab-ca` ClusterIssuer with a **Let's Encrypt staging** ACME issuer (HTTP-01 via Traefik). Note: only works if you have public DNS pointing at your kind cluster — usually not the case for a laptop. Read the YAML.
- Add the Ingress annotation pattern: `cert-manager.io/cluster-issuer: lab-ca` on a standard Ingress (instead of an explicit Certificate). Verify cert-manager auto-creates a Certificate.
- Set `duration: 1h` on a Certificate. Watch cert-manager renew it automatically (with `renewBefore` shorter than 1h, this happens fast).
- Use `kubectl-cert-manager` plugin (via krew): `kubectl krew install cert-manager`. Try `kubectl cert-manager status app-tls`.
- Inspect the Order + Challenge for an ACME issuer (only visible if using ACME — read the docs).
