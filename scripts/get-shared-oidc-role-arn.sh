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

python3 "$SCRIPT_DIR/utils/tenant-registry-query.py" "$REGISTRY" shared-oidc-role-arn

