#!/usr/bin/env bash
# Deploy root stacks (main.yaml) for multiple tenants/environments.
# Target environments per tenant are read from config/tenant-registry.yaml (environments: [...]).
# Uses deploy-tenant.sh for each (tenant, env).
#
# Usage:
#   ./scripts/deploy-tenants.sh                 # all tenants from tenant-registry.yaml
#   ./scripts/deploy-tenants.sh base abc        # explicit tenant list
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOY_TENANT_SCRIPT="$SCRIPT_DIR/deploy-tenant.sh"

if [[ ! -x "$DEPLOY_TENANT_SCRIPT" ]]; then
  echo "deploy-tenant.sh not found or not executable at $DEPLOY_TENANT_SCRIPT" >&2
  exit 1
fi

TENANT_REGISTRY="$INFRA_DIR/config/tenant-registry.yaml"
if [[ ! -f "$TENANT_REGISTRY" ]]; then
  echo "Tenant registry not found: $TENANT_REGISTRY" >&2
  exit 1
fi

if [[ "$#" -gt 0 ]]; then
  TENANTS="$*"
else
  # Default tenants: keys under tenants: in tenant-registry.yaml
  TENANTS="$(awk '
    $1 == "tenants:" { in_tenants=1; next }
    in_tenants && /^[^[:space:]]/ { in_tenants=0 }
    in_tenants && /^[[:space:]]{2}[a-zA-Z0-9_-]+:/ {
      key=$1
      sub(/:.*/, "", key)
      print key
    }
  ' "$TENANT_REGISTRY" | xargs)"
fi

GET_TENANT_ENVS_SCRIPT="$SCRIPT_DIR/get-tenant-envs.sh"
if [[ ! -x "$GET_TENANT_ENVS_SCRIPT" ]]; then
  echo "get-tenant-envs.sh not found or not executable at $GET_TENANT_ENVS_SCRIPT" >&2
  exit 1
fi

echo "Deploying root stacks (main.yaml) for tenants:"
echo "Tenants: $TENANTS"
echo "---"

for tenant in $TENANTS; do
  ENVS="$("$GET_TENANT_ENVS_SCRIPT" "$tenant")"

  for env in $ENVS; do
    echo ">>> Deploying $tenant / $env (root stack)"
    if ! "$DEPLOY_TENANT_SCRIPT" "$tenant" "$env"; then
      echo "Failed: $tenant $env" >&2
      exit 1
    fi
    echo "---"
  done
done

echo "Done. Root stacks deployed for each requested tenant and environment."
