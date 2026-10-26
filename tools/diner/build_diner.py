"""Rebuild only the issue-123 made models with the installed Blender.

Run from the repository root:
  blender --background --factory-startup --python tools/diner/build_diner.py -- --only furniture
The default builds both modules; no render, download, service or engine is run.
Exports and provenance reports are confined to assets/made/diner.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from common import Builder
from furniture import build_furniture


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", choices=("all", "furniture", "wall"), default="all")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    builder = Builder(HERE.parents[1])
    if args.only in ("all", "furniture"):
        build_furniture(builder)
    if args.only in ("all", "wall"):
        from wall_pieces import build_wall_pieces
        build_wall_pieces(builder)
    builder.write_manifest()


if __name__ == "__main__":
    main()
