#!/usr/bin/env bash
# Deploy root stack (main.yaml) for a (tenant, environment) using deploy-stack.sh.
# Usage: ./scripts/deploy-tenant.sh <tenant-id> [environment]
#   tenant-id: from config/tenant-registry.yaml
#   environment: optional; staging | production. If omitted, deploys all environments for the tenant from tenant-registry.yaml.
#
# Example:
#   ./scripts/deploy-tenant.sh base              # all envs for base (staging, production)
#   ./scripts/deploy-tenant.sh base staging
#   ./scripts/deploy-tenant.sh abc production
set -euo pipefail

TENANT_ID="${1:-}"
ENV_NAME="${2:-}"

if [[ -z "$TENANT_ID" ]]; then
  echo "Usage: ./scripts/deploy-tenant.sh <tenant-id> [environment]" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PREFIX="${STACK_PREFIX:-mt}"

TENANT_REGISTRY="$INFRA_DIR/config/tenant-registry.yaml"
if [[ ! -f "$TENANT_REGISTRY" ]]; then
  echo "Tenant registry not found: $TENANT_REGISTRY" >&2
  exit 1
fi

# Validate tenant ID against config/tenant-registry.yaml (tenants: section keys)
TENANT_IDS="$(awk '
  $1 == "tenants:" { in_tenants=1; next }
  in_tenants && /^[^[:space:]]/ { in_tenants=0 }
  in_tenants && /^[[:space:]]{2}[a-zA-Z0-9_-]+:/ {
    key=$1
    sub(/:.*/, "", key)
    print key
  }
' "$TENANT_REGISTRY")"

if ! printf '%s\n' "$TENANT_IDS" | grep -qx "$TENANT_ID"; then
  echo "Unsupported tenant-id '$TENANT_ID'. Valid tenants from tenant-registry.yaml are:" >&2
  printf '  - %s\n' $TENANT_IDS >&2
  exit 1
fi

# If no environment given, deploy all environments for this tenant from tenant-registry.yaml
if [[ -z "$ENV_NAME" ]]; then
  GET_TENANT_ENVS_SCRIPT="$SCRIPT_DIR/get-tenant-envs.sh"
  if [[ ! -x "$GET_TENANT_ENVS_SCRIPT" ]]; then
    echo "get-tenant-envs.sh not found or not executable at $GET_TENANT_ENVS_SCRIPT" >&2
    exit 1
  fi
  ENVS="$("$GET_TENANT_ENVS_SCRIPT" "$TENANT_ID")"
  for env in $ENVS; do
    "$SCRIPT_DIR/deploy-tenant.sh" "$TENANT_ID" "$env" || exit 1
  done
  exit 0
fi

if [[ "$ENV_NAME" != "staging" && "$ENV_NAME" != "production" ]]; then
  echo "Environment must be 'staging' or 'production'" >&2
  exit 1
fi

if [[ "$TENANT_ID" != "base" && "$ENV_NAME" == "staging" ]]; then
  echo "Only base tenant supports staging; use 'production' for $TENANT_ID" >&2
  exit 1
fi

# Resolve region from existing helper script (config/tenant-registry.yaml)
GET_REGION_SCRIPT="$SCRIPT_DIR/get-tenant-region.sh"
if [[ ! -x "$GET_REGION_SCRIPT" ]]; then
  echo "get-tenant-region.sh is not executable or not found at $GET_REGION_SCRIPT" >&2
  exit 1
fi

REGION="$("$GET_REGION_SCRIPT" "$TENANT_ID")"
if [[ -z "$REGION" ]]; then
  echo "Failed to resolve region for tenant $TENANT_ID" >&2
  exit 1
fi

export AWS_DEFAULT_REGION="$REGION"
export AWS_REGION="$REGION"
echo "Deploying tenant=$TENANT_ID env=$ENV_NAME to region: $REGION"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to merge network SSM paths from tenant-registry.yaml" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to merge CloudFormation parameters" >&2
  exit 1
fi

GET_ACCOUNT_SCRIPT="$SCRIPT_DIR/get-tenant-account-id.sh"
if [[ ! -x "$GET_ACCOUNT_SCRIPT" ]]; then
  chmod +x "$GET_ACCOUNT_SCRIPT" 2>/dev/null || true
fi
EXPECTED_ACCOUNT="$("$GET_ACCOUNT_SCRIPT" "$TENANT_ID" "$ENV_NAME")"
CURRENT_ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
if [[ "${SKIP_TENANT_ACCOUNT_CHECK:-0}" != "1" && "$EXPECTED_ACCOUNT" != "$CURRENT_ACCOUNT" ]]; then
  echo "tenant-registry accountId ($EXPECTED_ACCOUNT) != current AWS account ($CURRENT_ACCOUNT)." >&2
  echo "Assume the target account role or set SKIP_TENANT_ACCOUNT_CHECK=1 to skip this check." >&2
  exit 1
fi

# Map CLI env to directory and stack suffix
ENV_DIR="staging"
STACK_ENV_SUFFIX="staging"
if [[ "$ENV_NAME" == "production" ]]; then
  ENV_DIR="production"
  STACK_ENV_SUFFIX="production"
fi

STACK_NAME="${PREFIX}-${TENANT_ID}-${STACK_ENV_SUFFIX}"
TEMPLATE_REL="tenants/${TENANT_ID}/${ENV_DIR}/main.yaml"
PARAMS_REL="tenants/${TENANT_ID}/${ENV_DIR}/params.json"

TEMPLATE_PATH="$INFRA_DIR/$TEMPLATE_REL"
PARAMS_PATH="$INFRA_DIR/$PARAMS_REL"

if [[ ! -f "$TEMPLATE_PATH" ]]; then
  echo "Template not found: $TEMPLATE_PATH" >&2
  exit 1
fi
if [[ ! -f "$PARAMS_PATH" ]]; then
  echo "Params not found:   $PARAMS_PATH" >&2
  exit 1
fi

DEPLOY_STACK="$SCRIPT_DIR/deploy-stack.sh"
if [[ ! -x "$DEPLOY_STACK" ]]; then
  echo "deploy-stack.sh not found or not executable at $DEPLOY_STACK" >&2
  exit 1
fi

NETWORK_PY="$SCRIPT_DIR/tenant-network-ssm-params.py"
if [[ ! -f "$NETWORK_PY" ]]; then
  echo "Missing $NETWORK_PY" >&2
  exit 1
fi

NETWORK_JSON="$(python3 "$NETWORK_PY" "$TENANT_REGISTRY" "$TENANT_ID" "$ENV_NAME")"
MERGED_PARAMS="$(mktemp)"
trap 'rm -f "$MERGED_PARAMS"' EXIT
jq --argjson net "$NETWORK_JSON" '. + $net' "$PARAMS_PATH" > "$MERGED_PARAMS"

echo "Running: $DEPLOY_STACK $STACK_NAME $TEMPLATE_REL <merged-params>"
"$DEPLOY_STACK" "$STACK_NAME" "$TEMPLATE_REL" "$MERGED_PARAMS"

echo "Root stack deployed successfully for ${TENANT_ID}/${ENV_NAME} (${STACK_NAME})."
