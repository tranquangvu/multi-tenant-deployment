#!/usr/bin/env bash
# Upload CloudFormation templates to S3 for TemplateURL-based root stack deployment.
# Usage: TEMPLATES_S3_BUCKET=my-bucket [TEMPLATES_S3_PREFIX=cfn/templates] ./upload-templates-to-s3.sh
set -euo pipefail

BUCKET="${TEMPLATES_S3_BUCKET:?Missing TEMPLATES_S3_BUCKET}"
PREFIX="${TEMPLATES_S3_PREFIX:-cfn/templates}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$(cd "$SCRIPT_DIR/../templates" && pwd)"

echo "Uploading templates from $TEMPLATES_DIR to s3://$BUCKET/$PREFIX/"
aws s3 cp "$TEMPLATES_DIR/" "s3://$BUCKET/$PREFIX/" --recursive --exclude "*" --include "*.yaml"
echo "Done. Templates are at s3://$BUCKET/$PREFIX/"
