# Multi-Tenant Infrastructure (AWS CloudFormation)

This directory contains AWS CloudFormation templates and scripts for the multi-tenant deployment framework: **2 applications (app1, app2)** per tenant and **stage + prod** per tenant.

## Structure

- **`config/`** — Tenant and app registry (YAML)
- **`templates/`** — CloudFormation: network, security, secrets, data-app, compute-cluster, compute-app
- **`tenants/<id>/`** — Parameter files per tenant: `tenants/base/` (`base-stage-params.json`, `base-prod-params.json`), `tenants/abc/` (`stage-params.json`, `prod-params.json`), `tenants/xyz/` (same)
- **`scripts/`** — `deploy-stack.sh`, `deploy-tenant-env.sh`

## Stack order (per tenant + environment)

1. **network** — VPC, subnets, NAT, IGW  
2. **security** — Security groups, pipeline IAM role  
3. **secrets-app1** / **secrets-app2** — Secrets Manager placeholders per app  
4. **compute-cluster** — ECS cluster (shared by app1 and app2)  
5. **data-app1** / **data-app2** — RDS PostgreSQL per app  
6. **compute-app1** / **compute-app2** — ECS Fargate service per app  

## Deploy one (tenant, environment)

```bash
export AWS_PROFILE=your-profile   # or use env vars AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
./scripts/deploy-tenant-env.sh base stage
./scripts/deploy-tenant-env.sh base prod
./scripts/deploy-tenant-env.sh abc stage
./scripts/deploy-tenant-env.sh abc prod
```

## Stack naming

- Pattern: `{prefix}-{tenant-id}-{environment}-{layer}`  
- Example: `mt-base-stage-network`, `mt-abc-prod-compute-app1`  
- Prefix default: `mt` (override with `STACK_PREFIX`).

## Bitbucket (infra repo)

Use **`bitbucket-pipelines.yml`** in this repo (or copy from `../pipelines/bitbucket-pipelines-infra.yml`). Configure repository variables:

- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`  
- For multi-account: use one pipeline per account or assume role per tenant (see docs).

## Multi-account

For separate AWS accounts per tenant, run the pipeline (or script) in each account, or assume a role per tenant using `aws sts assume-role` and then run `deploy-tenant-env.sh`. Tenant account IDs are in `config/tenant-registry.yaml`.
