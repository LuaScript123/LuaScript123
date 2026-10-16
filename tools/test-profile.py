#!/usr/bin/env python3
"""Run unchanged profile service with explicit deterministic datastore doubles."""
from pathlib import Path
import subprocess
import sys
import tempfile
root = Path(__file__).resolve().parent.parent
binary = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / '.tools/bin/luau'
template = (root / 'tests/ProfileService.spec.luau').read_text()
marker = '-- INSERT_REAL_MODULES_HERE'
if template.count(marker) != 1:
    raise SystemExit('Expected exactly one real-module insertion point')
modules = []
for name, path in (
    ('Config', 'src/shared/Config.luau'),
    ('Catalog', 'src/shared/Catalog.luau'),
    ('ProfileRules', 'src/shared/ProfileRules.luau'),
    ('ProfileService', 'src/server/ProfileService.luau'),
):
    source = (root / path).read_text()
    modules.append(f'Modules.{name} = (function()\n{source}\nend)()')
with tempfile.TemporaryDirectory(prefix='fer-fioles-profile-test-') as directory:
    script = Path(directory) / 'ProfileService.spec.luau'
    script.write_text(template.replace(marker, '\n\n'.join(modules)))
    raise SystemExit(subprocess.run([str(binary), str(script)], cwd=root, check=False).returncode)
