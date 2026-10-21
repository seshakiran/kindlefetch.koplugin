#!/usr/bin/env python3
"""Build an installable plugin ZIP from an explicit source-only allowlist."""
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

root = Path(__file__).resolve().parents[1]
output = root / "dist" / "kindlefetch.koplugin.zip"
files = [root / name for name in ("main.lua", "kindlefetch.lua", "safemode.lua", "_meta.lua", "version.txt", "LICENSE", "README.md")]
for folder in ("api", "cache", "settings", "ui", "updater", "util"):
    files.extend(sorted((root / folder).rglob("*.lua")))
output.parent.mkdir(exist_ok=True)
with ZipFile(output, "w", compression=ZIP_DEFLATED) as archive:
    for path in files:
        archive.write(path, "kindlefetch.koplugin/" + path.relative_to(root).as_posix())
print(output)
