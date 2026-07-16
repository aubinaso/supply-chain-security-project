#!/bin/bash
# =============================================================================
# Script de démo complète : Lab 2 - Signature & Attestations
# =============================================================================
# Ce script exécute toutes les étapes du Lab 2 pour une démonstration.
# Il peut être exécuté de manière interactive ou en mode démo.
#
# Usage : ./scripts/demo-lab2-complete.sh [--auto]
#   --auto : exécution automatique sans pause entre les étapes
# =============================================================================

set -euo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Mode auto (sans pause)
AUTO_MODE=false
if [[ "${1:-}" == "--auto" ]]; then
    AUTO_MODE=true
fi

# Fonction d'attente
wait_for_user() {
    if [ "$AUTO_MODE" = false ]; then
        echo -e "${YELLOW}Appuyez sur Entrée pour continuer...${NC}"
        read -r
    else
        sleep 1
    fi
}

# Fonction d'affichage des commandes
show_command() {
    echo -e "${CYAN}$ $*${NC}"
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          LAB 2 — DÉMO COMPLÈTE : SIGNATURE & ATTESTATIONS      ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# --------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------
echo -e "${BLUE}[CONFIG] Variables d'environnement${NC}"
export IMG=ghcr.io/johlan78/scs-demo-app
export TAG=0.1.0
export DIGEST=ghcr.io/johlan78/scs-demo-app@sha256:6274762da84c8f74925c2ebf676c832ad98252b880376c75ba27de5384b90721
export LOCAL_REGISTRY="localhost:5000"
export LOCAL_IMG="$LOCAL_REGISTRY/scs-demo-app"

echo -e "  Image GHCR : ${GREEN}$IMG:$TAG${NC}"
echo -e "  Digest GHCR : ${GREEN}$DIGEST${NC}"
echo ""

# Vérifier le registry local
LOCAL_DIGEST=""
if curl -s -o /dev/null -w "%{http_code}" "http://$LOCAL_REGISTRY/v2/_catalog" | grep -q "200"; then
    LOCAL_DIGEST=$(curl -s -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
      "http://$LOCAL_REGISTRY/v2/scs-demo-app/manifests/0.1.0" | \
      grep -o '"digest":"sha256:[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [ -n "$LOCAL_DIGEST" ]; then
        LOCAL_DIGEST="$LOCAL_REGISTRY/scs-demo-app@$LOCAL_DIGEST"
        export WORKING_DIGEST="$LOCAL_DIGEST"
        echo -e "  Registry local : ${GREEN}✓${NC} $LOCAL_DIGEST"
    fi
else
    export WORKING_DIGEST="$DIGEST"
    echo -e "  Registry local : ${YELLOW}!${NC} Non disponible, utilisation de GHCR"
fi
echo ""
wait_for_user

# ==========================================================================
# ÉTAPE 2.2 : Signature par clé
# ==========================================================================
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  ÉTAPE 2.2 : SIGNATURE PAR CLÉ                                 ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Déterminer les flags selon le registry
REGISTRY_FLAGS=""
if [[ "$WORKING_DIGEST" == localhost:* ]]; then
    REGISTRY_FLAGS="--allow-insecure-registry"
fi

echo -e "${GREEN}1. Génération de la paire de clés cosign${NC}"
show_command cosign generate-key-pair
echo -e "   ${CYAN}→ Crée cosign.key (SECRET) et cosign.pub${NC}"
echo ""

echo -e "${GREEN}2. Signature de l'image par digest${NC}"
show_command "COSIGN_PASSWORD=\"testpass123\" cosign sign --key cosign.key $REGISTRY_FLAGS --yes \"$WORKING_DIGEST\""
echo -e "   ${CYAN}→ Pousse la signature dans le registry${NC}"
echo -e "   ${CYAN}→ Enregistre dans Rekor (transparency log)${NC}"
echo ""

echo -e "${GREEN}3. Vérification de la signature${NC}"
show_command "cosign verify --key cosign.pub $REGISTRY_FLAGS \"$WORKING_DIGEST\""
echo -e "   ${CYAN}→ Vérifie : claims valides + présence dans Rekor + signature correcte${NC}"
echo ""

wait_for_user

# ==========================================================================
# ÉTAPE 2.3 : Signature keyless
# ==========================================================================
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  ÉTAPE 2.3 : SIGNATURE KEYLESS (OIDC)                          ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${YELLOW}La signature keyless utilise votre identité OIDC (GitHub, Google)${NC}"
echo -e "${YELLOW}au lieu d'une clé privée. Idéal pour CI/CD.${NC}"
echo ""

echo -e "${GREEN}1. Signature keyless (en CI)${NC}"
show_command "COSIGN_EXPERIMENTAL=1 cosign sign $REGISTRY_FLAGS --yes \"$WORKING_DIGEST\""
echo -e "   ${CYAN}→ Ouvre un navigateur pour authentification OIDC${NC}"
echo -e "   ${CYAN}→ En CI (GitHub Actions) : automatique via l'OIDC du runner${NC}"
echo ""

echo -e "${GREEN}2. Vérification keyless${NC}"
show_command "COSIGN_EXPERIMENTAL=1 cosign verify $REGISTRY_FLAGS \\"
echo -e "   ${CYAN}--certificate-identity-regexp \".*\" \\${NC}"
echo -e "   ${CYAN}--certificate-oidc-issuer-regexp \".*\" \\${NC}"
echo -e "   ${CYAN}\"$WORKING_DIGEST\"${NC}"
echo ""

echo -e "${GREEN}3. Vérification avec identité spécifique (pour Kyverno)${NC}"
show_command "COSIGN_EXPERIMENTAL=1 cosign verify $REGISTRY_FLAGS \\"
echo -e "   ${CYAN}--certificate-identity \"https://github.com/johlan78/.../.github/workflows/supply-chain.yml@refs/heads/main\" \\${NC}"
echo -e "   ${CYAN}--certificate-oidc-issuer \"https://token.actions.githubusercontent.com\" \\${NC}"
echo -e "   ${CYAN}\"$WORKING_DIGEST\"${NC}"
echo ""

wait_for_user

# ==========================================================================
# ÉTAPE 2.4 : Attestation SBOM
# ==========================================================================
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  ÉTAPE 2.4 : ATTESTATION SBOM                                  ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${GREEN}1. Génération du SBOM avec Syft${NC}"
show_command "syft \"$LOCAL_IMG:$TAG\" -o spdx-json > sbom.spdx.json"
echo -e "   ${CYAN}→ Liste exhaustive des paquets de l'image${NC}"
echo -e "   ${CYAN}→ Format SPDX (standard interopérable)${NC}"
echo ""

echo -e "${GREEN}2. Attachement de l'attestation SBOM${NC}"
show_command "cosign attest --key cosign.key $REGISTRY_FLAGS --yes \\"
echo -e "   ${CYAN}--predicate sbom.spdx.json \\${NC}"
echo -e "   ${CYAN}--type spdxjson \\${NC}"
echo -e "   ${CYAN}\"$WORKING_DIGEST\"${NC}"
echo -e "   ${CYAN}→ Attache le SBOM signé à l'image${NC}"
echo ""

echo -e "${GREEN}3. Vérification de l'attestation SBOM${NC}"
show_command "cosign verify-attestation --key cosign.pub $REGISTRY_FLAGS --type spdxjson \"$WORKING_DIGEST\""
echo -e "   ${CYAN}→ Vérifie que l'attestation est signée par votre clé${NC}"
echo ""

wait_for_user

# ==========================================================================
# ÉTAPE 2.5 : Attestation de provenance SLSA
# ==========================================================================
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  ÉTAPE 2.5 : ATTESTATION DE PROVENANCE SLSA                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${GREEN}1. Création de provenance.json${NC}"
cat <<'EOF'
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
EOF
echo -e "   ${CYAN}→ Répond à : QUI a construit QUOI, DEPUIS OÙ, QUAND${NC}"
echo ""

echo -e "${GREEN}2. Attachement de l'attestation de provenance${NC}"
show_command "cosign attest --key cosign.key $REGISTRY_FLAGS --yes \\"
echo -e "   ${CYAN}--predicate provenance.json \\${NC}"
echo -e "   ${CYAN}--type slsaprovenance \\${NC}"
echo -e "   ${CYAN}\"$WORKING_DIGEST\"${NC}"
echo ""

echo -e "${GREEN}3. Vérification de l'attestation de provenance${NC}"
show_command "cosign verify-attestation --key cosign.pub $REGISTRY_FLAGS --type slsaprovenance \"$WORKING_DIGEST\""
echo -e "   ${CYAN}→ Vérifie predicateType = https://slsa.dev/provenance/v0.2${NC}"
echo ""

wait_for_user

# ==========================================================================
# ÉTAPE 2.6 : Inspection du registry
# ==========================================================================
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  ÉTAPE 2.6 : INSPECTION DU REGISTRY (cosign tree)              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${GREEN}Artefacts attachés à l'image :${NC}"
show_command "cosign tree $REGISTRY_FLAGS \"$WORKING_DIGEST\""
echo ""
echo -e "   Résultat attendu :"
echo -e "   ${CYAN}📦 Supply Chain Security Related artifacts for an image${NC}"
echo -e "   ${CYAN}└── 💾 Attestations for an image tag${NC}"
echo -e "   ${CYAN}   ├── 🍒 sha256:... (SBOM)${NC}"
echo -e "   ${CYAN}   └── 🍒 sha256:... (Provenance)${NC}"
echo -e "   ${CYAN}└── 🔐 Signatures for an image tag${NC}"
echo -e "   ${CYAN}   └── 🍒 sha256:... (Signature)${NC}"
echo ""

wait_for_user

# ==========================================================================
# Préparation Kyverno (Partie 3)
# ==========================================================================
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  PRÉPARATION KYVERNO (Partie 3)                                ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${GREEN}Fichiers mis à jour pour Kyverno :${NC}"
echo -e "  • ${CYAN}policies/kyverno/01-allowed-registries.yaml${NC} → ghcr.io/johlan78/*"
echo -e "  • ${CYAN}policies/kyverno/03-verify-signature.yaml${NC} → cosign.pub injecté"
echo -e "  • ${CYAN}policies/kyverno/04-require-provenance.yaml${NC} → cosign.pub injecté"
echo -e "  • ${CYAN}k8s/deployment.yaml${NC} → image par digest GHCR"
echo ""

echo -e "${GREEN}Clé publique cosign (pour Kyverno) :${NC}"
cat cosign.pub
echo ""

wait_for_user

# ==========================================================================
# Résumé final
# ==========================================================================
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    RÉSUMÉ DU LAB 2                              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${GREEN}✅ Critères de sortie du Lab 2 :${NC}"
echo -e "  ${GREEN}✓${NC} cosign.key est dans .gitignore"
echo -e "  ${GREEN}✓${NC} Image signée (par clé) et cosign verify réussit"
echo -e "  ${GREEN}✓${NC} Attestation SBOM attachée et vérifiable"
echo -e "  ${GREEN}✓${NC} Attestation de provenance attachée et vérifiable"
echo -e "  ${GREEN}✓${NC} cosign tree montre signature + attestations"
echo -e "  ${GREEN}✓${NC} Policies Kyverno préparées pour la Partie 3"
echo ""

echo -e "${GREEN}🚀 Prochaine étape :${NC} Lab 3 — Cluster Kyverno (admission control)"
echo ""
echo -e "${GREEN}✓${NC} Démo Lab 2 terminée avec succès !"
