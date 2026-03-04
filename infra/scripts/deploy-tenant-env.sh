#!/usr/bin/env bash
# Deploy all stacks for a (tenant, environment). Order: network -> security -> secrets (app1, app2) -> compute-cluster -> data-app (app1, app2) -> compute-app (app1, app2).
# Usage: ./deploy-tenant-env.sh <tenant-id> <environment> [params-dir]
# Example: ./deploy-tenant-env.sh base stage
set -euo pipefail

TENANT_ID="${1:?Tenant ID required (base|abc|xyz)}"
ENV="${2:?Environment required (stage|prod)}"
PARAMS_DIR="${3:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
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

# 2. Security (optional Bitbucket params via env or same file; add to base params if needed)
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

# 4. Compute cluster (shared by app1, app2)
deploy_stack "${PREFIX}-${TENANT_ID}-${ENV}-compute-cluster" "compute-cluster.yaml" "$BASE_PARAMS"

# 5. Data (RDS) per app - need DbSecretArn from secrets stack
for app in app1 app2; do
  DB_SECRET_ARN=$(aws cloudformation describe-stacks \
    --stack-name "${PREFIX}-${TENANT_ID}-${ENV}-secrets-${app}" \
    --query "Stacks[0].Outputs[?OutputKey=='DbSecretArn'].OutputValue | [0]" \
    --output text)
  PARAMS_DATA="/tmp/${TENANT_ID}-${ENV}-data-${app}-params.json"
  jq --arg app "$app" --arg arn "$DB_SECRET_ARN" \
    '. + [
      {"ParameterKey": "ApplicationId", "ParameterValue": $app},
      {"ParameterKey": "DbSecretArn", "ParameterValue": $arn}
    ]' "$BASE_PARAMS" > "$PARAMS_DATA"
  deploy_stack "${PREFIX}-${TENANT_ID}-${ENV}-data-${app}" "data-app.yaml" "$PARAMS_DATA"
done

# 6. Compute (ECS service) per app
for app in app1 app2; do
  PARAMS_APP="$PARAMS_DIR/${TENANT_ID}-${ENV}-params-${app}.json"
  if [[ ! -f "$PARAMS_APP" ]]; then
    PARAMS_APP="/tmp/${TENANT_ID}-${ENV}-compute-${app}-params.json"
    jq --arg app "$app" '. + [{"ParameterKey": "ApplicationId", "ParameterValue": $app}]' "$BASE_PARAMS" > "$PARAMS_APP"
  fi
  deploy_stack "${PREFIX}-${TENANT_ID}-${ENV}-compute-${app}" "compute-app.yaml" "$PARAMS_APP"
done

echo "All stacks for ${TENANT_ID}-${ENV} deployed successfully."
