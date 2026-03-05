#!/usr/bin/env bash
# Deploy all defined modules to one or more tenants and environments.
# Uses deploy-tenant-env.sh for each (tenant, env) so every tenant gets the full module set.
#
# Usage:
#   ./deploy-all-tenants.sh
#   DEPLOY_TENANTS="base abc" ./deploy-all-tenants.sh
#   DEPLOY_ENVS="stage" ./deploy-all-tenants.sh
#
# Env vars (optional):
#   DEPLOY_TENANTS  Space-separated tenant IDs (default: base abc xyz)
#   DEPLOY_ENVS     Space-separated environments (default: stage prod)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TENANTS="${DEPLOY_TENANTS:-base abc xyz}"
ENVS="${DEPLOY_ENVS:-stage prod}"

echo "Deploying all modules to tenants: $TENANTS"
echo "Environments: $ENVS"
echo "---"

for tenant in $TENANTS; do
  for env in $ENVS; do
    echo ">>> Deploying $tenant / $env (all modules)"
    "$SCRIPT_DIR/deploy-tenant-env.sh" "$tenant" "$env" || {
      echo "Failed: $tenant $env" >&2
      exit 1
    }
    echo "---"
  done
done

echo "Done. All modules deployed for each requested (tenant, environment)."
