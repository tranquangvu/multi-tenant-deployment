#!/usr/bin/env python3
"""
Emit CloudFormation parameter-overrides JSON array for network SSM paths.
Usage: tenant-network-ssm-params.py <tenant-registry.yaml> <tenant-id> <environment>
Env: SSM_NETWORK_PREFIX — optional root path
     (default from tenant ssmNetworkPrefix or /accelerator/network)
"""

import json
import os
import sys

try:
    import yaml
except Exception:
    raise SystemExit("python package 'pyyaml' is required")


def abort(msg: str) -> None:
    raise SystemExit(msg)


def subnet_param(prefix: str, vpc: str, subnet_name: str) -> str:
    return f"{prefix}/vpc/{vpc}/subnet/{subnet_name}/id"


def main() -> None:
    if len(sys.argv) < 4:
        abort("usage: tenant-network-ssm-params.py <registry.yaml> <tenant> <env>")
    registry_path = sys.argv[1]
    tenant_id = sys.argv[2]
    env_name = sys.argv[3]

    with open(registry_path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}

    tenant = (data.get("tenants") or {}).get(tenant_id)
    if not tenant:
        abort(f"unknown tenant: {tenant_id}")
    env = (tenant.get("environments") or {}).get(env_name)
    if not env:
        abort(f"unknown environment {env_name} for tenant {tenant_id}")

    raw_prefix = os.environ.get("SSM_NETWORK_PREFIX", "").strip()
    tenant_prefix = str(tenant.get("ssmNetworkPrefix", "")).strip()
    if raw_prefix:
        prefix = raw_prefix
    elif tenant_prefix:
        prefix = tenant_prefix
    else:
        prefix = "/accelerator/network"

    vpc = env.get("networkVpcName")
    if not vpc:
        abort(f"tenant-registry: missing networkVpcName for {tenant_id}/{env_name}")

    public_subnets = env.get("networkPublicSubnetNames")
    private_subnets = env.get("networkPrivateSubnetNames")
    if not isinstance(public_subnets, list) or len(public_subnets) < 2:
        abort("tenant-registry: need 2 public subnet names")
    if not isinstance(private_subnets, list) or len(private_subnets) < 2:
        abort("tenant-registry: need 2 private subnet names")

    params = [
        {"ParameterKey": "VpcIdSsmPath", "ParameterValue": f"{prefix}/vpc/{vpc}/id"},
        {
            "ParameterKey": "PublicSubnet1SsmPath",
            "ParameterValue": subnet_param(prefix, vpc, public_subnets[0]),
        },
        {
            "ParameterKey": "PublicSubnet2SsmPath",
            "ParameterValue": subnet_param(prefix, vpc, public_subnets[1]),
        },
        {
            "ParameterKey": "PrivateSubnet1SsmPath",
            "ParameterValue": subnet_param(prefix, vpc, private_subnets[0]),
        },
        {
            "ParameterKey": "PrivateSubnet2SsmPath",
            "ParameterValue": subnet_param(prefix, vpc, private_subnets[1]),
        },
    ]
    print(json.dumps(params))


if __name__ == "__main__":
    main()
