#!/usr/bin/env python3
"""Export the runtime arena and lobby using exactly MapBuilder.Build()."""
import argparse
import pathlib
import subprocess
import tempfile
import xml.etree.ElementTree as ET


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=pathlib.Path, default=root / "assets" / "Arena.rbxmx")
    parser.add_argument("--luau", type=pathlib.Path, default=root / ".tools" / "bin" / "luau")
    args = parser.parse_args()
    stub = (root / "tools" / "map-stub.luau").read_text()
    config = (root / "src" / "shared" / "Config.luau").read_text()
    catalog = (root / "src" / "shared" / "Catalog.luau").read_text()
    builder = (root / "src" / "server" / "MapBuilder.luau").read_text()
    source = (stub + "\nlocal configuration = (function()\n" + config
              + "\nend)()\nlocal catalog = (function()\n" + catalog + "\nend)()\n"
              + 'local require = function(module)\n'
              + '    if module.Name == "Config" then return configuration end\n'
              + '    if module.Name == "Catalog" then return catalog end\n'
              + '    error("Unexpected module: " .. module.Name)\nend\n'
              + "local builder = (function()\n" + builder + "\nend)()\nexport(builder.Build())\n")
    with tempfile.NamedTemporaryFile(mode="w", suffix=".luau", delete=False) as handle:
        handle.write(source)
        temporary = pathlib.Path(handle.name)
    try:
        result = subprocess.run([str(args.luau), str(temporary)], text=True, capture_output=True, check=True)
    finally:
        temporary.unlink(missing_ok=True)
    model = ET.fromstring(result.stdout)
    assert model.tag == "roblox" and model.find("Item").get("class") == "Model"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(result.stdout)
    print(result.stdout.splitlines()[0].removeprefix("<!-- ").removesuffix(" -->"))
    print("Exported", args.output)


if __name__ == "__main__":
    main()
