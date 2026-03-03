# Multi-Tenant Infrastructure — Master Plan

This document is the master plan for designing and implementing the complete infrastructure for the multi-tenant system as specified in **ST-67** and its subtasks. It uses **AWS**, **Bitbucket Pipelines**, and **AWS CloudFormation** for IaC.

## 1. Scope Summary

- **Base tenant**: First deployment target for all code and infrastructure changes; validation environment.
- **7 applications**: Each in silo mode per tenant (isolated DB, config, secrets).
- **Flow**: Deploy to base → validate → selectively promote to one, many, or all tenants.
- **Tools**: Bitbucket (VCS + pipelines), Jira (traceability), Flyway (DB migrations), AWS (Landing Zone / multi-account), CloudFormation (IaC).

## 2. Traceability to Requirements

| Requirement | Focus | Doc Reference |
|-------------|--------|----------------|
| **ST-67** | Multi-tenant deployment framework, base tenant, promotion, rollback, observability | All docs |
| **ST-156** | Tenant model, environment structure, metadata schema, naming | [02-architecture-and-tenant-model.md](02-architecture-and-tenant-model.md) |
| **ST-157** | CI/CD pipeline for base tenant, Bitbucket, Jira | [04-bitbucket-pipelines-and-cicd.md](04-bitbucket-pipelines-and-cicd.md) |
| **ST-158** | Flyway DB migrations, base-first then tenants | [05-database-migrations-and-rollback.md](05-database-migrations-and-rollback.md) |
| **ST-159** | Selective tenant promotion (single / set / all / none), audit | [04-bitbucket-pipelines-and-cicd.md](04-bitbucket-pipelines-and-cicd.md) |
| **ST-160** | Validation, approval workflow, smoke tests, health checks | [04-bitbucket-pipelines-and-cicd.md](04-bitbucket-pipelines-and-cicd.md) |
| **ST-161** | Rollback per tenant (app + DB) | [05-database-migrations-and-rollback.md](05-database-migrations-and-rollback.md) |
| **ST-162** | Centralized logging and monitoring | [06-logging-monitoring-and-operations.md](06-logging-monitoring-and-operations.md) |

## 3. High-Level Task Checklist

### Phase 1: Foundation and tenant model

- [ ] **1.1** Define and approve tenant model (base + N silo tenants) — ST-156  
- [ ] **1.2** Define tenant metadata schema (region, status, version, enablement) and version in Bitbucket — ST-156  
- [ ] **1.3** Define naming conventions for AWS accounts, pipelines, repos, stacks — ST-156  
- [ ] **1.4** Create central tenant configuration registry (e.g. `tenant-registry.yaml` / JSON) in config repo — ST-156  
- [ ] **1.5** Document app-to-tenant mapping and store in repo — ST-156  

### Phase 2: AWS and CloudFormation (IaC)

- [ ] **2.1** Design AWS account strategy (base tenant account, one account per tenant or OU structure) — ST-67  
- [ ] **2.2** Align with AWS Landing Zone / Landing Zone Accelerator (LZA) for governance — ST-67  
- [ ] **2.3** Design CloudFormation stack layout (shared vs per-tenant, nested stacks, parameters)  
- [ ] **2.4** Implement base-tenant infrastructure templates (VPC, compute/ECS/Lambda, RDS, secrets, IAM)  
- [ ] **2.5** Parameterize templates for tenant ID / account so same templates can deploy per tenant  
- [ ] **2.6** Define central log account and cross-account log shipping (per LZA) — ST-162  

### Phase 3: Bitbucket Pipelines and CI/CD

- [ ] **3.1** Implement main pipeline: build → deploy to base tenant — ST-157  
- [ ] **3.2** Integrate Jira (build/deploy status, transition on success/failure) — ST-157  
- [ ] **3.3** Add Flyway migration step (base tenant first) to pipeline — ST-158  
- [ ] **3.4** Add validation stage: smoke tests + health checks on base tenant — ST-160  
- [ ] **3.5** Add manual/approval gate before promotion to non-base tenants — ST-160  
- [ ] **3.6** Implement promotion stage with tenant selection (single / set / all / none) — ST-159  
- [ ] **3.7** Log deployment history and target tenant list for each promotion — ST-159  
- [ ] **3.8** Implement rollback pipeline or steps (per-tenant and optionally global) — ST-161  

### Phase 4: Database and rollback

- [ ] **4.1** Store Flyway migration scripts in repo; configure per-tenant DB connection — ST-158  
- [ ] **4.2** Document and implement rollback strategy (Flyway undo or snapshot restore) — ST-161  
- [ ] **4.3** Version/tag deployments per tenant for rollback — ST-161  

### Phase 5: Observability and compliance

- [ ] **5.1** Configure centralized log aggregation (e.g. CloudWatch Logs / OpenSearch in central account) — ST-162  
- [ ] **5.2** Configure cross-account logging from each tenant to central account — ST-162  
- [ ] **5.3** Set up deployment and validation metrics/dashboards per tenant — ST-162  
- [ ] **5.4** Configure alerts for failed deployments and validation errors — ST-162  
- [ ] **5.5** Ensure audit trails for deployments and config changes per tenant — ST-67  

### Phase 6: Documentation and governance

- [ ] **6.1** Document deployment flow, promotion steps, and approval workflow  
- [ ] **6.2** Document governance controls and runbooks (deploy, promote, rollback)  
- [ ] **6.3** Store all design docs in `./docs` and keep in sync with implementation  

## 4. Deliverables Summary

| Deliverable | Location / Tool |
|-------------|------------------|
| Architecture diagram | `02-architecture-and-tenant-model.md` |
| Tenant metadata schema | `02-architecture-and-tenant-model.md` + config repo |
| Naming conventions | `02-architecture-and-tenant-model.md` |
| Tenant registry (central config) | Config repo (Bitbucket) |
| CloudFormation templates | IaC repo (e.g. `cloudformation/` or `infrastructure/`) |
| Bitbucket pipeline definitions | Application/config repos (`bitbucket-pipelines.yml`) |
| Flyway migrations | Per-app repos or shared migrations repo |
| Rollback scripts / docs | Repo + `05-database-migrations-and-rollback.md` |
| Central logging/monitoring design | `06-logging-monitoring-and-operations.md` |
| Deployment and promotion docs | `04-bitbucket-pipelines-and-cicd.md`, runbooks in `./docs` |

## 5. Design Principles

- **Silo isolation**: One tenant’s failure must not affect others; separate DB, config, and secrets per tenant.
- **Base-first**: All changes land in base tenant before any promotion.
- **Repeatable**: Same CloudFormation and pipeline logic for every tenant; parameterize by tenant.
- **Auditable**: Deployment history, promotion targets, and approvals logged and traceable to Jira.
- **Scalable**: Tenant registry and parameterized IaC support adding new tenants with minimal manual work.

## 6. Next Steps

1. Review and approve [02-architecture-and-tenant-model.md](02-architecture-and-tenant-model.md) (tenant model and naming).  
2. Implement CloudFormation for base tenant per [03-aws-and-cloudformation-design.md](03-aws-and-cloudformation-design.md).  
3. Implement Bitbucket pipeline per [04-bitbucket-pipelines-and-cicd.md](04-bitbucket-pipelines-and-cicd.md).  
4. Integrate Flyway and rollback per [05-database-migrations-and-rollback.md](05-database-migrations-and-rollback.md).  
5. Configure logging and monitoring per [06-logging-monitoring-and-operations.md](06-logging-monitoring-and-operations.md).
