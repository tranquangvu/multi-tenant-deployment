# Multi-Tenant Infrastructure (AWS CloudFormation)

**2 applications (foo, baz)** per tenant. **Only base has staging + production**; other tenants (abc, xyz) have **production only**.

## Structure

- **`config/`** — Tenant and app registry (YAML)
- **`templates/`** — CloudFormation module templates (network, security, secrets, rds, alb, ecs-cluster, ecs-service). Uploaded to S3 for root stack deployment.
- **`shared/`** — Shared resources (ECR repository per app). Deploy with **`./scripts/deploy-shared.sh`** once per account/region; tenant stacks import ECR URI via CloudFormation export.
- **`tenants/[tenant-name]/[staging|production]/`** — Per-tenant, per-environment:
  - **`main.yaml`** — Root stack that registers all modules via **TemplateURL** (S3). Deploys nested stacks for each module.
  - **`params.json`** — Parameters for the root stack (TenantId, Environment, StackPrefix, TemplatesS3Bucket, TemplatesS3Prefix).
- **`scripts/`** — `deploy-shared.sh` (ECR stacks, run once per account/region), `upload-templates.sh`, `deploy-stack.sh`, `deploy-tenant.sh`, `deploy-tenants.sh`

## Tenant layout

```
tenants/
├── _shared/
│   └── main.yaml              # Root stack (TemplateURL → S3)
├── base/
│   ├── staging/
│   │   ├── main.yaml
│   │   └── params.json
│   └── production/
│       ├── main.yaml
│       └── params.json
├── abc/
│   └── production/
│       ├── main.yaml
│       └── params.json
└── xyz/
    └── production/
        ├── main.yaml
        └── params.json
```

## Deploy (root stack via S3)

1. **Upload templates to S3** (required once per change):

   ```bash
   export TEMPLATES_S3_BUCKET=your-cfn-templates-bucket
   ./scripts/upload-templates.sh
   ```

2. **Deploy root stack** (main.yaml) for one (tenant, environment). This creates the main stack and all nested stacks:

   ```bash
   export TEMPLATES_S3_BUCKET=your-cfn-templates-bucket
   ./scripts/deploy-stack.sh mt-base-staging tenants/base/staging/main.yaml tenants/base/staging/params.json
   ./scripts/deploy-stack.sh mt-base-production tenants/base/production/main.yaml tenants/base/production/params.json
   ./scripts/deploy-stack.sh mt-abc-production tenants/abc/production/main.yaml tenants/abc/production/params.json
   ./scripts/deploy-stack.sh mt-xyz-production tenants/xyz/production/main.yaml tenants/xyz/production/params.json
   ```

   **deploy-stack.sh** accepts a template path (e.g. `tenants/base/staging/main.yaml`) or a template filename (e.g. `network.yaml` for `templates/`). Params use `\${TEMPLATES_S3_BUCKET:-go-ascendasia}` and `\${TEMPLATES_S3_PREFIX:-cfn/templates}`; **deploy-stack.sh** resolves them like bash.

When deploying a **root stack** manually, set the region from the tenant registry so the stack is created in the correct region, or use `deploy-tenant.sh` which does this for you:

```bash
export AWS_DEFAULT_REGION="$(./scripts/get-tenant-region.sh base)"
./scripts/deploy-stack.sh mt-base-staging tenants/base/staging/main.yaml tenants/base/staging/params.json
# or:
./scripts/deploy-tenant.sh base staging
```

**deploy-tenant.sh** and the Bitbucket pipeline set `AWS_DEFAULT_REGION` from `config/tenant-registry.yaml` automatically for the tenant being deployed.

## Bitbucket pipeline (upload + deploy)

- **Repository variables:** `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`, **`TEMPLATES_S3_BUCKET`** (S3 bucket for templates).
- **main branch:** Upload templates to S3 → Deploy base staging (root stack); then manual step to deploy base production.
- **Custom `upload-templates`:** Upload templates to S3 only.
- **Custom `deploy-tenant`:** Upload templates then deploy root stack for chosen tenant and environment (staging or production).
- **Custom `promote-tenants`:** Upload templates then deploy root stack for selected tenants (production only for abc/xyz).

## Legacy deploy (per-stack, no S3)

1. **Deploy shared stacks once** (ECR per app) in the target account/region:

   ```bash
   export AWS_DEFAULT_REGION=ap-southeast-1   # or your region
   ./scripts/deploy-shared.sh                 # uses shared/params.json; creates mt-ecr-foo, mt-ecr-baz
   ```

2. Deploy each tenant/environment (root stack per tenant/env):

```bash
./scripts/deploy-tenant.sh base staging   # or base prod, abc prod, xyz prod
./scripts/deploy-tenants.sh
```

Under the hood these use **`deploy-stack.sh`** with the root stack (e.g. `tenants/base/staging/main.yaml`) and S3.

## Stack naming

- **Shared stacks:** `{prefix}-ecr-{app}` (e.g. `mt-ecr-foo`, `mt-ecr-baz`). Created by **`deploy-shared.sh`**.
- **Root stack:** `{prefix}-{tenant-id}-{staging|prod}` (e.g. `mt-base-staging`, `mt-abc-production`).
- **Nested stacks:** Created by the root stack with names assigned by CloudFormation (based on root stack name + logical ID).

Prefix default: `mt` (override with `STACK_PREFIX`).

## Multi-account

Use one S3 bucket per account (or shared bucket with prefix per account). Run upload and deploy in the target account (or after assuming the tenant role). Tenant account IDs are in `config/tenant-registry.yaml`.
