# Lab 2 (P3) — Helm Chart from Scratch + OCI

## Objectives

- Install, upgrade, rollback, and uninstall a public chart (bitnami/nginx) with the Helm 4 CLI
- Author a minimal chart from scratch, parameterize it via values
- Render with `helm template` and validate with `helm lint`
- Push the chart to a local OCI registry, then install from OCI

## Prerequisites

- Lab P3-01 completed; the kind cluster `devops-course` is up
- `helm` ≥ 4.1 installed (`brew install helm` or [installation guide](https://helm.sh/docs/intro/install/))

## Duration

~ 30 minutes

## Context

You'll exercise Helm two ways: as a consumer (install a public chart) and as an author (write one). The chart you build wraps a 2-Pod nginx Deployment + Service + ConfigMap.

## Starter Files

```
lab02-helm-chart/
├── mychart/
│   ├── Chart.yaml.TODO
│   ├── values.yaml.TODO
│   └── templates/
│       └── (you create these)
└── README.md
```

## Instructions

### Step 1 — Install a public chart

Add the Bitnami repo and install nginx:

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm search repo bitnami/nginx
helm install demo bitnami/nginx --version 18.x.x \
  --namespace demo --create-namespace \
  --set service.type=ClusterIP \
  --set replicaCount=2

helm list -A
kubectl get deploy,svc,po -n demo
```

Verify:

```bash
kubectl wait --for=condition=Available deploy -n demo --all --timeout=120s
kubectl port-forward -n demo svc/demo-nginx 8080:80 &
sleep 2
curl -sI http://localhost:8080
kill %1
```

### Step 2 — Upgrade and rollback

Bump replicas:

```bash
helm upgrade demo bitnami/nginx --version 18.x.x \
  --namespace demo --reuse-values \
  --set replicaCount=3

helm history demo -n demo
kubectl get pods -n demo
```

Roll back to revision 1:

```bash
helm rollback demo 1 -n demo
helm history demo -n demo
kubectl get pods -n demo            # back to 2 replicas
```

Uninstall:

```bash
helm uninstall demo -n demo
kubectl delete namespace demo
```

### Step 3 — Author a chart from scratch

Create `mychart/Chart.yaml`:

```yaml
apiVersion: v2
name: mychart
description: A minimal app chart
type: application
version: 0.1.0
appVersion: "1.0.0"
```

Create `mychart/values.yaml`:

```yaml
replicaCount: 2
image:
  repository: nginx
  tag: 1.27-alpine
service:
  type: ClusterIP
  port: 80
greeting: "hello from helm"
```

Create `mychart/templates/_helpers.tpl`:

```go-template
{{- define "mychart.fullname" -}}
{{ .Release.Name }}-{{ .Chart.Name }}
{{- end -}}

{{- define "mychart.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
```

Create `mychart/templates/configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "mychart.fullname" . }}
  labels:
    {{- include "mychart.labels" . | nindent 4 }}
data:
  index.html: |
    <html><body><h1>{{ .Values.greeting }}</h1></body></html>
```

Create `mychart/templates/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "mychart.fullname" . }}
  labels:
    {{- include "mychart.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app.kubernetes.io/name: {{ .Chart.Name }}
      app.kubernetes.io/instance: {{ .Release.Name }}
  template:
    metadata:
      labels:
        {{- include "mychart.labels" . | nindent 8 }}
    spec:
      containers:
        - name: web
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          ports:
            - containerPort: 80
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html
      volumes:
        - name: html
          configMap:
            name: {{ include "mychart.fullname" . }}
```

Create `mychart/templates/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "mychart.fullname" . }}
  labels:
    {{- include "mychart.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: 80
  selector:
    app.kubernetes.io/name: {{ .Chart.Name }}
    app.kubernetes.io/instance: {{ .Release.Name }}
```

### Step 4 — Lint and render

```bash
helm lint ./mychart
helm template myapp ./mychart                           # see the rendered YAML
helm template myapp ./mychart --show-only templates/deployment.yaml
helm template myapp ./mychart --set replicaCount=5 \
  | grep "replicas:"
```

### Step 5 — Install your chart

```bash
helm install myapp ./mychart
helm list

kubectl get deploy,svc,cm -l app.kubernetes.io/instance=myapp
kubectl wait --for=condition=Available deploy/myapp-mychart --timeout=60s

kubectl port-forward svc/myapp-mychart 8080:80 &
sleep 1
curl -s http://localhost:8080/
kill %1
```

Should print `<h1>hello from helm</h1>`.

### Step 6 — Upgrade with custom values

```bash
helm upgrade myapp ./mychart \
  --set greeting="hello v2" \
  --set replicaCount=3

helm history myapp
helm get values myapp                       # user-set
helm get values myapp --all | head -20      # all (with defaults)
```

```bash
kubectl rollout status deploy/myapp-mychart
kubectl port-forward svc/myapp-mychart 8080:80 &
sleep 1
curl -s http://localhost:8080/
kill %1
```

### Step 7 — Push to a local OCI registry

Run a registry (same as P1 ch08):

```bash
docker run -d --name registry -p 5000:5000 -v reg-data:/var/lib/registry registry:3
sleep 1
curl -fsS http://localhost:5000/v2/
```

Package and push the chart:

```bash
helm package ./mychart                      # produces mychart-0.1.0.tgz
ls *.tgz

helm push mychart-0.1.0.tgz oci://localhost:5000/charts
```

(Helm allows pushing to localhost:5000 without TLS by default. For real registries, configure auth.)

### Step 8 — Install from OCI

Uninstall the local-path version:

```bash
helm uninstall myapp
```

Install from the OCI registry:

```bash
helm install myapp-oci oci://localhost:5000/charts/mychart --version 0.1.0
helm list

kubectl wait --for=condition=Available deploy/myapp-oci-mychart --timeout=60s
kubectl get deploy,svc,cm -l app.kubernetes.io/instance=myapp-oci
```

### Step 9 — Cleanup

```bash
helm uninstall myapp-oci 2>/dev/null
helm uninstall myapp 2>/dev/null
helm repo remove bitnami 2>/dev/null

docker rm -f registry
docker volume rm reg-data
rm -f mychart-*.tgz
```

## Validation

```bash
helm list -A | grep -q . && echo "WARN: releases linger" || echo "[ok] no releases"
docker ps -a --filter name=registry --format '{{.Names}}' | grep -q . \
  && echo "WARN: registry container linger" \
  || echo "[ok] registry gone"
```

## Going Further (optional)

- Add a `values.schema.json` to your chart for JSON-Schema validation. Try `helm install` with bad values; observe the rejection.
- Add a `templates/tests/test-connection.yaml` with the `helm.sh/hook: test` annotation that wgets the Service. Run `helm test myapp`.
- Wrap your chart with a subchart: add a dependency on `bitnami/redis` (or any small chart). `helm dependency update` and `helm install`.
- Use `helm template` to render the chart, then apply with `kubectl apply -f -`. Observe the difference (Helm doesn't track this as a release).
- Try `helm upgrade --install --atomic myapp ./mychart --set image.tag=does-not-exist`. With `--atomic`, Helm rolls back automatically on failure.
