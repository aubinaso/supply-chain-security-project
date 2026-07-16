# Threat model — Chaîne d'approvisionnement logicielle

- **Groupe :** Johlan78
- **Date :** 16 juillet 2026
- **Partie réalisée :** Lab 2 (Signature & Attestations) + Lab 3 (Cluster Kyverno)

---

## 1. Actif à protéger

L'artefact à protéger est l'**image container** `ghcr.io/johlan78/scs-demo-app:0.1.0` qui tourne en production.

**Propriétés visées :**

| Propriété | Définition | Menace associée |
|---|---|---|
| **Intégrité** | L'image n'a pas été modifiée après sa création | Substitution d'image dans le registry |
| **Authenticité** | L'image provient bien de notre chaîne de build | Image pirate injectée |
| **Traçabilité** | On peut prouver qui a construit quoi, quand, depuis quel code | Origine inconnue, build non traçable |

---

## 2. Surface & acteurs de menace

### Surface d'attaque

```
Code source → Build → Registry → Cluster
     ↓           ↓        ↓         ↓
  Accès code   Build    Registry   Accès
  compromis   compromis compromis  cluster
```

### Acteurs de menace

| Acteur | Motivation | Vecteur |
|---|---|---|
| **Attaquant externe** | Injecter du code malveillant | Compromission du registry, typosquatting |
| **Développeur malveillant** | Backdoor, exfiltration de données | Modification du code ou du build |
| **Développeur négligent** | Erreur humaine | Image non signée, tag `:latest` |
| **Supply chain attack** | Attaque à grande scale | Dépendance compromise (ex: XZ Utils) |

---

## 3. Table menaces → contrôles → couverture

| # | Menace | Vecteur | Contrôle mis en place | Couverture | Résiduel |
|---|---|---|---|---|---|
| **T1** | Artefact altéré après build | Substitution dans le registry | **Signature cosign** liée au digest + `verifyImages` Kyverno | **Forte** | Le build lui-même peut être compromis |
| **T2** | Déploiement non autorisé | Accès cluster non contrôlé | **Admission Kyverno** `Enforce` (signature requise) | **Forte** | RBAC à durcir, accès cluster à contrôler |
| **T3** | Dépendance vulnérable | Backdoor dans une dépendance | **SBOM** (Syft) + **Grype** (gate CRITICAL) | **Moyenne** | 0-day, vulnérabilités sans correctif |
| **T4** | Origine inconnue | Absence de traçabilité | **Attestation de provenance** (SLSA) | **Forte** | Provenance falsifiable si build non isolé |
| **T5** | Substitution silencieuse | Tag mutable (`:latest`) | Interdiction `:latest`, déploiement **par digest** | **Forte** | — |
| **T6** | Registry pirate / typosquat | Image externe | **Politique registres autorisés** | **Forte** | — |
| **T7** | Image non signée déployée | Négligence | **verifyImages** Kyverno (signature requise) | **Forte** | — |
| **T8** | Clé de signature compromise | Vol de `cosign.key` | Clé dans `.gitignore`, protégée par mot de passe | **Moyenne** | Utiliser keyless en production |

### Détail des contrôles

#### T1 — Signature cosign (intégrité)

**Menace :** Un attaquant remplace l'image dans le registry par une version altérée.

**Contrôle :** La signature cosign est liée au **digest** de l'image. Si un octet change, le digest change, la signature ne correspond plus, et Kyverno refuse l'image.

**Commande de preuve :**
```bash
cosign verify --key cosign.pub "$DIGEST"
# → "The signatures were verified against the specified public key"
```

#### T2 — Admission Kyverno (déploiement contrôlé)

**Menace :** Un attaquant avec accès au cluster déploie une image non autorisée.

**Contrôle :** Kyverno intercepte chaque requête d'admission et vérifie la signature avant de créer le Pod. Mode `Enforce` = blocage automatique.

**Commande de preuve :**
```bash
kubectl run test-unsigned --image=nginx:latest -n app
# → "admission webhook denied the request: allowed-registries"
```

#### T3 — SBOM + Grype (dépendances)

**Menace :** Une dépendance contient une vulnérabilité critique (ex: CVE dans Flask).

**Contrôle :** Le SBOM liste toutes les dépendances. Grype scanne et bloque si une CVE `CRITICAL` corrigeable existe.

**Commande de preuve :**
```bash
grype "$IMG:$TAG" --fail-on critical
# → Code de sortie 2 si vuln critique trouvée
```

#### T4 — Attestation de provenance (traçabilité)

**Menace :** On ne sait pas qui a construit l'image, quand, ni depuis quel code.

**Contrôle :** L'attestation SLSA contient : le builder, le commit source, la date de build. Tout est signé cryptographiquement.

**Commande de preuve :**
```bash
cosign verify-attestation --key cosign.pub --type slsaprovenance "$DIGEST"
# → predicateType: https://slsa.dev/provenance/v0.2
```

#### T5 — Interdiction :latest (substitution)

**Menace :** Le tag `:latest` est mutable : son contenu peut changer sans que le digest change.

**Contrôle :** Kyverno refuse les images avec le tag `:latest` et force le déploiement par digest.

**Commande de preuve :**
```bash
kubectl run test-latest --image=172.17.0.1:5000/scs-demo-app:latest -n app
# → "disallow-latest-tag: Le tag :latest est interdit"
```

#### T6 — Registres autorisés (registry pirate)

**Menace :** Un attaquant publie une image malveillante sur un registry public (typosquatting).

**Contrôle :** Kyverno n'autorise que les images provenant de notre registry GHCR.

**Commande de preuve :**
```bash
kubectl run test-unsigned --image=nginx:latest -n app
# → "allowed-registries: Image refusée"
```

---

## 4. Ce qui reste hors périmètre / non couvert

| Risque | Justification | Piste de mitigation |
|---|---|---|
| **Compromission du build** | Le build local n'est pas isolé (SLSA L3) | Utiliser GitHub Actions avec runners éphémères |
| **Sécurité du poste développeur** | Les secrets (clés, tokens) sont sur le poste | Utiliser des secrets manager, keyless signing |
| **Vulnérabilités 0-day** | Aucun correctif disponible | Monitoring continu, SBOM pour réponse rapide |
| **Compromission du runner CI** | SolarWinds/Codecov | Isolation forte, vérification des workflows |
| **Attaque sur Rekor** | Le transparency log est public | Rekor est append-only, mais pas infalsifiable |

---

## 5. Niveau SLSA visé vs atteint

| Niveau | Visé | Atteint | Justification |
|---|---|---|---|
| **L1** : Provenance existe | ✅ | ✅ | Attestation de provenance SLSA attachée et vérifiable |
| **L2** : Build hébergé + provenance signée | ✅ | ⚠️ Partiel | Build local (pas en CI) ; signature par clé (pas keyless OIDC) |
| **L3** : Build isolé infalsifiable | — | ❌ | Hors périmètre ; nécessite des runners isolés et une provenance générée par un outil officiel |

### Justification du niveau atteint

**SLSA L1 ✅ :**
- La provenance existe (fichier `provenance.json`)
- Elle est signée et attachée à l'image comme attestation
- Vérifiable avec `cosign verify-attestation`

**SLSA L2 ⚠️ Partiel :**
- ❌ Build local (pas sur une plateforme hébergée)
- ❌ Signature par clé privée (pas keyless OIDC)
- ✅ Provenance signée et vérifiable
- ✅ Image stockée dans un registry (GHCR)

**Pour atteindre SLSA L2 complet :**
1. Builder sur GitHub Actions (plateforme hébergée)
2. Signer en keyless (OIDC du runner)
3. Utiliser `slsa-framework/slsa-github-generator` pour la provenance

**Pour atteindre SLSA L3 :**
1. Runners éphémères et isolés (pas de persistance)
2. Provenance générée par un outil officiel (pas manuelle)
3. Séparation stricte des permissions (build vs deploy)

---

## 6. Synthèse visuelle

```
┌─────────────────────────────────────────────────────────────────┐
│                    MENACE                CONTRÔLE                │
├─────────────────────────────────────────────────────────────────┤
│  Image altérée          ──────►  Signature cosign (digest)      │
│  Image non signée       ──────►  Kyverno verifyImages           │
│  Tag :latest            ──────►  Kyverno disallow-latest        │
│  Registry pirate        ──────►  Kyverno allowed-registries     │
│  Dépendance vulnérable  ──────►  SBOM + Grype (gate CRITICAL)   │
│  Origine inconnue       ──────►  Attestation SLSA provenance    │
│  Clé compromise         ──────►  Keyless OIDC (CI)              │
└─────────────────────────────────────────────────────────────────┘
```

---

## 7. Conclusion

La mise en place de la signature cosign, des attestations SBOM/provenance, et des politiques Kyverno couvre les menaces principales de la chaîne d'approvisionnement :

- **Intégrité** : garantie par la signature liée au digest
- **Authenticité** : garantie par la vérification de la signature à l'admission
- **Traçabilité** : garantie par l'attestation de provenance SLSA
- **Défense en profondeur** : chaque couche (registry, signature, admission) bloque les attaques

**Limites honnêtes :**
- Le build local n'est pas isolé (SLSA L3 non atteint)
- La clé privée doit être protégée (keyless recommandé en production)
- Les vulnérabilités 0-day ne sont pas couvertes

**Recommandation pour la production :**
1. Utiliser la signature keyless (OIDC GitHub Actions)
2. Automatiser en CI/CD (GitHub Actions)
3. Exiger la provenance à l'admission (pas seulement la signature)
4. Viser SLSA L2 avec `slsa-framework/slsa-github-generator`
