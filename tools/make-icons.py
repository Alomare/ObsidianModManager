"""Makes the app icons from the shaded logo, edge to edge at every size so it fills the taskbar, and
the logo the app and the README show, which keeps a margin. The logo files live outside the repo,
in ProjectObsidian/branding.

Usage: python tools/make-icons.py [path to logo-shaded.png]
"""
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT.parent / "branding" / "logo-shaded.png"
OUT = ROOT / "app" / "src-tauri" / "icons"
LOGO_MARGIN = 0.10  # of the logo's side, on every edge

logo = Image.open(SRC).convert("RGBA")
logo = logo.crop(logo.getbbox())


def icon(size: int, margin: float = 0) -> Image.Image:
    inner = size * (1 - 2 * margin)
    scale = inner / max(logo.size)
    w, h = max(1, round(logo.width * scale)), max(1, round(logo.height * scale))
    # An even margin left over on each axis, so the logo sits exactly in the middle.
    w, h = w - (size - w) % 2, h - (size - h) % 2
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(logo.resize((w, h), Image.LANCZOS), ((size - w) // 2, (size - h) // 2))
    return canvas


for name, size in [("32x32.png", 32), ("128x128.png", 128), ("128x128@2x.png", 256), ("icon.png", 512)]:
    icon(size).save(OUT / name)
sizes = [16, 24, 32, 48, 64, 256]
frames = [icon(s) for s in sizes]
frames[-1].save(OUT / "icon.ico", sizes=[(s, s) for s in sizes], append_images=frames[:-1])
icon(256, LOGO_MARGIN).save(ROOT / "app" / "src" / "assets" / "logo.png")
print("icons written to", OUT)
