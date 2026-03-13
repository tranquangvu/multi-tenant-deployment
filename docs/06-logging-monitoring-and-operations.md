# Logging, Monitoring, and Operations (ST-162)

This document describes **centralized logging**, **monitoring**, and **alerting** across all tenant environments, with a central log account aligned to AWS Landing Zone (LZA) best practices. It satisfies **ST-162**.

## 1. Centralized Logging (LZA-Style)

### 1.1 Architecture

- **Central log account**: Dedicated AWS account (e.g. `{org}-log`) that receives logs from all tenant accounts (including base).
- **Per-tenant accounts**: Application logs, pipeline logs, and CloudFormation/API logs are shipped to the central account (e.g. via CloudWatch Logs subscription filters, Kinesis Data Streams, or S3 replication).

### 1.2 Log Sources to Aggregate

| Source | Location | How to ship to central |
|--------|----------|------------------------|
| Application logs | CloudWatch Log groups per tenant/app | Cross-account subscription or Kinesis |
| Pipeline logs | Bitbucket (and optionally S3 in each account) | Push pipeline summary to S3/CloudWatch in central account |
| CloudFormation / Control plane | CloudTrail + CloudWatch in each account | CloudTrail to central S3; optional CloudWatch Events |
| Deployment history | Pipeline writes to S3 or DynamoDB | Same or central account; central dashboard reads from there |

### 1.3 Implementation Options

- **CloudWatch Logs**: In each tenant account, create subscription filter on relevant log groups → Kinesis Data Stream or cross-account destination → central account ingests into CloudWatch Logs or OpenSearch.
- **OpenSearch**: Central account runs OpenSearch (or Amazon OpenSearch Serverless); ingest from Kinesis or Lambda that reads from tenant log streams.
- **S3**: Export logs to S3 in each account, replicate to central S3 bucket (same region or cross-region); use Athena or OpenSearch to query.

### 1.4 Retention and Access

- Define retention (e.g. 90 days hot, then archive to S3/Glacier) in central account.
- Restrict access to central log account via IAM and, if needed, SCPs; only platform/DevOps roles can read.

## 2. Monitoring and Dashboards

### 2.1 Metrics to Track

- **Deployment status**: Success/failure per pipeline run, per tenant (from deployment history or pipeline-written metrics).
- **Validation**: Smoke test and health check results (pass/fail, duration).
- **Application health**: Per-tenant and per-app metrics (request count, errors, latency) from load balancer or application.

### 2.2 Dashboards

- **Per-tenant dashboard**: Key metrics and recent deployments for one tenant (e.g. CloudWatch dashboard or Grafana).
- **Central dashboard**: All tenants: deployment status, validation status, and alerts. Use CloudWatch dashboards or Grafana with data from central account.

### 2.3 Alerts (ST-162)

- **Failed deployment**: Pipeline fails on base or on a tenant → trigger alert (SNS → email/Slack/PagerDuty).
- **Validation errors**: Smoke test or health check failure → alert before promotion (and block promotion).
- **Application errors**: Per-tenant alarms (e.g. 5xx rate, latency p99) in CloudWatch; notify on-call.

## 3. Audit Trails (ST-67)

- **Deployments**: Every deploy and promotion logged with timestamp, tenant(s), version, and operator (or pipeline ID). Stored in deployment history (S3/DynamoDB) and/or central logs.
- **Configuration changes**: Tenant registry and parameter changes in Bitbucket (git history). Optionally mirror “who changed what” into central log or SIEM.
- **Infrastructure changes**: CloudTrail in each account (and aggregated in central) records CloudFormation and API calls; retain for compliance.

## 4. Operations Runbooks (High Level)

- **Deploy to base**: Run main pipeline on `main`; ensure build → deploy-base → validate pass.
- **Promote to tenants**: After approval, set `PROMOTE_TENANTS` and run promote step; verify deployment history and Jira.
- **Rollback a tenant**: Run rollback script with tenant ID (and optional version); verify app and DB state; update Jira and deployment log.
- **Investigate failed deployment**: Check pipeline logs, central dashboard, and tenant-specific CloudWatch/OpenSearch logs.
- **Add a new tenant**: Add tenant to tenant registry; create AWS account (LZA); run CloudFormation for new tenant; add to promotion list when ready.

## 5. Definition of Done (ST-162)

- [ ] Centralized log aggregation account configured (CloudWatch and/or OpenSearch).
- [ ] Logs from all tenant environments (including base) visible in central dashboard or queryable in central account.
- [ ] Deployment logs and deployment status visible in central dashboard.
- [ ] Alerts triggered on failed deployments or validation errors.
- [ ] Monitoring verified for all applications (per-tenant or aggregate as designed; see `config/app-registry.yaml` for current app list).
- [ ] Audit trails for deployments and configuration changes in place and documented.
