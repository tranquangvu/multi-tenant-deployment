#!/usr/bin/env bash
# Deploy a single CloudFormation stack.
# Usage: ./deploy-stack.sh <stack-name> <template-file-or-path> [params-file]
#   Template: filename (e.g. network.yaml) for templates/, or path (e.g. tenants/base/stage/main.yaml) for root stack.
#   Params: JSON array; ${TEMPLATES_S3_BUCKET} in values is replaced from env.
set -euo pipefail

STACK_NAME="${1:?Stack name required}"
TEMPLATE_FILE="${2:?Template file required}"
PARAMS_FILE="${3:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES_DIR="$INFRA_DIR/templates"

# Resolve template path: path (contains /) -> under project root; else -> templates/
if [[ "$TEMPLATE_FILE" == */* ]]; then
  TEMPLATE_PATH="$INFRA_DIR/$TEMPLATE_FILE"
else
  TEMPLATE_PATH="$TEMPLATES_DIR/$(basename "$TEMPLATE_FILE")"
fi

if [[ ! -f "$TEMPLATE_PATH" ]]; then
  echo "Template not found: $TEMPLATE_PATH" >&2
  exit 1
fi

# Root stack (main.yaml) needs CAPABILITY_AUTO_EXPAND for nested stacks
CAPS="CAPABILITY_NAMED_IAM"
if [[ "$TEMPLATE_FILE" == *main.yaml ]]; then
  CAPS="CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND"
fi

EXTRA_ARGS=()
if [[ -n "$PARAMS_FILE" ]]; then
  # Resolve params path (relative to project root if path contains /)
  if [[ "$PARAMS_FILE" == */* ]]; then
    PARAMS_PATH="$INFRA_DIR/$PARAMS_FILE"
  else
    PARAMS_PATH="$PARAMS_FILE"
  fi
  if [[ ! -f "$PARAMS_PATH" ]]; then
    echo "Params file not found: $PARAMS_PATH" >&2
    exit 1
  fi
  # Substitute ${TEMPLATES_S3_BUCKET} from environment then build overrides
  PARAMS_CONTENT=$(cat "$PARAMS_PATH")
  if [[ -n "${TEMPLATES_S3_BUCKET:-}" ]]; then
    PARAMS_CONTENT=$(echo "$PARAMS_CONTENT" | sed "s|\${TEMPLATES_S3_BUCKET}|$TEMPLATES_S3_BUCKET|g")
  fi
  OVERRIDES=$(echo "$PARAMS_CONTENT" | jq -r '.[] | "\(.ParameterKey)=\(.ParameterValue)"' | tr '\n' ' ')
  [[ -n "$OVERRIDES" ]] && EXTRA_ARGS=(--parameter-overrides $OVERRIDES)
fi

aws cloudformation deploy \
  --stack-name "$STACK_NAME" \
  --template-file "$TEMPLATE_PATH" \
  --capabilities $CAPS \
  --no-fail-on-empty-changeset \
  "${EXTRA_ARGS[@]}"

echo "Stack $STACK_NAME deployed successfully."
