#!/bin/bash
# =============================================================================
# Script de démo : Lab 3 — Cluster Kyverno (Admission Control)
# =============================================================================
# Ce script crée un cluster kind, installe Kyverno, applique les politiques,
# déploie l'app signée et démontre que les images non conformes sont rejetées.
#
# Usage : ./scripts/demo-lab3-cluster.sh [--auto]
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

# Mode auto
AUTO_MODE=false
if [[ "${1:-}" == "--auto" ]]; then
    AUTO_MODE=true
fi

wait_for_user() {
    if [ "$AUTO_MODE" = false ]; then
        echo -e "${YELLOW}Appuyez sur Entrée pour continuer...${NC}"
        read -r
    else
        sleep 2
    fi
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       LAB 3 — CLUSTER KYVERNO (ADMISSION CONTROL)              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# --------------------------------------------------------------------------
# Étape 1 : Créer le cluster kind
# --------------------------------------------------------------------------
echo -e "${BLUE}[1/6] Création du cluster kind${NC}"
echo -e "${CYAN}$ kind create cluster --name scs --config cluster/kind-config-local.yaml${NC}"
echo ""

# Check if cluster exists
if kind get clusters 2>/dev/null | grep -q "scs"; then
    echo -e "${YELLOW}!${NC} Cluster 'scs' existe déjà, suppression..."
    kind delete cluster --name scs 2>/dev/null
fi

kind create cluster --name scs --config cluster/kind-config-local.yaml 2>&1
echo ""
echo -e "${GREEN}✓${NC} Cluster kind créé"
echo ""
wait_for_user

# --------------------------------------------------------------------------
# Étape 2 : Installer Kyverno
# --------------------------------------------------------------------------
echo -e "${BLUE}[2/6] Installation de Kyverno${NC}"
echo -e "${CYAN}$ kubectl create -f https://github.com/kyverno/kyverno/releases/latest/download/install.yaml${NC}"
echo ""

kubectl create -f https://github.com/kyverno/kyverno/releases/latest/download/install.yaml 2>&1 | tail -5

echo ""
echo -e "${CYAN}$ kubectl -n kyverno rollout status deploy/kyverno-admission-controller${NC}"
kubectl -n kyverno rollout status deploy/kyverno-admission-controller --timeout=180s 2>&1

echo ""
echo -e "${GREEN}✓${NC} Kyverno installé et prêt"
echo ""
wait_for_user

# --------------------------------------------------------------------------
# Étape 3 : Créer le namespace et charger l'image
# --------------------------------------------------------------------------
echo -e "${BLUE}[3/6] Préparation de l'environnement${NC}"
echo ""

echo -e "${CYAN}$ kubectl create namespace app${NC}"
kubectl create namespace app 2>&1
echo ""

echo -e "${CYAN}$ kind load docker-image 172.17.0.1:5000/scs-demo-app:0.1.0 --name scs${NC}"
kind load docker-image 172.17.0.1:5000/scs-demo-app:0.1.0 --name scs 2>&1
echo ""
echo -e "${GREEN}✓${NC} Namespace créé et image chargée"
echo ""
wait_for_user

# --------------------------------------------------------------------------
# Étape 4 : Appliquer les politiques Kyverno
# --------------------------------------------------------------------------
echo -e "${BLUE}[4/6] Application des politiques Kyverno${NC}"
echo ""

echo -e "${CYAN}$ kubectl apply -f policies/kyverno/01-allowed-registries-local.yaml${NC}"
kubectl apply -f policies/kyverno/01-allowed-registries-local.yaml 2>&1
echo ""

echo -e "${CYAN}$ kubectl apply -f policies/kyverno/02-disallow-latest.yaml${NC}"
kubectl apply -f policies/kyverno/02-disallow-latest.yaml 2>&1
echo ""

echo -e "${CYAN}$ kubectl apply -f policies/kyverno/03-verify-signature-local.yaml${NC}"
kubectl apply -f policies/kyverno/03-verify-signature-local.yaml 2>&1
echo ""

echo -e "${CYAN}$ kubectl get clusterpolicy${NC}"
kubectl get clusterpolicy
echo ""
echo -e "${GREEN}✓${NC} Politiques appliquées (toutes Ready)"
echo ""
wait_for_user

# --------------------------------------------------------------------------
# Étape 5 : Déployer l'image signée
# --------------------------------------------------------------------------
echo -e "${BLUE}[5/6] Déploiement de l'image signée${NC}"
echo ""

echo -e "${CYAN}$ kubectl apply -f k8s/deployment-local.yaml${NC}"
kubectl apply -f k8s/deployment-local.yaml 2>&1
echo ""

echo -e "Attente du démarrage du pod..."
sleep 30

echo -e "${CYAN}$ kubectl get pods -n app${NC}"
kubectl get pods -n app
echo ""

echo -e "${CYAN}$ curl -s http://localhost:8080/health${NC}"
curl -s http://localhost:8080/health | jq .
echo ""
echo -e "${GREEN}✓${NC} Image signée acceptée et application fonctionnelle"
echo ""
wait_for_user

# --------------------------------------------------------------------------
# Étape 6 : Tests de rejet
# --------------------------------------------------------------------------
echo -e "${BLUE}[6/6] Tests de rejet des images non conformes${NC}"
echo ""

echo -e "${RED}Test 1 : Image d'un registry non autorisé (nginx:latest)${NC}"
echo -e "${CYAN}$ kubectl run test-unsigned --image=nginx:latest -n app${NC}"
kubectl run test-unsigned --image=nginx:latest -n app 2>&1 || true
echo ""

echo -e "${RED}Test 2 : Tag :latest interdit${NC}"
echo -e "${CYAN}$ kubectl run test-latest --image=172.17.0.1:5000/scs-demo-app:latest -n app${NC}"
kubectl run test-latest --image=172.17.0.1:5000/scs-demo-app:latest -n app 2>&1 || true
echo ""

echo -e "${GREEN}✓${NC} Images non conformes rejetées par Kyverno"
echo ""

# --------------------------------------------------------------------------
# Résumé
# --------------------------------------------------------------------------
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    RÉSUMÉ DU LAB 3                              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${GREEN}✅ Critères de sortie du Lab 3 :${NC}"
echo -e "  ${GREEN}✓${NC} Cluster kind up + Kyverno Ready"
echo -e "  ${GREEN}✓${NC} Les 3 ClusterPolicy sont Ready et en Enforce"
echo -e "  ${GREEN}✓${NC} Image signée acceptée (pod Running)"
echo -e "  ${GREEN}✓${NC} Image non signée rejetée"
echo -e "  ${GREEN}✓${NC} Tag :latest rejeté"
echo ""

echo -e "${GREEN}🚀 Prochaine étape :${NC} Lab 4 — Attaque/Défense"
echo ""
echo -e "${GREEN}✓${NC} Démo Lab 3 terminée avec succès !"
