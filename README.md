# Multi-Tenant Infrastructure (AWS CloudFormation)

**2 applications (foo, baz)** per tenant. **Only base has staging + production**; other tenants (abc, xyz) have **production only**.

## Structure

- **`config/`** — Tenant and app registry (YAML)
- **`templates/`** — CloudFormation module templates (network, security, secrets, ecr, rds, alb, ecs-cluster, ecs-service). Uploaded to S3 for root stack deployment.
- **`tenants/[tenant-name]/[staging|production]/`** — Per-tenant, per-environment:
  - **`main.yaml`** — Root stack that registers all modules via **TemplateURL** (S3). Deploys nested stacks for each module.
  - **`params.json`** — Parameters for the root stack (TenantId, Environment, StackPrefix, TemplatesS3Bucket, TemplatesS3Prefix).
- **`scripts/`** — `upload-templates-to-s3.sh`, `deploy-stack.sh` (use for both module stacks and root main.yaml), `deploy-tenant-env.sh`

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
   ./scripts/upload-templates-to-s3.sh
   ```

2. **Deploy root stack** (main.yaml) for one (tenant, environment). This creates the main stack and all nested stacks:

   ```bash
   export TEMPLATES_S3_BUCKET=your-cfn-templates-bucket
   ./scripts/deploy-stack.sh mt-base-staging tenants/base/staging/main.yaml tenants/base/staging/params.json
   ./scripts/deploy-stack.sh mt-base-prod tenants/base/production/main.yaml tenants/base/production/params.json
   ./scripts/deploy-stack.sh mt-abc-prod tenants/abc/production/main.yaml tenants/abc/production/params.json
   ./scripts/deploy-stack.sh mt-xyz-prod tenants/xyz/production/main.yaml tenants/xyz/production/params.json
   ```

   **deploy-stack.sh** accepts a template path (e.g. `tenants/base/staging/main.yaml`) or a template filename (e.g. `network.yaml` for `templates/`). It substitutes `\${TEMPLATES_S3_BUCKET}` in params from the environment.

When deploying a **root stack** manually, set the region from the tenant registry so the stack is created in the correct region:

```bash
export AWS_DEFAULT_REGION="$(./scripts/get-tenant-region.sh base)"
./scripts/deploy-stack.sh mt-base-staging tenants/base/staging/main.yaml tenants/base/staging/params.json
```

**deploy-tenant-env.sh** and the Bitbucket pipeline set `AWS_DEFAULT_REGION` from `config/tenant-registry.yaml` automatically for the tenant being deployed.

## Bitbucket pipeline (upload + deploy)

- **Repository variables:** `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`, **`TEMPLATES_S3_BUCKET`** (S3 bucket for templates).
- **main branch:** Upload templates to S3 → Deploy base staging (root stack); then manual step to deploy base production.
- **Custom `upload-templates`:** Upload templates to S3 only.
- **Custom `deploy-tenant`:** Upload templates then deploy root stack for chosen tenant and environment (staging or production).
- **Custom `promote-tenants`:** Upload templates then deploy root stack for selected tenants (production only for abc/xyz).

## Legacy deploy (per-stack, no S3)

To deploy each module stack individually (templates from repo, no S3):

```bash
./scripts/deploy-tenant-env.sh base staging   # or base prod, abc prod, xyz prod
./scripts/deploy-tenants.sh
```

Uses **`deploy-stack.sh`** and expects params in the old shape; for the new layout you use **`deploy-stack.sh`** with the root stack (e.g. `tenants/base/staging/main.yaml`) and S3 instead.

## Stack naming

- **Root stack:** `{prefix}-{tenant-id}-{staging|prod}` (e.g. `mt-base-staging`, `mt-abc-prod`).
- **Nested stacks:** Created by the root stack with names assigned by CloudFormation (based on root stack name + logical ID).

Prefix default: `mt` (override with `STACK_PREFIX`).

## Multi-account

Use one S3 bucket per account (or shared bucket with prefix per account). Run upload and deploy in the target account (or after assuming the tenant role). Tenant account IDs are in `config/tenant-registry.yaml`.
