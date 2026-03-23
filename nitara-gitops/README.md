# nitara-gitops

ArgoCD GitOps config repo for the Nitara platform.
**This is the single source of truth for all 4 Kubernetes environments.**

---

## Architecture

```
Proxmox (256 CPU / 1024 GB RAM)
│
├── Vmbr-20  Management cluster  →  ArgoCD + Jenkins + Grafana + SonarQube
│
├── Vmbr-30  DEV / Test
│   ├── DEV  cluster  (3 masters + 5 workers)  ←── ArgoCD auto-syncs
│   ├── Test cluster  (3 masters + 5 workers)  ←── ArgoCD auto-syncs
│   └── MZ   MS-SQL · Redis · Mongo · Postgres · Kafka · WebRTC · Apache Hop
│
├── Vmbr-35  MinIO S3  (Dev/Test storage)
│
├── Vmbr-40  UAT / STG
│   ├── UAT cluster  (3 masters + 5 workers)  ←── ArgoCD manual sync
│   ├── STG cluster  (3 masters + 5 workers)  ←── ArgoCD manual sync
│   └── MZ   same middleware stack as Vmbr-30
│
└── Vmbr-55  MinIO S3  (UAT/STG storage, Nitara Lab node)
```

---

## Repo structure

```
nitara-gitops/
├── argocd/
│   ├── applicationset.yaml   ← 1 ApplicationSet → 4 environments
│   └── projects.yaml         ← RBAC: dev-team, ops-team
│
├── charts/
│   └── nitara-app/           ← shared Helm chart
│       ├── Chart.yaml
│       ├── values.yaml       ← defaults
│       └── templates/
│           ├── deployment.yaml   env vars + liveness/readiness probes
│           ├── service.yaml
│           ├── ingress.yaml
│           ├── hpa.yaml          auto-scaling (UAT/STG only)
│           └── secrets.yaml      DB + MinIO credentials
│
├── values/
│   ├── dev-values.yaml    ← DEV  — Jenkins auto-updates image.tag
│   ├── test-values.yaml   ← Test — promoted from dev
│   ├── uat-values.yaml    ← UAT  — promoted from test, HPA on
│   └── stg-values.yaml    ← STG  — promoted from uat, max resources
│
├── middleware/
│   ├── mz-dev/services.yaml   ← ExternalName → Vmbr-30 MZ VMs
│   └── mz-uat/services.yaml   ← ExternalName → Vmbr-40 MZ VMs + Vmbr-55
│
└── promote.sh             ← one-command environment promotion
```

---

## One-time setup

### 1. Install ArgoCD on Vmbr-20 management cluster

```bash
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Get admin password
kubectl get secret argocd-initial-admin-secret \
  -n argocd -o jsonpath="{.data.password}" | base64 -d && echo
```

### 2. Register all 4 clusters

```bash
argocd login argocd.mgmt.nitara.internal --username admin

argocd cluster add dev-cluster  --name dev
argocd cluster add test-cluster --name test
argocd cluster add uat-cluster  --name uat
argocd cluster add stg-cluster  --name stg

argocd cluster list   # verify all 4 appear
```

### 3. Apply ArgoCD project + ApplicationSet

```bash
kubectl apply -f argocd/projects.yaml       -n argocd
kubectl apply -f argocd/applicationset.yaml -n argocd
```

ArgoCD will show 4 apps: `nitara-app-dev`, `nitara-app-test`, `nitara-app-uat`, `nitara-app-stg`

### 4. Apply middleware ExternalName services

```bash
kubectl apply -f middleware/mz-dev/services.yaml -n nitara-dev
kubectl apply -f middleware/mz-dev/services.yaml -n nitara-test
kubectl apply -f middleware/mz-uat/services.yaml -n nitara-uat
kubectl apply -f middleware/mz-uat/services.yaml -n nitara-stg
```

---

## Day-to-day flow

### Developer pushes code
```
git push origin main
  └── Jenkins builds + tests + pushes image
      └── Jenkins updates dev-values.yaml  image.tag
          └── ArgoCD detects commit → syncs DEV cluster automatically
```

### Promote DEV → Test
```bash
./promote.sh dev test
# ArgoCD auto-syncs Test cluster
```

### Promote Test → UAT  (needs ops approval)
```bash
./promote.sh test uat
# ArgoCD shows UAT as OutOfSync
argocd app sync nitara-app-uat   # ops team runs this
```

### Promote UAT → STG  (needs ops approval)
```bash
./promote.sh uat stg
argocd app sync nitara-app-stg
```

---

## Useful commands

```bash
argocd app list                          # all 4 apps + status
argocd app get    nitara-app-dev         # detailed view
argocd app diff   nitara-app-uat         # what would change
argocd app sync   nitara-app-uat         # trigger sync manually
argocd app rollback nitara-app-stg 3     # roll back to history #3
argocd app history  nitara-app-dev       # deployment history
```
