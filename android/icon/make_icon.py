"""Draws the Shades of Balatro launcher icon (original art, no game assets). Usage: python make_icon.py <outdir>"""
import sys
from PIL import Image, ImageDraw, ImageFont

def icon(size):
    s = 4  # supersample
    W = size * s
    im = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, W - 1, W - 1), radius=int(W * 0.22), fill=(30, 38, 52, 255))
    # two offset "shade" cards behind the main one
    for i, col in enumerate([(54, 116, 214, 255), (238, 72, 72, 255)]):
        off = int(W * (0.06 - i * 0.03))
        d.rounded_rectangle((W * 0.24 + off, W * 0.17 - off, W * 0.80 + off, W * 0.83 - off), radius=int(W * 0.06), fill=col)
    d.rounded_rectangle((W * 0.20, W * 0.20, W * 0.76, W * 0.86), radius=int(W * 0.06), fill=(244, 240, 230, 255))
    # spade: circle pair + triangle + stem
    cx, cy, r = W * 0.48, W * 0.50, W * 0.10
    d.ellipse((cx - 2 * r + r * 0.15, cy - r * 0.2, cx + r * 0.15, cy + r * 1.6), fill=(30, 38, 52, 255))
    d.ellipse((cx - r * 0.15, cy - r * 0.2, cx + 2 * r - r * 0.15, cy + r * 1.6), fill=(30, 38, 52, 255))
    d.polygon([(cx - 1.95 * r, cy + 0.55 * r), (cx + 1.95 * r, cy + 0.55 * r), (cx, cy - 1.9 * r)], fill=(30, 38, 52, 255))
    d.polygon([(cx - 0.55 * r, cy + 2.4 * r), (cx + 0.55 * r, cy + 2.4 * r), (cx, cy + 0.9 * r)], fill=(30, 38, 52, 255))
    return im.resize((size, size), Image.LANCZOS)

out = sys.argv[1]
for name, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192, "store": 512}.items():
    icon(px).save(f"{out}/icon-{name}.png")
print("ok")
