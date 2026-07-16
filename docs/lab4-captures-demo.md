# Lab 4 — Checklist de captures & script de démo (soutenance)

> Objectif de ce document : préparer, dans l'ordre, tout ce qu'il faut **prouver en direct** le
> jour de la soutenance (grille `evaluation/grille-soutenance.md`, critère 1 : **/6**), avec un
> **plan B vidéo** si le live échoue.

## 0. Où ranger les preuves

Créez un dossier `livrables/captures/` (non ignoré par `.gitignore`) et nommez les fichiers dans
l'ordre du scénario, ex. :

```
livrables/captures/
  00-scenario-nominal-accepte.png
  01-attaque-non-signee.png
  02-attaque-modifiee.png
  03-attaque-registry.png
  04-attaque-latest.png
  05-attaque-sans-provenance.png   (bonus)
  demo-video.mp4                    (ou lien si trop lourd pour Git)
```

> Si la vidéo est trop volumineuse pour le dépôt, hébergez-la ailleurs (Drive, YouTube non
> répertorié…) et mettez le **lien** dans le rapport (`livrables/TEMPLATE-rapport.md`, section 4)
> plutôt que de committer un gros binaire.

## 1. Checklist de captures — une par scénario du Lab 4

Chaque ligne = un scénario de [`labs/lab4-attaque-defense.md`](../labs/lab4-attaque-defense.md).
Cochez une fois la capture prise **et** relue (le message Kyverno doit être lisible à l'écran).

- [ ] **Scénario 0 (référence)** — image légitime (signée + provenance + bon registry + par
      digest) → Pod **Running**. Capture du `kubectl get pod` en état `Running`.
- [ ] **Attaque 1** — image non signée → `kubectl run pirate ...` refusé. Capture du message
      `admission webhook "mutate.kyverno.svc-fail" denied` complet.
- [ ] **Attaque 2** — image modifiée après signature (même tag, digest différent) →
      `kubectl run tampered ...` refusé. Capture montrant le nouveau digest + le refus.
- [ ] **Attaque 3** — registry non autorisé (ex. `nginx` Docker Hub) → refusé par
      `allowed-registries`. Capture du message de la politique 01.
- [ ] **Attaque 4** — tag `:latest` → refusé par `disallow-latest-tag`. Capture du message de
      la politique 02.
- [ ] **Attaque 5 (bonus)** — signée mais sans provenance → refusé par
      `require-provenance-attestation`. Capture du message de la politique 04.
- [ ] **Vidéo complète** de la séquence 0→5 enregistrée (plan B soutenance), durée ≤ 5-6 min.

## 2. Script de démo pour la soutenance (12 min au total)

Basé sur `evaluation/grille-soutenance.md` (12 min présentation+démo, 5 min questions).
Répartition indicative :

| Temps | Contenu | Objectif (grille) |
|---|---|---|
| 0:00–1:30 | Contexte : pourquoi la chaîne d'appro est une cible (1 exemple réel : SolarWinds **ou** XZ) | Critère 2 |
| 1:30–3:00 | Schéma rapide de la chaîne (build → SBOM → scan → sign → attest → admission) | Critère 2, 4 |
| 3:00–4:00 | **Démo — Scénario 0** : déployer l'image légitime → `Running` | Critère 1 |
| 4:00–4:45 | **Démo — Attaque 1** : image non signée → refus Kyverno affiché à l'écran | Critère 1 |
| 4:45–5:30 | **Démo — Attaque 2** : image modifiée après signature (le point « SolarWinds ») | Critère 1 |
| 5:30–6:15 | **Démo — Attaque 3 ou 4** (au choix, registry ou `:latest`) | Critère 1 |
| 6:15–7:00 | (Si bonus) **Attaque 5** : signée sans provenance → refus | Critère 1, bonus |
| 7:00–9:00 | Niveau **SLSA** visé vs atteint, ce qui reste contournable (honnêteté) | Critère 3 |
| 9:00–12:00 | Marge / transition questions | Critère 4 |
| 12:00–17:00 | Questions du jury (voir liste type dans la grille) | Critère 5 |

> Le critère 1 exige **au moins 2 attaques bloquées en direct** avec message Kyverno visible —
> prévoyez donc au minimum les Attaques 1 et 2 en live ; gardez 3/4/5 comme captures/vidéo si le
> temps manque.

## 3. Répétition — checklist avant le jour J

- [ ] Cluster `kind` propre, repartant de zéro (`kind delete cluster` puis recréation testée).
- [ ] Les 3 politiques Kyverno sont en `Enforce` (pas `Audit`) — vérifié avec
      `kubectl get clusterpolicy`.
- [ ] `cosign.key` **n'est pas** dans le dépôt (`.gitignore` vérifié).
- [ ] Chrono réel de la démo pris une fois en conditions (viser ≤ 12 min).
- [ ] Vidéo de secours accessible **hors ligne** (pas seulement un lien qui dépend du wifi de la
      salle).
- [ ] Chaque membre du groupe sait relancer au moins un scénario seul (pas un seul pilote).

## 4. Lien avec le threat model

Le tableau « Scénarios de démonstration » de
[`livrables/threat-model.md`](../livrables/threat-model.md) fait le lien explicite entre chaque
attaque jouée ici et la menace qu'elle couvre (T1–T5) — reprenez-le tel quel dans le rapport,
section 4.
