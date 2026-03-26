#!/usr/bin/env bash
# Print AWS_ROLE_ARN from shared.* in config/tenant-registry.yaml.
# Usage: ./scripts/get-shared-oidc-role-arn.sh
set -euo pipefail

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

python3 - "$REGISTRY" <<'PY'
import re
import sys
try:
    import yaml
except Exception:
    raise SystemExit("python package 'pyyaml' is required")

registry_path = sys.argv[1]
with open(registry_path, "r", encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}

shared = data.get("shared") or {}
account_id = str(shared.get("accountId", "")).strip()
role_name = str(shared.get("bitbucketOidcRoleName", "")).strip()

if not re.fullmatch(r"\d{12}", account_id):
    raise SystemExit("invalid or missing shared.accountId")
if not role_name:
    raise SystemExit("missing shared.bitbucketOidcRoleName")

print(f"arn:aws:iam::{account_id}:role/{role_name}")
PY

