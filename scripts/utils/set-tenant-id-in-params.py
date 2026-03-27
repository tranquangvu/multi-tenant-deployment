#!/usr/bin/env python3
"""
Set TenantId parameter value in a params.json array.
Usage: set-tenant-id-in-params.py <params.json> <tenant-id>
"""

import json
import sys
from pathlib import Path


def abort(msg: str) -> None:
    raise SystemExit(msg)


def main() -> None:
    if len(sys.argv) != 3:
        abort("usage: set-tenant-id-in-params.py <params.json> <tenant-id>")

    params_path = Path(sys.argv[1])
    tenant_id = sys.argv[2]

    if not params_path.is_file():
        abort(f"params file not found: {params_path}")

    with params_path.open("r", encoding="utf-8") as f:
        data = json.load(f)

    if not isinstance(data, list):
        abort("params.json must be a JSON array")

    updated = False
    for item in data:
        if isinstance(item, dict) and item.get("ParameterKey") == "TenantId":
            item["ParameterValue"] = tenant_id
            updated = True
            break

    if not updated:
        data.append({"ParameterKey": "TenantId", "ParameterValue": tenant_id})

    with params_path.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
