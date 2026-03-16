# Bitbucket Pipelines and CI/CD

This document describes the CI/CD design using **Bitbucket Pipelines** for base-tenant deployment, validation, selective promotion, and Jira integration (base tenant pipeline, selective promotion, validation and approval).

## 1. Deployment Flow Overview

```
  Commit to main (or release branch)
           │
           ▼
  ┌────────────────────┐
  │ Build & Package    │
  └─────────┬──────────┘
            │
            ▼
  ┌────────────────────┐
  │ Deploy to Base     │  ← CloudFormation + App deploy + Flyway (base)
  └─────────┬──────────┘
            │
            ▼
  ┌────────────────────┐
  │ Run Smoke Tests &  │  ← Automated validation
  │ Health Checks      │
  └─────────┬──────────┘
            │
      ┌─────┴─────┐
      │  Pass?    │── No ──► Fail pipeline, update Jira, no promotion
      └─────┬─────┘
            │
            Yes
            │
            ▼
  ┌────────────────────┐
  │ Manual Approval    │  ← Optional: Jira approval / Slack / manual step
  │ (for promotion)    │
  └─────────┬──────────┘
            │
            ▼
  ┌────────────────────┐
  │ Promote to         │  ← Single / set / all tenants (user choice)
  │ Selected Tenant(s) │
  └─────────┬──────────┘
            │
            ▼
  Log deployment history & update Jira
```

## 2. Pipeline Stages (bitbucket-pipelines.yml)

### 2.1 Stages Summary

| Stage | Trigger | Purpose |
|-------|--------|---------|
| **build** | On push/merge to `main` | Compile, test, package artifact (e.g. Docker image, ZIP). |
| **deploy-base** | After build | Deploy infra (CloudFormation) and app to **base** tenant; run Flyway for base DB. |
| **validate** | After deploy-base | Smoke tests + health checks against base tenant. |
| **approval** | Manual (or Jira-gated) | Gate before promotion. |
| **promote** | After approval, with input | Deploy same artifact to selected tenant(s). |

### 2.2 Branch Strategy

- **main** (or **release/**): Full flow → build → deploy-base → validate. Promotion is manual.
- **Feature branches**: Build and test only (no deploy to base), or deploy to a dev base if you have one.

### 2.3 Promotion Options

The promote stage must support:

- **Single tenant**: e.g. pipeline variable `PROMOTE_TENANTS=abc`
- **Multiple tenants**: e.g. `PROMOTE_TENANTS=abc,xyz`
- **All tenants**: `PROMOTE_TENANTS=all` (pipeline reads `config/tenant-registry.yaml` and promotes to all enabled silo tenants, e.g. abc, xyz)
- **None**: Do not run promote; validation only

Implementation: Use Bitbucket pipeline variables (or manual step input) to set `PROMOTE_TENANTS`. Pipeline parses this and, for each target tenant (e.g. abc, xyz), assumes role in that tenant’s account and runs the same deploy steps (CloudFormation + app + Flyway) for that tenant. Tenant list comes from `config/tenant-registry.yaml`.

### 2.4 Example Pipeline Skeleton

```yaml
# bitbucket-pipelines.yml (conceptual)
definitions:
  steps:
    - step: &build
        name: Build
        script:
          - ./scripts/build.sh
        artifacts:
          - dist/**

    - step: &deploy-base
        name: Deploy to Base Tenant
        deployment: base
        script:
          - ./scripts/deploy-tenant.sh base
        artifacts:
          - dist/**

    - step: &validate
        name: Validate Base Deployment
        script:
          - ./scripts/smoke-tests.sh base
          - ./scripts/health-checks.sh base

    - step: &promote
        name: Promote to Tenants
        trigger: manual
        script:
          - ./scripts/promote-tenants.sh $PROMOTE_TENANTS

pipelines:
  branches:
    main:
      - step: *build
      - step: *deploy-base
      - step: *validate
      - step:
          name: Approval for promotion
          trigger: manual
          script:
            - echo "Approve in Jira or run promote step"
      - step: *promote
```

- `deploy-tenant.sh` and `promote-tenants.sh` use AWS CLI and CloudFormation; they read tenant config from `config/tenant-registry.yaml` (in repo or from pipeline variables).
- **Jira integration**: Use Jira REST API or Bitbucket-Jira integration in script steps: update issue status/link build on success or failure (see section 4).

## 3. Validation and Approval

### 3.1 Automated Validation (Before Promotion)

- **Smoke tests**: Run against base tenant URLs/APIs after deploy (e.g. critical paths, login, key endpoints).
- **Health checks**: Call health endpoints per application; fail pipeline if any return non-2xx or unhealthy.
- Store base tenant endpoints in config or pipeline variables (from CloudFormation outputs or SSM).

### 3.2 Approval Gate

- **Manual step** in Bitbucket: “Approval for promotion” with `trigger: manual`.
- Optional: Use Jira transition (e.g. “Approve for production”) and a separate small pipeline or script that checks Jira issue state before running promote.
- Failed validation must **block** promotion (no manual override to skip, or only with a separate “override” variable and audit log).

## 4. Jira Integration

- **Build/deploy tracking**: In pipeline scripts, call Jira API to:
  - Add comment with build URL and status (success/failed).
  - Transition issue (e.g. “In progress” → “Done” on success, or “Blocked” on failure).
- Use **Jira issue key** from branch name or commit message and repository variables for Jira URL and API token.
- Bitbucket-Jira integration can also link commits and branches to issues; supplement with explicit status updates in script for deployment outcome.

## 5. Deployment History and Audit

- **Log** for each run: build ID, artifact version, base deploy result, validation result, list of tenants promoted (or “none”), timestamp.
- **Where to store**: Bitbucket pipeline logs (always); optionally push to S3, DynamoDB, or a small “deployment history” service; or write to central log account (see [06-logging-monitoring-and-operations.md](06-logging-monitoring-and-operations.md)).
- **Traceability**: Link pipeline run to Jira ticket; in Jira comment, include link to pipeline run and list of promoted tenants.

## 6. Silo Behavior

- Each tenant deploy runs **independently**: one tenant’s failure must not stop or affect others.
- In `promote-tenants.sh`: loop over selected tenants; for each tenant, run deploy in a subshell or capture exit code; log success/fail per tenant; continue to next tenant. Final pipeline status can be “failed” if any tenant failed, but all attempted tenants are logged.
