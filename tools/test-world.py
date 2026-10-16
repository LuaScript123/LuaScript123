#!/usr/bin/env python3
"""Run the real world service/rules with explicit lifecycle and network doubles.

This validates server control flow, not Roblox engine physics or network delivery.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
binary = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / ".tools/bin/luau"
template = (root / "tests/WorldService.spec.luau").read_text()
marker = "-- INSERT_REAL_MODULES_HERE"
assert template.count(marker) == 1
modules = []
for name, path in (
    ("Config", "src/shared/Config.luau"),
    ("WorldRules", "src/shared/WorldRules.luau"),
    ("WorldService", "src/server/WorldService.luau"),
):
    modules.append(f"Modules.{name} = (function()\n{(root / path).read_text()}\nend)()")
with tempfile.TemporaryDirectory(prefix="kingdom-world-test-") as directory:
    script = Path(directory) / "WorldService.spec.luau"
    script.write_text(template.replace(marker, "\n\n".join(modules)))
    result = subprocess.run([str(binary), str(script)], cwd=root, check=False)
    raise SystemExit(result.returncode)
