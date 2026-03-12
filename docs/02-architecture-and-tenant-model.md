# Architecture and Tenant Model (ST-156)

This document defines the multi-tenant structure: base tenant, silo tenants, metadata schema, and naming conventions. It satisfies **ST-156** deliverables.

## 1. Architecture Overview

- **Base tenant (foundation)**: Single environment used for first deployment and validation. All code and infrastructure changes deploy here first.
- **Silo tenants**: Each tenant has isolated environments per application — own database, configuration, and secrets. No shared runtime state between tenants.
- **Applications**: Each app has one environment per tenant (base + N tenants). Current implementation: 2 apps (foo, baz). Deployments are validated in base, then promoted to selected tenants.

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
│ Apps (foo, baz) │                    │ Apps (foo, baz) │                    │ Apps (foo, baz) │
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
# config/tenant-registry.yaml
# Base has staging + production; other tenants have production only.

tenants:
  base:
    name: Base
    region: ap-southeast-1
    environments: [staging, production]
    # Future (Landing Zone): account per environment
    # accounts:
    #   staging: "111111111111"
    #   production: "222222222222"

  abc:
    name: ABC
    region: ap-southeast-1
    environments: [production]
    # accounts:
    #   production: "333333333333"

  xyz:
    name: XYZ
    region: ap-southeast-1
    environments: [production]
    # accounts:
    #   production: "444444444444"
```

### 2.2 Field Definitions

The current registry (`config/tenant-registry.yaml`) uses **name**, **region**, and **environments** per tenant. The tenant key (e.g. `base`, `abc`) is the tenant identifier in pipelines and CloudFormation.

| Field            | Type    | Description                                                                 |
| ---------------- | ------- | --------------------------------------------------------------------------- |
| *(key)*          | string  | Tenant identifier (e.g. `base`, `abc`, `xyz`)                               |
| `name`           | string  | Human-readable name.                                                        |
| `region`         | string  | Primary AWS region for this tenant.                                         |
| `environments`   | array   | Environments for this tenant: `[staging, production]`                       |

Optional extensions (for promotion and versioning):

- `current_version` / `last_deployed_at`: Updated by pipeline or external process.
- `approval_required`: Boolean to enforce approval for this tenant.

## 3. App-to-Tenant Mapping

- Each application has one environment per tenant. The current implementation uses **2 applications** (foo, baz), defined in `config/apps-registry.yaml`; the design supports adding more.
- Mapping is implicit: **App × Tenant** = one environment (one DB, one config, one set of secrets).
- Document the list of application IDs in the same config repo, e.g.:

```yaml
# config/apps-registry.yaml
applications:
  - id: foo
    name: FooApp
  - id: baz
    name: BazApp
```

- Deployment matrix: for each promotion run, pipeline reads `config/tenant-registry.yaml` and optionally `config/apps-registry.yaml` to decide target tenants (and which apps to deploy where).

## 4. Naming Conventions

### 4.1 AWS Accounts

- **Base tenant**: `{org}-base-{env}` or `{org}-foundation-{env}` (e.g. `acme-base-production`).
- **Silo tenants**: `{org}-tenant-{tenant-id}` (e.g. `acme-tenant-abc`).
- **Central log account**: `{org}-log` or `{org}-central-log`.

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

## 5. Definition of Done (ST-156)

- [ ] Architecture diagram (above) approved and stored in `./docs`.
- [ ] Tenant metadata schema (YAML/JSON) defined and version-controlled in Bitbucket.
- [ ] Tenant configuration registry file created (e.g. `config/tenant-registry.yaml` in this repo).
- [ ] Naming convention document (this section) approved and linked from master plan.
- [ ] App-to-tenant mapping documented (applications list and deployment matrix).
