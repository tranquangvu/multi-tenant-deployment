#!/usr/bin/env bash
# Install CI dependencies used by deployment scripts.
# Usage: ./scripts/install-ci-deps.sh
# Ensures python3 + pyyaml + jq are available.
set -euo pipefail

install_pkg() {
  local pkg="$1"
  if command -v yum >/dev/null 2>&1; then
    yum install -y -q "$pkg"
  elif command -v microdnf >/dev/null 2>&1; then
    microdnf install -y "$pkg"
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache "$pkg"
  else
    return 1
  fi
}

if ! command -v python3 >/dev/null 2>&1; then
  if command -v apk >/dev/null 2>&1; then
    install_pkg python3 || true
    install_pkg py3-pip || true
  else
    install_pkg python3 || true
  fi
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 required for tenant-registry parsing" >&2
  exit 1
fi

if ! python3 -c "import yaml" >/dev/null 2>&1; then
  python3 -m pip install --quiet --no-cache-dir pyyaml
fi

if ! command -v jq >/dev/null 2>&1; then
  install_pkg jq || true
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq required for tenant-registry merge" >&2
  exit 1
fi
