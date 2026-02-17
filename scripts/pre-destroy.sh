#!/bin/bash
# pre-destroy.sh — run BEFORE terraform destroy
# Deletes K8s PVCs so CSI driver removes EBS volumes cleanly.
# Without this, EBS volumes become orphaned and keep billing after destroy.
#
# Usage: ./scripts/pre-destroy.sh [--skip-destroy]
#   --skip-destroy   Only delete PVCs, do not run terraform destroy

set -euo pipefail

CLUSTER_NAME="borod-bank-cluster"
REGION="us-east-1"
SKIP_DESTROY=false

# --- Parse args ---
for arg in "$@"; do
  case $arg in
    --skip-destroy) SKIP_DESTROY=true ;;
    *) echo "Unknown arg: $arg"; exit 1 ;;
  esac
done

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- Check cluster exists ---
info "Checking EKS cluster..."
CLUSTERS=$(aws eks list-clusters --region "$REGION" --query 'clusters' --output text 2>&1)
if ! echo "$CLUSTERS" | grep -q "$CLUSTER_NAME"; then
  warn "Cluster '$CLUSTER_NAME' not found — skipping kubectl steps"
  SKIP_KUBECTL=true
else
  SKIP_KUBECTL=false
fi

# --- Delete PVCs ---
if [ "$SKIP_KUBECTL" = false ]; then
  info "Updating kubeconfig..."
  aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"

  info "Deleting PVCs in all namespaces (triggers CSI EBS deletion)..."
  for NS in monitoring sonarqube jenkins; do
    PVC_COUNT=$(kubectl get pvc -n "$NS" --no-headers 2>/dev/null | wc -l || echo 0)
    if [ "$PVC_COUNT" -gt 0 ]; then
      info "  Deleting $PVC_COUNT PVC(s) in namespace: $NS"
      kubectl delete pvc --all -n "$NS" --timeout=60s 2>/dev/null || warn "  Some PVCs in $NS timed out"
    else
      info "  No PVCs in $NS"
    fi
  done

  info "Waiting 45s for CSI driver to delete EBS volumes..."
  sleep 45

  # --- Verify no orphan volumes ---
  info "Checking for remaining unattached EBS volumes..."
  ORPHANS=$(aws ec2 describe-volumes \
    --filters Name=status,Values=available \
    --query 'Volumes[?Tags[?Key==`kubernetes.io/created-for/pvc/name`]].VolumeId' \
    --region "$REGION" --output text 2>/dev/null || true)

  if [ -n "$ORPHANS" ]; then
    warn "Orphan volumes still exist, force-deleting: $ORPHANS"
    for VOL in $ORPHANS; do
      aws ec2 delete-volume --volume-id "$VOL" --region "$REGION"
      info "  Deleted $VOL"
    done
  else
    info "No orphan PVC volumes found — clean"
  fi

  # --- Also catch node root volumes (no K8s tags, but unattached) ---
  info "Checking for unattached node volumes..."
  NODE_VOLS=$(aws ec2 describe-volumes \
    --filters Name=status,Values=available \
    --query 'Volumes[].VolumeId' \
    --region "$REGION" --output text 2>/dev/null || true)

  if [ -n "$NODE_VOLS" ]; then
    warn "Found unattached volumes: $NODE_VOLS"
    read -rp "Delete these volumes? [y/N]: " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
      for VOL in $NODE_VOLS; do
        aws ec2 delete-volume --volume-id "$VOL" --region "$REGION"
        info "  Deleted $VOL"
      done
    fi
  else
    info "No unattached volumes found — clean"
  fi
fi

# --- Terraform destroy ---
if [ "$SKIP_DESTROY" = true ]; then
  info "Skipping terraform destroy (--skip-destroy flag)"
  info "PVC cleanup done. Run 'terraform destroy' manually when ready."
  exit 0
fi

echo ""
warn "About to run: terraform destroy"
warn "This will DELETE: EKS cluster, RDS, VPC, all networking."
read -rp "Type 'yes' to continue: " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  info "Aborted."
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"

info "Running terraform destroy..."
cd "$INFRA_DIR"
terraform destroy -auto-approve

info "Terraform destroy complete."

# --- Final orphan check ---
info "Final check for any remaining EBS volumes..."
FINAL_VOLS=$(aws ec2 describe-volumes \
  --filters Name=status,Values=available \
  --query 'Volumes[].{ID:VolumeId,GB:Size}' \
  --region "$REGION" --output text 2>/dev/null || true)

if [ -n "$FINAL_VOLS" ]; then
  warn "Still found unattached volumes after destroy:"
  echo "$FINAL_VOLS"
  warn "Run: aws ec2 delete-volume --volume-id <id> --region $REGION"
else
  echo ""
  info "All clean. No orphan EBS volumes."
fi

echo ""
info "Done. Infrastructure destroyed. Cost: \$0/hr"
