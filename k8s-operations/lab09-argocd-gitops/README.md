# Lab 9 (P3) — GitOps with Argo CD

## Objectives

- Install Argo CD via Helm
- Reach the Argo CD UI and CLI
- Deploy the canonical `guestbook` example from a public git repo
- Switch the Application to automated sync + prune + selfHeal
- Trigger manual drift and watch Argo CD revert it
- Observe an upgrade by changing `targetRevision`

## Prerequisites

- Lab P3-02 completed; the kind cluster is up
- Helm ≥ 4.1
- Optional: `argocd` CLI (`brew install argocd`) — UI works without it but CLI is faster

## Duration

~ 30 minutes

## Context

You'll layer Argo CD on top of the cluster and use it to deploy the project's canonical example app. The git repo `argoproj/argocd-example-apps` provides the manifests — public, no auth needed.

## Starter Files

```
lab09-argocd-gitops/
├── 01-app-manual.yaml.TODO       # initial Application: manual sync
├── 02-app-automated.yaml.TODO    # automated + prune + selfHeal version
└── README.md
```

## Instructions

### Step 1 — Install Argo CD

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --version 7.x.x \
  --set server.service.type=ClusterIP \
  --set configs.params."server\.insecure"=true

kubectl rollout status -n argocd deploy/argocd-server --timeout=180s
kubectl get pods -n argocd
```

You should see ~7 Pods running (server, application-controller as StatefulSet, repo-server, redis, applicationset-controller, notifications-controller, dex-server).

### Step 2 — Reach the UI

```bash
# Port-forward the server
kubectl port-forward -n argocd svc/argocd-server 8080:443 &

# Initial admin password
kubectl get secret -n argocd argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d ; echo
```

Open http://localhost:8080 (or https — accept the self-signed cert).
- Username: `admin`
- Password: from the command above

You'll land on the empty Applications dashboard.

### Step 3 — CLI login (optional but useful)

```bash
ADMIN_PWD=$(kubectl get secret -n argocd argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)

argocd login localhost:8080 --username admin --password "$ADMIN_PWD" --insecure

argocd cluster list
# https://kubernetes.default.svc          (in-cluster — auto-registered)
```

### Step 4 — A first Application (manual sync)

Author `01-app-manual.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps
    targetRevision: HEAD
    path: guestbook
  destination:
    server: https://kubernetes.default.svc
    namespace: guestbook
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
```

```bash
kubectl apply -f 01-app-manual.yaml
kubectl get applications -n argocd
```

In the UI: the `guestbook` Application appears, status `OutOfSync` + `Missing` (Argo CD has the manifests but hasn't applied them).

Sync manually:

```bash
argocd app sync guestbook
# Or click "Sync" in the UI

argocd app get guestbook
```

After sync:
- Status: `Synced` + `Healthy`
- Resources: `Service guestbook-ui` + `Deployment guestbook-ui`

```bash
kubectl get all -n guestbook
kubectl port-forward -n guestbook svc/guestbook-ui 3000:80 &
sleep 1
curl -sI http://localhost:3000
kill %1
```

### Step 5 — Switch to automated sync + prune + selfHeal

Author `02-app-automated.yaml` (delta vs `01`):

```yaml
spec:
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

Apply (Argo CD updates the existing Application):

```bash
kubectl apply -f 02-app-automated.yaml
argocd app get guestbook
# SYNC POLICY: Automated (Prune Enabled, Self-Heal Enabled)
```

### Step 6 — Trigger manual drift, observe self-heal

```bash
# Manually scale the Deployment (NOT through git)
kubectl -n guestbook scale deployment guestbook-ui --replicas=5
kubectl get deploy -n guestbook guestbook-ui
# REPLICAS: 5

# Wait ~30 seconds (Argo CD's default sync interval)
sleep 30

kubectl get deploy -n guestbook guestbook-ui
# REPLICAS: 1   ← Argo CD reverted to git's value

argocd app history guestbook
# A new sync event in the history
```

The `selfHeal` policy detected drift and reverted. In the UI: the diff briefly showed, then the sync ran.

### Step 7 — Trigger drift via deletion (prune behavior)

```bash
# Add a "rogue" Service (not in git) — Argo CD does NOT delete it (prune only deletes app-managed resources)
kubectl apply -n guestbook -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: rogue
  labels:
    app: rogue
spec:
  selector: { app: rogue }
  ports: [{ port: 80 }]
EOF

sleep 30
kubectl get svc -n guestbook
# rogue still exists — Argo CD only manages what's in git
```

Now delete a managed resource:

```bash
kubectl -n guestbook delete service guestbook-ui
sleep 30
kubectl get svc -n guestbook
# guestbook-ui re-created by Argo CD (selfHeal)
```

Cleanup the rogue:

```bash
kubectl -n guestbook delete service rogue
```

### Step 8 — Argo CD UI tour

In the Application detail page, explore:
- **APP DETAILS** — source, destination, sync policy
- **APP DIFF** — what differs between git and cluster (should be empty after sync)
- **HISTORY AND ROLLBACK** — every sync event; click to roll back
- **EVENTS** — recent state transitions
- **The visual graph** — resource ownership tree

### Step 9 — Cleanup

```bash
argocd app delete guestbook --cascade
# Or:
kubectl delete application guestbook -n argocd
sleep 5
kubectl delete namespace guestbook --ignore-not-found

helm uninstall argocd -n argocd
kubectl delete namespace argocd

# kill port-forwards
pkill -f "kubectl port-forward" 2>/dev/null
```

## Validation

```bash
helm list -n argocd 2>&1 | grep -q argocd && echo "WARN: argocd still installed" || echo "[ok] argocd gone"
kubectl get ns argocd 2>&1 | grep -q NotFound && echo "[ok] namespace gone"
kubectl get application -A 2>&1 | head -5
```

## Going Further (optional)

- Author an **ApplicationSet** that creates two Applications (`guestbook-dev`, `guestbook-prod`) from a `list` generator. Compare with hand-authoring two Apps.
- Set up the **App-of-Apps** pattern: one Application that points at a directory of Application manifests in git.
- Try a **Helm source**: replace the source with `chart: nginx, repoURL: https://charts.bitnami.com/bitnami, targetRevision: 18.x.x`.
- Add an `ignoreDifferences` block to ignore `spec.replicas` (so HPA can manage it without flapping).
- Set `targetRevision: "v0.5.0"` (a tag) for reproducibility, then bump it.
- Configure OIDC SSO with a public IdP (Okta, Auth0). Out of scope but read the docs.
- Compare with Flux: install Flux v2 in a separate cluster, deploy the same guestbook. Note the API differences.
