# Lab 6 — Persistent Volumes and Claims

## Objectives

- Inspect the cluster's default StorageClass and understand its parameters
- Author a PVC and watch dynamic provisioning create the matching PV
- Mount the PVC in a Pod, write data, prove persistence across Pod recreation
- Resize a bound PVC online (allowVolumeExpansion)
- Practice the reclaim-policy implications (Delete vs Retain)

## Prerequisites

- Lab 05 completed; the kind cluster is up
- `kubectl` configured (current context = `kind-devops-course`)

## Duration

~ 30 minutes

## Context

You will use kind's default `local-path` StorageClass, which dynamically provisions Node-local directories. The mechanics are identical to cloud SCs (EBS, PD); only the backend differs.

## Starter Files

```
lab06-pv-pvc/
├── 01-pvc.yaml.TODO
├── 02-pod-writer.yaml.TODO
├── 03-pod-reader.yaml.TODO
└── README.md
```

## Instructions

### Step 1 — Inspect the default StorageClass

```bash
kubectl get storageclass
# NAME                 PROVISIONER             DEFAULT   ALLOWVOLUMEEXPANSION
# standard (default)   rancher.io/local-path   true      false

kubectl get sc standard -o yaml | head -25
```

Note:
- `provisioner: rancher.io/local-path` — provisions Node-local paths on demand
- `volumeBindingMode: WaitForFirstConsumer` — bind happens when a Pod claims the PVC
- `reclaimPolicy: Delete` — disk goes when PVC goes
- `allowVolumeExpansion: false` (in stock kind) — we'll see the consequences in step 6

### Step 2 — Author a PVC

Author `01-pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: standard
  resources:
    requests:
      storage: 1Gi
```

```bash
kubectl apply -f 01-pvc.yaml
kubectl get pvc data
# Expected with WaitForFirstConsumer:
# NAME   STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
# data   Pending                                       standard
```

The PVC stays `Pending`. With `volumeBindingMode: WaitForFirstConsumer`, no PV is created yet — we need a Pod to consume it first.

```bash
kubectl describe pvc data | tail -10
# Events: ... waiting for first consumer to be created before binding
```

### Step 3 — Mount the PVC, write data

Author `02-pod-writer.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: writer
spec:
  containers:
    - name: writer
      image: busybox:1.37
      command:
        - sh
        - -c
        - |
          echo "First write at $(date)" >> /data/log.txt
          echo "host: $HOSTNAME"        >> /data/log.txt
          tail -f /data/log.txt
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: data
```

```bash
kubectl apply -f 02-pod-writer.yaml
kubectl wait --for=condition=Ready pod/writer --timeout=60s

# Now the PVC binds:
kubectl get pvc data
# NAME   STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
# data   Bound    pvc-...  1Gi        RWO            standard

kubectl get pv
# (one PV listed, owned by the PVC)

kubectl logs writer
kubectl exec writer -- cat /data/log.txt
```

### Step 4 — Add another write, then destroy the Pod

```bash
kubectl exec writer -- sh -c 'echo "Second write at $(date)" >> /data/log.txt'
kubectl exec writer -- cat /data/log.txt
# First write at ...
# host: writer
# Second write at ...

kubectl delete pod writer
kubectl get pvc data
# Still Bound. The PV survived.
```

### Step 5 — Mount the same PVC from a new Pod

Author `03-pod-reader.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: reader
spec:
  containers:
    - name: reader
      image: busybox:1.37
      command: ["sh", "-c", "cat /data/log.txt && sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: data
```

```bash
kubectl apply -f 03-pod-reader.yaml
kubectl wait --for=condition=Ready pod/reader --timeout=30s
kubectl logs reader
# First write at ...
# host: writer
# Second write at ...
```

The data wrote by `writer` is intact in `reader`. The PV survived Pod death.

### Step 6 — Try to resize (and see the limitation)

The kind `standard` SC has `allowVolumeExpansion: false`. Try to resize anyway:

```bash
kubectl patch pvc data -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'
# Error: persistentvolumeclaims "data" is forbidden:
#   only dynamically provisioned pvc can be resized and the storageclass that provisions
#   the pvc must support resize
```

Edit the StorageClass to allow expansion (admin operation):

```bash
kubectl patch storageclass standard -p '{"allowVolumeExpansion":true}'
kubectl get sc standard -o jsonpath='{.allowVolumeExpansion}{"\n"}'
# true
```

Retry the patch:

```bash
kubectl patch pvc data -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'
kubectl get pvc data
# CAPACITY now shows 2Gi (or "FileSystemResizePending" briefly)
```

> **Note**: local-path-provisioner doesn't actually resize the host directory (no quota enforced), so the resize is logical only. On a real cloud SC (EBS, PD), the underlying disk is grown and `resize2fs` runs automatically.

### Step 7 — Reclaim policy in action

```bash
kubectl get pvc data -o jsonpath='{.spec.volumeName}{"\n"}'
PV_NAME=$(kubectl get pvc data -o jsonpath='{.spec.volumeName}')
echo "PV: $PV_NAME"

kubectl get pv $PV_NAME -o jsonpath='{.spec.persistentVolumeReclaimPolicy}{"\n"}'
# Delete
```

Delete the PVC:

```bash
kubectl delete pod reader
kubectl delete pvc data
kubectl get pv
# The PV is gone too — reclaimPolicy: Delete kept its promise
```

If you wanted to preserve the data on PVC deletion: edit the PV BEFORE deleting the PVC:

```bash
# Hypothetical, before kubectl delete pvc:
# kubectl patch pv $PV_NAME -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```

Or set the SC's reclaim policy at creation time. **For production: set `Retain` on stateful workloads.**

### Step 8 — Clean up

```bash
kubectl delete pod writer reader --ignore-not-found
kubectl delete pvc data --ignore-not-found
kubectl get pv,pvc 2>&1 | head
```

Roll back the SC patch (so the cluster matches the kind defaults):

```bash
kubectl patch storageclass standard -p '{"allowVolumeExpansion":false}'
```

## Validation

```bash
kubectl get pvc data 2>&1 | grep -q "NotFound" && echo "[ok] PVC removed"
kubectl get pv | grep -q "pvc-" && echo "WARN: PVs still allocated" || echo "[ok] no orphan PVs"
```

## Going Further (optional)

- Author a static PV by hand (with `hostPath:` for demo) and a matching PVC. Observe the binding without dynamic provisioning.
- Try `accessModes: [ReadWriteMany]` on a PVC — what happens with the local-path SC? (Hint: it doesn't support RWX.) Which CSI drivers do (NFS, CephFS, EFS)?
- Set `volumeBindingMode: Immediate` on a custom SC, then create a PVC. Compare with the WFC default. What changes?
- Run a `Postgres` Deployment using a PVC for `/var/lib/postgresql/data`. Insert a row, delete the Pod, recreate, confirm the row survived.
- Use the `VolumeSnapshot` API (if supported by your CSI) to snapshot the PVC, restore to a new PVC.
