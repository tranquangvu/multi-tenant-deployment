# Runbooks: Deploy, Promote, Rollback

Short operational procedures for the multi-tenant deployment framework. Assumes Bitbucket Pipelines, AWS CloudFormation, and tenant registry are in place. All scripts below live in **this repo** (`multi-tenant-deployment/scripts/`).

## Scripts reference (multi-tenant-deployment/scripts/)

| Script | Purpose |
|--------|---------|
| `deploy-stack.sh` | Deploy a single CloudFormation stack. Usage: `./scripts/deploy-stack.sh <stack-name> <template-file> [params-file]`. Used by other scripts. Root stacks (main.yaml) get `CAPABILITY_AUTO_EXPAND`. Handles `ROLLBACK_COMPLETE` by deleting stack before deploy. |
| `deploy-tenant.sh` | Deploy root stack (main.yaml) for a tenant and optional environment. Usage: `./scripts/deploy-tenant.sh <tenant-id> [environment]`. Omit environment to deploy all envs for that tenant. Examples: `./scripts/deploy-tenant.sh base`, `./scripts/deploy-tenant.sh base staging`, `./scripts/deploy-tenant.sh abc production`. Reads `config/tenant-registry.yaml` for region, optional `accountId` check, and merges VPC/subnet SSM path parameters via `utils/tenant-network-ssm-params.py`; only base supports staging. |
| `deploy-shared.sh` | Deploy shared stacks (e.g. ECR repos via `shared/main.yaml`). Run once per account/region before deploying tenants. Usage: `AWS_DEFAULT_REGION=ap-southeast-1 ./scripts/deploy-shared.sh` or `./scripts/deploy-shared.sh [params-file]`. |
| `upload-config-templates.sh` | Upload CloudFormation templates from `templates/` and config from `config/` to S3. Optional env: `INFRA_S3_BUCKET`, `TEMPLATE_S3_PREFIX`, `CONFIG_S3_PREFIX`. Default bucket: `mt-infra`. |
| `get-tenant-envs.sh` | List environments for a tenant from `config/tenant-registry.yaml`. Usage: `./scripts/get-tenant-envs.sh <tenant-id>`. |
| `get-tenant-region.sh` | Output AWS region for a tenant from registry. Usage: `./scripts/get-tenant-region.sh <tenant-id>`. |

---

## 1. Deploy to Base Tenant

**When**: Every merge to `main` (or configured branch).

**Steps**:
1. Push/merge to `main` in the application (or infra) repo.
2. Bitbucket Pipeline runs automatically: Build → Deploy to Base → Validate.
3. **Infrastructure (manual or pipeline)**: From this repo, ensure templates are in S3 if using nested stacks: `./scripts/upload-config-templates.sh`. Then deploy base: `./scripts/deploy-tenant.sh base staging` or `./scripts/deploy-tenant.sh base` to deploy all base environments (staging, production).
4. Check pipeline result:
   - **Success**: Base tenant is updated; proceed to “Promote to Tenants” when ready.
   - **Failure**: Fix code/config, push again; check Jira for linked ticket status if integrated.
5. Confirm in Jira that deployment status was updated (if integrated).

**Rollback (base only)**: Use “Rollback a Tenant” below with tenant ID = `base`.

---

## 2. Promote to Tenants

**When**: After base deployment is validated and approval is granted.

**Steps**:
1. Open the pipeline run that deployed to base (on `main`).
2. Run the **manual “Approval for promotion”** step if required.
3. **Infrastructure**: To deploy/update stacks for tenants, from this repo run:
   - Single tenant: `./scripts/deploy-tenant.sh abc production`
4. If promotion is done via pipeline, set variables as required (e.g. `PROMOTE_TENANTS=abc` or `abc,xyz` or `all`).
5. Verify pipeline log for “Promotion” section: list of tenants and success/fail per tenant.
6. Check deployment history (dashboard or logs) and Jira for traceability.

**If one tenant fails**: Other tenants remain unchanged (silo). Fix the failing tenant (config/network/perms) and re-run `./scripts/deploy-tenant.sh <tenant-id> production` for that tenant only, or run rollback and then fix and re-promote.

---

## 3. Rollback a Tenant

**When**: A tenant has a bad deployment or failed migration and must be reverted.

**Steps**:
1. Identify **tenant ID** and, if needed, **target version** (e.g. previous template/params).
2. **Infrastructure**: There is no dedicated rollback script. Redeploy the previous stack revision:
   - Run `./scripts/deploy-tenant.sh <tenant-id> [environment]` with the same parameters/templates that were last known good. Ensure `tenants/<tenant-id>/<staging|production>/params.json` and templates reflect the desired state.
   - If the stack is in `ROLLBACK_COMPLETE`, `deploy-stack.sh` (used by `deploy-tenant.sh`) will delete the stack and create a fresh one on the next deploy.
3. **App/DB**: If app or DB must be reverted, use application pipelines or RDS restore (point-in-time or snapshot) for that tenant’s DB, then align app version if necessary.
4. Verify app and DB for that tenant; check deployment history and logs.
5. Update Jira if needed (e.g. comment “Rolled back abc to v1.2.3”).

**DB-only rollback**: Use RDS point-in-time restore or snapshot restore for that tenant’s DB, then align app version if necessary.

---

## 4. Add a New Tenant

**When**: Onboarding a new silo tenant.

**Steps**:
1. Create AWS account (via LZA or org process); note account ID.
2. Add tenant to **tenant registry** (`config/tenant-registry.yaml` in this repo): add a new key (e.g. `new-tenant`) with `name`, `region`, `environments` (e.g. `[production]`), and `accounts` (environment → account ID) if using multi-account. See existing entries (base, abc, xyz) for the schema.
3. Commit and merge registry change.
4. **Shared stacks (new account)**: In that account/region, run once: `AWS_DEFAULT_REGION=<region> ./scripts/deploy-shared.sh`.
5. **Templates**: Upload templates if using nested stacks: `./scripts/upload-templates.sh` (set `INFRA_S3_BUCKET` / `TEMPLATE_S3_PREFIX` if needed).
6. **Tenant stacks**: Create `tenants/<tenant-id>/production/main.yaml` and `params.json` (or staging if applicable), then run `./scripts/deploy-tenant.sh new-tenant production`.
7. Store secrets (DB, app config) in that account’s Secrets Manager (or Parameter Store).
8. When ready, include this tenant in promotion (e.g. run `./scripts/deploy-tenant.sh new-tenant production` or add it to your pipeline promotion list).

---

## 5. Investigate Failed Deployment or Validation

**Steps**:
1. Open Bitbucket pipeline run → check failed step and logs.
2. Check **central dashboard** for deployment status and any alerts.
3. For **validation failure**: Run smoke/health checks locally against base (or tenant) URLs; fix app or config and re-run pipeline.
4. For **infrastructure failure**: Check CloudFormation events in the target AWS account; fix template or parameters and re-run. Use `./scripts/deploy-stack.sh` for a single stack or `./scripts/deploy-tenant.sh <tenant-id> [environment]` for the tenant root stack.
5. For **tenant-specific failure**: Check that tenant’s account (IAM, network, secrets); compare with a working tenant. Confirm tenant exists in `config/tenant-registry.yaml`; run `./scripts/get-tenant-envs.sh <tenant-id>` and `./scripts/get-tenant-region.sh <tenant-id>` to verify registry resolution.
6. Log finding in Jira and link to pipeline run.

All documentation is in `./docs`; see [README](README.md) for the full index.
