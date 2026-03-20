#!/usr/bin/env bash
# Deploy shared stacks (ECR repos per app via nested shared/main.yaml). Run once per account/region before deploying tenants.
# Usage: ./deploy-shared.sh [params-file]
#   Params file defaults to shared/params.json (must include StackPrefix, TemplateS3Bucket, TemplateS3Prefix).
#   Uses AWS_DEFAULT_REGION; set it or run in an environment that has it.
# Example: AWS_DEFAULT_REGION=ap-southeast-1 ./deploy-shared.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PARAMS_FILE="${1:-$INFRA_DIR/shared/params.json}"
PREFIX="${STACK_PREFIX:-mt}"

if [[ ! -f "$PARAMS_FILE" ]]; then
  echo "Params file not found: $PARAMS_FILE" >&2
  exit 1
fi

if [[ -z "${AWS_DEFAULT_REGION:-}" ]]; then
  echo "AWS_DEFAULT_REGION is not set. Set it or export it before running this script." >&2
  exit 1
fi
export AWS_REGION="${AWS_DEFAULT_REGION}"
echo "Deploying shared stacks to region: $AWS_DEFAULT_REGION"

echo "Deploying shared main stack (nested ECR repos)..."
"$SCRIPT_DIR/deploy-stack.sh" "${PREFIX}-shared" "shared/main.yaml" "shared/params.json"

echo "Shared stacks deployed successfully. Tenant stacks can now use ECR via ImportValue."
