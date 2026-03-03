# AWS and CloudFormation Design

This document describes the AWS account strategy, alignment with AWS Landing Zone (LZA), and the CloudFormation (IaC) design for the multi-tenant system.

## 1. AWS Account Strategy

### 1.1 Option A: Multi-Account (Recommended for LZA)

- **One AWS account per tenant** (base + each silo tenant).
- **Separate central account** for logging (and optionally security, shared services).
- Aligns with AWS Landing Zone Accelerator (LZA) and best practices for isolation and governance.

| Account purpose | Naming example | Usage |
|-----------------|----------------|--------|
| Base (foundation) | `{org}-base` | First deployment, validation, smoke tests. |
| Silo tenant A | `{org}-tenant-tenant-a` | Isolated env for tenant A (all 7 apps). |
| Silo tenant B … N | `{org}-tenant-{id}` | Same for other tenants. |
| Central log | `{org}-log` | Log aggregation from all tenant accounts. |

### 1.2 Option B: Single Account, Multiple VPCs/Environments

- One AWS account; each tenant is a separate VPC (or separate namespace/stacks).
- Simpler to start; less isolation. Use if multi-account is not yet in place.
- CloudFormation stacks still use `TenantId` parameter for separation.

Recommendation: Prefer **Option A** for production and compliance; use **Option B** only for PoC or constrained environments.

## 2. AWS Landing Zone (LZA) Alignment

- Use **AWS Landing Zone Accelerator (LZA)** or existing Landing Zone for:
  - **Account vending**: New tenant = new account via LZA.
  - **Governance**: SCPs, guardrails, centralized identity (e.g. IAM Identity Center).
  - **Centralized logging**: All accounts send logs to the central log account (e.g. CloudWatch Logs, or S3 → OpenSearch).
- Ensure base and tenant accounts are part of the same LZA organization; log account receives cross-account log streams.

## 3. CloudFormation Stack Design

### 3.1 Principles

- **Reusable templates**: Same templates for base and every tenant; parameterize by `TenantId`, `AWS::AccountId`, region.
- **Layered stacks**: Network → Security/Secrets → Data (RDS) → Compute (ECS/Lambda/App) so that dependencies are clear and rollback is manageable.
- **No hardcoded tenant data**: Tenant-specific values come from parameters or SSM Parameter Store (populated from tenant registry or pipeline).

### 3.2 Suggested Stack Layout (Per Tenant / Base)

For each tenant (including base), use a small set of stacks:

| Layer | Stack name pattern | Contents |
|-------|--------------------|----------|
| Network | `{prefix}-{tenant-id}-network` | VPC, subnets, NAT, VPC endpoints. |
| Security | `{prefix}-{tenant-id}-security` | IAM roles, security groups, KMS (optional). |
| Secrets | `{prefix}-{tenant-id}-secrets` | Secrets Manager (or Parameter Store) placeholders. |
| Data (per app or shared) | `{prefix}-{tenant-id}-app{N}-data` or `-data` | RDS, ElastiCache, etc. |
| Compute (per app) | `{prefix}-{tenant-id}-app{N}-compute` | ECS cluster/service, Lambda, etc. |

- **Base tenant**: `tenant-id = base`; same template set.
- **Pipeline**: For each target tenant, assume role in that account and run `aws cloudformation deploy` (or create/update stack) with the same template and tenant-specific parameters.

### 3.3 Parameter Strategy

- **Required parameters**: `TenantId`, `Environment`, `AWSRegion` (and optionally `AWSAccountId` for cross-account).
- **Per-application**: `ApplicationId` for app-level stacks.
- **Secrets**: Do not store secrets in template; use Secrets Manager ARNs or Parameter Store names as parameters, or resolve in pipeline and pass as parameter overrides.

### 3.4 Nested vs Flat Stacks

- **Nested stacks**: Use a root stack per tenant that includes child stacks (network, security, data, compute). Eases single-command deploy; harder to partial update.
- **Flat stacks**: Pipeline deploys each stack separately in order. Better for selective updates and rollback of a single layer.
- Recommendation: Start with **flat stacks** and a clear order in the pipeline; introduce a root stack later if desired.

### 3.5 Directory Layout (IaC Repo)

```
infrastructure/   (or cloudformation/)
├── templates/
│   ├── network.yaml
│   ├── security.yaml
│   ├── secrets.yaml
│   ├── data-app.yaml      # e.g. RDS per app
│   └── compute-app.yaml   # e.g. ECS/Lambda per app
├── parameters/
│   ├── base/
│   │   └── base-params.json
│   └── tenants/
│       ├── tenant-a-params.json
│       └── ...
├── scripts/
│   ├── deploy-stack.sh
│   └── destroy-stack.sh
└── docs/
    └── (link to ./docs in repo root)
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

## 7. Definition of Done (Infrastructure)

- [ ] Account strategy (multi-account vs single-account) decided and documented.
- [ ] CloudFormation templates for base tenant implemented and deployable.
- [ ] Templates parameterized by `TenantId` (and app where needed).
- [ ] Parameter files or pipeline logic to supply tenant-specific values from tenant registry.
- [ ] Central log account design and cross-account log shipping approach documented.
- [ ] Pipeline IAM roles and permissions documented (and implemented in Bitbucket + AWS).
