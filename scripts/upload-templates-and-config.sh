#!/usr/bin/env bash
# Upload CloudFormation templates (and repo config) to S3 for TemplateURL-based deployment.
# Usage:
#   [INFRA_S3_BUCKET=my-bucket] [TEMPLATE_S3_PREFIX=templates] [CONFIG_S3_PREFIX=config] ./upload-templates.sh
# Default bucket: mt-infra when INFRA_S3_BUCKET is unset.
set -euo pipefail

BUCKET="${INFRA_S3_BUCKET:-mt-infra}"
TEMPLATE_PREFIX="${TEMPLATE_S3_PREFIX:-templates}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$(cd "$SCRIPT_DIR/../templates" && pwd)"
CONFIG_DIR="$(cd "$SCRIPT_DIR/../config" && pwd)"

# If TEMPLATE_S3_PREFIX ends with `templates`, default config prefix becomes `<base>/config`.
# Handle both `cfn/templates` and bare `templates`.
if [[ "${TEMPLATE_PREFIX}" == */templates ]]; then
  DEFAULT_CONFIG_PREFIX="${TEMPLATE_PREFIX%/templates}/config"
elif [[ "${TEMPLATE_PREFIX}" == "templates" ]]; then
  DEFAULT_CONFIG_PREFIX="config"
else
  DEFAULT_CONFIG_PREFIX="${TEMPLATE_PREFIX%/}/config"
fi
CONFIG_PREFIX="${CONFIG_S3_PREFIX:-$DEFAULT_CONFIG_PREFIX}"

echo "Uploading templates from $TEMPLATES_DIR to s3://$BUCKET/$TEMPLATE_PREFIX/"
aws s3 cp "$TEMPLATES_DIR/" "s3://$BUCKET/$TEMPLATE_PREFIX/" --recursive --exclude "*" --include "*.yaml" --include "*.yml"
echo "Done. Templates are at s3://$BUCKET/$TEMPLATE_PREFIX/"

echo "Uploading config from $CONFIG_DIR to s3://$BUCKET/$CONFIG_PREFIX/"
aws s3 cp "$CONFIG_DIR/" "s3://$BUCKET/$CONFIG_PREFIX/" --recursive --exclude "*" --include "*.yaml" --include "*.yml"
echo "Done. Config is at s3://$BUCKET/$CONFIG_PREFIX/"
