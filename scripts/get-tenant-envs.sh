#!/usr/bin/env bash
# Output environments for a tenant from config/tenant-registry.yaml.
# Usage: ./scripts/get-tenant-envs.sh <tenant-id>
# Output: space-separated environment names (e.g. "staging production").
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

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to parse $TENANT_REGISTRY" >&2
  exit 1
fi

python3 - "$TENANT_REGISTRY" "$TENANT_ID" <<'PY'
import sys
try:
    import yaml
except Exception:
    raise SystemExit("python package 'pyyaml' is required")

registry_path = sys.argv[1]
tenant_id = sys.argv[2]

with open(registry_path, "r", encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}

tenant = (data.get("tenants") or {}).get(tenant_id)
if not tenant:
    raise SystemExit("unknown tenant")
envs = tenant.get("environments")
if not isinstance(envs, dict) or not envs:
    raise SystemExit("no environments")
print(" ".join(envs.keys()))
PY
