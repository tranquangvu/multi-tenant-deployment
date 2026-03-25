#!/usr/bin/env bash
# Print accountId for (tenant, environment) from config/tenant-registry.yaml.
# Usage: ./scripts/get-tenant-account-id.sh <tenant-id> <environment>
set -euo pipefail

TENANT_ID="${1:?tenant required}"
ENV_NAME="${2:?environment required}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="$SCRIPT_DIR/../config/tenant-registry.yaml"

if [[ ! -f "$REGISTRY" ]]; then
  echo "Registry not found: $REGISTRY" >&2
  exit 1
fi

if ! command -v ruby >/dev/null 2>&1; then
  echo "ruby is required (parse tenant-registry.yaml)" >&2
  exit 1
fi

ruby -ryaml -e '
  r = YAML.load_file(ARGV[0])
  t = r["tenants"][ARGV[1]] or abort("unknown tenant")
  e = t["environments"][ARGV[2]] or abort("unknown environment")
  id = e["accountId"] or abort("missing accountId")
  puts id.to_s
' "$REGISTRY" "$TENANT_ID" "$ENV_NAME"
