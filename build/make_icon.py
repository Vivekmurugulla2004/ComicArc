"""Generate ComicArc app icons from scratch using Pillow."""
import os
import shutil
from PIL import Image, ImageDraw

ROOT   = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
ASSETS = os.path.join(ROOT, 'assets')
os.makedirs(ASSETS, exist_ok=True)

SIZE = 1024
cx = cy = SIZE // 2

GOLD     = (235, 186, 74)
GOLD_DIM = (180, 136, 44)
BG_DARK  = (11,  12,  24)
BG_MID   = (16,  18,  36)


def make_base(size):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))

    # Gradient background (top-dark → bottom-slightly-lighter)
    bg = Image.new('RGBA', (size, size))
    d  = ImageDraw.Draw(bg)
    for y in range(size):
        t = y / size
        r = int(BG_DARK[0] + t * 9)
        g = int(BG_DARK[1] + t * 7)
        b = int(BG_DARK[2] + t * 20)
        d.line([(0, y), (size - 1, y)], fill=(r, g, b, 255))

    # Rounded-rect clip mask (macOS ~22% radius)
    mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size - 1, size - 1],
        radius=int(size * 0.218),
        fill=255,
    )
    bg.putalpha(mask)
    img.paste(bg, (0, 0), bg)

    draw = ImageDraw.Draw(img)
    s = size / SIZE  # scale factor

    # ── Diamond outline ──────────────────────────────────
    do = int(318 * s)   # outer half-width
    di = int(272 * s)   # inner half-width (creates stroke thickness)
    outer = [(cx*s*2//2, cy*s*2//2 - do),
             (cx*s*2//2 + do, cy*s*2//2),
             (cx*s*2//2,      cy*s*2//2 + do),
             (cx*s*2//2 - do, cy*s*2//2)]

    # recalculate with proper center
    c = size // 2
    outer = [(c, c - do), (c + do, c), (c, c + do), (c - do, c)]
    inner = [(c, c - di), (c + di, c), (c, c + di), (c - di, c)]

    draw.polygon(outer, fill=GOLD)
    draw.polygon(inner, fill=BG_MID)

    # ── Center ring ───────────────────────────────────────
    ro = int(102 * s)   # outer radius
    ri = int(62  * s)   # inner radius (hole)
    draw.ellipse([c - ro, c - ro, c + ro, c + ro], fill=GOLD)
    draw.ellipse([c - ri, c - ri, c + ri, c + ri], fill=BG_MID)

    # ── Subtle corner glow dots (compass feel) ────────────
    dot_r = int(14 * s)
    offset = int(318 * s)
    for dx, dy in [(0, -offset), (offset, 0), (0, offset), (-offset, 0)]:
        draw.ellipse(
            [c + dx - dot_r, c + dy - dot_r,
             c + dx + dot_r, c + dy + dot_r],
            fill=GOLD_DIM,
        )

    return img


# ── PNG (1024) ───────────────────────────────────────────
png_path = os.path.join(ASSETS, 'icon.png')
base = make_base(1024)
base.save(png_path)
print(f"  icon.png")

# ── ICO (Windows — multi-size) ───────────────────────────
ico_path = os.path.join(ASSETS, 'icon.ico')
sizes = [16, 32, 48, 64, 128, 256]
frames = [make_base(s).convert('RGBA') for s in sizes]
frames[0].save(ico_path, format='ICO', append_images=frames[1:],
               sizes=[(s, s) for s in sizes])
print(f"  icon.ico")

# ── ICNS (macOS — via iconset + iconutil) ────────────────
iconset_dir = os.path.join(ASSETS, 'icon.iconset')
os.makedirs(iconset_dir, exist_ok=True)

icns_sizes = {
    'icon_16x16.png':      16,
    'icon_16x16@2x.png':   32,
    'icon_32x32.png':      32,
    'icon_32x32@2x.png':   64,
    'icon_128x128.png':    128,
    'icon_128x128@2x.png': 256,
    'icon_256x256.png':    256,
    'icon_256x256@2x.png': 512,
    'icon_512x512.png':    512,
    'icon_512x512@2x.png': 1024,
}
for filename, px in icns_sizes.items():
    make_base(px).save(os.path.join(iconset_dir, filename))

icns_path = os.path.join(ASSETS, 'icon.icns')
ret = os.system(f'iconutil -c icns "{iconset_dir}" -o "{icns_path}"')
shutil.rmtree(iconset_dir)
if ret == 0:
    print(f"  icon.icns")
else:
    print("  icon.icns FAILED (iconutil not available — macOS only)")

print("\nAll icons written to assets/")
