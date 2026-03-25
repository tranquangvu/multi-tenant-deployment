# Multi-Tenant Infrastructure (AWS CloudFormation)

**2 applications (foo, baz)** per tenant. **Only base has staging + production**; other tenants (abc, xyz) have **production only**.

## Structure

- **`config/`** — Tenant and app registry (YAML)
  - `tenant-registry.yaml` — Tenants (base, abc, xyz), region, and per-environment metadata. Currently used by `deploy-tenant.sh` and `get-tenant-region.sh` / `get-tenant-envs.sh` for tenant/environment resolution.
  - `app-registry.yaml` — Applications (foo, baz).
- **`templates/`** — CloudFormation module templates (security, secrets, rds, alb, ecs-cluster, ecs-service, ecr). Uploaded to S3 for root stack deployment via **`./scripts/upload-config-templates.sh`**.
- **`shared/`** — Shared resources: ECR repositories per app via **`shared/main.yaml`** (nested stacks from S3). Deploy with **`./scripts/deploy-shared.sh`** once per account/region; tenant stacks import ECR URI via CloudFormation export.
- **`tenants/<tenant-id>/<staging|production>/`** — Per-tenant, per-environment:
  - **`main.yaml`** — Root stack that references module templates via **TemplateURL** (S3). Deploys nested stacks for each module.
  - **`params.json`** — Parameters for the root stack (TenantId, Environment, StackPrefix, TemplateS3Bucket, TemplateS3Prefix, app desired counts, etc.).
- **`scripts/`** — Deployment and helpers:
  - `deploy-shared.sh` — Deploy shared stack (ECR per app); run once per account/region.
  - `upload-config-templates.sh` — Upload `templates/*.yaml` (and `config/*.yaml`) to S3.
  - `deploy-stack.sh` — Deploy a single CloudFormation stack (used by other scripts).
  - `deploy-tenant.sh` — Deploy root stack for one tenant (and optional environment); sets region from registry, merges VPC/subnet SSM parameter names from the registry, and optionally checks AWS account vs `accountId`.
  - `get-tenant-envs.sh` — List environments for a tenant from registry.
  - `get-tenant-region.sh` — Output region for a tenant from registry.
  - `get-tenant-account-id.sh` — Output `accountId` for a (tenant, environment).
  - `tenant-network-ssm-params.rb` — Emit JSON array of CloudFormation parameters for SSM paths (used by `deploy-tenant.sh`).
- **`docs/`** — Design and runbooks (see [docs/README.md](docs/README.md)).

## Tenant layout

```
multi-tenant-deployment/
├── config/
│   ├── tenant-registry.yaml
│   └── app-registry.yaml
├── templates/
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
    ├── upload-config-templates.sh
    ├── deploy-stack.sh
    ├── deploy-tenant.sh
    ├── get-tenant-envs.sh
    ├── get-tenant-region.sh
    ├── get-tenant-account-id.sh
    └── tenant-network-ssm-params.rb
```

## Tenant registry schema

`config/tenant-registry.yaml` now stores per-environment account and network metadata:

- `tenants.<tenant>.region` — deployment region.
- `tenants.<tenant>.environments.<env>.accountId` — AWS account ID.
- `tenants.<tenant>.environments.<env>.accountName` — account display name.
- `tenants.<tenant>.environments.<env>.networkVpcName` — target VPC name.
- `tenants.<tenant>.environments.<env>.networkPublicSubnetNames` — public subnet names.
- `tenants.<tenant>.environments.<env>.networkPrivateSubnetNames` — private subnet names.

**SSM path convention** (Landing Zone / shared network; resolved at CloudFormation deploy time):

- Default root: `/accelerator/network` (override with env `SSM_NETWORK_PREFIX` or optional tenant key `ssmNetworkPrefix`).
- VPC id: `{prefix}/vpc/{networkVpcName}/id`
- Subnet id: `{prefix}/vpc/{networkVpcName}/subnet/{subnetName}/id`

The root stack uses `AWS::SSM::Parameter::Value<AWS::EC2::VPC::Id>` (and subnet types) for those parameters and passes resolved IDs into nested modules. The IAM principal that runs `aws cloudformation deploy` must allow `ssm:GetParameter` on those ARNs.

**Script behavior:**

- `deploy-tenant.sh` reads `accountId`, subnet names, and VPC name; merges five parameters (`VpcIdSsmPath`, `PublicSubnet1SsmPath`, …) into `params.json` before calling `deploy-stack.sh`. It compares `sts get-caller-identity` to `accountId` unless `SKIP_TENANT_ACCOUNT_CHECK=1`.
- Requires **Ruby** (YAML parsing) and **jq** (merge). Bitbucket steps install Ruby on the image when missing.

## Deploy (root stack via S3)

All root stacks (shared and per-tenant) pull module templates from S3. Upload templates first.

1. **Upload templates to S3** (required after template changes):

   ```bash
   export INFRA_S3_BUCKET=your-s3-bucket   # optional; default mt-infra
   ./scripts/upload-config-templates.sh
   ```

2. **Deploy shared stacks** (ECR per app) once per account/region:

   ```bash
   export AWS_DEFAULT_REGION=ap-southeast-1
   ./scripts/deploy-shared.sh
   ```

3. **Deploy root stack** for one (tenant, environment). Use **`deploy-tenant.sh`** so VPC and subnet SSM paths are merged from the registry. Calling **`deploy-stack.sh`** with only `params.json` will **omit** those parameters and the deploy will fail.

   **Recommended — `deploy-tenant.sh`:** sets region from the registry, merges network SSM parameters, optional account check:

   ```bash
   ./scripts/deploy-tenant.sh base staging
   ./scripts/deploy-tenant.sh base production
   ./scripts/deploy-tenant.sh abc production
   ./scripts/deploy-tenant.sh xyz production
   # Or all envs for a tenant:
   ./scripts/deploy-tenant.sh base
   ```

   **Manual `deploy-stack.sh`:** build a merged params file first, then deploy (same merge `deploy-tenant.sh` uses):

   ```bash
   export INFRA_S3_BUCKET=your-s3-bucket
   export AWS_DEFAULT_REGION="$(./scripts/get-tenant-region.sh base)"
   NET="$(ruby ./scripts/tenant-network-ssm-params.rb ./config/tenant-registry.yaml base staging)"
   jq --argjson net "$NET" '. + $net' tenants/base/staging/params.json > /tmp/merged-params.json
   ./scripts/deploy-stack.sh mt-base-staging tenants/base/staging/main.yaml /tmp/merged-params.json
   ```

   **deploy-stack.sh** accepts a template path (e.g. `tenants/base/staging/main.yaml`) or a template filename (e.g. `alb.yaml` under `templates/`). Params can use `${INFRA_S3_BUCKET:-mt-infra}` and `${TEMPLATE_S3_PREFIX:-templates}`; **deploy-stack.sh** resolves them. Root stacks (main.yaml) get `CAPABILITY_AUTO_EXPAND`; stacks in `ROLLBACK_COMPLETE` are deleted before deploy.

   **Migration:** Older stacks may still have a nested `NetworkStack` resource. Updating to this layout removes that nested stack; CloudFormation deletes it on successful update. If the update fails, you may need a one-time stack recreation.

## Bitbucket pipeline

- **Repository variables:** `INFRA_S3_BUCKET` (default `mt-infra`), `TEMPLATE_S3_PREFIX` (default `templates`), `AWS_ROLE_ARN` for OIDC.
- **main branch:** Upload templates → Deploy shared → Deploy base staging (root stack). Base production is available as a manual step (commented out by default).
- **Custom `deploy-tenant`:** Variables `DEPLOY_TENANT_ID` (default `base`), `DEPLOY_ENVIRONMENT` (default `staging`). Uploads templates, deploys shared, then deploys root stack for the chosen tenant/environment.
- **Custom `promote-tenants`:** Variable `TARGET_TENANTS` (e.g. `abc`, `abc,xyz`, or `all`). Manual trigger. Uploads templates, then for each tenant deploys shared and `deploy-tenant.sh <tenant> production`.

Pipeline uses OIDC (`oidc: true`); set `AWS_ROLE_ARN` in repo or deployment environment. Steps that run `deploy-tenant.sh` install **Ruby** and **jq** on the image when missing (needed to merge SSM path parameters from the registry).

## Stack naming

- **Shared stack:** `{prefix}-shared` (e.g. `mt-shared`). Contains nested stacks that create ECR repos per app (repository names: `mt-foo`, `mt-baz`). Prefix default: `mt` (override with `STACK_PREFIX`).
- **Root stack (per tenant/env):** `{prefix}-{tenant-id}-{staging|production}` (e.g. `mt-base-staging`, `mt-abc-production`).
- **Nested stacks:** Created by the root stack; names assigned by CloudFormation (root stack name + logical ID).

## Multi-account

Use one S3 bucket per account (or a shared bucket with prefix per account). Run upload and deploy in the target account (or after assuming the tenant role). Tenant environment metadata (including `accountId`) is tracked in `config/tenant-registry.yaml` under `tenants.<tenant>.environments.<env>`. See [docs/02-architecture-and-tenant-model.md](docs/02-architecture-and-tenant-model.md) and [docs/07-runbooks.md](docs/07-runbooks.md).
