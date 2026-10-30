"""Refreshes bundled/ from the repositories of the starter pack mods, cloned into ../Bundled. Takes what
each one has committed, the same files its release zip holds. Edit the mods there, not in bundled/.

Usage: python tools/starter_pack.py
"""
import io
import shutil
import subprocess
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPOS = {"ObsidianAPI": "obsidian.api", "ObsidianTrainer": "obsidian.trainer", "ObsidianQoL": "obsidian.qol"}

for repo, mod in REPOS.items():
    src = ROOT.parent / "Bundled" / repo
    assert src.is_dir(), f"clone https://github.com/Alomare/{repo} into {src}"
    files = subprocess.run(["git", "-C", str(src), "archive", "--format=tar", "HEAD"], check=True, capture_output=True).stdout
    target = ROOT / "bundled" / mod
    shutil.rmtree(target, ignore_errors=True)
    with tarfile.open(fileobj=io.BytesIO(files)) as tar:
        tar.extractall(target, filter="data")
    print(target)
