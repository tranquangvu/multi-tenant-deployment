#!/usr/bin/env bash
# Update ECS task definition with new image tag and force new deployment.
# Run from multi-tenant-deployment repo (e.g. from Bitbucket pipeline or after trigger from app repo).
#
# Usage:
#   DEPLOY_ENV=staging TARGET_TENANTS=base IMAGE_TAG=sha-abc1234 APP_ID=baz ./scripts/deploy-ecs-svc.sh
#   DEPLOY_ENV=production TARGET_TENANTS=abc,xyz IMAGE_TAG=v1.0.0 ./scripts/deploy-ecs-svc.sh
#
# Env:
#   DEPLOY_ENV (required): staging | production
#   TARGET_TENANTS (required): comma-separated (e.g. base,abc,xyz) or "all" (requires TENANTS to be set)
#   IMAGE_TAG (required): image tag to deploy (e.g. sha-abc1234, v1.0.0)
#   APP_ID (required): app to update (e.g. foo, baz)
#   STACK_PREFIX (default: mt)
#   AWS_DEFAULT_REGION
set -euo pipefail

DEPLOY_ENV="${DEPLOY_ENV:-}"
TARGET_TENANTS="${TARGET_TENANTS:-}"
IMAGE_TAG="${IMAGE_TAG:-}"
APP_ID="${APP_ID:-}"
PREFIX="${STACK_PREFIX:-mt}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-southeast-1}"
export AWS_REGION="${AWS_DEFAULT_REGION}"

if [[ -z "$DEPLOY_ENV" || -z "$TARGET_TENANTS" || -z "$IMAGE_TAG" || -z "$APP_ID" ]]; then
  echo "Usage: DEPLOY_ENV=staging|production TARGET_TENANTS=... IMAGE_TAG=... APP_ID=... ./scripts/deploy-ecs-service.sh" >&2
  echo "  DEPLOY_ENV: staging or production" >&2
  echo "  TARGET_TENANTS: comma-separated tenant ids, or 'all' (then set TENANTS=abc,xyz)" >&2
  echo "  APP_ID: app to update (e.g. foo, baz)" >&2
  exit 1
fi

if [[ "$TARGET_TENANTS" == "all" ]]; then
  if [[ -z "${TENANTS:-}" ]]; then
    echo "TARGET_TENANTS=all requires TENANTS to be set (e.g. TENANTS=abc,xyz)" >&2
    exit 1
  fi
  TARGET_TENANTS="$TENANTS"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GET_REGION="${SCRIPT_DIR}/get-tenant-region.sh"

update_one() {
  local tenant="$1"
  local region
  if [[ -x "$GET_REGION" ]]; then
    region="$("$GET_REGION" "$tenant")"
  else
    region="${AWS_DEFAULT_REGION:-ap-southeast-1}"
  fi
  export AWS_DEFAULT_REGION="$region"
  export AWS_REGION="$region"

  local cluster="${PREFIX}-${tenant}-${DEPLOY_ENV}-cluster"
  local service="${PREFIX}-${tenant}-${DEPLOY_ENV}-${APP_ID}-svc"

  echo "Updating ${APP_ID}@${IMAGE_TAG} → tenant ${tenant} ${DEPLOY_ENV} (region $region)..."

  local current_td
  current_td="$(aws ecs describe-services --cluster "$cluster" --services "$service" --query 'services[0].taskDefinition' --output text)"
  if [[ -z "$current_td" || "$current_td" == "None" ]]; then
    echo "Service or task definition not found: $cluster / $service" >&2
    return 1
  fi

  local new_image_base
  new_image_base="$(aws ecs describe-task-definition --task-definition "$current_td" --query 'taskDefinition.containerDefinitions[0].image' --output text | sed 's/:.*//')"
  if [[ -z "$new_image_base" ]]; then
    echo "Could not get current image from task definition $current_td" >&2
    return 1
  fi
  local new_image="${new_image_base}:${IMAGE_TAG}"

  # Build new task def JSON (strip read-only fields, set new image). Use Python for portability (no jq in amazon/aws-cli image).
  local td_json
  td_json="$(aws ecs describe-task-definition --task-definition "$current_td" --query 'taskDefinition' --output json | python3 -c "
import json, sys
d = json.load(sys.stdin)
for k in ('taskDefinitionArn', 'revision', 'status', 'requiresAttributes', 'compatibilities', 'registeredAt', 'registeredBy'):
    d.pop(k, None)
if d.get('containerDefinitions'):
    d['containerDefinitions'][0]['image'] = sys.argv[1]
print(json.dumps(d))
" "$new_image")"

  local new_td_arn
  new_td_arn="$(echo "$td_json" | aws ecs register-task-definition --cli-input-json file:///dev/stdin --query 'taskDefinition.taskDefinitionArn' --output text)"
  if [[ -z "$new_td_arn" ]]; then
    echo "Failed to register new task definition" >&2
    return 1
  fi

  aws ecs update-service --cluster "$cluster" --service "$service" --task-definition "$new_td_arn" --force-new-deployment --query 'service.serviceName' --output text >/dev/null
  echo "  → Service updated to $new_td_arn; waiting for stability (best-effort)..."
  aws ecs wait services-stable --cluster "$cluster" --services "$service" || true
  echo "  → Done: $tenant ${DEPLOY_ENV}"
}

IFS=',' read -ra TARR <<< "$TARGET_TENANTS"
for t in "${TARR[@]}"; do
  t="$(echo "$t" | tr -d ' ')"
  [[ -z "$t" ]] && continue
  update_one "$t" || { echo "Failed for tenant $t" >&2; exit 1; }
done

echo "Deployment complete: ${APP_ID}@${IMAGE_TAG} to $TARGET_TENANTS (${DEPLOY_ENV})."
