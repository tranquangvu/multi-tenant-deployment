# Architecture and Tenant Model (ST-156)

This document defines the multi-tenant structure: base tenant, silo tenants, metadata schema, and naming conventions. It satisfies **ST-156** deliverables.

## 1. Architecture Overview

- **Base tenant (foundation)**: Single environment used for first deployment and validation. All code and infrastructure changes deploy here first.
- **Silo tenants**: Each tenant has isolated environments per application — own database, configuration, and secrets. No shared runtime state between tenants.
- **7 applications**: Each app has one environment per tenant (base + N tenants). Deployments are validated in base, then promoted to selected tenants.

```
                    ┌─────────────────────────────────────────────────────────┐
                    │                  Bitbucket Pipelines                     │
                    │  (Build → Deploy Base → Validate → Approve → Promote)   │
                    └───────────────────────────┬─────────────────────────────┘
                                                │
        ┌───────────────────────────────────────┼───────────────────────────────────────┐
        │                                       │                                       │
        ▼                                       ▼                                       ▼
┌───────────────┐                     ┌─────────────────┐                     ┌─────────────────┐
│  Base Tenant  │                     │  Tenant A       │                     │  Tenant B … N   │
│  (Foundation) │                     │  (Silo)         │                     │  (Silo)         │
├───────────────┤                     ├─────────────────┤                     ├─────────────────┤
│ App1 … App7   │                     │ App1 … App7     │                     │ App1 … App7     │
│ DB, config,  │                     │ DB, config,     │                     │ DB, config,     │
│ secrets each  │                     │ secrets each    │                     │ secrets each    │
└───────┬───────┘                     └────────┬────────┘                     └────────┬────────┘
        │                                      │                                       │
        └──────────────────────────────────────┼───────────────────────────────────────┘
                                               │
                                    ┌──────────▼──────────┐
                                    │ Central Log Account │
                                    │ (LZA-style)         │
                                    └────────────────────┘
```

## 2. Tenant Metadata Schema

Tenant metadata is stored in a **central configuration repository** (Bitbucket), in a single registry file. Suggested format: YAML (or JSON).

### 2.1 Schema (YAML)

```yaml
# tenant-registry.yaml
version: "1.0"
updated_at: "2025-03-03"

tenants:
  base:
    id: base
    name: Foundation
    type: base
    enabled: true
    region: us-east-1
    aws_account_id: "111111111111"
    status: active
    description: First deployment target; validation environment.

  tenant-a:
    id: tenant-a
    name: Tenant A
    type: silo
    enabled: true
    region: us-east-1
    aws_account_id: "222222222222"
    status: active
    description: Production tenant A.

  tenant-b:
    id: tenant-b
    name: Tenant B
    type: silo
    enabled: true
    region: eu-west-1
    aws_account_id: "333333333333"
    status: active
```

### 2.2 Field Definitions

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique tenant identifier; used in pipelines and CloudFormation parameters. |
| `name` | string | Human-readable name. |
| `type` | enum | `base` \| `silo`. |
| `enabled` | boolean | If `false`, tenant is skipped for promotions. |
| `region` | string | Primary AWS region for this tenant. |
| `aws_account_id` | string | AWS account ID (for multi-account model). |
| `status` | string | e.g. `active`, `maintenance`, `deprecated`. |
| `description` | string | Optional notes. |

Optional extensions (for promotion and versioning):

- `current_version` / `last_deployed_at`: Updated by pipeline or external process.
- `approval_required`: Boolean to enforce approval for this tenant.

## 3. App-to-Tenant Mapping

- Each of the **7 applications** has one environment per tenant.
- Mapping is implicit: **App × Tenant** = one environment (one DB, one config, one set of secrets).
- Document the list of application IDs in the same config repo, e.g.:

```yaml
# apps-registry.yaml (optional, or in same file as tenant-registry)
applications:
  - id: app1
    name: Application One
  - id: app2
    name: Application Two
  # ... app3 .. app7
```

- Deployment matrix: for each promotion run, pipeline reads `tenant-registry.yaml` and optionally `apps-registry.yaml` to decide target tenants (and which apps to deploy where).

## 4. Naming Conventions

### 4.1 AWS Accounts

- **Base tenant**: `{org}-base-{env}` or `{org}-foundation-{env}` (e.g. `acme-base-prod`).
- **Silo tenants**: `{org}-tenant-{tenant-id}` (e.g. `acme-tenant-tenant-a`).
- **Central log account**: `{org}-log` or `{org}-central-log`.

### 4.2 CloudFormation Stacks

- **Base tenant**: `{stack-prefix}-base-{layer}` e.g. `mt-base-network`, `mt-base-app1`.
- **Per tenant**: `{stack-prefix}-{tenant-id}-{layer}` e.g. `mt-tenant-a-network`, `mt-tenant-a-app1`.
- **Shared (if any)**: `{stack-prefix}-shared-{purpose}`.

### 4.3 Bitbucket Repositories

- **Application code**: `{org}/{app-id}` or `{org}/{app-id}-service`.
- **Configuration / tenant registry**: `{org}/tenant-config` or `{org}/multi-tenant-config`.
- **Infrastructure (CloudFormation)**: `{org}/infrastructure` or `{org}/multi-tenant-iac`.

### 4.4 Pipelines

- **Main deployment pipeline**: e.g. `Deploy to Base` then `Promote to Tenants` (stages in one `bitbucket-pipelines.yml` or separate pipeline for promotion).
- **Branch strategy**: e.g. `main` → deploy to base; promotion triggered manually or via custom branch/tag.

### 4.5 Resources Within AWS

- **Resource tags**: Enforce `TenantId`, `ApplicationId`, `Environment`, `ManagedBy=CloudFormation`.
- **Names**: `{tenant-id}-{app-id}-{resource-type}` e.g. `base-app1-rds`, `tenant-a-app2-s3-bucket`.

## 5. Definition of Done (ST-156)

- [ ] Architecture diagram (above) approved and stored in `./docs`.
- [ ] Tenant metadata schema (YAML/JSON) defined and version-controlled in Bitbucket.
- [ ] Tenant configuration registry file created in central config repo.
- [ ] Naming convention document (this section) approved and linked from master plan.
- [ ] App-to-tenant mapping documented (applications list and deployment matrix).
