# Rapport — Chaîne d'approvisionnement logicielle sécurisée

- **Groupe :** Johlan78
- **Fork :** https://github.com/Johlan78/supply-chain-security-project
- **Voie :** ☒ Local (kind/k3s) ☐ Azure (AKS/ACR)
- **Date :** 16 juillet 2026
- **Partie réalisée :** Lab 2 (Signature & Attestations) + Lab 3 (Cluster Kyverno)

---

## 1. Contexte & objectif (½ p.)

La sécurisation de la chaîne d'approvisionnement logicielle est devenue critique suite aux attaques majeures de 2020-2024 :

- **SolarWinds (2020)** : injection de code malveillant dans le processus de build, signé par l'éditeur, déployé chez 18 000 clients.
- **XZ Utils (2024)** : backdoor introduite sur 3 ans dans une dépendance open source.

**Objectif :** Garantir que l'image déployée en production est **exactement** celle produite à partir du code revu, sans altération, et que le cluster **refuse** automatiquement toute image non conforme.

**Propriétés visées :**
- **Intégrité** : l'image n'a pas été modifiée après sa création
- **Authenticité** : l'image provient bien de notre chaîne de build
- **Traçabilité** : on peut prouver qui a construit quoi, quand, et depuis quel code

---

## 2. Architecture de la chaîne (1 p.)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  BUILD LOCAL (poste dev)                                                     │
│                                                                              │
│   app/ (code) ──► docker build ──► image:0.1.0                               │
│                          │                                                   │
│                          ├─► syft   ──► SBOM (SPDX)                          │
│                          ├─► cosign sign            (signature par clé)      │
│                          ├─► cosign attest --type spdxjson  (attestation SBOM)│
│                          └─► cosign attest --type slsaprovenance (provenance)│
│                          │                                                   │
│                     push ──► localhost:5000/scs-demo-app@sha256:...           │
└─────────────────────────────────────────────────────────────────────────────┘
                                     │
                     (signatures + attestations stockées comme artefacts OCI)
                                     │
┌────────────────────────────────────▼────────────────────────────────────────┐
│  CLUSTER KIND + KYVERNO                                                      │
│                                                                              │
│   kubectl apply Deployment (image signée par digest)                         │
│                          │                                                   │
│                          ▼                                                   │
│        ┌──────────── KYVERNO (admission webhook) ───────────┐               │
│        │  verifyImages :                                     │              │
│        │   • signature présente & faite par NOTRE clé ?      │              │
│        │  validate :                                          │              │
│        │   • image depuis registry autorisé uniquement ?      │              │
│        │   • pas de tag :latest ?                             │              │
│        └───────────────┬───────────────────────┬────────────┘               │
│                        │ OUI                    │ NON                        │
│                        ▼                        ▼                            │
│                   ✅ Pod créé            ❌ requête REJETÉE                   │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Outils utilisés :**

| Outil | Rôle | Version |
|---|---|---|
| **Syft** | Génération du SBOM (Software Bill of Materials) | v1.18.1 |
| **cosign** | Signature et attestations (projet Sigstore) | v2.4.1 |
| **Kyverno** | Admission control Kubernetes (policy-as-code) | latest |
| **kind** | Cluster Kubernetes local pour la démo | v0.24.0 |

---

## 3. Mise en œuvre (2-3 p.)

### 3.1 Signature de l'image (cosign)

**Mode choisi :** signature par clé privée (pour la démo locale) + documentation keyless (pour CI)

**Génération de la paire de clés :**
```bash
cosign generate-key-pair
# cosign.key (SECRET, dans .gitignore) et cosign.pub générés
```

**Signature de l'image par digest :**
```bash
COSIGN_PASSWORD="testpass123" cosign sign --key cosign.key --yes "$DIGEST"
```

**Preuve de signature :**
```
tlog entry created with index: 2185498871
```

**Vérification de la signature :**
```bash
cosign verify --key cosign.pub "$DIGEST"
```

**Sortie :**
```
Verification for localhost:5000/scs-demo-app@sha256:b506d38852c87a77b6701a5fb03e332dd47d9ccf3fbf82c176e781f09edf0854 --
The following checks were performed on each of these signatures:
  - The cosign claims were validated
  - Existence of the claims in the transparency log was verified offline
  - The signatures were verified against the specified public key
```

✅ **Signature vérifiée avec succès**

### 3.2 Attestation SBOM

**Génération du SBOM avec Syft :**
```bash
syft "$IMG:$TAG" -o spdx-json > sbom.spdx.json
```

**Résultat :** fichier `sbom.spdx.json` généré (2.3 MB, format SPDX)

**Attachement de l'attestation SBOM :**
```bash
cosign attest --key cosign.key --yes \
  --predicate sbom.spdx.json \
  --type spdxjson \
  "$DIGEST"
```

**Preuve :**
```
tlog entry created with index: 2185505306
```

**Vérification :**
```bash
cosign verify-attestation --key cosign.pub --type spdxjson "$DIGEST"
```

✅ **Attestation SBOM vérifiée avec succès**

### 3.3 Attestation de provenance SLSA

**Création de provenance.json :**
```json
{
  "buildType": "https://example.com/manual-local-build/v1",
  "builder": { "id": "local:johlan78" },
  "invocation": {
    "configSource": {
      "uri": "git+https://github.com/johlan78/supply-chain-security-project",
      "digest": { "sha1": "72d646c" }
    }
  },
  "metadata": { "buildStartedOn": "2026-07-16T15:00:00Z" }
}
```

**Attachement de l'attestation de provenance :**
```bash
cosign attest --key cosign.key --yes \
  --predicate provenance.json \
  --type slsaprovenance \
  "$DIGEST"
```

**Preuve :**
```
tlog entry created with index: 2185515187
```

**Vérification :**
```bash
cosign verify-attestation --key cosign.pub --type slsaprovenance "$DIGEST"
```

**Sortie :** predicateType = `https://slsa.dev/provenance/v0.2`

✅ **Attestation de provenance vérifiée avec succès**

### 3.4 Inspection du registry (cosign tree)

```bash
cosign tree "$DIGEST"
```

**Résultat :**
```
📦 Supply Chain Security Related artifacts for an image
└── 💾 Attestations for an image tag
   ├── 🍒 sha256:414a77c48cf5... (SBOM)
   └── 🍒 sha256:ac802cc6399a... (Provenance)
└── 🔐 Signatures for an image tag
   └── 🍒 sha256:01fab776d562... (Signature)
```

✅ **1 signature + 2 attestations** attachées au digest

### 3.5 Signature keyless (OIDC)

**Principe :** Au lieu d'une clé privée, la signature utilise l'identité OIDC (GitHub Actions) via :
- **Fulcio** : autorité de certification éphémère
- **Rekor** : journal de transparence public et immuable

**Commandes (en CI GitHub Actions) :**
```bash
# Signature keyless (automatique via OIDC du runner)
COSIGN_EXPERIMENTAL=1 cosign sign --yes "$DIGEST"

# Vérification avec identité spécifique
COSIGN_EXPERIMENTAL=1 cosign verify \
  --certificate-identity "https://github.com/johlan78/supply-chain-security-project/.github/workflows/supply-chain.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  "$DIGEST"
```

✅ **Signature keyless documentée et prête pour CI**

### 3.6 Admission control (Kyverno)

**Cluster créé :**
```bash
kind create cluster --name scs --config cluster/kind-config-local.yaml
```

**Kyverno installé :**
```bash
kubectl create -f https://github.com/kyverno/kyverno/releases/latest/download/install.yaml
kubectl -n kyverno rollout status deploy/kyverno-admission-controller
```

**Politiques appliquées :**

| Politique | Action | Description |
|---|---|---|
| `allowed-registries` | Enforce | N'autorise que le registry local |
| `disallow-latest-tag` | Enforce | Interdit le tag :latest |
| `verify-image-signature` | Enforce | Exige une signature cosign valide |

**État des politiques :**
```
NAME                     ADMISSION   BACKGROUND   READY
allowed-registries       true        true         True
disallow-latest-tag      true        true         True
verify-image-signature   true        false        True
```

✅ **Toutes les politiques sont Ready et en Enforce**

---

## 4. Démonstration attaque / défense (1 p.)

### Scénarios testés

| Scénario | Résultat | Contrôle déclenché | Preuve |
|---|---|---|---|
| Image légitime (signée) | ✅ acceptée | — | Pod Running, `/health` → 200 |
| Image non signée (nginx) | ❌ refusée | `allowed-registries` | Message d'erreur Kyverno |
| Tag `:latest` | ❌ refusée | `disallow-latest-tag` + `verify-image-signature` | Message d'erreur Kyverno |

### Preuve : image légitime acceptée

```bash
$ kubectl get pods -n app
NAME                            READY   STATUS    RESTARTS   AGE
scs-demo-app-7b6df5dc46-rg4cw   1/1     Running   0          98s

$ curl -s http://localhost:8080/health
{"status":"ok","version":"1.0.0"}
```

### Preuve : image non signée rejetée

```bash
$ kubectl run test-unsigned --image=nginx:latest -n app
Error from server: admission webhook "validate.kyverno.svc-fail" denied the request:
allowed-registries: Image refusée : seules les images de 172.17.0.1:5000/ sont autorisées.
disallow-latest-tag: Le tag :latest est interdit
```

### Preuve : tag :latest rejeté

```bash
$ kubectl run test-latest --image=172.17.0.1:5000/scs-demo-app:latest -n app
Error from server: admission webhook "mutate.kyverno.svc-fail" denied the request:
verify-image-signature: image tag not found
```

✅ **Le cluster bloque automatiquement les images non conformes**

---

## 5. Positionnement SLSA & limites (1 p.)

### Niveau SLSA atteint

| Niveau | Visé | Atteint | Justification |
|---|---|---|---|
| **L1** : Provenance existe | ✅ | ✅ | Attestation de provenance SLSA attachée et vérifiable |
| **L2** : Build hébergé + provenance signée | ✅ | ⚠️ Partiel | Build local (pas en CI) ; signature par clé (pas keyless) |
| **L3** : Build isolé infalsifiable | — | ❌ | Hors périmètre du projet |

### Ce qui reste contournable

1. **Build local** : le build a lieu sur le poste du développeur, pas sur une plateforme hébergée. Un développeur malveillant pourrait altérer le build.

2. **Clé privée** : la clé `cosign.key` doit être protégée. Si elle est compromise, un attaquant peut signer des images malveillantes.

3. **Pas de build isolé** : le build n'est pas dans un environnement éphémère et isolé (SLSA L3).

4. **Provenance manuelle** : la provenance est créée manuellement, pas par un générateur officiel comme `slsa-github-generator`.

### Pistes vers SLSA L2/L3

1. **Build sur GitHub Actions** : utiliser le workflow CI pour builder et signer automatiquement
2. **Signature keyless** : utiliser l'OIDC du runner GitHub au lieu d'une clé privée
3. **SLSA GitHub Generator** : utiliser `slsa-framework/slsa-github-generator` pour une provenance infalsifiable
4. **Isolation du build** : utiliser des runners éphémères et isolés

---

## 6. Reproductibilité (½ p.)

### Prérequis

```bash
# Installer les outils
docker version
kind version
kubectl version --client
syft version
cosign version
jq --version
```

### Étapes de reconstruction

```bash
# 1. Cloner le dépôt
git clone https://github.com/Johlan78/supply-chain-security-project.git
cd supply-chain-security-project
git checkout partie-2-signature-attestations

# 2. Construire l'image
docker build -t 172.17.0.1:5000/scs-demo-app:0.1.0 app/

# 3. Démarrer le registry local
docker run -d --name registry -p 5000:5000 --restart=always registry:2
docker push 172.17.0.1:5000/scs-demo-app:0.1.0

# 4. Signer l'image (Lab 2)
cosign generate-key-pair
COSIGN_PASSWORD="testpass123" cosign sign --key cosign.key --yes 172.17.0.1:5000/scs-demo-app@sha256:<digest>
cosign verify --key cosign.pub 172.17.0.1:5000/scs-demo-app@sha256:<digest>

# 5. Créer les attestations (Lab 2)
syft 172.17.0.1:5000/scs-demo-app:0.1.0 -o spdx-json > sbom.spdx.json
cosign attest --key cosign.key --yes --predicate sbom.spdx.json --type spdxjson 172.17.0.1:5000/scs-demo-app@sha256:<digest>
cosign attest --key cosign.key --yes --predicate provenance.json --type slsaprovenance 172.17.0.1:5000/scs-demo-app@sha256:<digest>

# 6. Créer le cluster kind (Lab 3)
kind create cluster --name scs --config cluster/kind-config-local.yaml
kind load docker-image 172.17.0.1:5000/scs-demo-app:0.1.0 --name scs

# 7. Installer Kyverno et appliquer les politiques (Lab 3)
kubectl create -f https://github.com/kyverno/kyverno/releases/latest/download/install.yaml
kubectl create namespace app
kubectl apply -f policies/kyverno/01-allowed-registries-local.yaml
kubectl apply -f policies/kyverno/02-disallow-latest.yaml
kubectl apply -f policies/kyverno/03-verify-signature-local.yaml

# 8. Déployer l'app
kubectl apply -f k8s/deployment-local.yaml
kubectl get pods -n app
curl -s http://localhost:8080/health
```

### Script de démo automatisée

```bash
# Démo complète du Lab 2
./scripts/demo-lab2-complete.sh

# Démo complète du Lab 3
./scripts/demo-lab3-cluster.sh
```

---

## 7. Bilan (½ p.)

### Ce que j'ai appris

1. **Signature container** : cosign permet de signer des images de manière cryptographique, garantissant l'intégrité et l'authenticité.

2. **Attestations** : les attestations SBOM et provenance sont des métadonnées signées attachées à l'image, permettant de tracer l'origine et la composition.

3. **Admission control** : Kyverno permet de définir des politiques d'admission qui bloquent automatiquement les images non conformes.

4. **Zero-trust** : le modèle "ne pas faire confiance, mais vérifier" est applicable aux images container via la signature et les attestations.

### Répartition du travail

- **Partie 1 (Lab 0-1)** : Setup, build, SBOM, scan Grype (collègue)
- **Partie 2 (Lab 2-3)** : Signature cosign, attestations, cluster Kyverno (moi)
- **Partie 3 (Lab 4-5)** : Attaque/défense, CI/CD (collègue)

### Ce que je ferai différemment

1. **Utiliser la signature keyless** : en production, la signature par clé privée est moins sécurisée que la signature keyless via OIDC.

2. **Automatiser en CI** : intégrer la signature et les attestations dans le pipeline CI/CD (GitHub Actions) pour éviter les étapes manuelles.

3. **Vérifier la provenance à l'admission** : ajouter une politique Kyverno qui exige l'attestation de provenance (pas seulement la signature).

---

## Annexes

### A. Clé publique cosign

```
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE6f2oWMWAxWIpA2xVNKH1YwETmKLw
Dek2mBPug4Nem/MnPr2ijuJIqRtzbirywHA+JuVW9WyvgDjBls625QBtSQ==
-----END PUBLIC KEY-----
```

### B. Identifiants Rekor (transparency log)

| Opération | Index Rekor |
|---|---|
| Signature | 2185498871 |
| Attestation SBOM | 2185505306 |
| Attestation Provenance | 2185515187 |

### C. Fichiers du projet

```
policies/kyverno/
├── 01-allowed-registries-local.yaml
├── 02-disallow-latest.yaml
├── 03-verify-signature-local.yaml
└── 04-require-provenance-local.yaml

k8s/
├── deployment.yaml (GHCR)
└── deployment-local.yaml (registry local)

scripts/
├── demo-lab2-complete.sh
└── demo-lab3-cluster.sh

preuves/
├── lab2-sign-attest.md
└── lab3-cluster-admission.md
```
