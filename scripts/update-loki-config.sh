#!/bin/bash
# update-loki-config.sh — Update Loki ArgoCD app with actual AWS account ID and role ARN
# Run AFTER terraform apply to populate ACCOUNT_ID placeholders

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
CD_REPO_PATH="${CD_REPO_PATH:-${HOME}/Documents/Projects/GitOps Project & Doc/borod-bank-cd}"
LOKI_APP_FILE="$CD_REPO_PATH/argocd/apps/loki.yml"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; }

# Get terraform outputs
cd "$INFRA_DIR"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
LOKI_ROLE_ARN=$(terraform output -raw loki_role_arn 2>/dev/null || echo "")
LOKI_S3_BUCKET=$(terraform output -raw loki_s3_bucket 2>/dev/null || echo "")

if [ -z "$LOKI_ROLE_ARN" ] || [ -z "$LOKI_S3_BUCKET" ]; then
  warn "Terraform outputs not found. Run 'terraform apply' first."
  exit 1
fi

info "Account ID:       $ACCOUNT_ID"
info "Loki Role ARN:    $LOKI_ROLE_ARN"
info "Loki S3 Bucket:   $LOKI_S3_BUCKET"

# Update loki.yml
if [ ! -f "$LOKI_APP_FILE" ]; then
  warn "File not found: $LOKI_APP_FILE"
  exit 1
fi

sed -i "s|ACCOUNT_ID|${ACCOUNT_ID}|g" "$LOKI_APP_FILE"
sed -i "s|arn:aws:iam::.*:role/borod-bank-loki-role|${LOKI_ROLE_ARN}|" "$LOKI_APP_FILE"
sed -i "s|s3://us-east-1/borod-bank-logs-.*|s3://us-east-1/${LOKI_S3_BUCKET}|" "$LOKI_APP_FILE"

info "Updated $LOKI_APP_FILE"

# Commit and push
cd "$CD_REPO_PATH"
git add argocd/apps/loki.yml
if git diff --cached --quiet; then
  info "No changes to commit"
else
  git commit -m "infra: update Loki config with actual AWS account ID and S3 bucket"
  git push
  info "Pushed Loki config update to borod-bank-cd"
fi

info "✅ Loki configuration updated successfully"
