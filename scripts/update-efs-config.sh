#!/bin/bash
# update-efs-config.sh — Inject EFS filesystem ID into StorageClass manifest
# Run AFTER terraform apply to replace PLACEHOLDER with actual EFS ID

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
CD_REPO_PATH="${CD_REPO_PATH:-${HOME}/Documents/Projects/GitOps Project & Doc/borod-bank-cd}"
STORAGECLASS_FILE="$CD_REPO_PATH/efs/storageclass.yml"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; }

# Get terraform outputs
cd "$INFRA_DIR"
EFS_ID=$(terraform output -raw efs_filesystem_id 2>/dev/null || echo "")

if [ -z "$EFS_ID" ]; then
  warn "efs_filesystem_id not found. Run 'terraform apply' first."
  exit 1
fi

info "EFS Filesystem ID: $EFS_ID"

# Validate target file exists
if [ ! -f "$STORAGECLASS_FILE" ]; then
  warn "File not found: $STORAGECLASS_FILE"
  exit 1
fi

# Inject EFS ID (replace PLACEHOLDER)
sed -i "s|fileSystemId: PLACEHOLDER|fileSystemId: ${EFS_ID}|" "$STORAGECLASS_FILE"

info "Updated $STORAGECLASS_FILE"

# Commit and push
cd "$CD_REPO_PATH"
git add efs/storageclass.yml
if git diff --cached --quiet; then
  info "No changes to commit (EFS ID already injected)"
else
  git commit -m "infra: inject EFS filesystem ID into StorageClass"
  git push
  info "Pushed EFS config update to borod-bank-cd"
fi

info "✅ EFS StorageClass updated — ArgoCD will sync maven-cache PVC"
