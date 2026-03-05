# Multi-Tenant Infrastructure (AWS CloudFormation)

This directory contains AWS CloudFormation templates and scripts for the multi-tenant deployment framework: **2 applications (app1, app2)** per tenant. **Only base has stage + prod**; all other tenants (abc, xyz) have **production only**.

## Structure

- **`config/`** — Tenant and app registry (YAML)
- **`templates/`** — CloudFormation templates by AWS service:
  - **network** — VPC, subnets, NAT, IGW
  - **security** — Security groups, pipeline IAM role
  - **secrets** — Secrets Manager per app
  - **ecr** — ECR repository per app
  - **rds** — RDS PostgreSQL per app
  - **alb** — Application Load Balancer + target groups (app1, app2)
  - **ecs-cluster** — ECS cluster (shared by app1 and app2)
  - **ecs-service** — ECS Fargate service + task definition per app
- **`tenants/<id>/`** — Parameter files per tenant: `tenants/base/`, `tenants/abc/`, `tenants/xyz/`
- **`scripts/`** — `deploy-stack.sh`, `deploy-tenant-env.sh`

## How all modules are used in each tenant

**Every (tenant, environment)** gets the **full set** of modules. One run of `deploy-tenant-env.sh <tenant-id> <environment>` deploys all of these stacks for that tenant + env:

| Module      | Stacks per (tenant, env) | Description                  |
| ----------- | ------------------------ | ---------------------------- |
| network     | 1                        | VPC, subnets, NAT, IGW       |
| security    | 1                        | App SG, DB SG, pipeline role |
| secrets     | 2 (app1, app2)           | Secrets Manager per app      |
| ecr         | 2 (app1, app2)           | ECR repo per app             |
| ecs-cluster | 1                        | ECS cluster (shared)         |
| rds         | 2 (app1, app2)           | RDS PostgreSQL per app       |
| alb         | 1                        | ALB + 2 target groups        |
| ecs-service | 2 (app1, app2)           | Fargate service per app      |

**Example:** For `base` + `stage` you get e.g. `mt-base-stage-network`, … `mt-base-stage-ecs-app2`. Same stack set for `base`+`prod`. For `abc` and `xyz` only **prod** exists: `mt-abc-prod-network`, … `mt-xyz-prod-ecs-app2` (each tenant has params under `tenants/<id>/`).

## Deploy order (per tenant + environment)

1. **network** → **security** → **secrets** (app1, app2) → **ecr** (app1, app2) → **ecs-cluster** → **rds** (app1, app2) → **alb** → **ecs-service** (app1, app2)

## Deploy one (tenant, environment)

```bash
export AWS_PROFILE=your-profile   # or use env vars AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
# Base: stage and prod
./scripts/deploy-tenant-env.sh base stage
./scripts/deploy-tenant-env.sh base prod
# Other tenants: prod only (deploying abc/xyz with stage will exit with an error)
./scripts/deploy-tenant-env.sh abc prod
./scripts/deploy-tenant-env.sh xyz prod
```

## Deploy all tenants (all modules in each)

Runs **all modules** for each tenant. Base gets **stage** then **prod**; abc and xyz get **prod** only.

```bash
./scripts/deploy-all-tenants.sh
```

Optional: limit to specific tenants:

```bash
DEPLOY_TENANTS="base abc" ./scripts/deploy-all-tenants.sh   # base (stage+prod), abc (prod only)
```

## Stack naming

- Pattern: `{prefix}-{tenant-id}-{environment}-{layer}`
- Example: `mt-base-stage-network`, `mt-abc-prod-ecs-app1`, `mt-base-stage-alb`
- Prefix default: `mt` (override with `STACK_PREFIX`).

## Bitbucket (infra repo)

Use **`bitbucket-pipelines.yml`** in this repo (or copy from `../pipelines/bitbucket-pipelines-infra.yml`). Configure repository variables:

- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`
- For multi-account: use one pipeline per account or assume role per tenant (see docs).

## Multi-account

For separate AWS accounts per tenant, run the pipeline (or script) in each account, or assume a role per tenant using `aws sts assume-role` and then run `deploy-tenant-env.sh`. Tenant account IDs are in `config/tenant-registry.yaml`.
