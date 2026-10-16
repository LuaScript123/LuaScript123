#!/usr/bin/env python3
"""Exercise the unchanged MatchService source with explicit lifecycle doubles.

This is a deterministic Luau test, not a Roblox engine or physics simulation.
"""
from pathlib import Path
import subprocess
import sys
import tempfile


root = Path(__file__).resolve().parent.parent
binary = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / ".tools/bin/luau"
template = (root / "tests/MatchService.spec.luau").read_text()
marker = "-- INSERT_REAL_MODULES_HERE"
if template.count(marker) != 1:
    raise SystemExit("Expected exactly one real-module insertion point")

modules = []
for name, path in (
    ("Config", "src/shared/Config.luau"),
    ("MatchRules", "src/shared/MatchRules.luau"),
    ("InvitationRules", "src/shared/InvitationRules.luau"),
    ("MatchService", "src/server/MatchService.luau"),
):
    source = (root / path).read_text()
    modules.append(f"Modules.{name} = (function()\n{source}\nend)()")

with tempfile.TemporaryDirectory(prefix="fer-fioles-match-test-") as directory:
    script = Path(directory) / "MatchService.spec.luau"
    script.write_text(template.replace(marker, "\n\n".join(modules)))
    result = subprocess.run([str(binary), str(script)], cwd=root, check=False)
    raise SystemExit(result.returncode)
