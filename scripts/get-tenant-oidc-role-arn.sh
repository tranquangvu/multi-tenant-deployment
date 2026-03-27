#!/usr/bin/env bash
# Print AWS_ROLE_ARN for (tenant, environment) from config/tenant-registry.yaml.
# Usage: ./scripts/get-tenant-oidc-role-arn.sh <tenant-id> <environment>
set -euo pipefail

TENANT_ID="${1:?tenant required}"
ENV_NAME="${2:?environment required}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="$SCRIPT_DIR/../config/tenant-registry.yaml"

if [[ ! -f "$REGISTRY" ]]; then
  echo "Registry not found: $REGISTRY" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required (parse tenant-registry.yaml)" >&2
  exit 1
fi

python3 "$SCRIPT_DIR/utils/tenant-registry-query.py" "$REGISTRY" tenant-oidc-role-arn --tenant "$TENANT_ID" --env "$ENV_NAME"
