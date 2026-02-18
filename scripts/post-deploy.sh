#!/bin/bash
# post-deploy.sh — run AFTER terraform apply
# Automates all manual steps from the Next Deploy Checklist in CLAUDE.md.
#
# Usage: ./scripts/post-deploy.sh
#
# Prerequisites:
#   - terraform apply completed successfully
#   - AWS credentials configured (aws sts get-caller-identity must work)
#   - borod-bank-cd repo cloned at path set in CD_REPO_PATH
#   - kubectl installed
#   - jq installed

set -euo pipefail

# --- Config ---
CLUSTER_NAME="borod-bank-cluster"
REGION="us-east-1"
ARGOCD_NAMESPACE="argocd"
CD_REPO_PATH="${CD_REPO_PATH:-${HOME}/Documents/Projects/GitOps Project & Doc/borod-bank-cd}"
ARGOCD_REPO_URL="https://github.com/Synaptix-Innovations/borod-bank-cd"
SONAR_NAMESPACE="sonarqube"
SONAR_SVC="sonarqube-service"
JENKINS_NAMESPACE="jenkins"
SM_JENKINS_SECRET="borod-bank/jenkins"

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
step()  { echo -e "${CYAN}[STEP]${NC}  $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; exit 1; }

check_deps() {
  for cmd in aws kubectl terraform jq curl; do
    command -v "$cmd" &>/dev/null || error "Required: $cmd is not installed"
  done
}

# ─────────────────────────────────────────────
# STEP 1 — Get terraform outputs
# ─────────────────────────────────────────────
get_outputs() {
  step "1/10 — Reading terraform outputs..."
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  INFRA_DIR="$(dirname "$SCRIPT_DIR")"
  cd "$INFRA_DIR"

  VPC_ID=$(terraform output -raw vpc_id)
  RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
  RDS_SECRET_ARN=$(terraform output -raw rds_secret_arn)
  EIP_ALLOCATION_IDS=$(terraform output -json eip_allocation_ids | jq -r 'join(",")')
  EIP_PUBLIC_IPS=$(terraform output -json eip_public_ips | jq -r 'join(", ")')

  info "VPC ID:            $VPC_ID"
  info "RDS Endpoint:      $RDS_ENDPOINT"
  info "RDS Secret:        $RDS_SECRET_ARN"
  info "EIP Alloc IDs:     $EIP_ALLOCATION_IDS"
  info "EIP Public IPs:    $EIP_PUBLIC_IPS"
}

# ─────────────────────────────────────────────
# STEP 2 — Update kubeconfig
# ─────────────────────────────────────────────
update_kubeconfig() {
  step "2/10 — Updating kubeconfig..."
  aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"

  info "Waiting for nodes to be Ready..."
  kubectl wait --for=condition=Ready nodes --all --timeout=300s
  info "All nodes Ready"
}

# ─────────────────────────────────────────────
# STEP 3 — Update vpcId in aws-lbc.yml and push
# ─────────────────────────────────────────────
update_vpc_id() {
  step "3/10 — Updating vpcId in aws-lbc.yml..."
  LBC_FILE="$CD_REPO_PATH/argocd/apps/aws-load-balancer-controller.yml"

  if [ ! -f "$LBC_FILE" ]; then
    error "File not found: $LBC_FILE (set CD_REPO_PATH env var)"
  fi

  sed -i "s/vpcId: .*/vpcId: ${VPC_ID}/" "$LBC_FILE"
  info "Updated vpcId to: $VPC_ID"

  cd "$CD_REPO_PATH"
  git add argocd/apps/aws-load-balancer-controller.yml
  git commit -m "infra: update vpcId after terraform apply"
  git push
  info "Pushed vpcId update to borod-bank-cd"
}

# ─────────────────────────────────────────────
# STEP 4 — Update AWS SM: mysql secret
# ─────────────────────────────────────────────
# ─────────────────────────────────────────────
# STEP 4 — Update EIP allocations in ingress-nginx.yml
# ─────────────────────────────────────────────
update_eip_annotations() {
  step "4/10 — Updating EIP allocation IDs in ingress-nginx.yml..."
  NGINX_FILE="$CD_REPO_PATH/argocd/apps/ingress-nginx.yml"

  if [ ! -f "$NGINX_FILE" ]; then
    error "File not found: $NGINX_FILE (set CD_REPO_PATH env var)"
  fi

  sed -i "s|aws-load-balancer-eip-allocations: .*|aws-load-balancer-eip-allocations: \"${EIP_ALLOCATION_IDS}\"|" "$NGINX_FILE"
  info "Updated EIP allocations to: $EIP_ALLOCATION_IDS"

  cd "$CD_REPO_PATH"
  git add argocd/apps/ingress-nginx.yml
  if git diff --cached --quiet; then
    info "EIP allocation IDs unchanged — no commit needed"
  else
    git commit -m "infra: update NLB EIP allocation IDs after terraform apply"
    git push
    info "Pushed EIP annotation update to borod-bank-cd"
  fi
}

# ─────────────────────────────────────────────
# STEP 5 — Update AWS SM: mysql secret
# ─────────────────────────────────────────────
update_mysql_secret() {
  step "5/10 — Updating borod-bank/mysql in AWS Secrets Manager..."

  # RDS managed password is in RDS_SECRET_ARN — extract it
  RDS_PASSWORD=$(aws secretsmanager get-secret-value \
    --secret-id "$RDS_SECRET_ARN" \
    --query 'SecretString' --output text \
    --region "$REGION" | jq -r '.password')

  DATASOURCE_URL="jdbc:mysql://${RDS_ENDPOINT}:3306/borodbankdb?useSSL=true&serverTimezone=UTC"

  # Check if secret exists
  if aws secretsmanager describe-secret --secret-id borod-bank/mysql --region "$REGION" &>/dev/null; then
    aws secretsmanager put-secret-value \
      --secret-id borod-bank/mysql \
      --secret-string "{
        \"MYSQL_ROOT_USER\": \"admin\",
        \"MYSQL_ROOT_PASSWORD\": \"${RDS_PASSWORD}\",
        \"SPRING_DATASOURCE_URL\": \"${DATASOURCE_URL}\"
      }" \
      --region "$REGION"
    info "Updated borod-bank/mysql"
  else
    aws secretsmanager create-secret \
      --name borod-bank/mysql \
      --secret-string "{
        \"MYSQL_ROOT_USER\": \"admin\",
        \"MYSQL_ROOT_PASSWORD\": \"${RDS_PASSWORD}\",
        \"SPRING_DATASOURCE_URL\": \"${DATASOURCE_URL}\"
      }" \
      --region "$REGION"
    info "Created borod-bank/mysql"
  fi
}

# ─────────────────────────────────────────────
# STEP 5 — Bootstrap ArgoCD
# ─────────────────────────────────────────────
bootstrap_argocd() {
  step "6/10 — Bootstrapping ArgoCD..."

  kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -n "$ARGOCD_NAMESPACE" \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  info "Waiting for ArgoCD server to be ready..."
  kubectl wait --for=condition=Available deployment/argocd-server \
    -n "$ARGOCD_NAMESPACE" --timeout=300s

  # Add private CD repo
  ARGOCD_PASSWORD=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' | base64 -d)

  # Port-forward to use argocd CLI
  kubectl port-forward svc/argocd-server -n "$ARGOCD_NAMESPACE" 8443:443 &
  PF_PID=$!
  sleep 5

  argocd login localhost:8443 \
    --username admin \
    --password "$ARGOCD_PASSWORD" \
    --insecure

  # Add repo using GITHUB_TOKEN env var
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    warn "GITHUB_TOKEN not set — skipping repo registration"
    warn "Add manually: argocd repo add $ARGOCD_REPO_URL --username Vlad774 --password <token>"
  else
    argocd repo add "$ARGOCD_REPO_URL" \
      --username Vlad774 \
      --password "$GITHUB_TOKEN" \
      --insecure
    info "Registered borod-bank-cd repo in ArgoCD"
  fi

  kill $PF_PID 2>/dev/null || true

  # Apply App of Apps
  kubectl apply -f "$CD_REPO_PATH/argocd/app-of-apps.yml"
  info "App of Apps applied — ArgoCD will sync all apps"
}

# ─────────────────────────────────────────────
# STEP 6 — Wait for core apps to sync
# ─────────────────────────────────────────────
wait_for_apps() {
  step "7/10 — Waiting for core pods to come up..."
  info "This takes 5-10 minutes for all images to pull..."

  for NS in kube-system cert-manager ingress-nginx; do
    info "Waiting for namespace: $NS"
    kubectl wait --for=condition=Available deployment --all \
      -n "$NS" --timeout=300s 2>/dev/null || warn "Some deployments in $NS not ready yet"
  done

  info "Core namespaces ready"
}

# ─────────────────────────────────────────────
# STEP 7 — SonarQube post-deploy
# ─────────────────────────────────────────────
setup_sonarqube() {
  step "8/10 — SonarQube post-deploy setup..."

  info "Waiting for SonarQube pod..."
  kubectl wait --for=condition=Ready pod -l app=sonarqube \
    -n "$SONAR_NAMESPACE" --timeout=300s 2>/dev/null || {
    warn "SonarQube pod not ready yet, skipping"
    return
  }

  # Get SonarQube admin password from SM
  SONAR_PASS=$(aws secretsmanager get-secret-value \
    --secret-id borod-bank/sonarqube \
    --query 'SecretString' --output text \
    --region "$REGION" 2>/dev/null | jq -r '.SONARQUBE_ADMIN_PASSWORD' || echo "")

  if [ -z "$SONAR_PASS" ]; then
    warn "borod-bank/sonarqube secret not found in AWS SM"
    warn "Create it first, then re-run: ./scripts/post-deploy.sh"
    return
  fi

  # Port-forward SonarQube
  kubectl port-forward svc/"$SONAR_SVC" -n "$SONAR_NAMESPACE" 9000:9000 &
  PF_PID=$!
  sleep 10

  # Generate token
  NEW_TOKEN=$(curl -s -u "admin:${SONAR_PASS}" -X POST \
    "http://127.0.0.1:9000/api/user_tokens/generate" \
    --data-urlencode "name=jenkins-token" | jq -r '.token' || echo "")

  if [ -z "$NEW_TOKEN" ] || [ "$NEW_TOKEN" = "null" ]; then
    warn "Could not generate SonarQube token — may need manual setup"
    kill $PF_PID 2>/dev/null || true
    return
  fi

  info "Generated new SONAR_TOKEN"

  # Update AWS SM jenkins secret
  CURRENT=$(aws secretsmanager get-secret-value \
    --secret-id "$SM_JENKINS_SECRET" \
    --query SecretString --output text --region "$REGION" 2>/dev/null || echo '{}')

  aws secretsmanager put-secret-value \
    --secret-id "$SM_JENKINS_SECRET" \
    --secret-string "$(echo "$CURRENT" | jq --arg t "$NEW_TOKEN" \
      '.SONAR_TOKEN=$t | .SONARQUBE_TOKEN=$t')" \
    --region "$REGION"
  info "Updated SONAR_TOKEN in AWS SM"

  # Add webhook
  curl -s -u "admin:${SONAR_PASS}" -X POST \
    "http://127.0.0.1:9000/api/webhooks/create" \
    --data-urlencode "name=Jenkins" \
    --data-urlencode "url=http://jenkins-service.jenkins:80/sonarqube-webhook/" > /dev/null
  info "Added SonarQube webhook → Jenkins"

  kill $PF_PID 2>/dev/null || true
}

# ─────────────────────────────────────────────
# STEP 8 — ESO resync + Jenkins restart
# ─────────────────────────────────────────────
resync_secrets() {
  step "9/10 — ESO resync and Jenkins restart..."

  # Force ESO to re-pull updated secrets
  for ES in jenkins-secrets mysql-secret sonarqube-secret grafana-secret; do
    kubectl annotate externalsecret "$ES" \
      -n "$JENKINS_NAMESPACE" \
      force-sync="$(date +%s)" --overwrite 2>/dev/null || true
  done

  kubectl annotate externalsecret mysql-secret \
    -n borod-bank \
    force-sync="$(date +%s)" --overwrite 2>/dev/null || true

  info "Forced ESO resync on all secrets"
  sleep 10

  kubectl rollout restart deployment/jenkins -n "$JENKINS_NAMESPACE" 2>/dev/null || \
    warn "Jenkins deployment not found — will pick up secrets on first start"

  info "Jenkins restart triggered"
}

# ─────────────────────────────────────────────
# STEP 9 — Print summary
# ─────────────────────────────────────────────
print_summary() {
  step "10/10 — Summary"
  echo ""

  ARGOCD_PASS=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' | base64 -d 2>/dev/null || echo "check kubectl")

  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}  Borod Bank deploy complete${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo "  Static EIP IPs:  $EIP_PUBLIC_IPS"
  echo "  ArgoCD pass:     $ARGOCD_PASS"
  echo ""
  echo -e "${YELLOW}  DNS A-records (set ONCE — IPs never change between deploys):${NC}"
  for IP in $(echo "$EIP_PUBLIC_IPS" | tr ',' ' '); do
    IP=$(echo "$IP" | xargs)
    echo "  A  vladinnovations.info     → $IP"
    echo "  A  app.vladinnovations.info → $IP"
  done
  echo ""
  echo -e "${YELLOW}  Next:${NC}"
  echo "  1. Set DNS A-records above (only if not already set)"
  echo "  2. Trigger Jenkins build in ArgoCD UI"
  echo "  3. Access: https://app.vladinnovations.info"
  echo ""
}

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────
main() {
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║        Borod Bank Post-Deploy Script         ║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
  echo ""

  check_deps
  get_outputs
  update_kubeconfig
  update_vpc_id
  update_eip_annotations
  update_mysql_secret
  bootstrap_argocd
  wait_for_apps
  setup_sonarqube
  resync_secrets
  print_summary
}

main "$@"
