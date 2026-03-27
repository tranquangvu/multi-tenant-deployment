#!/usr/bin/env bash
# Create a tenant onboarding PR:
# - create branch feat/add-new-tenant-<tenant-id>
# - commit tenant scaffold files
# - push branch
# - open Bitbucket PR to main with title/description
#
# Required env vars:
#   NEW_TENANT_ID
#   NEW_TENANT_NAME
#
# Optional env vars (recommended if direct push is not allowed):
#   BITBUCKET_USERNAME
#   BITBUCKET_APP_PASSWORD
set -euo pipefail

TENANT_ID="${NEW_TENANT_ID:-}"
TENANT_NAME="${NEW_TENANT_NAME:-}"
TARGET_BRANCH="${PR_TARGET_BRANCH:-main}"
SOURCE_BRANCH="feat/add-new-tenant-${TENANT_ID}"

if [[ -z "$TENANT_ID" || -z "$TENANT_NAME" ]]; then
  echo "Missing required env vars: NEW_TENANT_ID, NEW_TENANT_NAME" >&2
  exit 1
fi

if [[ ! -f "config/tenant-registry.yaml" ]]; then
  echo "Run this script from repo root (config/tenant-registry.yaml not found)." >&2
  exit 1
fi

if [[ ! -d "tenants/${TENANT_ID}/production" ]]; then
  echo "Expected scaffold directory missing: tenants/${TENANT_ID}/production" >&2
  exit 1
fi

ORIGIN_URL="$(git config --get remote.origin.url || true)"
if [[ -n "$ORIGIN_URL" ]]; then
  if [[ "$ORIGIN_URL" =~ ^https://bitbucket\.org/([^/]+)/([^/.]+)(\.git)?$ ]]; then
    WORKSPACE="${BASH_REMATCH[1]}"
    REPO_SLUG="${BASH_REMATCH[2]}"
  elif [[ "$ORIGIN_URL" =~ ^git@bitbucket\.org:([^/]+)/([^/.]+)(\.git)?$ ]]; then
    WORKSPACE="${BASH_REMATCH[1]}"
    REPO_SLUG="${BASH_REMATCH[2]}"
  fi
fi

if [[ -z "${WORKSPACE:-}" || -z "${REPO_SLUG:-}" ]]; then
  echo "Could not resolve repository workspace/slug from git remote.origin.url." >&2
  echo "Expected Bitbucket origin like https://bitbucket.org/<workspace>/<repo>.git" >&2
  exit 1
fi

git checkout -b "$SOURCE_BRANCH"
git add "config/tenant-registry.yaml" "tenants/${TENANT_ID}/production"

if git diff --cached --quiet; then
  echo "No staged changes found for new tenant PR." >&2
  exit 1
fi

git -c user.name="${GIT_AUTHOR_NAME:-bitbucket-pipelines}" \
    -c user.email="${GIT_AUTHOR_EMAIL:-bitbucket-pipelines@local}" \
    commit -m "feat: scaffold tenant ${TENANT_ID}"

if ! git push -u origin "$SOURCE_BRANCH"; then
  if [[ -n "${BITBUCKET_USERNAME:-}" && -n "${BITBUCKET_APP_PASSWORD:-}" ]]; then
    git push -u "https://${BITBUCKET_USERNAME}:${BITBUCKET_APP_PASSWORD}@bitbucket.org/${WORKSPACE}/${REPO_SLUG}.git" "$SOURCE_BRANCH"
  else
    echo "Push failed and no BITBUCKET_USERNAME/BITBUCKET_APP_PASSWORD provided for fallback auth." >&2
    exit 1
  fi
fi

PR_TITLE="[ONBOARDING] Add new tenant scaffold for ${TENANT_NAME} (${TENANT_ID})"
PR_BODY="$(cat <<EOF
## Summary
- Add new tenant metadata in \`config/tenant-registry.yaml\` for \`${TENANT_ID}\` production
- Scaffold \`tenants/${TENANT_ID}/production\` from base production template
- Set \`TenantId=${TENANT_ID}\` in copied params to align with stack naming/deploy scripts

## Validation
- Reviewed tenant registry fields: account, network, and OIDC role
- Confirmed new tenant directory structure and params file were generated
- Ready for infra review before running deployment pipelines
EOF
)"

PR_PAYLOAD="$(python3 - <<'PY'
import json, os
title = os.environ["PR_TITLE"]
body = os.environ["PR_BODY"]
source_branch = os.environ["SOURCE_BRANCH"]
target_branch = os.environ["TARGET_BRANCH"]
print(json.dumps({
    "title": title,
    "description": body,
    "source": {"branch": {"name": source_branch}},
    "destination": {"branch": {"name": target_branch}},
    "close_source_branch": False
}))
PY
)"

CREATE_PR_URL="https://api.bitbucket.org/2.0/repositories/${WORKSPACE}/${REPO_SLUG}/pullrequests"

if [[ -n "${BITBUCKET_USERNAME:-}" && -n "${BITBUCKET_APP_PASSWORD:-}" ]]; then
  PR_RESPONSE="$(curl -sS -u "${BITBUCKET_USERNAME}:${BITBUCKET_APP_PASSWORD}" \
    -H "Content-Type: application/json" \
    -X POST "$CREATE_PR_URL" \
    -d "$PR_PAYLOAD")"
else
  PR_RESPONSE="$(curl -sS -H "Authorization: Bearer ${BITBUCKET_STEP_OIDC_TOKEN:-}" \
    -H "Content-Type: application/json" \
    -X POST "$CREATE_PR_URL" \
    -d "$PR_PAYLOAD")"
fi

PR_LINK="$(python3 - <<'PY'
import json, sys
raw = sys.stdin.read()
try:
    data = json.loads(raw)
except Exception:
    print("")
    raise SystemExit(0)
print((data.get("links") or {}).get("html", {}).get("href", ""))
PY
<<< "$PR_RESPONSE")"

if [[ -z "$PR_LINK" ]]; then
  echo "Failed to create PR. Bitbucket API response:" >&2
  echo "$PR_RESPONSE" >&2
  exit 1
fi

echo "PR created: $PR_LINK"
