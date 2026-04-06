#!/usr/bin/env bash
# =============================================================================
# Workshop Setup Script
# Replaces ALL placeholder tokens in every manifest with real values.
#
# Usage:
#   1. Edit setup.env with your values
#   2. source setup.env
#   3. ./setup.sh
# =============================================================================
set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD} Workshop Variable Setup${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""

# ── Validate required variables ───────────────────────────────────────────
[[ -z "${GITHUB_ORG:-}"  ]] && die "GITHUB_ORG is not set. Run: source setup.env"
[[ -z "${GITHUB_REPO:-}" ]] && die "GITHUB_REPO is not set. Run: source setup.env"
[[ -z "${QUAY_ORG:-}"    ]] && die "QUAY_ORG is not set. Run: source setup.env"

# ── Auto-detect OCP domain if not set ────────────────────────────────────
if [[ -z "${OCP_DOMAIN:-}" ]]; then
  info "Auto-detecting OpenShift cluster domain..."
  if ! command -v oc &>/dev/null; then
    die "oc CLI not found and OCP_DOMAIN not set. Set OCP_DOMAIN in setup.env"
  fi
  OCP_DOMAIN=$(oc get ingress.config.openshift.io cluster \
    -o jsonpath='{.spec.domain}' 2>/dev/null) \
    || die "Could not detect OCP domain. Are you logged in? (oc whoami)"
  ok "Detected cluster domain: ${OCP_DOMAIN}"
else
  ok "Using cluster domain from env: ${OCP_DOMAIN}"
fi

# ── Derived values ────────────────────────────────────────────────────────
GITHUB_REPO_URL="https://github.com/${GITHUB_ORG}/${GITHUB_REPO}"
KS_ROUTE_HOST="kickstart-server-workshop-virt.apps.${OCP_DOMAIN}"
KS_URL="http://${KS_ROUTE_HOST}/centos10-workshop.ks"

echo ""
info "Substituting variables:"
echo "  GITHUB_ORG       = ${GITHUB_ORG}"
echo "  GITHUB_REPO      = ${GITHUB_REPO}"
echo "  GITHUB_REPO_URL  = ${GITHUB_REPO_URL}"
echo "  QUAY_ORG         = ${QUAY_ORG}"
echo "  OCP_DOMAIN       = ${OCP_DOMAIN}"
echo "  KS_URL           = ${KS_URL}"
echo ""

# ── Files to process ─────────────────────────────────────────────────────
# All YAML files and the Dockerfile that contain placeholder tokens.
FILES=(
  # ArgoCD app manifests
  argocd/appproject.yaml
  argocd/applications/workshop-dev.yaml
  argocd/applications/workshop-test.yaml
  argocd/applications/workshop-prod.yaml

  # GitOps instance
  gitops/argocd-instance.yaml

  # Helm values
  helm/workshop-app/values.yaml

  # Tekton manifests
  tekton/namespaces.yaml
  tekton/rbac.yaml
  tekton/pipelineruns/run-dev.yaml
  tekton/pipelineruns/run-test.yaml
  tekton/pipelineruns/run-prod.yaml

  # Virt ArgoCD manifests
  virt/argocd/appproject.yaml
  virt/argocd/applications/kickstart-server.yaml
  virt/argocd/applications/centos-workshop-vm.yaml

  # Virt app manifests
  virt/kickstart-server.yaml
  virt/namespace.yaml
  virt/rbac.yaml
  virt/vm/kickstart-configmap.yaml
)

# ── Substitution function ─────────────────────────────────────────────────
substitute() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    warn "Skipping (not found): $file"
    return
  fi
  sed -i \
    -e "s|YOUR_GITHUB_ORG|${GITHUB_ORG}|g" \
    -e "s|YOUR_GITHUB_REPO|${GITHUB_REPO}|g" \
    -e "s|YOUR_QUAY_ORG|${QUAY_ORG}|g" \
    -e "s|YOUR_CLUSTER_DOMAIN|${OCP_DOMAIN}|g" \
    -e "s|YOUR_CLUSTER_APPS_DOMAIN|${OCP_DOMAIN}|g" \
    "$file"
  ok "Processed: $file"
}

for f in "${FILES[@]}"; do
  substitute "$f"
done

# ── Special: kickstart configmap needs full URL ───────────────────────────
sed -i \
  -e "s|http://kickstart-server-workshop-virt.apps.YOUR_CLUSTER_DOMAIN|${KS_URL%/centos10-workshop.ks}|g" \
  virt/vm/kickstart-configmap.yaml 2>/dev/null || true

echo ""
ok "All variables substituted."
echo ""

# ── Verify no placeholders remain ────────────────────────────────────────
info "Checking for remaining placeholders..."
REMAINING=$(grep -rn "YOUR_GITHUB_ORG\|YOUR_GITHUB_REPO\|YOUR_QUAY_ORG\|YOUR_CLUSTER_DOMAIN" \
  argocd/ gitops/ helm/ tekton/ virt/ 2>/dev/null | grep -v ".git" || true)

if [[ -n "$REMAINING" ]]; then
  warn "Remaining unresolved placeholders found:"
  echo "$REMAINING"
else
  ok "No unresolved placeholders found."
fi

echo ""
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD} Next steps${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""
echo "  1. Commit the updated manifests to git:"
echo "     git add -A && git commit -m 'chore: apply workshop variables' && git push origin main"
echo ""
echo "  2. Create Quay registry credentials:"
echo "     See README.md → Step 3 (Quay Credentials)"
echo ""
echo "  3. Deploy the workshop GitOps instance:"
echo "     oc apply -f gitops/"
echo ""
echo "  4. Continue with README.md → Step 4"
echo ""
