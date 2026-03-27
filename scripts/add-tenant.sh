#!/usr/bin/env bash
# Add a new tenant scaffold:
# 1) update config/tenant-registry.yaml
# 2) copy tenants/base/production -> tenants/<tenant-id>/production
# 3) set TenantId in copied params.json
#
# Usage:
# ./scripts/add-tenant.sh \
#   --tenant-id newtenant \
#   --tenant-name "New Tenant" \
#   --region ap-southeast-1 \
#   --account-id 123456789012 \
#   --account-name "Account Name" \
#   --network-vpc-name MyVpc \
#   --network-public-subnets PublicA,PublicB \
#   --network-private-subnets PrivateA,PrivateB \
#   --bitbucket-oidc-role-name bitbucket-oidc-role
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/add-tenant.sh --tenant-id <id> --tenant-name <name> --region <region> \
  --account-id <12-digit> --account-name <name> --network-vpc-name <vpc-name> \
  --network-public-subnets <subnetA,subnetB> --network-private-subnets <subnetA,subnetB> \
  --bitbucket-oidc-role-name <role-name>
EOF
}

TENANT_ID=""
TENANT_NAME=""
REGION=""
ACCOUNT_ID=""
ACCOUNT_NAME=""
NETWORK_VPC_NAME=""
PUBLIC_SUBNETS_CSV=""
PRIVATE_SUBNETS_CSV=""
OIDC_ROLE_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tenant-id) TENANT_ID="${2:-}"; shift 2 ;;
    --tenant-name) TENANT_NAME="${2:-}"; shift 2 ;;
    --region) REGION="${2:-}"; shift 2 ;;
    --account-id) ACCOUNT_ID="${2:-}"; shift 2 ;;
    --account-name) ACCOUNT_NAME="${2:-}"; shift 2 ;;
    --network-vpc-name) NETWORK_VPC_NAME="${2:-}"; shift 2 ;;
    --network-public-subnets) PUBLIC_SUBNETS_CSV="${2:-}"; shift 2 ;;
    --network-private-subnets) PRIVATE_SUBNETS_CSV="${2:-}"; shift 2 ;;
    --bitbucket-oidc-role-name) OIDC_ROLE_NAME="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$TENANT_ID" || -z "$TENANT_NAME" || -z "$REGION" || -z "$ACCOUNT_ID" || -z "$ACCOUNT_NAME" || -z "$NETWORK_VPC_NAME" || -z "$PUBLIC_SUBNETS_CSV" || -z "$PRIVATE_SUBNETS_CSV" || -z "$OIDC_ROLE_NAME" ]]; then
  echo "Missing required arguments." >&2
  usage
  exit 1
fi

if [[ ! "$TENANT_ID" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
  echo "Invalid tenant-id '$TENANT_ID' (allowed: lowercase letters, digits, _ and -)." >&2
  exit 1
fi

if [[ ! "$ACCOUNT_ID" =~ ^[0-9]{12}$ ]]; then
  echo "Invalid account-id '$ACCOUNT_ID' (must be 12 digits)." >&2
  exit 1
fi

if [[ "$PUBLIC_SUBNETS_CSV" != *,* ]]; then
  echo "--network-public-subnets must be comma-separated with at least 2 names." >&2
  exit 1
fi

if [[ "$PRIVATE_SUBNETS_CSV" != *,* ]]; then
  echo "--network-private-subnets must be comma-separated with at least 2 names." >&2
  exit 1
fi

IFS=',' read -r PUBLIC_SUBNET_1 PUBLIC_SUBNET_2 _REST_PUBLIC <<< "$PUBLIC_SUBNETS_CSV"
IFS=',' read -r PRIVATE_SUBNET_1 PRIVATE_SUBNET_2 _REST_PRIVATE <<< "$PRIVATE_SUBNETS_CSV"

if [[ -z "${PUBLIC_SUBNET_1// }" || -z "${PUBLIC_SUBNET_2// }" ]]; then
  echo "Need at least 2 public subnet names." >&2
  exit 1
fi

if [[ -z "${PRIVATE_SUBNET_1// }" || -z "${PRIVATE_SUBNET_2// }" ]]; then
  echo "Need at least 2 private subnet names." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY="$INFRA_DIR/config/tenant-registry.yaml"
BASE_PROD_DIR="$INFRA_DIR/tenants/base/production"
NEW_TENANT_DIR="$INFRA_DIR/tenants/$TENANT_ID"
NEW_PROD_DIR="$NEW_TENANT_DIR/production"
SET_TENANT_PARAMS_PY="$SCRIPT_DIR/utils/set-tenant-id-in-params.py"

if [[ ! -f "$REGISTRY" ]]; then
  echo "Registry not found: $REGISTRY" >&2
  exit 1
fi

if [[ ! -d "$BASE_PROD_DIR" ]]; then
  echo "Base production template directory not found: $BASE_PROD_DIR" >&2
  exit 1
fi

if [[ -d "$NEW_TENANT_DIR" ]]; then
  echo "Target tenant directory already exists: $NEW_TENANT_DIR" >&2
  exit 1
fi

if [[ ! -f "$SET_TENANT_PARAMS_PY" ]]; then
  echo "Missing utility script: $SET_TENANT_PARAMS_PY" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi

TENANT_IDS="$(awk '
  $1 == "tenants:" { in_tenants=1; next }
  in_tenants && /^[^[:space:]]/ { in_tenants=0 }
  in_tenants && /^[[:space:]]{2}[a-zA-Z0-9_-]+:/ {
    key=$1
    sub(/:.*/, "", key)
    print key
  }
' "$REGISTRY")"

if printf '%s\n' "$TENANT_IDS" | grep -qx "$TENANT_ID"; then
  echo "Tenant '$TENANT_ID' already exists in registry." >&2
  exit 1
fi

TENANT_BLOCK="$(cat <<EOF
  $TENANT_ID:
    id: $TENANT_ID
    name: $TENANT_NAME
    region: $REGION
    environments:
      production:
        accountId: $ACCOUNT_ID
        accountName: $ACCOUNT_NAME
        networkVpcName: $NETWORK_VPC_NAME
        networkPrivateSubnetNames: [${PRIVATE_SUBNET_1// /}, ${PRIVATE_SUBNET_2// /}]
        networkPublicSubnetNames: [${PUBLIC_SUBNET_1// /}, ${PUBLIC_SUBNET_2// /}]
        bitbucketOidcRoleName: $OIDC_ROLE_NAME

EOF
)"

TMP_REGISTRY="$(mktemp)"
trap 'rm -f "$TMP_REGISTRY"' EXIT

awk -v block="$TENANT_BLOCK" '
  BEGIN { inserted=0 }
  !inserted && /^shared:/ { printf "%s", block; inserted=1 }
  { print }
  END {
    if (!inserted) {
      printf "\n%s", block
    }
  }
' "$REGISTRY" > "$TMP_REGISTRY"

cp "$TMP_REGISTRY" "$REGISTRY"

mkdir -p "$NEW_TENANT_DIR"
cp -R "$BASE_PROD_DIR" "$NEW_PROD_DIR"

NEW_PARAMS="$NEW_PROD_DIR/params.json"
if [[ ! -f "$NEW_PARAMS" ]]; then
  echo "Copied params.json not found: $NEW_PARAMS" >&2
  exit 1
fi
python3 "$SET_TENANT_PARAMS_PY" "$NEW_PARAMS" "$TENANT_ID"

echo "Tenant scaffold created successfully:"
echo "  - Registry updated: config/tenant-registry.yaml"
echo "  - Directory created: tenants/$TENANT_ID/production"
echo "Next steps:"
echo "  1) Review tenant values in config/tenant-registry.yaml"
echo "  2) Review tenants/$TENANT_ID/production/main.yaml and params.json"
echo "  3) Commit changes"
