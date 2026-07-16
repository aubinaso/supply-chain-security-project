# Threat model — Chaîne d'approvisionnement logicielle

- **Groupe :** _(noms)_  · **Date :** 2026-07-16

> 1-3 pages. Objectif : montrer que vous **raisonnez menaces → contrôles → couverture**,
> pas seulement « on a installé des outils ».

## 1. Actif à protéger

L'artefact (image `ghcr.io/<votre-user>/scs-demo-app`) qui tourne en production doit être
**exactement** celui produit à partir du code revu, par notre chaîne CI, sans altération.
Propriétés visées :

- **Intégrité** — le contenu déployé n'a pas été modifié entre le build et l'exécution.
- **Authenticité** — l'image provient bien de notre chaîne (signature cosign), pas d'un tiers.
- **Traçabilité (provenance)** — on peut prouver qui/quoi/quand a construit l'image (SLSA).

## 2. Surface & acteurs de menace

- **Dépendances tierces (amont)** — package compromis dans `app/requirements.txt` (ex. réel :
  backdoor **XZ Utils**).
- **Runner / étape de CI compromis** — injection dans le pipeline de build (ex. réel :
  **SolarWinds**, **Codecov**).
- **Registry compromis / substitution d'image** — un tag est réécrit après coup pour pointer
  vers un contenu différent.
- **Accès cluster non autorisé** — un attaquant (ou un dev pressé) déploie directement une
  image qui n'a jamais transité par la chaîne signée (`kubectl run` avec une image arbitraire).
- **Développeur négligent** — usage du tag mutable `:latest`, oubli de signer, image tirée
  d'un registry public non vérifié (Docker Hub) au lieu de GHCR.

## 3. Table menaces → contrôles → couverture

Correspondance directe avec les 5 scénarios d'attaque du [Lab 4](../labs/lab4-attaque-defense.md).

| # | Menace | Vecteur | Contrôle mis en place | Politique Kyverno | Couverture | Résiduel |
|---|---|---|---|---|---|---|
| T1 | Image jamais signée déployée | accès cluster direct | signature cosign requise à l'admission | `03-verify-signature` | Forte | Compromission de la clé/identité de signature elle-même |
| T2 | Artefact modifié après signature (**SolarWinds**) | substitution sous le même tag | signature liée au **digest** exact (`mutateDigest`/`verifyDigest`) + déploiement par digest | `03-verify-signature` | Forte | Compromission du build **avant** la signature (contenu malveillant signé légitimement) |
| T3 | Registry pirate / typosquat | image externe (ex. Docker Hub) | liste blanche de registres | `01-allowed-registries` | Forte | Registre autorisé lui-même compromis |
| T4 | Substitution silencieuse sous tag mutable | tag `:latest` réécrit | interdiction de `:latest` / tag implicite, déploiement par digest | `02-disallow-latest` | Forte | — |
| T5 | Origine inconnue / non vérifiable | absence de traçabilité | attestation de **provenance SLSA** exigée en plus de la signature | `04-require-provenance` | Forte | Provenance falsifiable si le build n'est pas isolé (pas de SLSA L3) |
| T6 | Dépendance vulnérable | amont (`requirements.txt`) | SBOM (Syft) + scan (Grype), gate CI sur sévérité CRITICAL | — (contrôle en amont, pas à l'admission) | Moyenne | 0-day, vulnérabilité sans correctif disponible |

_(Compléter/ajuster la colonne « Résiduel » selon vos observations réelles pendant le Lab 4 —
notamment si vous avez identifié un contournement pendant vos tests.)_

## 4. Scénarios de démonstration (Lab 4) et lien avec la table ci-dessus

| Scénario | Résultat attendu | Menace couverte |
|---|---|---|
| Image légitime (signée, provenance, bon registry, par digest) | ✅ **ACCEPTÉE** | référence — le cas nominal doit passer |
| Image **non signée** | ❌ **REFUSÉE** | T1 |
| Image **modifiée après signature** (contenu changé sous le même tag) | ❌ **REFUSÉE** | T2 — analogue **SolarWinds** |
| Registry **non autorisé** (ex. `nginx` depuis Docker Hub) | ❌ **REFUSÉE** | T3 |
| Tag `:latest` | ❌ **REFUSÉE** | T4 |
| Signée **sans provenance** (bonus) | ❌ **REFUSÉE** | T5 |

> Preuves : messages d'erreur Kyverno (admission webhook denied) + captures d'écran, voir
> [`docs/lab4-captures-demo.md`](../docs/lab4-captures-demo.md).

## 5. Ce qui reste hors périmètre / non couvert

- Compromission du **build** lui-même avant la signature (viser SLSA L3 : build isolé,
  provenance infalsifiable).
- Sécurité du poste développeur / des secrets en amont (ex. vol de `cosign.key` en mode par clé).
- Vulnérabilités **0-day** ou sans correctif disponible au moment du scan.
- RBAC Kubernetes fin (qui a le droit de créer des Pods dans le cluster) — le Lab 4 démontre le
  blocage **applicatif** (Kyverno), pas le durcissement de l'accès cluster lui-même.

## 6. Niveau SLSA visé vs atteint

| | Visé | Atteint | Justification |
|---|---|---|---|
| Provenance existe (L1) | ✅ | _(à compléter après Lab 5)_ | Attestation `slsaprovenance` attachée et vérifiée par Kyverno |
| Build hébergé + provenance signée (L2) | ✅ | _(à compléter après Lab 5)_ | Dépend du passage en CI GitHub Actions (keyless, identité du workflow) |
| Build isolé infalsifiable (L3) | — | ✗ | Hors périmètre du projet (nécessiterait un générateur SLSA isolé type `slsa-framework/slsa-github-generator`) |

**À trancher honnêtement en soutenance :** tant que la signature est faite **par clé** en local
(mode A des politiques `03-verify-signature`/`04-require-provenance`), la provenance ne prouve
que « quelqu'un possédant `cosign.key` a signé », pas « le workflow CI officiel a signé ». Le
passage au mode **keyless** avec identité de workflow (Lab 5) est ce qui rapproche réellement
de SLSA L2.
