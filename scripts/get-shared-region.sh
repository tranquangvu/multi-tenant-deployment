#!/usr/bin/env bash
# Print region from shared.region in config/tenant-registry.yaml.
# Usage: ./scripts/get-shared-region.sh
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
import sys
try:
    import yaml
except Exception:
    raise SystemExit("python package 'pyyaml' is required")

registry_path = sys.argv[1]
with open(registry_path, "r", encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}

shared = data.get("shared") or {}
region = str(shared.get("region", "")).strip()
if not region:
    raise SystemExit("missing shared.region")
print(region)
PY

