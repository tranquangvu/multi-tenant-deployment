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

python3 - "$REGISTRY" "$TENANT_ID" "$ENV_NAME" <<'PY'
import re
import sys
try:
    import yaml
except Exception:
    raise SystemExit("python package 'pyyaml' is required")

registry_path, tenant_id, env_name = sys.argv[1:4]
with open(registry_path, "r", encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}

tenant = (data.get("tenants") or {}).get(tenant_id)
if not tenant:
    raise SystemExit("unknown tenant")
env = (tenant.get("environments") or {}).get(env_name)
if not env:
    raise SystemExit("unknown environment")

account_id = str(env.get("accountId", "")).strip()
role_name = str(env.get("bitbucketOidcRoleName", "")).strip()
if not re.fullmatch(r"\d{12}", account_id):
    raise SystemExit("invalid or missing accountId")
if not role_name:
    raise SystemExit("missing bitbucketOidcRoleName")

print(f"arn:aws:iam::{account_id}:role/{role_name}")
PY
