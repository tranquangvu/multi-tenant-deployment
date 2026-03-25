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

if ! command -v ruby >/dev/null 2>&1; then
  echo "ruby is required to parse $TENANT_REGISTRY" >&2
  exit 1
fi

ruby -ryaml -e '
  r = YAML.load_file(ARGV[0])
  t = r["tenants"][ARGV[1]] or abort("unknown tenant")
  envs = t["environments"] or abort("no environments")
  abort("environments must be a map") unless envs.is_a?(Hash)
  puts envs.keys.join(" ")
' "$TENANT_REGISTRY" "$TENANT_ID"
