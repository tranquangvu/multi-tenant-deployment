# Multi-Tenant Infrastructure (AWS CloudFormation)

**2 applications (foo, baz)** per tenant. **Only base has staging + production**; other tenants (abc, xyz) have **production only**.

## Structure

- **`config/`** — Tenant and app registry (YAML)
  - `tenant-registry.yaml` — Tenants (base, abc, xyz), region, environments. Used by `deploy-tenant.sh` and `get-tenant-region.sh` / `get-tenant-envs.sh`.
  - `app-registry.yaml` — Applications (foo, baz).
- **`templates/`** — CloudFormation module templates (network, security, secrets, rds, alb, ecs-cluster, ecs-service, ecr). Uploaded to S3 for root stack deployment via **`./scripts/upload-templates.sh`**.
- **`shared/`** — Shared resources: ECR repositories per app via **`shared/main.yaml`** (nested stacks from S3). Deploy with **`./scripts/deploy-shared.sh`** once per account/region; tenant stacks import ECR URI via CloudFormation export.
- **`tenants/<tenant-id>/<staging|production>/`** — Per-tenant, per-environment:
  - **`main.yaml`** — Root stack that references module templates via **TemplateURL** (S3). Deploys nested stacks for each module.
  - **`params.json`** — Parameters for the root stack (TenantId, Environment, StackPrefix, TemplatesS3Bucket, TemplatesS3Prefix, app desired counts, etc.).
- **`scripts/`** — Deployment and helpers:
  - `deploy-shared.sh` — Deploy shared stack (ECR per app); run once per account/region.
  - `upload-templates.sh` — Upload `templates/*.yaml` to S3.
  - `deploy-stack.sh` — Deploy a single CloudFormation stack (used by other scripts).
  - `deploy-tenant.sh` — Deploy root stack for one tenant (and optional environment); sets region from registry.
  - `deploy-tenants.sh` — Deploy root stacks for multiple tenants (all or explicit list).
  - `get-tenant-envs.sh` — List environments for a tenant from registry.
  - `get-tenant-region.sh` — Output region for a tenant from registry.
- **`docs/`** — Design and runbooks (see [docs/README.md](docs/README.md)).

## Tenant layout

```
multi-tenant-deployment/
├── config/
│   ├── tenant-registry.yaml
│   └── app-registry.yaml
├── templates/
│   ├── network.yaml
│   ├── security.yaml
│   ├── secrets.yaml
│   ├── rds.yaml
│   ├── ecr.yaml
│   ├── ecs-cluster.yaml
│   ├── ecs-service.yaml
│   └── alb.yaml
├── shared/
│   ├── main.yaml
│   └── params.json
├── tenants/
│   ├── base/
│   │   ├── staging/
│   │   │   ├── main.yaml
│   │   │   └── params.json
│   │   └── production/
│   │       ├── main.yaml
│   │       └── params.json
│   ├── abc/
│   │   └── production/
│   │       ├── main.yaml
│   │       └── params.json
│   └── xyz/
│       └── production/
│           ├── main.yaml
│           └── params.json
└── scripts/
    ├── deploy-shared.sh
    ├── upload-templates.sh
    ├── deploy-stack.sh
    ├── deploy-tenant.sh
    ├── deploy-tenants.sh
    ├── get-tenant-envs.sh
    └── get-tenant-region.sh
```

## Deploy (root stack via S3)

All root stacks (shared and per-tenant) pull module templates from S3. Upload templates first.

1. **Upload templates to S3** (required after template changes):

   ```bash
   export TEMPLATES_S3_BUCKET=your-cfn-templates-bucket   # optional; default go-ascendasia
   ./scripts/upload-templates.sh
   ```

2. **Deploy shared stacks** (ECR per app) once per account/region:

   ```bash
   export AWS_DEFAULT_REGION=ap-southeast-1
   ./scripts/deploy-shared.sh
   ```

3. **Deploy root stack** for one (tenant, environment). Either use the helper (sets region from registry) or call `deploy-stack.sh` directly:

   **Option A — Helper (recommended):** sets `AWS_DEFAULT_REGION` from `config/tenant-registry.yaml`:

   ```bash
   ./scripts/deploy-tenant.sh base staging
   ./scripts/deploy-tenant.sh base production
   ./scripts/deploy-tenant.sh abc production
   ./scripts/deploy-tenant.sh xyz production
   # Or all envs for a tenant:
   ./scripts/deploy-tenant.sh base
   # Or all tenants (all their envs):
   ./scripts/deploy-tenants.sh
   ./scripts/deploy-tenants.sh base abc
   ```

   **Option B — Manual stack name and paths:** set region first, then:

   ```bash
   export TEMPLATES_S3_BUCKET=your-cfn-templates-bucket
   export AWS_DEFAULT_REGION="$(./scripts/get-tenant-region.sh base)"
   ./scripts/deploy-stack.sh mt-base-staging tenants/base/staging/main.yaml tenants/base/staging/params.json
   ./scripts/deploy-stack.sh mt-base-production tenants/base/production/main.yaml tenants/base/production/params.json
   ./scripts/deploy-stack.sh mt-abc-production tenants/abc/production/main.yaml tenants/abc/production/params.json
   ./scripts/deploy-stack.sh mt-xyz-production tenants/xyz/production/main.yaml tenants/xyz/production/params.json
   ```

   **deploy-stack.sh** accepts a template path (e.g. `tenants/base/staging/main.yaml`) or a template filename (e.g. `network.yaml` for `templates/`). Params can use `${TEMPLATES_S3_BUCKET:-go-ascendasia}` and `${TEMPLATES_S3_PREFIX:-cfn/templates}`; **deploy-stack.sh** resolves them. Root stacks (main.yaml) get `CAPABILITY_AUTO_EXPAND`; stacks in `ROLLBACK_COMPLETE` are deleted before deploy.

## Bitbucket pipeline

- **Repository variables:** `TEMPLATES_S3_BUCKET` (default `go-ascendasia`), `AWS_ROLE_ARN` for OIDC.
- **main branch:** Upload templates → Deploy shared → Deploy base staging (root stack). Base production is available as a manual step (commented out by default).
- **Custom `deploy-tenant`:** Variables `DEPLOY_TENANT_ID` (default `base`), `DEPLOY_ENVIRONMENT` (default `staging`). Uploads templates, deploys shared, then deploys root stack for the chosen tenant/environment.
- **Custom `promote-tenants`:** Variable `PROMOTE_TENANTS` (e.g. `abc`, `abc,xyz`, or `all`). Manual trigger. Uploads templates, then for each tenant deploys shared and root stack for production.

Pipeline uses OIDC (`oidc: true`); set `AWS_ROLE_ARN` in repo or deployment environment.

## Stack naming

- **Shared stack:** `{prefix}-shared` (e.g. `mt-shared`). Contains nested stacks that create ECR repos per app (repository names: `mt-foo`, `mt-baz`). Prefix default: `mt` (override with `STACK_PREFIX`).
- **Root stack (per tenant/env):** `{prefix}-{tenant-id}-{staging|production}` (e.g. `mt-base-staging`, `mt-abc-production`).
- **Nested stacks:** Created by the root stack; names assigned by CloudFormation (root stack name + logical ID).

## Multi-account

Use one S3 bucket per account (or a shared bucket with prefix per account). Run upload and deploy in the target account (or after assuming the tenant role). Tenant account IDs can be added to `config/tenant-registry.yaml` under `accounts` per environment for Landing Zone / multi-account. See [docs/02-architecture-and-tenant-model.md](docs/02-architecture-and-tenant-model.md) and [docs/07-runbooks.md](docs/07-runbooks.md).
