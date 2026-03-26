#!/usr/bin/env bash
# Upload CloudFormation templates (and repo config) to S3 for TemplateURL-based deployment.
# Usage:
#   [INFRA_S3_BUCKET=my-bucket] [TEMPLATE_S3_PREFIX=templates] [CONFIG_S3_PREFIX=config] ./upload-templates.sh
# Default bucket: mt-infra when INFRA_S3_BUCKET is unset.
set -euo pipefail

BUCKET="${INFRA_S3_BUCKET:-mt-infra}"
TEMPLATE_PREFIX="${TEMPLATE_S3_PREFIX:-templates}"
CONFIG_PREFIX="${CONFIG_S3_PREFIX:-config}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$(cd "$SCRIPT_DIR/../templates" && pwd)"
CONFIG_DIR="$(cd "$SCRIPT_DIR/../config" && pwd)"

if ! aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || true)}}"
  REGION="${REGION:-us-east-1}"
  echo "Bucket s3://$BUCKET not found. Creating in region: $REGION"
  if [[ "$REGION" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$BUCKET"
  else
    aws s3api create-bucket \
      --bucket "$BUCKET" \
      --create-bucket-configuration "LocationConstraint=$REGION"
  fi
  echo "Created bucket s3://$BUCKET"
fi

echo "Uploading templates from $TEMPLATES_DIR to s3://$BUCKET/$TEMPLATE_PREFIX/"
aws s3 cp "$TEMPLATES_DIR/" "s3://$BUCKET/$TEMPLATE_PREFIX/" --recursive --exclude "*" --include "*.yaml" --include "*.yml"
echo "Done. Templates are at s3://$BUCKET/$TEMPLATE_PREFIX/"

echo "Uploading config from $CONFIG_DIR to s3://$BUCKET/$CONFIG_PREFIX/"
aws s3 cp "$CONFIG_DIR/" "s3://$BUCKET/$CONFIG_PREFIX/" --recursive --exclude "*" --include "*.yaml" --include "*.yml"
echo "Done. Config is at s3://$BUCKET/$CONFIG_PREFIX/"
