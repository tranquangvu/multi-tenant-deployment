#!/usr/bin/env bash
# Deploy all modules for a (tenant, environment).
# Order: network -> security -> secrets -> ecr -> ecs-cluster -> rds -> alb -> ecs-service (per app).
# Usage: ./deploy-tenant-env.sh <tenant-id> <environment> [params-dir]
# Base: stage or prod. Other tenants (abc, xyz): prod only.
# Example: ./deploy-tenant-env.sh base stage  |  ./deploy-tenant-env.sh abc prod
set -euo pipefail

TENANT_ID="${1:?Tenant ID required (base|abc|xyz)}"
ENV="${2:?Environment required (stage|prod)}"
PARAMS_DIR="${3:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${STACK_PREFIX:-mt}"

# Use region from tenant registry (config/tenant-registry.yaml) so all AWS/CloudFormation calls target that region
export AWS_DEFAULT_REGION="$("$SCRIPT_DIR/get-tenant-region.sh" "$TENANT_ID")"
export AWS_REGION="$AWS_DEFAULT_REGION"
echo "Deploying to region: $AWS_DEFAULT_REGION"

# Only base has stage; all other tenants (abc, xyz) have prod only
if [[ "$TENANT_ID" != "base" && "$ENV" == "stage" ]]; then
  echo "Only base tenant has a stage environment. Use prod for ${TENANT_ID}." >&2
  exit 1
fi

# Legacy deploy: use tenants/<id>/<stage|production>/params.json; only TenantId, Environment, StackPrefix passed to module templates
PARAMS_DIR="${PARAMS_DIR:-$SCRIPT_DIR/../tenants/${TENANT_ID}}"
ENV_DIR="stage"
[[ "$ENV" == "prod" ]] && ENV_DIR="production"
if [[ ! -f "$PARAMS_DIR/${ENV_DIR}/params.json" ]]; then
  echo "Parameters file not found: $PARAMS_DIR/${ENV_DIR}/params.json" >&2
  exit 1
fi
BASE_PARAMS="/tmp/${TENANT_ID}-${ENV}-legacy-params.json"
jq '[.[] | select(.ParameterKey | IN("TenantId", "Environment", "StackPrefix"))]' "$PARAMS_DIR/${ENV_DIR}/params.json" > "$BASE_PARAMS"

deploy_stack() {
  local name="$1"
  local template="$2"
  local params="$3"
  echo "Deploying stack: $name"
  "$SCRIPT_DIR/deploy-stack.sh" "$name" "$template" "$params"
}

# 1. Network
deploy_stack "${PREFIX}-${TENANT_ID}-${ENV}-network" "network.yaml" "$BASE_PARAMS"

# 2. Security
deploy_stack "${PREFIX}-${TENANT_ID}-${ENV}-security" "security.yaml" "$BASE_PARAMS"

# 3. Secrets per app (foo, baz)
for app in foo baz; do
  PARAMS_APP="$PARAMS_DIR/${TENANT_ID}-${ENV}-params-${app}.json"
  if [[ ! -f "$PARAMS_APP" ]]; then
    PARAMS_APP="/tmp/${TENANT_ID}-${ENV}-${app}-params.json"
    jq --arg app "$app" '. + [{"ParameterKey": "AppId", "ParameterValue": $app}]' "$BASE_PARAMS" > "$PARAMS_APP"
  fi
  deploy_stack "${PREFIX}-${TENANT_ID}-${ENV}-secrets-${app}" "secrets.yaml" "$PARAMS_APP"
done

# 4. ECR per app
for app in foo baz; do
  PARAMS_APP="/tmp/${TENANT_ID}-${ENV}-ecr-${app}-params.json"
  jq --arg app "$app" '. + [{"ParameterKey": "AppId", "ParameterValue": $app}]' "$BASE_PARAMS" > "$PARAMS_APP"
  deploy_stack "${PREFIX}-${TENANT_ID}-${ENV}-ecr-${app}" "ecr.yaml" "$PARAMS_APP"
done

# 5. ECS cluster
deploy_stack "${PREFIX}-${TENANT_ID}-${ENV}-ecs-cluster" "ecs-cluster.yaml" "$BASE_PARAMS"

# 6. RDS per app
for app in foo baz; do
  APP_SECRET_ARN=$(aws cloudformation describe-stacks \
    --stack-name "${PREFIX}-${TENANT_ID}-${ENV}-secrets-${app}" \
    --query "Stacks[0].Outputs[?OutputKey=='AppSecretArn'].OutputValue | [0]" \
    --output text)
  PARAMS_DATA="/tmp/${TENANT_ID}-${ENV}-rds-${app}-params.json"
  jq --arg app "$app" --arg arn "$APP_SECRET_ARN" \
    '. + [
      {"ParameterKey": "AppId", "ParameterValue": $app},
      {"ParameterKey": "AppSecretArn", "ParameterValue": $arn}
    ]' "$BASE_PARAMS" > "$PARAMS_DATA"
  deploy_stack "${PREFIX}-${TENANT_ID}-${ENV}-rds-${app}" "rds.yaml" "$PARAMS_DATA"
done

# 7. ALB
deploy_stack "${PREFIX}-${TENANT_ID}-${ENV}-alb" "alb.yaml" "$BASE_PARAMS"

# 8. ECS service per app (with ECR URI, target group, app secret for DATABASE_URL and other env vars)
for app in foo baz; do
  ECR_URI=$(aws cloudformation describe-stacks \
    --stack-name "${PREFIX}-${TENANT_ID}-${ENV}-ecr-${app}" \
    --query "Stacks[0].Outputs[?OutputKey=='EcrRepoUri'].OutputValue | [0]" \
    --output text)
  APP_SECRET_ARN=$(aws cloudformation describe-stacks \
    --stack-name "${PREFIX}-${TENANT_ID}-${ENV}-secrets-${app}" \
    --query "Stacks[0].Outputs[?OutputKey=='AppSecretArn'].OutputValue | [0]" \
    --output text)
  if [[ "$app" == "foo" ]]; then
    TG_KEY="TargetGroupFooArn"
  else
    TG_KEY="TargetGroupBazArn"
  fi
  TG_ARN=$(aws cloudformation describe-stacks \
    --stack-name "${PREFIX}-${TENANT_ID}-${ENV}-alb" \
    --query "Stacks[0].Outputs[?OutputKey=='${TG_KEY}'].OutputValue | [0]" \
    --output text)
  PARAMS_ECS="/tmp/${TENANT_ID}-${ENV}-ecs-${app}-params.json"
  jq -n \
    --arg app "$app" \
    --arg uri "$ECR_URI" \
    --arg tg "$TG_ARN" \
    --arg appSecret "$APP_SECRET_ARN" \
    --slurpfile b "$BASE_PARAMS" \
    '($b[0] // []) + [
      {"ParameterKey": "AppId", "ParameterValue": $app},
      {"ParameterKey": "EcrRepoUri", "ParameterValue": $uri},
      {"ParameterKey": "TargetGroupArn", "ParameterValue": $tg},
      {"ParameterKey": "AppSecretArn", "ParameterValue": $appSecret}
    ]' > "$PARAMS_ECS"
  deploy_stack "${PREFIX}-${TENANT_ID}-${ENV}-ecs-${app}" "ecs-service.yaml" "$PARAMS_ECS"
done

echo "All stacks for ${TENANT_ID}-${ENV} deployed successfully."
