# Multi-Tenant Deployment Framework — Documentation

This directory contains the design and implementation documentation for the **Multi-Tenant Deployment Framework with Base Tenant**, using **AWS**, **Bitbucket Pipelines**, and **AWS CloudFormation** for Infrastructure as Code (IaC).

## Documentation Index

| Document | Description |
|----------|-------------|
| [01-infrastructure-plan.md](01-infrastructure-plan.md) | Master plan: scope, deliverables, task checklist, and traceability |
| [02-architecture-and-tenant-model.md](02-architecture-and-tenant-model.md) | Architecture diagram, tenant model, metadata schema, naming conventions |
| [03-aws-and-cloudformation-design.md](03-aws-and-cloudformation-design.md) | AWS account strategy, Landing Zone, CloudFormation stack design and IaC structure |
| [04-bitbucket-pipelines-and-cicd.md](04-bitbucket-pipelines-and-cicd.md) | CI/CD design: base tenant deployment, promotion, validation, Jira integration |
| [05-database-migrations-and-rollback.md](05-database-migrations-and-rollback.md) | Flyway migrations and per-tenant rollback strategy |
| [06-logging-monitoring-and-operations.md](06-logging-monitoring-and-operations.md) | Centralized logging, monitoring, alerting, and operations |
| [07-runbooks.md](07-runbooks.md) | Operational runbooks: deploy to base, promote, rollback, add tenant, troubleshoot |

## Quick Reference

- **Requirements**: Store requirement docs in `requirements/` as needed for traceability.
- **IaC**: AWS CloudFormation (templates and stack strategy in `03-aws-and-cloudformation-design.md`)
- **CI/CD**: Bitbucket Pipelines (design in `04-bitbucket-pipelines-and-cicd.md`)
- **Tenant config**: Central tenant registry and metadata (schema in `02-architecture-and-tenant-model.md`)
