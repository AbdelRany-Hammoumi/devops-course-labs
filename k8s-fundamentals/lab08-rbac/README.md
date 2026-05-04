# Lab 8 — Namespaces, RBAC, ServiceAccounts

## Objectives

- Create a namespace with a ResourceQuota and a LimitRange
- Test the quota by trying to exceed it
- Create a ServiceAccount in that namespace
- Author a Role + RoleBinding granting limited permissions
- Verify the SA's permissions with `kubectl auth can-i --as=...`
- Bind a default ClusterRole (`view`) into the namespace via RoleBinding

## Prerequisites

- Lab 07 completed; the kind cluster is up
- All previous-lab Pods cleaned up

## Duration

~ 25 minutes

## Context

You are the platform admin for a team called `team-a`. They need their own namespace with cost guardrails, a service-account-bound deploy bot, and read-only access for a reviewer.

## Starter Files

```
lab08-rbac/
├── 01-namespace.yaml.TODO
├── 02-quota-limits.yaml.TODO
├── 03-sa-and-role.yaml.TODO
├── 04-view-binding.yaml.TODO
└── README.md
```

## Instructions

### Step 1 — Namespace

Author `01-namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: team-a
  labels:
    team: a
    env: dev
```

```bash
kubectl apply -f 01-namespace.yaml
kubectl get ns team-a
```

### Step 2 — ResourceQuota + LimitRange

Author `02-quota-limits.yaml`:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-a-quota
  namespace: team-a
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 2Gi
    limits.cpu: "4"
    limits.memory: 4Gi
    pods: "10"
    services: "5"
    persistentvolumeclaims: "3"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: team-a-defaults
  namespace: team-a
spec:
  limits:
    - type: Container
      default:
        cpu: 200m
        memory: 256Mi
      defaultRequest:
        cpu: 50m
        memory: 64Mi
      max:
        cpu: "1"
        memory: 1Gi
```

```bash
kubectl apply -f 02-quota-limits.yaml
kubectl get resourcequota,limitrange -n team-a
kubectl describe resourcequota team-a-quota -n team-a
```

### Step 3 — Test the quota

Deploy a Pod without explicit resources — LimitRange auto-fills defaults:

```bash
kubectl run mypod --image=nginx:1.27-alpine -n team-a
kubectl get pod mypod -n team-a -o jsonpath='{.spec.containers[0].resources}{"\n"}'
# {"limits":{"cpu":"200m","memory":"256Mi"},"requests":{"cpu":"50m","memory":"64Mi"}}
```

Try to deploy a Pod that exceeds the LimitRange max:

```bash
kubectl run too-big --image=nginx:1.27-alpine -n team-a \
  --overrides='{"spec":{"containers":[{"name":"too-big","image":"nginx:1.27-alpine","resources":{"requests":{"cpu":"3","memory":"3Gi"}}}]}}'
# Expected error:
# Error: maximum cpu usage per Container is 1, but request is 3
```

Quota usage:

```bash
kubectl describe resourcequota team-a-quota -n team-a
# requests.cpu: 50m / 2  (only mypod consumes 50m)
```

### Step 4 — A ServiceAccount with a Role

Author `03-sa-and-role.yaml`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: deploy-bot
  namespace: team-a
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: deployer
  namespace: team-a
rules:
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: [""]
    resources: ["pods", "configmaps", "services"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: deploy-bot-can-deploy
  namespace: team-a
subjects:
  - kind: ServiceAccount
    name: deploy-bot
    namespace: team-a
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: deployer
```

```bash
kubectl apply -f 03-sa-and-role.yaml
kubectl get sa,role,rolebinding -n team-a
```

### Step 5 — Verify with `kubectl auth can-i`

```bash
SA="system:serviceaccount:team-a:deploy-bot"

kubectl auth can-i create deployments --as=$SA -n team-a
# yes

kubectl auth can-i create deployments --as=$SA -n default
# no    ← Role is namespaced to team-a

kubectl auth can-i list secrets --as=$SA -n team-a
# no    ← Role doesn't include secrets

kubectl auth can-i create namespaces --as=$SA
# no    ← namespaces are cluster-scoped; SA has no ClusterRole

# Print every action the SA can take in team-a
kubectl auth can-i --list --as=$SA -n team-a | head -20
```

### Step 6 — Bind the default `view` ClusterRole into the namespace

Author `04-view-binding.yaml`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: reviewer
  namespace: team-a
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: reviewer-can-view
  namespace: team-a
subjects:
  - kind: ServiceAccount
    name: reviewer
    namespace: team-a
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole                     # ← binding a ClusterRole...
  name: view                            # ← ...into one namespace via RoleBinding
```

```bash
kubectl apply -f 04-view-binding.yaml

REV="system:serviceaccount:team-a:reviewer"
kubectl auth can-i list pods       --as=$REV -n team-a   # yes
kubectl auth can-i list secrets    --as=$REV -n team-a   # NO (view excludes secrets)
kubectl auth can-i create pods     --as=$REV -n team-a   # no
kubectl auth can-i list pods       --as=$REV -n default  # no (RoleBinding scopes to team-a)
```

This is the canonical pattern for "give Alice read-only on this team's namespace": bind the default `view` ClusterRole via a RoleBinding.

### Step 7 — Run a Pod as the SA, prove it from inside

```bash
kubectl run cli --image=bitnami/kubectl:1.35 -n team-a \
  --overrides='{"spec":{"serviceAccountName":"deploy-bot"}}' \
  --command -- sleep 3600

kubectl wait --for=condition=Ready pod/cli -n team-a --timeout=30s

# Inside the Pod, kubectl picks up the SA token automatically
kubectl exec -it cli -n team-a -- kubectl get pods
# (should succeed — SA can list pods in team-a)

kubectl exec -it cli -n team-a -- kubectl get pods -n default
# Error from server (Forbidden): pods is forbidden:
#   User "system:serviceaccount:team-a:deploy-bot" cannot list resource "pods" in API group "" in the namespace "default"
```

### Step 8 — Clean up

```bash
kubectl delete namespace team-a
# Deleting the namespace cascades — all SAs, Roles, RoleBindings, Pods, quotas inside go with it.
```

## Validation

```bash
kubectl get ns team-a 2>&1 | grep -q "NotFound" && echo "[ok] namespace gone"
```

## Going Further (optional)

- Make the `deployer` Role narrower: only `get`, `list`, `watch` (read-only). Verify with `can-i`.
- Add a `ClusterRoleBinding` granting `view` cluster-wide to a Group named `auditors`. Test with `--as=alice --as-group=auditors`.
- Use the projected SA token (slide 13's pattern) — bind it to an audience like `kubernetes.default.svc`. Inspect with `kubectl exec cli -- cat /var/run/secrets/tokens/token`.
- Annotate a Pod with `kubectl.kubernetes.io/default-container` to skip the `-c <name>` flag on `kubectl logs / exec`.
- Try `kubectl auth can-i --list -n kube-system` as the deploy-bot SA. What's the result? Why?
