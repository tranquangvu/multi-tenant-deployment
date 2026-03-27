#!/usr/bin/env python3
"""Query values from config/tenant-registry.yaml for shell wrappers."""

import argparse
import re
import sys

try:
    import yaml
except Exception:
    raise SystemExit("python package 'pyyaml' is required")


def load_registry(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def get_tenant_env(data: dict, tenant_id: str, env_name: str) -> dict:
    tenant = (data.get("tenants") or {}).get(tenant_id)
    if not tenant:
        raise SystemExit("unknown tenant")
    env = (tenant.get("environments") or {}).get(env_name)
    if not env:
        raise SystemExit("unknown environment")
    return env


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("registry")
    parser.add_argument(
        "query",
        choices=[
            "tenant-envs",
            "tenant-account-id",
            "tenant-oidc-role-arn",
            "shared-oidc-role-arn",
            "shared-region",
        ],
    )
    parser.add_argument("--tenant")
    parser.add_argument("--env")
    args = parser.parse_args()

    data = load_registry(args.registry)

    if args.query == "tenant-envs":
        if not args.tenant:
            raise SystemExit("--tenant is required")
        tenant = (data.get("tenants") or {}).get(args.tenant)
        if not tenant:
            raise SystemExit("unknown tenant")
        envs = tenant.get("environments")
        if not isinstance(envs, dict) or not envs:
            raise SystemExit("no environments")
        print(" ".join(envs.keys()))
        return

    if args.query == "tenant-account-id":
        if not args.tenant or not args.env:
            raise SystemExit("--tenant and --env are required")
        env = get_tenant_env(data, args.tenant, args.env)
        account_id = env.get("accountId")
        if not account_id:
            raise SystemExit("missing accountId")
        print(str(account_id))
        return

    if args.query == "tenant-oidc-role-arn":
        if not args.tenant or not args.env:
            raise SystemExit("--tenant and --env are required")
        env = get_tenant_env(data, args.tenant, args.env)
        account_id = str(env.get("accountId", "")).strip()
        role_name = str(env.get("bitbucketOidcRoleName", "")).strip()
        if not re.fullmatch(r"\d{12}", account_id):
            raise SystemExit("invalid or missing accountId")
        if not role_name:
            raise SystemExit("missing bitbucketOidcRoleName")
        print(f"arn:aws:iam::{account_id}:role/{role_name}")
        return

    shared = data.get("shared") or {}
    if args.query == "shared-oidc-role-arn":
        account_id = str(shared.get("accountId", "")).strip()
        role_name = str(shared.get("bitbucketOidcRoleName", "")).strip()
        if not re.fullmatch(r"\d{12}", account_id):
            raise SystemExit("invalid or missing shared.accountId")
        if not role_name:
            raise SystemExit("missing shared.bitbucketOidcRoleName")
        print(f"arn:aws:iam::{account_id}:role/{role_name}")
        return

    if args.query == "shared-region":
        region = str(shared.get("region", "")).strip()
        if not region:
            raise SystemExit("missing shared.region")
        print(region)
        return


if __name__ == "__main__":
    main()
