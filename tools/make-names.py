"""Writes core/data/names.txt, the game resource names Obsidian shows instead of hashes, from the
research dictionary (path-like strings found in the game's bundles, internal/research/names.json).
Keeps only names that look like resource paths; every line is `<hash> <name>`, sorted by hash.

Usage: python tools/make-names.py [names.json]
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
src = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "internal" / "research" / "names.json"
names = json.loads(src.read_text(encoding="utf-8"))["names"]
path = re.compile(r"^[a-z_][a-z0-9_]*(/[a-z0-9_]+)+$")
keep = {h: n for h, n in names.items() if path.match(n) and len(n) >= 8 and any(len(p) >= 3 for p in n.split("/"))}
out = ROOT / "core" / "data" / "names.txt"
out.parent.mkdir(exist_ok=True)
out.write_text("".join(f"{h} {n}\n" for h, n in sorted(keep.items())), encoding="utf-8", newline="\n")
print(f"{len(keep)} of {len(names)} names -> {out}")
