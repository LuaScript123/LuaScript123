#!/usr/bin/env python3
"""Bundle the sources and freshly built Roblox places without local tools/caches."""
from pathlib import Path
import zipfile
import shutil

root = Path(__file__).resolve().parent.parent
files = [root / name for name in (
    "README.md", "Makefile", "default.project.json", "test.project.json", ".gitignore",
    "build/FerEtFioles.rbxlx", "build/StudioSmoke.rbxlx",
)]
for directory in ("src", "assets", "tools", "tests", "docs"):
    files.extend(path for path in (root / directory).rglob("*")
                 if path.is_file() and "__pycache__" not in path.parts)

output = root / "build/FerEtFioles.zip"
with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(files):
        archive.write(path, Path("FerEtFioles") / path.relative_to(root))
with zipfile.ZipFile(output) as archive:
    assert archive.testzip() is None, "Corrupt archive"
release_dir = root / "releases"
release_dir.mkdir(exist_ok=True)
shutil.copyfile(root / "build/FerEtFioles.rbxlx", release_dir / "FerEtFioles.rbxlx")
shutil.copyfile(output, release_dir / "FerEtFioles.zip")
print(f"Archive: {output.name}, {len(files)} files, {output.stat().st_size} bytes")
print("Updated releases/FerEtFioles.rbxlx and releases/FerEtFioles.zip")
