# Bitbucket Pipelines — Multi-Tenant

Two pipeline definitions: **infrastructure repo** and **application repo(s)**.  
Assumes **2 apps (app1, app2)**. **Base** has stage + prod; **other tenants** have prod only.

## Infrastructure repo

- **File:** `bitbucket-pipelines-infra.yml`  
- **Use:** Copy to the root of your infra repo as `bitbucket-pipelines.yml`.  
- **Behavior:**  
  - **main:** Deploy to base stage (auto), then base prod (manual).  
  - **Custom `deploy-tenant`:** Deploy a single (tenant, env) via variables.  
  - **Custom `promote-tenants`:** Deploy to multiple tenants/envs (manual; set `PROMOTE_TENANTS`, `PROMOTE_ENVS`).  
- **Variables:** `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION` (and, if multi-account, role assumption per tenant).

## Application repo (app1 or app2)

- **File:** `bitbucket-pipelines-apps.yml`  
- **Use:** Copy to the root of each app repo as `bitbucket-pipelines.yml`.  
- **Behavior:**  
  - **main:** Build → Deploy to base stage → Validate → Manual approval → Promote to tenants (manual step).  
  - **Custom `build-only`:** Build only.  
  - **Custom `deploy-base`:** Build + deploy to base (default stage).  
  - **Custom `promote`:** Run promotion only (set `PROMOTE_TENANTS`, `PROMOTE_ENVS`).  
- **Repo variables:**  
  - `APP_ID` — `app1` or `app2`  
  - `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`  
  - `ECR_REGISTRY` — e.g. `123456789012.dkr.ecr.us-east-1.amazonaws.com`  
  - `ECR_REPO` — must match the ECR repo created by CloudFormation: `{STACK_PREFIX}-{tenant}-{env}-{APP_ID}` (e.g. `mt-base-stage-app1` for base stage).  
  - Optional: `STACK_PREFIX` (default `mt`), `BASE_APP_URL` for health checks  

## Promotion

- **Infra:** Use custom pipeline `promote-tenants` with `PROMOTE_TENANTS=abc,xyz` or `all`, and `PROMOTE_ENVS=prod` (other tenants are prod only).  
- **Apps:** After approval on main, run the “Promote to Tenants” step and set `PROMOTE_TENANTS` and `PROMOTE_ENVS` (or use custom `promote` pipeline).
