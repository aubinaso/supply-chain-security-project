# Lab 2 — Signature & Attestations

## Environnement

- **Image locale** : `localhost:5000/scs-demo-app:0.1.0`
- **Digest local** : `localhost:5000/scs-demo-app@sha256:b506d38852c87a77b6701a5fb03e332dd47d9ccf3fbf82c176e781f09edf0854`
- **Image GHCR de référence** : `ghcr.io/johlan78/scs-demo-app:0.1.0`
- **Digest GHCR** : `ghcr.io/johlan78/scs-demo-app@sha256:6274762da84c8f74925c2ebf676c832ad98252b880376c75ba27de5384b90721`
- **Note** : utilisation d'un registry local (localhost:5000) car accès GHCR non disponible dans cet environnement

## 2.2 Signature par clé

### Génération de la paire de clés

```bash
cosign generate-key-pair
# cosign.key (SECRET) et cosign.pub générés
```

✅ `cosign.key` est dans `.gitignore`

### Signature de l'image

```bash
COSIGN_PASSWORD="testpass123" cosign sign --key cosign.key --allow-insecure-registry --yes "$DIGEST"
```

**Résultat** : `tlog entry created with index: 2185498871`

### Vérification de la signature

```bash
cosign verify --key cosign.pub --allow-insecure-registry "$DIGEST"
```

**Résultat** :
```
Verification for localhost:5000/scs-demo-app@sha256:b506d38852c87a77b6701a5fb03e332dd47d9ccf3fbf82c176e781f09edf0854 --
The following checks were performed on each of these signatures:
  - The cosign claims were validated
  - Existence of the claims in the transparency log was verified offline
  - The signatures were verified against the specified public key
```

✅ Signature vérifiée avec succès

## 2.4 Attestation SBOM

### Génération du SBOM avec Syft

```bash
syft "$LOCAL_IMG:$TAG" -o spdx-json > sbom.spdx.json
```

**Résultat** : fichier `sbom.spdx.json` généré (2.3 MB)

### Attachement de l'attestation SBOM

```bash
cosign attest --key cosign.key --allow-insecure-registry --yes \
  --predicate sbom.spdx.json \
  --type spdxjson \
  "$DIGEST"
```

**Résultat** : `tlog entry created with index: 2185505306`

### Vérification de l'attestation SBOM

```bash
cosign verify-attestation --key cosign.pub --allow-insecure-registry --type spdxjson "$DIGEST"
```

✅ Attestation SBOM vérifiée avec succès

## 2.5 Attestation de provenance SLSA

### Création de provenance.json

```json
{
  "buildType": "https://example.com/manual-local-build/v1",
  "builder": { "id": "local:root" },
  "invocation": {
    "configSource": {
      "uri": "git+https://github.com/johlan78/supply-chain-security-project",
      "digest": { "sha1": "72d646c" }
    }
  },
  "metadata": { "buildStartedOn": "2026-07-16T15:00:00Z" }
}
```

### Attachement de l'attestation de provenance

```bash
cosign attest --key cosign.key --allow-insecure-registry --yes \
  --predicate provenance.json \
  --type slsaprovenance \
  "$DIGEST"
```

**Résultat** : `tlog entry created with index: 2185515187`

### Vérification de l'attestation de provenance

```bash
cosign verify-attestation --key cosign.pub --allow-insecure-registry --type slsaprovenance "$DIGEST"
```

**Résultat** : Vérification réussie, predicateType = `https://slsa.dev/provenance/v0.2`

✅ Attestation de provenance vérifiée avec succès

## 2.6 Inspection du registry

```bash
cosign tree --allow-insecure-registry "$DIGEST"
```

**Résultat** :
```
📦 Supply Chain Security Related artifacts for an image: localhost:5000/scs-demo-app@sha256:b506d38852c87a77b6701a5fb03e332dd47d9ccf3fbf82c176e781f09edf0854
└── 💾 Attestations for an image tag: localhost:5000/scs-demo-app:sha256-b506d38852c87a77b6701a5fb03e332dd47d9ccf3fbf82c176e781f09edf0854.att
   ├── 🍒 sha256:414a77c48cf5ad5f4a59157d8cd92ad3952bc133d9153766a1527dc3625c416b
   └── 🍒 sha256:ac802cc6399ac9d8ee58bf4e7684fe25e544c2e3a3bcafb10c9dc958ca692440
└── 🔐 Signatures for an image tag: localhost:5000/scs-demo-app:sha256-b506d38852c87a77b6701a5fb03e332dd47d9ccf3fbf82c176e781f09edf0854.sig
   └── 🍒 sha256:01fab776d5624597b6d62a2b27d90fc6a43810a1abd918e8795490ee40c22399
```

✅ **1 signature** (`.sig`) + **2 attestations** (`.att` : SBOM + provenance)

## Préparation pour Kyverno (Partie 3)

### Fichiers mis à jour

| Fichier | Modification |
|---|---|
| `policies/kyverno/01-allowed-registries.yaml` | `ghcr.io/johlan78/*` |
| `policies/kyverno/03-verify-signature.yaml` | `cosign.pub` injecté, `ghcr.io/johlan78/scs-demo-app*` |
| `policies/kyverno/04-require-provenance.yaml` | `cosign.pub` injecté, `ghcr.io/johlan78/scs-demo-app*` |
| `k8s/deployment.yaml` | Image par digest GHCR |

### Clé publique cosign (pour Kyverno)

```
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE6f2oWMWAxWIpA2xVNKH1YwETmKLw
Dek2mBPug4Nem/MnPr2ijuJIqRtzbirywHA+JuVW9WyvgDjBls625QBtSQ==
-----END PUBLIC KEY-----
```

## Critères de sortie ✅

- [x] `cosign.key` est dans `.gitignore` (jamais commité)
- [x] Image **signée** (par clé) et `cosign verify` réussit
- [x] Attestation **SBOM** attachée et vérifiable
- [x] Attestation de **provenance** attachée et vérifiable
- [x] `cosign tree` montre signature + attestations sur le digest
- [x] Policies Kyverno préparées pour la Partie 3

## 2.3 Signature keyless (OIDC)

### Principe

La signature keyless utilise votre **identité OIDC** (GitHub, Google) au lieu d'une clé privée :
- **Pas de clé privée** à gérer ou stocker
- Identité basée sur votre compte GitHub/Google
- Certificate Authority éphémère (Fulcio)
- Transparency log (Rekor) pour l'audit

### Commandes (en CI GitHub Actions)

```bash
# Signature keyless (automatique en CI via OIDC du runner)
COSIGN_EXPERIMENTAL=1 cosign sign --yes "$DIGEST"

# Vérification keyless
COSIGN_EXPERIMENTAL=1 cosign verify \
  --certificate-identity-regexp ".*" \
  --certificate-oidc-issuer-regexp ".*" \
  "$DIGEST"

# Vérification avec identité spécifique (pour Kyverno)
COSIGN_EXPERIMENTAL=1 cosign verify \
  --certificate-identity "https://github.com/johlan78/supply-chain-security-project/.github/workflows/supply-chain.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  "$DIGEST"
```

### Résultat en CI

En GitHub Actions, la signature keyless :
1. Utilise l'OIDC du runner GitHub
2. Obtient un certificat éphémère de Fulcio
3. Signe l'image avec une clé éphémère
4. Enregistre dans Rekor (transparency log)

✅ Signature keyless documentée et prête pour CI

### Configuration Kyverno pour keyless

Pour utiliser le mode keyless dans Kyverno, voir le fichier `policies/kyverno/03-verify-signature-keyless.yaml` qui contient la configuration avec :
```yaml
attestors:
  - count: 1
    entries:
      - keyless:
          issuer: "https://token.actions.githubusercontent.com"
          subject: "https://github.com/johlan78/supply-chain-security-project/.github/workflows/supply-chain.yml@refs/heads/main"
          rekor:
            url: "https://rekor.sigstore.dev"
```

## Critères de sortie (mis à jour)

- [x] `cosign.key` est dans `.gitignore` (jamais commité)
- [x] Image **signée** (par clé) et `cosign verify` réussit
- [x] **Signature keyless** documentée et prête pour CI (GitHub Actions)
- [x] Attestation **SBOM** attachée et vérifiable
- [x] Attestation de **provenance** attachée et vérifiable
- [x] `cosign tree` montre signature + attestations sur le digest
- [x] Policies Kyverno préparées pour la Partie 3 (clé + keyless)
