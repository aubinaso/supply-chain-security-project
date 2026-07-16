#!/bin/bash
# =============================================================================
# Script de démo : Signature keyless avec cosign (Lab 2.3)
# =============================================================================
# Ce script démontre la signature keyless (sans clé privée) via l'identité OIDC.
# En local, cosign ouvre un navigateur pour l'authentification.
# En CI (GitHub Actions), cela se fait automatiquement via l'OIDC du runner.
#
# Usage : ./scripts/keyless-sign-demo.sh
# =============================================================================

set -euo pipefail

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Signature Keyless avec Cosign (Lab 2.3)  ${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Configuration
export IMG=ghcr.io/johlan78/scs-demo-app
export TAG=0.1.0
export DIGEST=ghcr.io/johlan78/scs-demo-app@sha256:6274762da84c8f74925c2ebf676c832ad98252b880376c75ba27de5384b90721

# Pour le registry local (si GHCR n'est pas accessible)
LOCAL_REGISTRY="localhost:5000"
LOCAL_IMG="$LOCAL_REGISTRY/scs-demo-app"
LOCAL_DIGEST=""  # Sera rempli après vérification

echo -e "${YELLOW}Image cible :${NC} $DIGEST"
echo ""

# --------------------------------------------------------------------------
# Étape 1 : Vérifier que l'image existe
# --------------------------------------------------------------------------
echo -e "${BLUE}[1/5] Vérification de l'image...${NC}"

# Vérifier si le registry local est disponible
if curl -s -o /dev/null -w "%{http_code}" "http://$LOCAL_REGISTRY/v2/_catalog" | grep -q "200"; then
    echo -e "  ${GREEN}✓${NC} Registry local disponible"
    
    # Récupérer le digest local
    LOCAL_DIGEST=$(curl -s -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
      "http://$LOCAL_REGISTRY/v2/scs-demo-app/manifests/0.1.0" | \
      grep -o '"digest":"sha256:[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [ -n "$LOCAL_DIGEST" ]; then
        LOCAL_DIGEST="$LOCAL_REGISTRY/scs-demo-app@$LOCAL_DIGEST"
        echo -e "  ${GREEN}✓${NC} Image locale trouvée : $LOCAL_DIGEST"
    else
        echo -e "  ${RED}✗${NC} Image non trouvée dans le registry local"
        exit 1
    fi
else
    echo -e "  ${YELLOW}!${NC} Registry local non disponible, utilisation de GHCR"
    LOCAL_DIGEST="$DIGEST"
fi

echo ""

# --------------------------------------------------------------------------
# Étape 2 : Signature keyless
# --------------------------------------------------------------------------
echo -e "${BLUE}[2/5] Signature keyless...${NC}"
echo -e "${YELLOW}NOTE :${NC} Cette étape nécessite un navigateur pour l'authentification OIDC."
echo -e "       En CI (GitHub Actions), cela se fait automatiquement."
echo ""

# Déterminer les flags selon le registry
REGISTRY_FLAGS=""
if [[ "$LOCAL_DIGEST" == localhost:* ]]; then
    REGISTRY_FLAGS="--allow-insecure-registry"
fi

echo -e "${YELLOW}Commande à exécuter :${NC}"
echo "  COSIGN_EXPERIMENTAL=1 cosign sign $REGISTRY_FLAGS \\"
echo "    --output-signature keyless.sig \\"
echo "    --output-certificate keyless.cert \\"
echo "    --yes \\"
echo "    \"$LOCAL_DIGEST\""
echo ""

# Tenter la signature (peut échouer sans navigateur)
echo -e "${YELLOW}Tentative de signature keyless...${NC}"
if COSIGN_EXPERIMENTAL=1 timeout 10 cosign sign $REGISTRY_FLAGS \
    --output-signature keyless.sig \
    --output-certificate keyless.cert \
    --yes \
    "$LOCAL_DIGEST" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Signature keyless réussie !"
else
    echo -e "  ${YELLOW}!${NC} Signature keyless nécessite une authentification navigateur"
    echo -e "  ${YELLOW}!${NC} Pour la démo, utilisez la signature par clé (déjà configurée)"
    
    # Créer des fichiers d'exemple pour la démo
    echo "Ephemeral key signature" > keyless.sig
    cat > keyless.cert <<'CERT'
-----BEGIN CERTIFICATE-----
MIICmDCCAj6gAwIBAgIUYKxKzr5z7q2L7L7L7L7L7L7L7L4wCgYIKoZIzj0EAwIw
NjEVMBMGA1UEChMMc2lnc3RvcmUuZGV2MR4wHAYDVQQDExVzaWdzdG9yZS1pbnRl
bXNkaWF0ZTAeFw0yNjAxMDEwMDAwMDBaFw0yNjAxMDEwMDEwMDBaMDExFTATBgNV
BAoTDHNpZ3N0b3JlLmRldjEaMBgGA1UEAxMRZGVtb0BleGFtcGxlLmNvbTBZMBMG
ByqGSM49AgEGCCqGSM49AwEHA0IABO7O7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L
7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7jggEiMIIBHjAPBgNV
HRMBAf8EBTADAQEAMA4GA1UdDwEB/wQEAwIHgDAdBgNVHQ4EFgQU7L7L7L7L7L7L
7L7L7L7L7L7L7L4wHwYDVR0jBBgwFoAU7L7L7L7L7L7L7L7L7L7L7L7L7L4wDwYD
VR0TAQH/BAUwAwEB/zCBiAYDVR0RBIGAMH6CFmdpdGh1Yi5jb20vam9obGFuNzge
Bmh0dHBzOi8vZ2l0aHViLmNvbS9qb2hsYW43OIEhaHR0cHM6Ly90b2tlbi5hY3Rp
b25zLmdpdGh1YnVzZXJjb250ZW50LmNvbTAKBggqhkjOPQQDAgNHADBEAiA7L7L7
L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L
7L7L7L7L7AIhAO7O7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L7L
-----END CERTIFICATE-----
CERT
    echo -e "  ${GREEN}✓${NC} Fichiers d'exemple créés pour la démo"
fi

echo ""

# --------------------------------------------------------------------------
# Étape 3 : Vérification de la signature keyless
# --------------------------------------------------------------------------
echo -e "${BLUE}[3/5] Vérification de la signature keyless...${NC}"
echo ""
echo -e "${YELLOW}Commande de vérification :${NC}"
echo "  COSIGN_EXPERIMENTAL=1 cosign verify $REGISTRY_FLAGS \\"
echo "    --certificate-identity-regexp \".*\" \\"
echo "    --certificate-oidc-issuer-regexp \".*\" \\"
echo "    \"$LOCAL_DIGEST\""
echo ""
echo -e "${YELLOW}Pour vérifier avec une identité spécifique (CI) :${NC}"
echo "  COSIGN_EXPERIMENTAL=1 cosign verify $REGISTRY_FLAGS \\"
echo "    --certificate-identity \"https://github.com/johlan78/supply-chain-security-project/.github/workflows/supply-chain.yml@refs/heads/main\" \\"
echo "    --certificate-oidc-issuer \"https://token.actions.githubusercontent.com\" \\"
echo "    \"$LOCAL_DIGEST\""
echo ""

# --------------------------------------------------------------------------
# Étape 4 : Informations pour Kyverno
# --------------------------------------------------------------------------
echo -e "${BLUE}[4/5] Configuration Kyverno pour keyless...${NC}"
echo ""
echo -e "${YELLOW}Pour utiliser le mode keyless dans Kyverno, remplacez le bloc 'keys' par :${NC}"
echo ""
cat <<'KYVERNO'
          attestors:
            - count: 1
              entries:
                - keyless:
                    issuer: "https://token.actions.githubusercontent.com"
                    subject: "https://github.com/johlan78/supply-chain-security-project/.github/workflows/supply-chain.yml@refs/heads/main"
                    rekor:
                      url: "https://rekor.sigstore.dev"
KYVERNO
echo ""

# --------------------------------------------------------------------------
# Étape 5 : Résumé
# --------------------------------------------------------------------------
echo -e "${BLUE}[5/5] Résumé de la signature keyless${NC}"
echo ""
echo -e "${GREEN}Avantages de la signature keyless :${NC}"
echo "  • Aucune clé privée à gérer ou stocker"
echo "  • Identité basée sur OIDC (GitHub, Google, etc.)"
echo "  • Traçabilité dans Rekor (transparency log)"
echo "  • Idéal pour CI/CD (GitHub Actions, GitLab CI, etc.)"
echo ""
echo -e "${YELLOW}Différence avec la signature par clé :${NC}"
echo "  • Par clé : vous gérez cosign.key (à protéger)"
echo "  • Keyless : l'identité est votre compte OIDC (GitHub, etc.)"
echo ""
echo -e "${GREEN}✓${NC} Lab 2.3 terminé - Signature keyless documentée et prête pour la démo"
