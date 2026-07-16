#!/bin/bash
# =============================================================================
# Script de démo : Lab 4 — Attaque / Défense (registry local)
# =============================================================================
# Prérequis : le cluster 'scs' du Lab 3 est up, Kyverno Ready, les 3 politiques
# (allowed-registries-local, disallow-latest-tag, verify-signature-local) sont
# appliquées, et l'image de référence (172.17.0.1:5000/scs-demo-app:0.1.0)
# tourne déjà (voir scripts/demo-lab3-cluster.sh).
#
# Ce script isole chaque attaque du Lab 4 (une politique déclenchée à la fois),
# contrairement aux tests groupés du Lab 3 (nginx:latest déclenche 2 politiques
# en même temps). Chaque étape correspond à une capture attendue dans
# docs/lab4-captures-demo.md.
#
# Usage : ./scripts/demo-lab4-attaque-defense.sh [--auto]
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

REGISTRY="172.17.0.1:5000"
IMG="$REGISTRY/scs-demo-app"
TAG="0.1.0"
NS="app"
COSIGN_PASSWORD="${COSIGN_PASSWORD:-testpass123}"

AUTO_MODE=false
if [[ "${1:-}" == "--auto" ]]; then
    AUTO_MODE=true
fi

wait_for_user() {
    if [ "$AUTO_MODE" = false ]; then
        echo -e "${YELLOW}Appuyez sur Entrée pour continuer (prenez la capture avant)...${NC}"
        read -r
    else
        sleep 2
    fi
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       LAB 4 — ATTAQUE / DÉFENSE (chaque attaque isolée)         ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# --------------------------------------------------------------------------
# Scénario 0 (rappel) : l'image légitime tourne déjà
# --------------------------------------------------------------------------
echo -e "${BLUE}[0/4] Rappel — cas nominal${NC}"
echo -e "${CYAN}$ kubectl get pods -n $NS${NC}"
kubectl get pods -n "$NS"
echo -e "${GREEN}✓${NC} 📸 Capture 0 : image légitime en Running (déjà couvert au Lab 3)"
echo ""
wait_for_user

# --------------------------------------------------------------------------
# Attaque 1 : image NON signée
# --------------------------------------------------------------------------
echo -e "${BLUE}[1/4] Attaque 1 — image NON signée${NC}"
echo -e "${CYAN}$ docker build -t $IMG:unsigned app/${NC}"
docker build -t "$IMG:unsigned" app/
echo -e "${CYAN}$ docker push $IMG:unsigned${NC}"
docker push "$IMG:unsigned"
DIGEST_UNSIGNED=$(docker inspect --format='{{index .RepoDigests 0}}' "$IMG:unsigned")
echo "Digest non signé : $DIGEST_UNSIGNED"
echo ""
echo -e "${RED}$ kubectl run pirate --image=\"$DIGEST_UNSIGNED\" -n $NS${NC}"
kubectl run pirate --image="$DIGEST_UNSIGNED" -n "$NS" 2>&1 || true
echo -e "${GREEN}✓${NC} 📸 Capture 1 : refus attendu de verify-image-signature (pas de signature)"
echo ""
wait_for_user

# --------------------------------------------------------------------------
# Attaque 2 : image MODIFIÉE après signature (scénario SolarWinds)
# --------------------------------------------------------------------------
echo -e "${BLUE}[2/4] Attaque 2 — image MODIFIÉE après signature (SolarWinds)${NC}"
echo "On rebâtit le MÊME tag ($TAG) avec un contenu différent :"
echo -e "${CYAN}$ echo \"RUN echo 'backdoor'\" >> app/Dockerfile${NC}"
echo "RUN echo 'backdoor'" >> app/Dockerfile
echo -e "${CYAN}$ docker build -t $IMG:$TAG app/${NC}"
docker build -t "$IMG:$TAG" app/
echo -e "${CYAN}$ docker push $IMG:$TAG${NC}"
docker push "$IMG:$TAG"
DIGEST_TAMPERED=$(docker inspect --format='{{index .RepoDigests 0}}' "$IMG:$TAG")
echo "Nouveau digest (contenu modifié) : $DIGEST_TAMPERED"
echo ""
echo -e "${RED}$ kubectl run tampered --image=\"$DIGEST_TAMPERED\" -n $NS${NC}"
kubectl run tampered --image="$DIGEST_TAMPERED" -n "$NS" 2>&1 || true
echo -e "${GREEN}✓${NC} 📸 Capture 2 : refus attendu — aucune signature n'existe pour ce nouveau digest"
echo ""
echo -e "${CYAN}$ git checkout app/Dockerfile${NC}  (annule la modif malveillante simulée)"
git checkout app/Dockerfile
echo ""
echo -e "${YELLOW}Le tag $TAG pointe maintenant sur le contenu trafiqué dans le registry local.${NC}"
echo -e "${YELLOW}On republie la version propre pour ne pas casser une répétition ultérieure :${NC}"
echo -e "${CYAN}$ docker build -t $IMG:$TAG app/ && docker push $IMG:$TAG${NC}"
docker build -t "$IMG:$TAG" app/
docker push "$IMG:$TAG"
echo -e "${GREEN}✓${NC} Tag $TAG restauré au contenu légitime"
echo -e "${YELLOW}Note : un rebuild Docker n'est pas garanti bit-à-bit identique (couches, cache).${NC}"
echo -e "${YELLOW}Si le digest diffère de l'original signé, re-signez avant la prochaine répétition${NC}"
echo -e "${YELLOW}(cosign sign --key cosign.key ... sur le nouveau digest).${NC}"
echo ""
wait_for_user

# --------------------------------------------------------------------------
# Attaque 3 : registry NON autorisé (isolée de :latest)
# --------------------------------------------------------------------------
echo -e "${BLUE}[3/4] Attaque 3 — registry NON autorisé${NC}"
echo -e "${RED}$ kubectl run fromdockerhub --image=nginx:1.25 -n $NS${NC}"
kubectl run fromdockerhub --image=nginx:1.25 -n "$NS" 2>&1 || true
echo -e "${GREEN}✓${NC} 📸 Capture 3 : refus attendu d'allowed-registries (nginx ≠ $REGISTRY)"
echo ""
wait_for_user

# --------------------------------------------------------------------------
# Attaque 4 : tag :latest sur NOTRE image (isolée du registry)
# --------------------------------------------------------------------------
echo -e "${BLUE}[4/4] Attaque 4 — tag :latest${NC}"
echo -e "${CYAN}$ docker tag $IMG:$TAG $IMG:latest && docker push $IMG:latest${NC}"
docker tag "$IMG:$TAG" "$IMG:latest"
docker push "$IMG:latest"
echo -e "${RED}$ kubectl run uselatest --image=$IMG:latest -n $NS${NC}"
kubectl run uselatest --image="$IMG:latest" -n "$NS" 2>&1 || true
echo -e "${GREEN}✓${NC} 📸 Capture 4 : refus attendu de disallow-latest-tag"
echo ""

# --------------------------------------------------------------------------
# Attaque 5 (bonus) : NON exécutable en l'état
# --------------------------------------------------------------------------
echo -e "${YELLOW}[bonus] Attaque 5 — signée sans provenance : NON exécutable en l'état.${NC}"
echo -e "${YELLOW}La politique 04-require-provenance-local a été retirée (Lab 3) car l'attestation${NC}"
echo -e "${YELLOW}SBOM (2.3 Mo) dépasse la limite de vérification Kyverno (2 Mo). Voir la note${NC}"
echo -e "${YELLOW}« Limites connues » du threat model avant de tenter ce scénario en démo.${NC}"
echo ""

# --------------------------------------------------------------------------
# Nettoyage des pods de test (ne pas laisser traîner en Error/ImagePullBackOff)
# --------------------------------------------------------------------------
echo -e "${BLUE}Nettoyage des pods de test${NC}"
kubectl delete pod pirate tampered fromdockerhub uselatest -n "$NS" --ignore-not-found 2>&1 || true
echo ""

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    RÉSUMÉ DU LAB 4                              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo -e "${GREEN}✓${NC} Attaque 1 (non signée), 2 (modifiée), 3 (registry), 4 (:latest) : rejouées."
echo -e "${YELLOW}!${NC} Attaque 5 (bonus, sans provenance) : bloquée par une limite technique connue."
echo ""
echo -e "Cochez les captures dans docs/lab4-captures-demo.md, puis complétez"
echo -e "livrables/threat-model.md avec ce qui a réellement été observé."
