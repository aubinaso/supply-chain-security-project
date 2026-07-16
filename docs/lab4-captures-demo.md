# Lab 4 — Checklist de captures & script de démo (soutenance)

> Objectif de ce document : préparer, dans l'ordre, tout ce qu'il faut **prouver en direct** le
> jour de la soutenance (grille `evaluation/grille-soutenance.md`, critère 1 : **/6**), avec un
> **plan B vidéo** si le live échoue.

## 0. Environnement de référence

Ce document suppose le cluster de démo du Lab 3 déjà en place (voir
`preuves/lab3-cluster-admission.md` et `scripts/demo-lab3-cluster.sh`) :

- Cluster `kind` nommé **`scs`**, namespace `app`.
- Registry local `172.17.0.1:5000` (pas GHCR — voir la note « divergence de digest » dans
  [`livrables/threat-model.md`](../livrables/threat-model.md), section 4).
- 3 politiques Kyverno en `Enforce` : `allowed-registries-local`, `disallow-latest-tag`,
  `verify-signature-local`. La 4ᵉ (`require-provenance-local`) est **désactivée** (attestation
  SBOM trop volumineuse pour la limite Kyverno) — voir section 3 ci-dessous.

Script d'exécution des attaques : [`scripts/demo-lab4-attaque-defense.sh`](../scripts/demo-lab4-attaque-defense.sh)
(à lancer **après** `scripts/demo-lab3-cluster.sh`, sur une machine avec Docker + kind + cosign
opérationnels — pas dans cette session).

## 1. Où ranger les preuves

Créez/complétez le dossier `livrables/captures/` (déjà présent, non ignoré par `.gitignore`) et
nommez les fichiers dans l'ordre du scénario :

```
livrables/captures/
  00-scenario-nominal-accepte.png
  01-attaque-non-signee.png
  02-attaque-modifiee.png
  03-attaque-registry.png
  04-attaque-latest.png
  demo-video.mp4                    (ou lien si trop lourd pour Git)
```

> L'attaque 5 (bonus, sans provenance) n'a **pas** de capture attendue tant que la limite
> Kyverno n'est pas corrigée (voir section 3). Ne pas inventer de capture pour un scénario non
> exécutable.

> Si la vidéo est trop volumineuse pour le dépôt, hébergez-la ailleurs (Drive, YouTube non
> répertorié…) et mettez le **lien** dans le rapport (`livrables/TEMPLATE-rapport.md`, section 4)
> plutôt que de committer un gros binaire.

## 2. Checklist de captures — une par scénario réellement exécutable

Chaque ligne correspond à une étape de `scripts/demo-lab4-attaque-defense.sh`. Cochez une fois la
capture prise **et** relue (le message Kyverno doit être lisible à l'écran).

- [ ] **Scénario 0 (référence)** — `kubectl get pods -n app` → Pod **Running** (image légitime,
      signée, bon registry, par digest).
- [ ] **Attaque 1** — image non signée → `kubectl run pirate ...` refusé par
      `verify-image-signature`. Capture du message complet.
- [ ] **Attaque 2** — image modifiée après signature, même tag (**scénario SolarWinds**) →
      `kubectl run tampered ...` refusé. Capture montrant le nouveau digest **et** le refus.
- [ ] **Attaque 3** — registry non autorisé (`nginx:1.25`, isolée de `:latest`) → refusé par
      `allowed-registries-local`. Capture du message.
- [ ] **Attaque 4** — tag `:latest` sur notre propre image (isolée du registry) → refusé par
      `disallow-latest-tag`. Capture du message.
- [ ] **Vidéo complète** de la séquence 0→4 enregistrée (plan B soutenance), durée ≤ 5-6 min.

## 3. Limite connue — Attaque 5 (bonus, sans provenance)

`policies/kyverno/04-require-provenance-local.yaml` a été **retirée** du cluster de démo au
Lab 3 : l'attestation SBOM (2,3 Mo) dépasse la limite de vérification de Kyverno (2 Mo). Tant que
ce point n'est pas corrigé, l'attaque « signée sans provenance ⇒ refusée » **n'est pas
démontrable en direct**. Deux options si le temps le permet avant la soutenance :

1. Réduire la taille du SBOM (ex. format plus compact, filtrer les métadonnées) pour repasser
   sous la limite Kyverno, puis réactiver la politique et rejouer le scénario.
2. Documenter la limite telle quelle et l'assumer en soutenance (la grille valorise l'honnêteté
   sur les limites, critère 3).

**Ne pas** annoncer ce scénario comme acquis dans le rapport tant qu'il n'a pas été rejoué avec
succès.

## 4. Script de démo pour la soutenance (12 min au total)

Basé sur `evaluation/grille-soutenance.md` (12 min présentation+démo, 5 min questions).
Répartition indicative :

| Temps | Contenu | Objectif (grille) |
|---|---|---|
| 0:00–1:30 | Contexte : pourquoi la chaîne d'appro est une cible (1 exemple réel : SolarWinds **ou** XZ) | Critère 2 |
| 1:30–3:00 | Schéma rapide de la chaîne (build → SBOM → scan → sign → attest → admission) | Critère 2, 4 |
| 3:00–4:00 | **Démo — Scénario 0** : `kubectl get pods -n app` → `Running` | Critère 1 |
| 4:00–4:45 | **Démo — Attaque 1** : image non signée → refus Kyverno affiché à l'écran | Critère 1 |
| 4:45–5:30 | **Démo — Attaque 2** : image modifiée après signature (le point « SolarWinds ») | Critère 1 |
| 5:30–6:15 | **Démo — Attaque 3 ou 4** (au choix, registry ou `:latest`) | Critère 1 |
| 6:15–7:00 | Positionnement **SLSA** visé vs atteint, **y compris la limite provenance non appliquée** | Critère 3 |
| 7:00–9:00 | Reste des limites honnêtes (build non isolé, digest local vs GHCR) | Critère 3 |
| 9:00–12:00 | Marge / transition questions | Critère 4 |
| 12:00–17:00 | Questions du jury (voir liste type dans la grille) | Critère 5 |

> Le critère 1 exige **au moins 2 attaques bloquées en direct** avec message Kyverno visible —
> prévoyez donc au minimum les Attaques 1 et 2 en live ; gardez 3/4 comme captures/vidéo si le
> temps manque. Ne présentez **pas** l'Attaque 5 en live tant qu'elle n'est pas corrigée
> (section 3).

## 5. Répétition — checklist avant le jour J

- [ ] Cluster `kind` (`scs`) propre, repartant de zéro (`kind delete cluster --name scs` puis
      `scripts/demo-lab3-cluster.sh` testé de bout en bout).
- [ ] `scripts/demo-lab4-attaque-defense.sh` rejoué au moins une fois sans erreur.
- [ ] Les 3 politiques Kyverno actives sont en `Enforce` (pas `Audit`) — vérifié avec
      `kubectl get clusterpolicy`.
- [ ] `cosign.key` **n'est pas** dans le dépôt (`.gitignore` vérifié).
- [ ] Chrono réel de la démo pris une fois en conditions (viser ≤ 12 min).
- [ ] Vidéo de secours accessible **hors ligne** (pas seulement un lien qui dépend du wifi de la
      salle).
- [ ] Chaque membre du groupe sait relancer au moins un scénario seul (pas un seul pilote).

## 6. Lien avec le threat model

Le tableau « Scénarios de démonstration » de
[`livrables/threat-model.md`](../livrables/threat-model.md), section 6, fait le lien explicite
entre chaque attaque jouée ici et la menace qu'elle couvre (T1–T8), y compris la limite
provenance — reprenez-le tel quel dans le rapport, section 4.
