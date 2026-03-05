#!/usr/bin/env bash
# Deploy all defined modules to one or more tenants.
# Base has stage + prod; all other tenants have prod only.
# Uses deploy-tenant-env.sh for each (tenant, env) so every tenant gets the full module set.
#
# Usage:
#   ./deploy-all-tenants.sh
#   DEPLOY_TENANTS="base abc" ./deploy-all-tenants.sh
#
# Env vars (optional):
#   DEPLOY_TENANTS  Space-separated tenant IDs (default: base abc xyz)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TENANTS="${DEPLOY_TENANTS:-base abc xyz}"

echo "Deploying all modules (base: stage+prod; others: prod only)"
echo "Tenants: $TENANTS"
echo "---"

for tenant in $TENANTS; do
  if [[ "$tenant" == "base" ]]; then
    ENVS="stage prod"
  else
    ENVS="prod"
  fi
  for env in $ENVS; do
    echo ">>> Deploying $tenant / $env (all modules)"
    "$SCRIPT_DIR/deploy-tenant-env.sh" "$tenant" "$env" || {
      echo "Failed: $tenant $env" >&2
      exit 1
    }
    echo "---"
  done
done

echo "Done. All modules deployed for each requested tenant and environment."
