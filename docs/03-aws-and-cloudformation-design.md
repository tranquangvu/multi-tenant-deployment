# AWS and CloudFormation Design

This document describes the AWS account strategy, alignment with **AWS Landing Zone (LZA) with multiple accounts**, and the CloudFormation (IaC) design for the multi-tenant system.

## 1. AWS Account Strategy

### 1.1 Landing Zone with Multiple Accounts (Recommended)

The design **supports and recommends** an **AWS Landing Zone (LZA)** where:

- **One AWS account per tenant** (base + each silo tenant); optionally one account per base environment (staging vs production).
- **One central account** for logging (and optionally security, shared services).
- All accounts live under the same **AWS Organization**; governance, SCPs, and identity (e.g. IAM Identity Center) are applied centrally.

```
     ┌─────────────────────────────────────────────────────────────────┐
     │                  AWS Organization / Landing Zone                 │
     ├─────────────┬─────────────┬─────────────┬─────────────┬──────────┤
     │ Base        │ Tenant A    │ Tenant B    │ Tenant …N   │ Central  │
     │ Account     │ Account     │ Account     │ Account     │ Log      │
     │ (foundation)│ (silo)      │ (silo)      │ (silo)      │ Account  │
     └─────────────┴─────────────┴─────────────┴─────────────┴──────────┘
```

| Account purpose | Naming example | Usage |
|-----------------|----------------|--------|
| Base (foundation) | `{org}-base` or `{org}-base-{env}` | First deployment, validation, smoke tests. |
| Silo tenant (e.g. abc) | `{org}-tenant-{tenant-id}` (e.g. `{org}-tenant-abc`) | Isolated env for that tenant (all apps per `config/app-registry.yaml`). |
| Silo tenant B … N | `{org}-tenant-{id}` | Same for other tenants. |
| Central log | `{org}-log` | Log aggregation from all tenant and base accounts. |

The **tenant registry** (`config/tenant-registry.yaml`) holds the mapping of tenant + environment → AWS account ID; the pipeline assumes a role in each target account to deploy. See [02-architecture-and-tenant-model.md](02-architecture-and-tenant-model.md) for the architecture diagram and schema.

### 1.2 Option B: Single Account, Multiple VPCs/Environments

- One AWS account; each tenant is a separate VPC (or separate namespace/stacks).
- Simpler to start; less isolation. Use if a multi-account landing zone is not yet in place.
- CloudFormation stacks still use `TenantId` parameter for separation.

Recommendation: Prefer **Option A (Landing Zone with multiple accounts)** for production and compliance; use **Option B** only for PoC or constrained environments.

## 2. AWS Landing Zone (LZA) Alignment

- Use **AWS Landing Zone Accelerator (LZA)** or an existing **Landing Zone with multiple accounts** for:
  - **Account vending**: New tenant = new account via LZA; base can have one account or one per environment.
  - **Governance**: SCPs, guardrails, centralized identity (e.g. IAM Identity Center).
  - **Centralized logging**: All workload accounts (base + tenants) send logs to the central log account (e.g. CloudWatch Logs cross-account subscription, or S3 → OpenSearch).
- Ensure base and all tenant accounts are part of the same LZA organization; the central log account receives cross-account log streams from every workload account.

## 3. CloudFormation Stack Design

### 3.1 Principles

- **Reusable templates**: Same templates for base and every tenant; parameterize by `TenantId`, `AWS::AccountId`, region.
- **Layered stacks**: Security/Secrets → Data (RDS) → Compute (ECS) with **VPC/subnets from LZ SSM** at the root (no dedicated network nested stack).
- **No hardcoded tenant data**: Tenant-specific values come from parameters or SSM Parameter Store (populated from tenant registry or pipeline).

### 3.2 Suggested Stack Layout (Per Tenant / Base)

For each tenant (including base), use a small set of stacks:

| Layer | Stack name pattern | Template | Contents |
|-------|--------------------|----------|----------|
| Network (LZ) | *(none — no nested stack)* | — | VPC and subnet IDs come from **SSM** (Landing Zone). Root `main.yaml` uses `AWS::SSM::Parameter::Value<…>` parameters; values are passed into security, ALB, RDS, and ECS modules. |
| Security | `{prefix}-{tenant-id}-security` | `security.yaml` | IAM roles, security groups, KMS (optional). |
| Secrets | per app | `secrets.yaml` | Secrets Manager (or Parameter Store) placeholders. |
| Data (per app) | e.g. RdsFooAppStack | `rds.yaml` | RDS per app. |
| ECR | per app | `ecr.yaml` (module), `shared/main.yaml` (nested root) | One ECR repository per app, shared by all tenants. `ecr.yaml` is the module uploaded to S3; `shared/main.yaml` is a nested root that calls it for all apps. Deploy with **`scripts/deploy-shared.sh`** once per account/region. Use image tags for environment. |
| ECS cluster | shared per tenant/env | `ecs-cluster.yaml` | ECS cluster. |
| Compute (per app) | e.g. EcsFooAppStack | `ecs-service.yaml` | ECS Fargate service per app. |
| ALB | shared per tenant/env | `alb.yaml` | Application Load Balancer. |

- **Base tenant**: `tenant-id = base`; same template set. Current implementation uses a **root stack** (`tenants/<tenant-id>/<env>/main.yaml`) that deploys these as nested stacks.
- **Pipeline**: For each target tenant, assume role in that account and run `aws cloudformation deploy` (or create/update stack) with the same template and tenant-specific parameters.

### 3.3 Parameter Strategy

- **Required parameters**: `TenantId`, `Environment`, `AWSRegion` (and optionally `AWSAccountId` for cross-account).
- **Per-application**: `AppId` for app-level stacks.
- **Secrets**: Do not store secrets in template; use Secrets Manager ARNs or Parameter Store names as parameters, or resolve in pipeline and pass as parameter overrides.

### 3.4 Nested vs Flat Stacks

- **Nested stacks**: Use a root stack per tenant that includes child stacks (security, secrets, RDS, ALB, ECS cluster, ECS services). Eases single-command deploy; harder to partial update.
- **Flat stacks**: Pipeline deploys each stack separately in order. Better for selective updates and rollback of a single layer.
- Recommendation: Start with **flat stacks** and a clear order in the pipeline; introduce a root stack later if desired.

### 3.5 Directory Layout (IaC Repo)

Current layout (root stack per tenant/environment with nested stacks):

```
├── config/
│   ├── tenant-registry.yaml   # config/tenant-registry.yaml in this repo
│   └── app-registry.yaml
├── templates/
│   ├── security.yaml
│   ├── secrets.yaml
│   ├── rds.yaml            # RDS per app
│   ├── ecs-cluster.yaml
│   ├── ecs-service.yaml    # ECS Fargate service per app
│   └── alb.yaml
├── shared/
│   └── ecr.yaml           # ECR per app; use image tags for environment (standalone stacks)
├── tenants/
│   ├── base/
│   │   └── staging/        # (or production)
│   │       ├── main.yaml   # root stack; nested stacks reference templates
│   │       └── params.json
│   └── <tenant-id>/
│       └── production/
│           ├── main.yaml
│           └── params.json
├── scripts/
│   ├── deploy-stack.sh
│   ├── deploy-tenant.sh
│   ├── get-tenant-envs.sh
│   ├── get-tenant-region.sh
│   └── upload-config-templates.sh
└── docs/
    └── (this documentation)
```

## 4. Base Tenant Resources (Checklist)

Ensure base tenant stacks provision at least:

- [ ] VPC and subnets (public/private).
- [ ] RDS (or equivalent) per application — or one DB with schema per app.
- [ ] Secrets Manager (or Parameter Store) for app config and DB credentials.
- [ ] Compute: ECS cluster + services, or Lambda, or EC2 — per application.
- [ ] IAM roles for pipeline (e.g. OIDC with Bitbucket) and for application runtime.
- [ ] Security groups and minimal network rules.
- [ ] (Optional) Application Load Balancer per app or shared ALB with host/path rules.

## 5. Central Log Account

- **Account**: Dedicated log account (e.g. `{org}-log`).
- **Ingestion**: From each tenant account, use CloudWatch Logs cross-account subscription or Kinesis Data Streams, or S3 replication to log account; then aggregate in OpenSearch or CloudWatch Logs Insights.
- **Resource policy**: Each tenant account’s log group (or Kinesis stream) allows the central log account to read.
- Document exact log sources (pipelines, app logs, CloudFormation events) in [06-logging-monitoring-and-operations.md](06-logging-monitoring-and-operations.md).

## 6. Pipeline Permissions (Bitbucket → AWS)

- **Option 1**: OIDC federation (Bitbucket Pipelines OIDC → AWS IAM role). No long-lived keys.
- **Option 2**: IAM user with access keys stored in Bitbucket repository variables (less secure).
- For each tenant account (and base): one role that the pipeline can assume (e.g. `BitbucketPipelineRole`) with permissions to create/update CloudFormation stacks, read parameters, and write to S3 (if using S3 for templates). Restrict by `TenantId` in resource tags or condition keys where possible.
