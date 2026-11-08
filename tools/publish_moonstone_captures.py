"""Select reviewed Flutter captures for documentation; never modify PNG pixels."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct


def selected(name: str) -> bool:
    if name.startswith(("compare-level-", "board-", "chapter-", "guardian-")):
        return True
    dark_ko = {
        "tutorial", "echo", "blocked", "home", "map", "daily", "portraits-48",
        *[f"stage{i}" for i in (2, 3, 4, 5, 9, 14, 25)],
        "discovery-mori", *[f"discovery-{i}" for i in (5, 6, 10, 13, 15, 20, 25)],
        *[f"album-{i}" for i in range(1, 6)],
        *[f"guardian-{i}" for i in range(1, 6)],
        *[f"share-chapter-{i}" for i in range(1, 6)], "share-guardian-5",
    }
    other = {"home", "stage9", "stage25", "album-5", "guardian-5", "portraits-48", "share-chapter-5", "share-guardian-5"}
    for prefix in ("dark-ko-", "dark-en-", "light-ko-", "light-en-"):
        if name.startswith(prefix):
            return name[len(prefix):] in (dark_ko if prefix == "dark-ko-" else other)
    return False


def publish(source: Path, output: Path) -> list[dict]:
    if not source.is_dir():
        raise FileNotFoundError(f"Run CAPTURE_SEASON1 first: {source}")
    output.mkdir(parents=True, exist_ok=True)
    records = []
    for path in sorted(source.glob("*.png")):
        if not selected(path.stem):
            continue
        data = path.read_bytes()
        if data[:8] != b"\x89PNG\r\n\x1a\n":
            raise ValueError(f"Invalid capture: {path}")
        width, height = struct.unpack(">II", data[16:24])
        shutil.copy2(path, output / path.name)
        records.append({"file": path.name, "width": width, "height": height, "sha256": hashlib.sha256(data).hexdigest()})
    (output / "manifest.json").write_text(json.dumps({"source": "Flutter widget/Canvas renderer; synthetic test progress", "rawCaptureCount": len(list(source.glob('*.png'))), "captures": records}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return records


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("build/moonstone-captures"))
    parser.add_argument("--output", type=Path, default=Path("docs/screenshots/moonstone-season1"))
    args = parser.parse_args()
    result = publish(args.source, args.output)
    print(f"Published {len(result)} selected PNGs; raw captures remain in {args.source}.")
