#!/usr/bin/env bash
# Delete root stack (main.yaml) for a (tenant, environment).
# Usage: ./scripts/delete-tenant.sh <tenant-id> [environment]
#   tenant-id: from config/tenant-registry.yaml
#   environment: optional; staging | production. If omitted, deletes all environments for the tenant from tenant-registry.yaml.
#
# Safety:
#   Set CONFIRM_DELETE_TENANT=1 to actually delete (otherwise exits).
#
# Example:
#   CONFIRM_DELETE_TENANT=1 ./scripts/delete-tenant.sh base staging
#   CONFIRM_DELETE_TENANT=1 ./scripts/delete-tenant.sh base              # all envs for base
set -euo pipefail

TENANT_ID="${1:-}"
ENV_NAME="${2:-}"

if [[ -z "$TENANT_ID" ]]; then
  echo "Usage: ./scripts/delete-tenant.sh <tenant-id> [environment]" >&2
  exit 1
fi

if [[ "${CONFIRM_DELETE_TENANT:-0}" != "1" ]]; then
  echo "Refusing to delete stacks without CONFIRM_DELETE_TENANT=1" >&2
  echo "Example: CONFIRM_DELETE_TENANT=1 ./scripts/delete-tenant.sh $TENANT_ID ${ENV_NAME:-<environment>}" >&2
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

# If no environment given, delete all environments for this tenant from tenant-registry.yaml
if [[ -z "$ENV_NAME" ]]; then
  GET_TENANT_ENVS_SCRIPT="$SCRIPT_DIR/get-tenant-envs.sh"
  if [[ ! -x "$GET_TENANT_ENVS_SCRIPT" ]]; then
    echo "get-tenant-envs.sh not found or not executable at $GET_TENANT_ENVS_SCRIPT" >&2
    exit 1
  fi
  ENVS="$("$GET_TENANT_ENVS_SCRIPT" "$TENANT_ID")"
  for env in $ENVS; do
    CONFIRM_DELETE_TENANT=1 "$SCRIPT_DIR/delete-tenant.sh" "$TENANT_ID" "$env" || exit 1
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
echo "Deleting tenant=$TENANT_ID env=$ENV_NAME in region: $REGION"

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

STACK_ENV_SUFFIX="$ENV_NAME"
STACK_NAME="${PREFIX}-${TENANT_ID}-${STACK_ENV_SUFFIX}"

STATUS="$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "DOES_NOT_EXIST")"
if [[ "$STATUS" == "DOES_NOT_EXIST" ]]; then
  echo "Stack does not exist, nothing to delete: $STACK_NAME"
  exit 0
fi

echo "Deleting stack: $STACK_NAME (current status: $STATUS)"
aws cloudformation delete-stack --stack-name "$STACK_NAME"
aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME"
echo "Root stack deleted successfully for ${TENANT_ID}/${ENV_NAME} (${STACK_NAME})."
