# Multi-Tenant Deployment Presentation

## 1) What This Platform Solves

- Standardize infrastructure deployment for multiple tenants/environments using one shared framework.
- Keep tenant-specific configuration in one source of truth: `config/tenant-registry.yaml`.
- Reduce manual AWS ops with scripted deployment and Bitbucket OIDC authentication.
- Support full lifecycle: upload templates, deploy tenant stacks, and delete tenant stacks safely.

---

## 2) High-Level Architecture

### Design Principles

- **Tenant-first config**: tenant metadata + network mapping are centralized in `tenant-registry.yaml`.
- **Composable stacks**: root tenant stacks orchestrate module templates (`security`, `alb`, `ecs`, `rds`, etc.).
- **Landing Zone networking**: VPC/subnet IDs are resolved from SSM paths, not created by this repo.
- **Pipeline auth without hardcoded role ARN**: role is derived dynamically from `accountId` + `bitbucketOidcRoleName`.

### Stack Model

- **Shared stack** (`mt-shared`)
  - global/shared resources (for example ECR repos)
- **Tenant root stack** (`mt-<tenant>-<environment>`)
  - composes module templates
  - per-tenant/per-env parameters and wiring

---

## 3) Tenant Registry Model

Primary file: `config/tenant-registry.yaml`

- `tenants.<tenant>.region`
- `tenants.<tenant>.environments.<env>.accountId`
- `tenants.<tenant>.environments.<env>.bitbucketOidcRoleName`
- `tenants.<tenant>.environments.<env>.networkVpcName`
- `tenants.<tenant>.environments.<env>.networkPublicSubnetNames`
- `tenants.<tenant>.environments.<env>.networkPrivateSubnetNames`

Also includes `shared` section:

- `shared.region`
- `shared.accountId`
- `shared.bitbucketOidcRoleName`

This `shared` section is now used by upload step auth and region resolution.

---

## 4) Bitbucket Pipeline Workflow + Script Execution

Primary file: `bitbucket-pipelines.yml`

### Branch pipeline (`main`)

1. Verify OIDC token
2. Upload config/templates
3. Deploy base production

### Custom pipelines

- `deploy-tenant`
- `delete-tenant`
- `deploy-tenants-production`

### Dynamic OIDC role resolution

No static hardcoded `AWS_ROLE_ARN` in pipeline variables required now.

- For shared upload:
  - `scripts/get-shared-oidc-role-arn.sh`
  - `scripts/get-shared-region.sh`
- For tenant operations:
  - `scripts/get-tenant-oidc-role-arn.sh <tenant> <env>`

Role ARN format:

- `arn:aws:iam::<accountId>:role/<bitbucketOidcRoleName>`

### Which scripts run in each pipeline stage

- **Upload config/templates**
  - `scripts/upload-config-templates.sh`
  - Ensures S3 bucket exists (auto-creates if missing)
  - Uploads template files to `s3://<bucket>/<template-prefix>/`
  - Uploads config files to `s3://<bucket>/<config-prefix>/`
- **Deploy base production / deploy-tenant / deploy-tenants-production**
  - `scripts/deploy-shared.sh` (shared resources)
  - `scripts/deploy-tenant.sh <tenant-id> [environment]`
  - Internally calls `scripts/deploy-stack.sh`
  - Merges SSM network parameters via `scripts/utils/tenant-network-ssm-params.py`
- **Delete tenant**
  - `scripts/delete-tenant.sh <tenant-id> [environment]`
  - Deletes root stack and waits for completion
  - Safety gate: requires `CONFIRM_DELETE_TENANT=1`

---

## 5) CI Dependency Management

Script: `scripts/install-ci-deps.sh`

- Standardizes dependency prep in pipeline steps.
- Ensures:
  - `python3`
  - `pip` module for python
  - `pyyaml`
  - `jq`
- Avoids duplicated install logic across multiple pipeline jobs.

---

## 6) Common Troubleshooting

### OIDC / Assume role issues

- Verify `accountId` and `bitbucketOidcRoleName` in `tenant-registry.yaml`.
- Confirm OIDC role trust policy allows Bitbucket OIDC provider + claims.
- Confirm pipeline exports `AWS_ROLE_ARN` before AWS CLI calls.

### Deploy fails on account mismatch

- Script checks tenant registry account vs current account.
- Fix by using correct role/account or temporarily set `SKIP_TENANT_ACCOUNT_CHECK=1`.

### ECS service healthy task but ALB health check fails

- Check subnet mapping + SG ingress rules to app port.
- Validate target group health path/port and SG path ALB -> ECS.

### Missing Python package in CI

- Re-run with `scripts/install-ci-deps.sh` included in the step.
