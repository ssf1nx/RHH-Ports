#!/usr/bin/env python3
import json
import sys
from pathlib import Path

def resolve_root() -> Path:
    if len(sys.argv) > 1:
        return Path(sys.argv[1]).expanduser().resolve()
    return Path.cwd().resolve()

root = resolve_root()
port_files = list(root.glob('ports/**/port.json'))

attr_keys = [
    "title",
    "porter",
    "desc",
    "desc_md",
    "inst",
    "inst_md",
    "genres",
    "image",
    "rtr",
    "exp",
    "runtime",
    "store",
    "availability",
    "reqs",
    "arch",
    "min_glibc",
]


def default_for(key: str):
    if key in {"porter", "genres", "runtime", "store", "reqs", "arch"}:
        return []
    if key in {"rtr", "exp"}:
        return None
    if key in {"desc_md", "inst_md", "image", "min_glibc"}:
        return None
    return ""


def normalize_port_json(path: Path) -> bool:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        print(f"Invalid JSON: {path} (line {exc.lineno}, col {exc.colno})")
        return False
    attr = data.get("attr") or {}

    new_attr = {}
    for k in attr_keys:
        if k in attr and attr[k] is not None:
            new_attr[k] = attr[k]
        else:
            new_attr[k] = default_for(k)

    for k, v in attr.items():
        if k not in new_attr:
            new_attr[k] = v

    new_attr["image"] = None
    new_attr["exp"] = False

    list_fields = {"porter", "genres", "runtime", "store", "reqs", "arch"}
    for key in list_fields:
        value = new_attr.get(key)
        if value is None:
            new_attr[key] = []
        elif not isinstance(value, list):
            new_attr[key] = [value]

    items_opt = data.get("items_opt")
    if items_opt is None:
        items_opt = []

    new_data = {
        "version": 4,
        "name": data.get("name", ""),
        "items": data.get("items", []),
        "items_opt": items_opt,
        "attr": new_attr,
    }

    for k, v in data.items():
        if k not in new_data:
            new_data[k] = v

    path.write_text(json.dumps(new_data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return True


if not port_files:
    print(f"No port.json files found under: {root}")
    sys.exit(0)

failed = 0
for path in port_files:
    if not normalize_port_json(path):
        failed += 1

if failed:
    print(f"Skipped {failed} invalid port.json file(s). Fix them and re-run.")
    sys.exit(1)

print(f"Updated {len(port_files)} port.json files under: {root}")
