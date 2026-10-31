"""Bakes TrueType fonts into the files HELLDIVERS (2015) reads: a font, its atlas and a material.

Usage: python tools/bake_font.py --out res --base mymod/fonts one=Some-Font.ttf two=Other-Font.ttf

Needs Pillow, and uharfbuzz for kerning. Writes <id>.font and <id>.texture for each font, and
fonts.material for all of them. Put them in a mod's "resources": see the wiki's Custom fonts section.
"""
import argparse
import struct
from pathlib import Path

from PIL import Image, ImageFont

try:
    import uharfbuzz
except ImportError:
    uharfbuzz = None

FONT_VERSION = 5
MATERIAL_VERSION = 10
# From the game's own materials: the font shader, its diffuse_map slot, and its one variable.
TEMPLATE, DIFFUSE_MAP, VARIABLE = 0xba25de35, 0x3aa8b87e, 0x46f80ade
PAD = 4
MAX_KERNS = 600
# Latin-1, Latin Extended-A, and the punctuation a text is likely to hold.
CODEPOINTS = [*range(0x20, 0x7f), *range(0xa0, 0x180), 0x2013, 0x2014, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2026, 0x20ac, 0x2122]


def murmur64(data, seed=0):
    m, r, mask = 0xc6a4a7935bd1e995, 47, (1 << 64) - 1
    h = (seed ^ (len(data) * m)) & mask
    tail = len(data) & ~7
    for (k,) in struct.iter_unpack("<Q", data[:tail]):
        k = (k * m) & mask
        k ^= k >> r
        k = (k * m) & mask
        h = ((h ^ k) * m) & mask
    rest = data[tail:]
    if rest:
        h = ((h ^ int.from_bytes(rest, "little")) * m) & mask
    h ^= h >> r
    h = (h * m) & mask
    return h ^ (h >> r)


def alpha_block(values):
    """A DXT5 alpha block for 16 values, with white colour after it."""
    high, low = max(values), min(values)
    if high == low:
        return bytes([high, low, 0, 0, 0, 0, 0, 0]) + b"\xff\xff\xff\xff\0\0\0\0"
    ramp = [high, low] + [((7 - i) * high + i * low) // 7 for i in range(1, 7)]
    bits = 0
    for i, value in enumerate(values):
        best = min(range(8), key=lambda n: abs(ramp[n] - value))
        bits |= best << (3 * i)
    return bytes([high, low]) + bits.to_bytes(6, "little") + b"\xff\xff\xff\xff\0\0\0\0"


def compress(image):
    width, height = image.size
    pixels = image.tobytes()
    out = bytearray()
    for by in range(0, height, 4):
        for bx in range(0, width, 4):
            values = []
            for y in range(by, by + 4):
                row = min(y, height - 1) * width
                for x in range(bx, bx + 4):
                    values.append(pixels[row + min(x, width - 1)])
            out += alpha_block(values)
    return bytes(out)


def dds(image):
    """A DDS with every mip, in the layout of the game's own atlases."""
    width, height = image.size
    mips = [image]
    while mips[-1].size != (1, 1):
        w, h = mips[-1].size
        mips.append(mips[-1].resize((max(1, w // 2), max(1, h // 2)), Image.Resampling.BOX))
    header = bytearray(128)
    header[:4] = b"DDS "
    struct.pack_into("<IIIIIII", header, 4, 124, 0x000a1007, height, width, width * height, 0, len(mips))
    # The two tags NVIDIA's tools leave, which every atlas of the game has.
    header[60:64], header[68:72] = b"UVER", b"NVTT"
    struct.pack_into("<I", header, 72, 0x00020100)
    struct.pack_into("<II4s", header, 76, 32, 4, b"DXT5")
    struct.pack_into("<I", header, 108, 0x00401008)
    # Every texture resource ends with a four byte category. Without it the engine reads past the end,
    # and the game stalls on a black window at boot. Zero is what the foundation bundle's fonts have.
    return bytes(header) + b"".join(compress(mip) for mip in mips) + bytes(4)


def covered(path):
    if not uharfbuzz:
        return None, None
    blob = uharfbuzz.Blob.from_file_path(str(path))
    font = uharfbuzz.Font(uharfbuzz.Face(blob))
    return font, {cp for cp in CODEPOINTS if font.get_nominal_glyph(cp)}


def kerning(hb_font, chars, scale):
    """Pairs that sit closer or further than their advances, largest first."""
    def advance(text):
        buffer = uharfbuzz.Buffer()
        buffer.add_str(text)
        buffer.guess_segment_properties()
        uharfbuzz.shape(hb_font, buffer, {"kern": True, "liga": False})
        return sum(p.x_advance for p in buffer.glyph_positions)

    single = {c: advance(chr(c)) for c in chars}
    pairs = []
    for left in chars:
        for right in chars:
            amount = (advance(chr(left) + chr(right)) - single[left] - single[right]) * scale
            if abs(amount) >= 1:
                pairs.append((left, right, round(amount)))
    pairs.sort(key=lambda p: -abs(p[2]))
    return pairs[:MAX_KERNS]


def fit(cells):
    """The smallest atlas, as powers of two, that holds these cells in rows."""
    for width in (256, 512, 1024, 2048, 4096):
        x, y, row = PAD, PAD, 0
        placed = []
        for cell in cells:
            w, h = cell["mask"].size
            if x + w + PAD > width:
                x, y, row = PAD, y + row + PAD, 0
            placed.append((x, y))
            x += w + PAD
            row = max(row, h)
        needed = y + row + PAD
        height = 256
        while height < needed:
            height *= 2
        if height <= width:
            return width, height, placed
    raise SystemExit("too many glyphs for one atlas")


def bake(path, size):
    font = ImageFont.truetype(str(path), size, layout_engine=ImageFont.Layout.BASIC)
    ascent, _ = font.getmetrics()
    hb_font, have = covered(path)
    cells = []
    for cp in CODEPOINTS:
        if have is not None and cp not in have:
            continue
        ch = chr(cp)
        left, top, right, bottom = font.getbbox(ch, anchor="ls")
        w, h = right - left, bottom - top
        mask = Image.new("L", (max(1, w), max(1, h)), 0)
        if w > 0 and h > 0:
            piece = Image.new("L", (w, h), 0)
            piece_font = font
            from PIL import ImageDraw
            ImageDraw.Draw(piece).text((-left, -top), ch, font=piece_font, fill=255, anchor="ls")
            mask = piece
        cells.append({"cp": cp, "mask": mask, "x": left, "top": top, "advance": font.getlength(ch)})
    cells.sort(key=lambda c: -c["mask"].size[1])
    width, height, placed = fit(cells)
    atlas = Image.new("L", (width, height), 0)
    records = {}
    for cell, (x, y) in zip(cells, placed):
        atlas.paste(cell["mask"], (x, y))
        w, h = cell["mask"].size
        records[cell["cp"]] = (x, y, w, h, cell["x"], ascent + cell["top"], round(cell["advance"]))
    fallback = records[ord("?")]
    kerns = []
    if hb_font:
        chars = [cp for cp in sorted(records) if 0x20 <= cp < 0x7f]
        kerns = kerning(hb_font, chars, size / hb_font.face.upem)

    out = bytearray(struct.pack("<IfffffII", FONT_VERSION, size, size, ascent, 1 / width, 1 / height, len(records), len(kerns)))
    out += struct.pack("<7f", *fallback)
    out += struct.pack("<I", len(records))
    for cp, record in records.items():
        out += struct.pack("<I7f", cp, *record)
    out += struct.pack("<I", len(kerns))
    for left, right, amount in kerns:
        out += struct.pack("<IIf", left, right, amount)
    return bytes(out), atlas, len(kerns)


def material(fonts):
    """One record per font, sorted by name, as the game's are."""
    records = []
    for material_name, texture in fonts:
        name = murmur64(material_name.encode()) >> 32
        tex = murmur64(texture.encode())
        records.append((name, struct.pack("<13I", name, TEMPLATE, 0, 0, 1, DIFFUSE_MAP, tex & 0xffffffff, tex >> 32, 1, VARIABLE, 0, 0, 0)))
    records.sort()
    return struct.pack("<II", MATERIAL_VERSION, len(records)) + b"".join(r for _, r in records)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("fonts", nargs="+", help="id=path.ttf")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--base", required=True, help="the folder of the resource names, such as mymod/fonts")
    parser.add_argument("--size", type=int, default=48, help="pixels per em in the atlas: crisp up to this size on screen")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    fonts = []
    for spec in args.fonts:
        font_id, path = spec.split("=", 1)
        data, atlas, kerns = bake(Path(path), args.size)
        (args.out / f"{font_id}.font").write_bytes(data)
        texture = dds(atlas)
        (args.out / f"{font_id}.texture").write_bytes(texture)
        fonts.append((font_id, f"{args.base}/{font_id}"))
        print(f"{font_id}: atlas {atlas.size[0]}x{atlas.size[1]}, {len(texture)} bytes, {kerns} kerning pairs")
    (args.out / "fonts.material").write_bytes(material(fonts))
    print(f"material: {args.base}/fonts")


if __name__ == "__main__":
    main()
