#!/usr/bin/env bash
# Deploy a single CloudFormation stack.
# Usage: ./deploy-stack.sh <stack-name> <template-file> [params-file]
set -euo pipefail

STACK_NAME="${1:?Stack name required}"
TEMPLATE_FILE="${2:?Template file required}"
PARAMS_FILE="${3:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$(cd "$SCRIPT_DIR/../templates" && pwd)"
TEMPLATE_PATH="$TEMPLATES_DIR/$(basename "$TEMPLATE_FILE")"

if [[ ! -f "$TEMPLATE_PATH" ]]; then
  echo "Template not found: $TEMPLATE_PATH" >&2
  exit 1
fi

EXTRA_ARGS=()
if [[ -n "$PARAMS_FILE" && -f "$PARAMS_FILE" ]]; then
  # Build Key=Value list from JSON array of {ParameterKey, ParameterValue}
  OVERRIDES=$(jq -r '.[] | "\(.ParameterKey)=\(.ParameterValue)"' "$PARAMS_FILE" | tr '\n' ' ')
  [[ -n "$OVERRIDES" ]] && EXTRA_ARGS=(--parameter-overrides $OVERRIDES)
fi

aws cloudformation deploy \
  --stack-name "$STACK_NAME" \
  --template-file "$TEMPLATE_PATH" \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset \
  "${EXTRA_ARGS[@]}"

echo "Stack $STACK_NAME deployed successfully."
