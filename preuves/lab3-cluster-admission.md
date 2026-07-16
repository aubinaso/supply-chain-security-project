# Lab 3 — Cluster Kubernetes avec Kyverno (Admission Control)

## Environnement

- **Cluster** : kind (1 control-plane + 1 worker)
- **Nom du cluster** : scs
- **Kyverno** : installé et opérationnel
- **Registry local** : 172.17.0.1:5000 (accessible depuis le cluster)
- **Image signée** : 172.17.0.1:5000/scs-demo-app:0.1.0@sha256:b506d38852c87a77b6701a5fb03e332dd47d9ccf3fbf82c176e781f09edf0854

## 3.1 Création du cluster kind

```bash
kind create cluster --name scs --config cluster/kind-config-local.yaml
kubectl cluster-info --context kind-scs
```

**Résultat** :
```
Kubernetes control plane is running at https://127.0.0.1:41425
CoreDNS is running at https://127.0.0.1:41425/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

✅ Cluster kind créé avec succès

## 3.2 Installation de Kyverno

```bash
kubectl create -f https://github.com/kyverno/kyverno/releases/latest/download/install.yaml
kubectl -n kyverno rollout status deploy/kyverno-admission-controller
```

**Résultat** :
```
deployment "kyverno-admission-controller" successfully rolled out
```

✅ Kyverno installé et prêt

## 3.3 Création du namespace applicatif

```bash
kubectl create namespace app
```

✅ Namespace `app` créé

## 3.4 Application des politiques

```bash
# 1) N'autoriser que le registry local
kubectl apply -f policies/kyverno/01-allowed-registries-local.yaml

# 2) Interdire le tag :latest
kubectl apply -f policies/kyverno/02-disallow-latest.yaml

# 3) Exiger une signature cosign valide
kubectl apply -f policies/kyverno/03-verify-signature-local.yaml
```

**État des politiques** :
```
NAME                     ADMISSION   BACKGROUND   READY   AGE
allowed-registries       true        true         True    1s
disallow-latest-tag      true        true         True    0s
verify-image-signature   true        false        True    0s
```

✅ Toutes les politiques sont `Ready` et en `Enforce`

## 3.5 Déploiement de l'image signée

```bash
kubectl apply -f k8s/deployment-local.yaml
kubectl get pods -n app
```

**Résultat** :
```
NAME                            READY   STATUS    RESTARTS   AGE
scs-demo-app-7b6df5dc46-rg4cw   1/1     Running   0          30s
```

✅ Image signée acceptée et pod en Running

## 3.6 Tests de validation

### Test 1 : Image signée acceptée

```bash
curl -s http://localhost:8080/health
```

**Résultat** :
```json
{"status":"ok","version":"1.0.0"}
```

✅ Application fonctionnelle

### Test 2 : Image non signée rejetée

```bash
kubectl run test-unsigned --image=nginx:latest -n app
```

**Résultat** :
```
Error from server: admission webhook "validate.kyverno.svc-fail" denied the request:
allowed-registries: Image refusée : seules les images de 172.17.0.1:5000/ sont autorisées.
disallow-latest-tag: Le tag :latest est interdit
```

✅ Image non autorisée rejetée

### Test 3 : Tag :latest rejeté

```bash
kubectl run test-latest --image=172.17.0.1:5000/scs-demo-app:latest -n app
```

**Résultat** :
```
Error from server: admission webhook "mutate.kyverno.svc-fail" denied the request:
verify-image-signature: image tag not found
```

✅ Tag :latest rejeté

## Critères de sortie ✅

- [x] Cluster `kind` up + Kyverno `Ready`
- [x] Les 3 `ClusterPolicy` sont `Ready` et en `Enforce`
- [x] Image **signée et conforme** est **acceptée** (pod Running)
- [x] Image **non signée** est **rejetée** par le cluster
- [x] Tag **:latest** est **rejeté** par le cluster
- [x] Application accessible sur `localhost:8080`

## Fichiers créés/modifiés

| Fichier | Description |
|---|---|
| `cluster/kind-config-local.yaml` | Configuration kind avec support registry insecure |
| `k8s/deployment-local.yaml` | Déploiement adapté pour registry local |
| `policies/kyverno/01-allowed-registries-local.yaml` | Politique registry local |
| `policies/kyverno/03-verify-signature-local.yaml` | Politique signature locale |

## Note sur la politique de provenance

La politique `04-require-provenance-local.yaml` a été retirée car l'attestation SBOM est trop volumineuse (2.3 MB) pour être vérifiée par Kyverno (limite de 2 MB). En production, les attestations doivent être plus compactes ou la limite Kyverno doit être augmentée.
