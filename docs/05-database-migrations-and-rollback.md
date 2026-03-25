# Database Migrations and Rollback

This document covers **Flyway** for database migrations and **per-tenant rollback** strategy.

## 1. Flyway Integration

### 1.1 Approach

- **Flyway** runs as part of the pipeline: first against the **base tenant** DB, then against each **selected tenant** DB during promotion.
- Migration scripts are stored in the **repository** (e.g. `db/migrations/` per application or in a dedicated migrations repo).
- Each tenant has its **own database** (and schema if multi-schema); Flyway connects using tenant-specific URL and credentials (from Secrets Manager or Parameter Store).

### 1.2 Directory Layout

```
<app-repo or migrations-repo>/
  db/
    migrations/
      V1__initial_schema.sql
      V2__add_feature_x.sql
      V3__add_index.sql
```

- Use **versioned** migrations only (V1, V2, …) for repeatable, ordered application.
- Optionally use **undo** migrations (Flyway Teams) for rollback; otherwise rely on restore/snapshot (see section 3).

### 1.3 Environment Configuration per Tenant

- **Pipeline**: For each target (base or tenant), retrieve DB URL and credentials from AWS Secrets Manager (or SSM) for that tenant and app.
- **Flyway config**: Use env vars or `flyway.conf` overrides (e.g. `FLYWAY_URL`, `FLYWAY_USER`, `FLYWAY_PASSWORD`) so the same scripts run against any tenant’s DB.
- Do **not** store credentials in repo; pipeline fetches them from AWS before invoking Flyway.

### 1.4 Pipeline Placement

- **Base tenant**: After CloudFormation and app deploy, run Flyway against base DB (in same stage or right after “Deploy to Base”).
- **Promotion**: For each promoted tenant, after deploying app to that tenant, run Flyway against that tenant’s DB. Order: infra → app → Flyway (or Flyway before app restart, depending on compatibility).

### 1.5 Acceptance Criteria

- [ ] Flyway migration scripts stored in repo.
- [ ] Successful DB migration to base tenant in pipeline.
- [ ] Migration tested and validated in pipeline (e.g. post-migration smoke or schema check).
- [ ] Migration process repeatable across tenants (same scripts, different URL/creds).
- [ ] Rollback strategy documented (below).

## 2. Rollback Strategy

### 2.1 Application Rollback (Per Tenant)

- **Versioned deployments**: Each deploy is tied to a **version/tag** (e.g. Docker image tag, S3 artifact version). Store “current version” per tenant (e.g. in SSM Parameter Store or DynamoDB).
- **Rollback**: Redeploy the **previous** version to the affected tenant(s). Pipeline can have a “rollback” mode: input = tenant ID + optional “target version”; script deploys that version and updates “current version”.
- **Scope**: Rollback one tenant at a time (silo); optional “global” rollback = roll back all tenants to previous version (use with care).

### 2.2 Database Rollback

**Option A – Flyway Undo (Flyway Teams)**
- Maintain undo migrations (U2, U1, …). On rollback, run Flyway undo to previous version.
- Requires Flyway Teams and disciplined undo script authoring.

**Option B – Snapshot / Point-in-Time Restore (Recommended)**
- **RDS**: Use automated backups and **point-in-time recovery** to restore to a time before the migration; then redeploy the previous app version.
- **Snapshot before migration**: Before running Flyway in pipeline, create a DB snapshot (RDS snapshot or export). If migration fails or rollback is needed, restore from snapshot and fix.

**Option C – Forward-only fix**
- Do not undo migration; add a new migration (V4) that reverts schema/data changes. Prefer when undo is complex or not available.

### 2.3 Rollback Pipeline / Scripts

- **Scripts**: e.g. `scripts/rollback-tenant.sh <tenant-id> [target-version]` (to be implemented) that:
  1. Looks up previous (or target) artifact version.
  2. Deploys that version to the tenant (CloudFormation if needed, then app deploy).
  3. For DB: either trigger RDS restore from snapshot (manual or automated) or run Flyway undo if in use.
  4. Logs rollback in deployment history and updates Jira if desired.
- **Pipeline**: Optional dedicated “Rollback” pipeline or manual step that calls these scripts with tenant and version inputs.

### 2.4 Acceptance Criteria

- [ ] Rollback can be executed per tenant.
- [ ] Pipeline (or script) logs reflect rollback actions.
- [ ] Rollback tested on at least one tenant successfully.
- [ ] Version tagging per tenant deployment in place.
- [ ] DB rollback approach (undo vs snapshot vs forward fix) documented and implemented.
