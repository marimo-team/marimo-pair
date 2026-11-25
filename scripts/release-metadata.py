"""Prepare a stable release version or read the coordinated current version."""

import json
import re
import sys
from pathlib import Path

primary = Path(".codex-plugin/plugin.json")
secondary = Path(".claude-plugin/marketplace.json")
catalog_path = Path("skills/index.json")
data = json.loads(primary.read_text(encoding="utf-8"))
marketplace = json.loads(secondary.read_text(encoding="utf-8"))
catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
current = data["version"]
if marketplace["metadata"]["version"] != current:
    raise ValueError("Plugin versions must match")
if any(skill["version"] != current for skill in catalog["skills"]):
    raise ValueError("OpenCode skill versions must match the plugin version")
version = current
if len(sys.argv) == 2:
    request = sys.argv[1]
    if request in ("patch", "minor", "major"):
        parts = [int(part) for part in current.split(".")]
        index = {"major": 0, "minor": 1, "patch": 2}[request]
        parts[index] += 1
        parts[index + 1 :] = [0] * (2 - index)
        version = ".".join(map(str, parts))
    else:
        version = request
    if not re.fullmatch("(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)", version):
        raise ValueError("Expected a stable X.Y.Z version")
    if tuple(map(int, version.split("."))) <= tuple(map(int, current.split("."))):
        raise ValueError("The release version must increase")
    data["version"] = version
    marketplace["metadata"]["version"] = version
    for skill in catalog["skills"]:
        skill["version"] = version
    primary.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    secondary.write_text(json.dumps(marketplace, indent=2) + "\n", encoding="utf-8")
    catalog_path.write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"version": version}))
