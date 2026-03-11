#!/usr/bin/env bash
# Output environments for a tenant from config/tenant-registry.yaml (environments: [staging, production] or [production]).
# Usage: ./scripts/get-tenant-envs.sh <tenant-id>
# Output: space-separated list of environment names (e.g. "staging production" or "production").
# Exit: 0 if found, 1 if tenant missing or registry/envs not found.
set -euo pipefail

TENANT_ID="${1:-}"
if [[ -z "$TENANT_ID" ]]; then
  echo "Usage: ./scripts/get-tenant-envs.sh <tenant-id>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TENANT_REGISTRY="$INFRA_DIR/config/tenant-registry.yaml"

if [[ ! -f "$TENANT_REGISTRY" ]]; then
  echo "Tenant registry not found: $TENANT_REGISTRY" >&2
  exit 1
fi

ENVS="$(awk -v tenant="$TENANT_ID" '
  $1 == tenant ":" { in_tenant=1; next }
  in_tenant && /^[[:space:]]*environments:/ {
    sub(/.*\[/, ""); sub(/\].*/, ""); gsub(/,/, " "); print
    in_tenant=0
  }
  in_tenant && /^[^[:space:]]/ { in_tenant=0 }
' "$TENANT_REGISTRY" | xargs)"

if [[ -z "$ENVS" ]]; then
  echo "No environments found for tenant '$TENANT_ID' in $TENANT_REGISTRY" >&2
  exit 1
fi

echo "$ENVS"
