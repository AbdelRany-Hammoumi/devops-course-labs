# Lab 3 (P3) — Ingress with Traefik v3

## Objectives

- Install Traefik v3 via Helm with NodePort access
- Deploy two backend Services (api + web) and route to them via Ingress
- Switch one route to Traefik's IngressRoute CRD for richer matching
- Apply a rate-limit Middleware
- Reach the Traefik dashboard

## Prerequisites

- Lab P3-02 completed; the kind cluster is up
- Helm ≥ 4.1, kubectl ≥ 1.35
- Ports 80 and 443 free on the host (the kind config maps them)

## Duration

~ 30 minutes

## Context

You'll stand up the cluster's HTTP entry point. By the end, two apps respond on `localhost` based on hostname, with a working dashboard.

## Starter Files

```
lab03-traefik-ingress/
├── 01-backends.yaml           # provided — api + web Deployments and Services
├── 02-ingress.yaml.TODO       # standard Ingress
├── 03-ingressroute.yaml.TODO  # Traefik CRD
├── 04-middleware.yaml.TODO    # rate-limit middleware
└── README.md
```

## Instructions

### Step 1 — Install Traefik

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

helm install traefik traefik/traefik \
  --version 34.x.x \
  --namespace traefik --create-namespace \
  --set service.type=NodePort \
  --set ports.web.nodePort=30080 \
  --set ports.websecure.nodePort=30443 \
  --set ingressClass.name=traefik \
  --set ingressClass.isDefaultClass=true \
  --set providers.kubernetesIngress.enabled=true \
  --set providers.kubernetesCRD.enabled=true \
  --set dashboard.enabled=true

kubectl rollout status -n traefik deploy/traefik --timeout=120s
kubectl get pods -n traefik
kubectl get svc -n traefik
kubectl get ingressclass
```

> The kind cluster maps host port 80 → control-plane Node port 80. The Traefik service uses NodePort 30080 for HTTP. We'll wire host port 80 to NodePort 30080 next.

For our setup, the kind cluster's `extraPortMappings` directly forward 80→80 to the control-plane Node. Patch the Traefik Service to bind the standard ports:

```bash
kubectl patch svc traefik -n traefik --type=json -p='[
  {"op": "replace", "path": "/spec/ports/0/port", "value": 80},
  {"op": "replace", "path": "/spec/ports/0/nodePort", "value": 80},
  {"op": "replace", "path": "/spec/ports/1/port", "value": 443},
  {"op": "replace", "path": "/spec/ports/1/nodePort", "value": 443}
]' 2>/dev/null || true
```

If the patch fails (kind disallows NodePort 80/443), use port-forward instead:

```bash
kubectl port-forward -n traefik svc/traefik 8080:80 &
```

For the rest of the lab we'll use `localhost:8080` if the patch failed, or `localhost` otherwise. Pick one and stick with it.

### Step 2 — Deploy two backends

`01-backends.yaml` (provided):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  replicas: 1
  selector: { matchLabels: { app: api } }
  template:
    metadata: { labels: { app: api } }
    spec:
      containers:
        - name: api
          image: hashicorp/http-echo:1.0
          args: ["-text=hello from api"]
          ports: [{ containerPort: 5678 }]
---
apiVersion: v1
kind: Service
metadata: { name: api }
spec:
  selector: { app: api }
  ports:
    - port: 80
      targetPort: 5678
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: web }
spec:
  replicas: 1
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
        - name: web
          image: hashicorp/http-echo:1.0
          args: ["-text=hello from web"]
          ports: [{ containerPort: 5678 }]
---
apiVersion: v1
kind: Service
metadata: { name: web }
spec:
  selector: { app: web }
  ports:
    - port: 80
      targetPort: 5678
```

```bash
kubectl apply -f 01-backends.yaml
kubectl wait --for=condition=Available deploy/api deploy/web --timeout=60s
```

### Step 3 — Standard Ingress with host routing

Author `02-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
    - host: api.localtest.me
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api
                port: { number: 80 }
    - host: web.localtest.me
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web
                port: { number: 80 }
```

```bash
kubectl apply -f 02-ingress.yaml
kubectl get ingress shop
```

Test (replace `localhost` with `localhost:8080` if you used port-forward in step 1):

```bash
curl -H "Host: api.localtest.me" http://localhost/
# hello from api

curl -H "Host: web.localtest.me" http://localhost/
# hello from web
```

> `localtest.me` resolves to 127.0.0.1 globally — no /etc/hosts edit needed.

### Step 4 — IngressRoute (Traefik CRD)

Switch the api route to a richer Traefik IngressRoute. Author `03-ingressroute.yaml`:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: api-richroute
spec:
  entryPoints: [web]
  routes:
    - match: Host(`api.localtest.me`) && PathPrefix(`/v1`)
      kind: Rule
      services:
        - name: api
          port: 80
    - match: Host(`api.localtest.me`)
      kind: Rule
      services:
        - name: api
          port: 80
```

```bash
# Remove the api rule from the standard Ingress (avoid conflict)
kubectl apply -f 03-ingressroute.yaml

curl -H "Host: api.localtest.me" http://localhost/v1/anything
curl -H "Host: api.localtest.me" http://localhost/
```

Both work — IngressRoute matches on path prefix `/v1` first; falls through to the catch-all.

### Step 5 — Add a rate-limit middleware

Author `04-middleware.yaml`:

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: rate-limit-low
spec:
  rateLimit:
    average: 5         # 5 req/s
    burst: 5
```

Update the IngressRoute to use it (edit `03-ingressroute.yaml` and add `middlewares:`):

```yaml
spec:
  entryPoints: [web]
  routes:
    - match: Host(`api.localtest.me`)
      kind: Rule
      services: [{ name: api, port: 80 }]
      middlewares:
        - name: rate-limit-low
```

```bash
kubectl apply -f 04-middleware.yaml
kubectl apply -f 03-ingressroute.yaml

# Hammer the endpoint
for i in $(seq 1 30); do
  curl -sI -H "Host: api.localtest.me" http://localhost/ | head -1
done
```

You'll see a mix of `HTTP/1.1 200 OK` and `HTTP/1.1 429 Too Many Requests`. Traefik enforces the rate limit.

### Step 6 — Traefik dashboard

```bash
kubectl port-forward -n traefik deploy/traefik 9000:9000 &
```

Open in a browser: http://localhost:9000/dashboard/

Browse:
- HTTP routers
- Services
- Middlewares

Kill the port-forward when done: `kill %1`.

### Step 7 — Cleanup

```bash
kubectl delete -f 04-middleware.yaml --ignore-not-found
kubectl delete -f 03-ingressroute.yaml --ignore-not-found
kubectl delete -f 02-ingress.yaml --ignore-not-found
kubectl delete -f 01-backends.yaml --ignore-not-found
helm uninstall traefik -n traefik
kubectl delete namespace traefik
```

## Validation

```bash
helm list -n traefik 2>&1 | grep -q traefik \
  && echo "WARN: traefik still installed" \
  || echo "[ok] traefik gone"
kubectl get ingress -A 2>&1 | grep -q shop \
  && echo "WARN: ingress lingers" \
  || echo "[ok] no test ingress"
```

## Going Further (optional)

- Add a TLS Secret manually (`kubectl create secret tls ...` with a self-signed cert) and route via `entrypoint: websecure`.
- Author a `redirectScheme: https` Middleware and apply it to the HTTP IngressRoute. Verify HTTP requests redirect to HTTPS.
- Configure `basicAuth` Middleware: create an htpasswd Secret and protect the api route. Test with `curl -u user:pass`.
- Replace the standard Ingress with a Gateway API HTTPRoute (Traefik v3 supports it). Read https://traefik.io/blog/ on the Gateway API support.
- Inspect a real ingress-nginx annotation (e.g. `nginx.ingress.kubernetes.io/rewrite-target`) and find its Traefik equivalent (StripPrefix Middleware).
