# Runbooks: Deploy, Promote, Rollback

Short operational procedures for the multi-tenant deployment framework. Assumes Bitbucket Pipelines, AWS CloudFormation, and tenant registry are in place.

## 1. Deploy to Base Tenant

**When**: Every merge to `main` (or configured branch).

**Steps**:
1. Push/merge to `main` in the application (or infra) repo.
2. Bitbucket Pipeline runs automatically: Build → Deploy to Base → Validate.
3. Check pipeline result:
   - **Success**: Base tenant is updated; proceed to “Promote to Tenants” when ready.
   - **Failure**: Fix code/config, push again; check Jira for linked ticket status.
4. Confirm in Jira that deployment status was updated (if integrated).

**Rollback (base only)**: Use “Rollback a Tenant” below with tenant ID = `base`.

---

## 2. Promote to Tenants

**When**: After base deployment is validated and approval is granted.

**Steps**:
1. Open the pipeline run that deployed to base (on `main`).
2. Run the **manual “Approval for promotion”** step if required.
3. Run the **“Promote to Tenants”** step. When prompted (or via variables), set:
   - **Single**: `PROMOTE_TENANTS=abc`
   - **Multiple**: `PROMOTE_TENANTS=abc,xyz`
   - **All**: `PROMOTE_TENANTS=all`
   - **None**: Do not run the step.
4. Verify pipeline log for “Promotion” section: list of tenants and success/fail per tenant.
5. Check deployment history (dashboard or logs) and Jira for traceability.

**If one tenant fails**: Other tenants remain unchanged (silo). Fix the failing tenant (config/network/perms) and re-run promotion for that tenant only, or run rollback for that tenant and then fix and re-promote.

---

## 3. Rollback a Tenant

**When**: A tenant has a bad deployment or failed migration and must be reverted.

**Steps**:
1. Identify **tenant ID** and, if needed, **target version** (e.g. previous app version).
2. Run rollback script or pipeline:
   - A dedicated `scripts/rollback-tenant.sh` is not yet implemented; redeploy the previous app version using `scripts/deploy-tenant-env.sh` with the target tenant and version/parameters, or use a "Rollback" pipeline with variables for tenant and version when available.
3. Script/pipeline will:
   - Deploy previous (or specified) app version to that tenant.
   - If DB rollback is required: follow DB runbook (RDS restore from snapshot or Flyway undo).
4. Verify app and DB for that tenant; check deployment history and logs.
5. Update Jira if needed (e.g. comment “Rolled back abc to v1.2.3”).

**DB-only rollback**: If only DB migration must be reverted, use RDS point-in-time restore or snapshot restore for that tenant’s DB, then align app version if necessary.

---

## 4. Add a New Tenant

**When**: Onboarding a new silo tenant.

**Steps**:
1. Create AWS account (via LZA or org process); note account ID.
2. Add tenant to **tenant registry** (`config/tenant-registry.yaml`): add a new key (e.g. `new-tenant`) with `name`, `region`, and `environments` (e.g. `[prod]`). See existing entries (base, abc, xyz) for the schema.
3. Commit and merge registry change.
4. Run infrastructure pipeline (or manual CloudFormation) to deploy stacks for the new tenant (network, security, data, compute) using the new tenant id and account.
5. Store secrets (DB, app config) in that account’s Secrets Manager (or Parameter Store).
6. When ready, include this tenant in promotion (e.g. `PROMOTE_TENANTS=new-tenant` or add to “all” when enabled).

---

## 5. Investigate Failed Deployment or Validation

**Steps**:
1. Open Bitbucket pipeline run → check failed step and logs.
2. Check **central dashboard** for deployment status and any alerts.
3. For **validation failure**: Run smoke/health checks locally against base (or tenant) URLs; fix app or config and re-run pipeline.
4. For **infrastructure failure**: Check CloudFormation events in the target AWS account; fix template or parameters and re-run.
5. For **tenant-specific failure**: Check that tenant’s account (IAM, network, secrets); compare with a working tenant’s config.
6. Log finding in Jira and link to pipeline run.

All documentation is in `./docs`; see [README](README.md) for the full index.
