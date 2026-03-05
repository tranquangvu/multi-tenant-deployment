#!/usr/bin/env bash
# Deploy all modules for a (tenant, environment).
# Order: network -> security -> secrets -> ecr -> ecs-cluster -> rds -> alb -> ecs-service (per app).
# Usage: ./deploy-tenant-env.sh <tenant-id> <environment> [params-dir]
# Example: ./deploy-tenant-env.sh base stage
set -euo pipefail

TENANT_ID="${1:?Tenant ID required (base|abc|xyz)}"
ENV="${2:?Environment required (stage|prod)}"
PARAMS_DIR="${3:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${STACK_PREFIX:-mt}"

if [[ -z "$PARAMS_DIR" ]]; then
  PARAMS_DIR="$SCRIPT_DIR/../tenants/${TENANT_ID}"
  if [[ "$TENANT_ID" == "base" ]]; then
    BASE_PARAMS="$PARAMS_DIR/${TENANT_ID}-${ENV}-params.json"
  else
    BASE_PARAMS="$PARAMS_DIR/${ENV}-params.json"
  fi
else
  if [[ "$TENANT_ID" == "base" ]]; then
    BASE_PARAMS="$PARAMS_DIR/${TENANT_ID}-${ENV}-params.json"
  else
    BASE_PARAMS="$PARAMS_DIR/${ENV}-params.json"
  fi
fi
if [[ ! -f "$BASE_PARAMS" ]]; then
  echo "Parameters file not found: $BASE_PARAMS" >&2
  exit 1
fi

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

# 3. Secrets per app (app1, app2)
for app in app1 app2; do
  PARAMS_APP="$PARAMS_DIR/${TENANT_ID}-${ENV}-params-${app}.json"
  if [[ ! -f "$PARAMS_APP" ]]; then
    PARAMS_APP="/tmp/${TENANT_ID}-${ENV}-${app}-params.json"
    jq --arg app "$app" '. + [{"ParameterKey": "ApplicationId", "ParameterValue": $app}]' "$BASE_PARAMS" > "$PARAMS_APP"
  fi
  deploy_stack "${PREFIX}-${TENANT_ID}-${ENV}-secrets-${app}" "secrets.yaml" "$PARAMS_APP"
done

# 4. ECR per app
for app in app1 app2; do
  PARAMS_APP="/tmp/${TENANT_ID}-${ENV}-ecr-${app}-params.json"
  jq --arg app "$app" '. + [{"ParameterKey": "ApplicationId", "ParameterValue": $app}]' "$BASE_PARAMS" > "$PARAMS_APP"
  deploy_stack "${PREFIX}-${TENANT_ID}-${ENV}-ecr-${app}" "ecr.yaml" "$PARAMS_APP"
done

# 5. ECS cluster
deploy_stack "${PREFIX}-${TENANT_ID}-${ENV}-ecs-cluster" "ecs-cluster.yaml" "$BASE_PARAMS"

# 6. RDS per app
for app in app1 app2; do
  DB_SECRET_ARN=$(aws cloudformation describe-stacks \
    --stack-name "${PREFIX}-${TENANT_ID}-${ENV}-secrets-${app}" \
    --query "Stacks[0].Outputs[?OutputKey=='DbSecretArn'].OutputValue | [0]" \
    --output text)
  PARAMS_DATA="/tmp/${TENANT_ID}-${ENV}-rds-${app}-params.json"
  jq --arg app "$app" --arg arn "$DB_SECRET_ARN" \
    '. + [
      {"ParameterKey": "ApplicationId", "ParameterValue": $app},
      {"ParameterKey": "DbSecretArn", "ParameterValue": $arn}
    ]' "$BASE_PARAMS" > "$PARAMS_DATA"
  deploy_stack "${PREFIX}-${TENANT_ID}-${ENV}-rds-${app}" "rds.yaml" "$PARAMS_DATA"
done

# 7. ALB
deploy_stack "${PREFIX}-${TENANT_ID}-${ENV}-alb" "alb.yaml" "$BASE_PARAMS"

# 8. ECS service per app (with ECR URI and target group)
for app in app1 app2; do
  ECR_URI=$(aws cloudformation describe-stacks \
    --stack-name "${PREFIX}-${TENANT_ID}-${ENV}-ecr-${app}" \
    --query "Stacks[0].Outputs[?OutputKey=='EcrRepoUri'].OutputValue | [0]" \
    --output text)
  if [[ "$app" == "app1" ]]; then
    TG_KEY="TargetGroupApp1Arn"
  else
    TG_KEY="TargetGroupApp2Arn"
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
    --slurpfile b "$BASE_PARAMS" \
    '($b[0] // []) + [
      {"ParameterKey": "ApplicationId", "ParameterValue": $app},
      {"ParameterKey": "EcrRepoUri", "ParameterValue": $uri},
      {"ParameterKey": "TargetGroupArn", "ParameterValue": $tg}
    ]' > "$PARAMS_ECS"
  deploy_stack "${PREFIX}-${TENANT_ID}-${ENV}-ecs-${app}" "ecs-service.yaml" "$PARAMS_ECS"
done

echo "All stacks for ${TENANT_ID}-${ENV} deployed successfully."
