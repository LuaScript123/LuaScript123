#!/usr/bin/env python3
"""Export and validate the actual kingdom WorldMapBuilder through deterministic Luau primitives."""
import argparse
import pathlib
import subprocess
import tempfile
import xml.etree.ElementTree as ET


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=pathlib.Path, default=root / "assets" / "Kingdoms.rbxmx")
    parser.add_argument("--luau", type=pathlib.Path, default=root / ".tools" / "bin" / "luau")
    args = parser.parse_args()
    # Reuse the arena exporter's math, Instance doubles and XML serializer. Its
    # duel-specific geometry validator is replaced; the original file is intact.
    common = (root / "tools" / "map-stub.luau").read_text()
    primitives, tail = common.split("local function validate(map)\n", 1)
    _, serializer = tail.split("local function escape(value)\n", 1)
    validation = (root / "tools" / "world-map-stub.luau").read_text()
    config = (root / "src" / "shared" / "Config.luau").read_text()
    builder = (root / "src" / "server" / "WorldMapBuilder.luau").read_text()
    source = (primitives + validation + "\nlocal function escape(value)\n" + serializer
              + "\nlocal configuration = (function()\n" + config + "\nend)()\n"
              + 'local require = function(module)\n'
              + '    assert(module.Name == "Config", "Unexpected dependency: " .. module.Name)\n'
              + '    return configuration\nend\n'
              + "local builder = (function()\n" + builder + "\nend)()\nexport(builder.Build())\n")
    with tempfile.NamedTemporaryFile(mode="w", suffix=".luau", delete=False) as handle:
        handle.write(source)
        temporary = pathlib.Path(handle.name)
    try:
        result = subprocess.run([str(args.luau), str(temporary)], text=True, capture_output=True, check=True)
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.stderr or error.stdout) from error
    finally:
        temporary.unlink(missing_ok=True)
    model = ET.fromstring(result.stdout)
    item = model.find("Item")
    assert model.tag == "roblox" and item is not None and item.get("class") == "Model"
    assert item.find("./Properties/string[@name='Name']").text == "FerEtFiolesArena"
    assert 0 < len(model.findall(".//Item[@class='Part']")) < 1000
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(result.stdout)
    print(result.stdout.splitlines()[0].removeprefix("<!-- ").removesuffix(" -->"))
    print("Exported", args.output)


if __name__ == "__main__":
    main()
