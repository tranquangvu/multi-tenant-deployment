#!/usr/bin/env bash
# Output the AWS region for a tenant from config/tenant-registry.yaml.
# Usage: ./get-tenant-region.sh <tenant-id>
# Exit 0 with region on stdout; exit 1 if tenant not found or no region (default: us-east-1 on stdout).
set -euo pipefail

TENANT_ID="${1:?Tenant ID required}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="$SCRIPT_DIR/../config/tenant-registry.yaml"

if [[ ! -f "$REGISTRY" ]]; then
  echo "us-east-1"
  exit 0
fi

# Extract region from the tenant block (YAML: "  tenant_id:" ... "region: value")
REGION=$(awk -v tenant="$TENANT_ID" '
  $0 ~ "^  " tenant ":" { block=1; next }
  block && $0 ~ /^  [a-z]+:/ { block=0 }
  block && $0 ~ /region:/ { sub(/^.*region:[[:space:]]*/, ""); sub(/["\r].*$/, ""); gsub(/^"|"$/, ""); print; exit }
' "$REGISTRY")

echo "${REGION:-us-east-1}"
