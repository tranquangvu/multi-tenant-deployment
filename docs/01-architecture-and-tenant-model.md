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
# Landing zone: typically one AWS account per tenant (and optionally per environment).
# Base has staging + production; other tenants have production only.
# Scripts (e.g. deploy-tenant.sh) read region, accountId, and network names to merge SSM paths.

tenants:
  base:
    id: base
    name: Base
    region: ap-southeast-1
    # Optional: ssmNetworkPrefix — root for SSM paths (default /accelerator/network; overridable via SSM_NETWORK_PREFIX).
    environments:
      staging:
        accountId: "111111111111"
        accountName: org-base-staging
        networkVpcName: base-staging-vpc
        networkPublicSubnetNames: [public-subnet-a, public-subnet-b]
        networkPrivateSubnetNames: [private-subnet-a, private-subnet-b]
      production:
        accountId: "222222222222"
        accountName: org-base-production
        networkVpcName: base-production-vpc
        networkPublicSubnetNames: [public-subnet-a, public-subnet-b]
        networkPrivateSubnetNames: [private-subnet-a, private-subnet-b]

  abc:
    id: abc
    name: ABC
    region: ap-southeast-1
    environments:
      production:
        accountId: "333333333333"
        accountName: org-tenant-abc
        networkVpcName: abc-vpc
        networkPublicSubnetNames: [public-subnet-a, public-subnet-b]
        networkPrivateSubnetNames: [private-subnet-a, private-subnet-b]

  xyz:
    id: xyz
    name: XYZ
    region: ap-southeast-1
    environments:
      production:
        accountId: "444444444444"
        accountName: org-tenant-xyz
        networkVpcName: xyz-vpc
        networkPublicSubnetNames: [public-subnet-a, public-subnet-b]
        networkPrivateSubnetNames: [private-subnet-a, private-subnet-b]
```

### 2.2 Field Definitions

The registry (`config/tenant-registry.yaml`) is keyed by **tenant id** (`base`, `abc`, `xyz`, …). That key matches `TenantId` in CloudFormation and pipeline variables. Each tenant includes **`id`** (same as the key), **`name`**, **`region`**, and a map **`environments`**.

| Field | Type | Description |
| ----- | ---- | ----------- |
| *(YAML key)* | string | Tenant identifier (`base`, `abc`, `xyz`). |
| `id` | string | Same as the tenant key; explicit id for scripts. |
| `name` | string | Human-readable name. |
| `region` | string | Primary AWS region for this tenant. |
| `ssmNetworkPrefix` | string | *(Optional.)* Root for Landing Zone SSM paths (e.g. `/accelerator/network`). If omitted, use env `SSM_NETWORK_PREFIX` or the default `/accelerator/network`. |
| `environments` | map | Keys: `staging` and/or `production`. **Base** has both; **abc** / **xyz** have **production** only. Values use the per-environment fields below. |

Per-environment fields (under `tenants.<tenant>.environments.<staging|production>`):

| Field | Type | Description |
| ----- | ---- | ----------- |
| `accountId` | string | AWS account ID for this (tenant, environment). `deploy-tenant.sh` compares this to `sts get-caller-identity` unless `SKIP_TENANT_ACCOUNT_CHECK=1`. |
| `accountName` | string | Display / documentation name for the account. |
| `networkVpcName` | string | VPC name segment used in SSM: `{prefix}/vpc/{networkVpcName}/id`. |
| `networkPublicSubnetNames` | array (2) | Two public subnet **names** for SSM subnet id paths (ALB). |
| `networkPrivateSubnetNames` | array (2) | Two private subnet **names** for SSM paths (RDS, ECS tasks). |

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

- **Root stack per (tenant, environment)**: `{stack-prefix}-{tenant-id}-{staging|production}` e.g. `mt-base-staging`, `mt-abc-production`. Nested stacks (security, RDS, ALB, ECS, …) are created inside that root.
- **Shared (ECR, etc.)**: `{stack-prefix}-shared` e.g. `mt-shared`.

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
