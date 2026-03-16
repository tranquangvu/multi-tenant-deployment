# Architecture and Tenant Model

This document defines the multi-tenant structure: base tenant, silo tenants, metadata schema, and naming conventions.

## 1. Architecture Overview

- **Landing zone with multiple accounts**: The design uses an **AWS Landing Zone (LZA)** with **one AWS account per tenant** plus a **central log account**. Pipelines assume roles in each target account to deploy; isolation and governance follow LZA best practices.
- **Base tenant (foundation)**: Single environment used for first deployment and validation; runs in its own AWS account. All code and infrastructure changes deploy here first.
- **Silo tenants**: Each tenant has its own AWS account and isolated environments per application — own database, configuration, and secrets. No shared runtime state between tenants.
- **Applications**: Each app has one environment per tenant (base + N tenants). Current implementation: 2 apps (foo, baz). Deployments are validated in base, then promoted to selected tenants.

```
                         ┌─────────────────────────────────────────────────────────┐
                         │                  Bitbucket Pipelines                    │
                         │  (Build → Deploy Base → Validate → Approve → Promote)   │
                         └───────────────────────────┬─────────────────────────────┘
                                                     │
                         ┌───────────────────────────▼───────────────────────────────┐
                         │              AWS Organization / Landing Zone (LZA)        │
                         │                  Multiple accounts per tenant             │
                         │                                                           │
     ┌───────────────────┼───────────────────┬───────────────────┬───────────────────┼───────────────────┐
     │                   │                   │                   │                   │                   │
     ▼                   ▼                   ▼                   ▼                   ▼                   │
┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌─────────────────────────┐      │
│ AWS Account │   │ AWS Account │   │ AWS Account │   │ AWS Account │   │ Central Log Account     │      │
│   (Base)    │   │ (Tenant A)  │   │ (Tenant B)  │   │ (Tenant …N) │   │ (org-log / LZA-style)   │      │
├─────────────┤   ├─────────────┤   ├─────────────┤   ├─────────────┤   ├─────────────────────────┤      │
│ Base Tenant │   │ Tenant A    │   │ Tenant B    │   │ Tenant N    │   │ Log aggregation from    │      │
│ (Foundation)│   │ (Silo)      │   │ (Silo)      │   │ (Silo)      │   │ all workload accounts   │◄──-──┘
├─────────────┤   ├─────────────┤   ├─────────────┤   ├─────────────┤   └────────────▲────────────┘
│ Apps:       │   │ Apps:       │   │ Apps:       │   │ Apps:       │                │
│ foo, baz    │   │ foo, baz    │   │ foo, baz    │   │ foo, baz    │   cross-account log shipping
│ DB, config, │   │ DB, config, │   │ DB, config, │   │ DB, config, │   from base + all tenant accounts
│ secrets     │   │ secrets     │   │ secrets     │   │ secrets     │
└─────────────┘   └─────────────┘   └─────────────┘   └─────────────┘
```

## 2. Tenant Metadata Schema

Tenant metadata is stored in a **central configuration repository** (Bitbucket), in a single registry file. Suggested format: YAML (or JSON).

### 2.1 Schema (YAML)

```yaml
# config/tenant-registry.yaml
# Landing zone: one AWS account per tenant (and optionally per environment).
# Base has staging + production; other tenants have production only.

tenants:
  base:
    name: Base
    region: ap-southeast-1
    environments: [staging, production]
    accounts:
      staging: "111111111111"
      production: "222222222222"

  abc:
    name: ABC
    region: ap-southeast-1
    environments: [production]
    accounts:
      production: "333333333333"

  xyz:
    name: XYZ
    region: ap-southeast-1
    environments: [production]
    accounts:
      production: "444444444444"
```

### 2.2 Field Definitions

The current registry (`config/tenant-registry.yaml`) uses **name**, **region**, and **environments** per tenant. The tenant key (e.g. `base`, `abc`) is the tenant identifier in pipelines and CloudFormation.

| Field            | Type    | Description                                                                 |
| ---------------- | ------- | --------------------------------------------------------------------------- |
| *(key)*          | string  | Tenant identifier (e.g. `base`, `abc`, `xyz`)                               |
| `name`           | string  | Human-readable name.                                                        |
| `region`         | string  | Primary AWS region for this tenant.                                         |
| `environments`   | array   | Environments for this tenant: `[staging, production]`                       |
| `accounts`       | object  | *(Landing zone multi-account)* Map of environment → AWS account ID (e.g. `production: "333333333333"`). Pipeline uses this to assume role and deploy to the correct account. |

Optional extensions (for promotion and versioning):

- `current_version` / `last_deployed_at`: Updated by pipeline or external process.
- `approval_required`: Boolean to enforce approval for this tenant.

## 3. App-to-Tenant Mapping

- Each application has one environment per tenant. The current implementation uses **2 applications** (foo, baz), defined in `config/app-registry.yaml`; the design supports adding more.
- Mapping is implicit: **App × Tenant** = one environment (one DB, one config, one set of secrets).
- Document the list of application IDs in the same config repo, e.g.:

```yaml
# config/app-registry.yaml
applications:
  - id: foo
    name: FooApp
  - id: baz
    name: BazApp
```

- Deployment matrix: for each promotion run, pipeline reads `config/tenant-registry.yaml` and optionally `config/app-registry.yaml` to decide target tenants (and which apps to deploy where).

## 4. Naming Conventions

### 4.1 AWS Accounts (Landing Zone Multi-Account)

- **Base tenant**: One or more accounts, e.g. `{org}-base-staging`, `{org}-base-production` or a single `{org}-base` with environments inside.
- **Silo tenants**: One account per tenant: `{org}-tenant-{tenant-id}` (e.g. `acme-tenant-abc`).
- **Central log account**: `{org}-log` or `{org}-central-log`; receives cross-account logs from all workload accounts.
- All accounts sit under the same **AWS Organization / Landing Zone (LZA)** for governance, SCPs, and centralized logging.

### 4.2 CloudFormation Stacks

- **Base tenant**: `{stack-prefix}-base-{layer}` e.g. `mt-base-network`, `mt-base-foo` (or per-app stack).
- **Per tenant**: `{stack-prefix}-{tenant-id}-{layer}` e.g. `mt-abc-network`, `mt-abc-foo`.
- **Shared (if any)**: `{stack-prefix}-shared-{purpose}`.

### 4.3 Bitbucket Repositories

- **Application code**: `{org}/{app-id}` or `{org}/{app-id}-service`.
- **Configuration / tenant registry**: `{org}/tenant-config` or `{org}/multi-tenant-config`.
- **Infrastructure (CloudFormation)**: `{org}/infrastructure` or `{org}/multi-tenant-iac`.

### 4.4 Pipelines

- **Main deployment pipeline**: e.g. `Deploy to Base` then `Promote to Tenants` (stages in one `bitbucket-pipelines.yml` or separate pipeline for promotion).
- **Branch strategy**: e.g. `main` → deploy to base; promotion triggered manually or via custom branch/tag.

### 4.5 Resources Within AWS

- **Resource tags**: Enforce `TenantId`, `AppId`, `Environment`, `ManagedBy=CloudFormation`.
- **Names**: `{tenant-id}-{app-id}-{resource-type}` e.g. `base-foo-rds`, `abc-baz-s3-bucket`.
