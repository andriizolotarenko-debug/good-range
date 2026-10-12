"""Draws the Good Range icon: you (the gold minimap arrow) in the middle of coloured range rings,
an enemy marker on the green ring and a gold measuring line between you.

Writes media/icon.tga (64x64, addon list and minimap), store/icon_400.png (CurseForge) and
store/icon_1024.png. Run from the repo root: python3 tools/make_icon.py
"""
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

N = 2048                      # working size; everything is drawn at 2x and scaled down
C = N / 2


def radial(size, inner, outer, center=None, radius=None):
    """RGBA radial gradient from inner colour (centre) to outer colour (edge)."""
    cx, cy = center or (size / 2, size / 2)
    radius = radius or size / 2
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(0, size, 2):
        for x in range(0, size, 2):
            t = min(1.0, math.hypot(x - cx, y - cy) / radius)
            c = tuple(round(a + (b - a) * t) for a, b in zip(inner, outer))
            px[x, y] = c
            if x + 1 < size:
                px[x + 1, y] = c
            if y + 1 < size:
                px[x, y + 1] = c
                if x + 1 < size:
                    px[x + 1, y + 1] = c
    return img


def rounded_mask(size, inset, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([inset, inset, size - 1 - inset, size - 1 - inset], radius=radius, fill=255)
    return m


def glow(layer, blur, strength=1.0):
    g = layer.filter(ImageFilter.GaussianBlur(blur))
    if strength != 1.0:
        a = g.getchannel("A").point(lambda v: min(255, round(v * strength)))
        g.putalpha(a)
    return g


def ring(size, r, width, color):
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse([C - r - width / 2, C - r - width / 2, C + r + width / 2, C + r + width / 2], fill=color)
    d.ellipse([C - r + width / 2, C - r + width / 2, C + r - width / 2, C + r - width / 2], fill=(0, 0, 0, 0))
    return layer


def main():
    canvas = Image.new("RGBA", (N, N), (0, 0, 0, 0))

    # tile: dark slate, lighter in the middle
    tile = radial(N, (38, 48, 66, 255), (8, 10, 16, 255), radius=N * 0.72)
    canvas.paste(tile, (0, 0), rounded_mask(N, 40, 300))

    # range rings, outer to inner: grey (out of range), green (your range), red (dead zone), blue (melee)
    rings = [
        (880, 26, (139, 144, 153, 150)),
        (700, 200, (70, 210, 90, 255)),
        (520, 64, (235, 70, 62, 255)),
        (220, 440, (62, 150, 255, 255)),   # melee: a solid disc around you
    ]
    zone = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    for r, w, col in rings:
        zone = Image.alpha_composite(zone, ring(N, r, w, col))
    # soft shading: brighter at the top left of each band
    shade = radial(N, (255, 255, 255, 70), (0, 0, 0, 90), center=(C - 500, C - 500), radius=N * 0.95)
    shaded = ImageChops.multiply(zone, Image.merge("RGBA", (shade.getchannel("R"),) * 3 + (Image.new("L", (N, N), 255),)))
    shaded.putalpha(zone.getchannel("A"))
    canvas = Image.alpha_composite(canvas, glow(zone, 40, 0.8))
    canvas = Image.alpha_composite(canvas, shaded)
    # dark separating lines between the bands
    lines = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lines)
    for r, w, _ in rings:
        for edge in (r - w / 2, r + w / 2):
            if edge > 5:
                ld.ellipse([C - edge, C - edge, C + edge, C + edge], outline=(10, 12, 18, 200), width=10)
    canvas = Image.alpha_composite(canvas, lines)

    # enemy on the green ring, upper right
    ang = math.radians(-45)
    ex, ey = C + 700 * math.cos(ang), C + 700 * math.sin(ang)
    hx, hy = C, C

    # measuring line: gold, with ticks, from you to the enemy
    meas = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    md = ImageDraw.Draw(meas)
    ux, uy = math.cos(ang), math.sin(ang)
    px_, py_ = -uy, ux
    start, end = 170, 700 - 160
    md.line([(hx + ux * start, hy + uy * start), (hx + ux * end, hy + uy * end)], fill=(20, 12, 0, 255), width=96)
    md.line([(hx + ux * start, hy + uy * start), (hx + ux * end, hy + uy * end)], fill=(255, 214, 60, 255), width=64)
    for t in range(start + 70, end - 20, 90):
        cx_, cy_ = hx + ux * t, hy + uy * t
        md.line([(cx_ - px_ * 70, cy_ - py_ * 70), (cx_ + px_ * 70, cy_ + py_ * 70)], fill=(20, 12, 0, 255), width=40)
        md.line([(cx_ - px_ * 60, cy_ - py_ * 60), (cx_ + px_ * 60, cy_ + py_ * 60)], fill=(255, 214, 60, 255), width=22)
    canvas = Image.alpha_composite(canvas, glow(meas, 24, 0.7))
    canvas = Image.alpha_composite(canvas, meas)

    # enemy marker: a red gem (raid-marker style diamond) with a dark rim and a highlight
    enemy = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ed = ImageDraw.Draw(enemy)
    s = 175
    ed.polygon([(ex, ey - s - 26), (ex + s + 26, ey), (ex, ey + s + 26), (ex - s - 26, ey)], fill=(20, 4, 4, 255))
    ed.polygon([(ex, ey - s), (ex + s, ey), (ex, ey + s), (ex - s, ey)], fill=(222, 38, 38, 255))
    ed.polygon([(ex, ey - s), (ex + s, ey), (ex, ey)], fill=(255, 92, 80, 255))
    ed.polygon([(ex - s, ey), (ex, ey + s), (ex, ey)], fill=(160, 20, 24, 255))
    ed.polygon([(ex - s * 0.45, ey - s * 0.25), (ex - s * 0.05, ey - s * 0.62), (ex + s * 0.05, ey - s * 0.5),
                (ex - s * 0.35, ey - s * 0.12)], fill=(255, 210, 200, 230))
    canvas = Image.alpha_composite(canvas, glow(enemy, 50, 1.2))
    canvas = Image.alpha_composite(canvas, enemy)

    # you: the gold minimap arrow, pointing at the enemy
    you = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    yd = ImageDraw.Draw(you)

    def arrow(scale):
        pts = [(0, -1.0), (0.62, 0.72), (0, 0.38), (-0.62, 0.72)]
        rot = ang + math.pi / 2
        out = []
        for x, y in pts:
            x, y = x * scale, y * scale
            out.append((hx + x * math.cos(rot) - y * math.sin(rot), hy + x * math.sin(rot) + y * math.cos(rot)))
        return out

    yd.polygon(arrow(250), fill=(30, 18, 0, 255))
    yd.polygon(arrow(205), fill=(255, 205, 40, 255))
    half = arrow(205)
    yd.polygon([half[0], half[1], half[2]], fill=(255, 238, 140, 255))
    canvas = Image.alpha_composite(canvas, glow(you, 40, 1.0))
    canvas = Image.alpha_composite(canvas, you)

    # bronze bevelled frame
    frame = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    outer = rounded_mask(N, 40, 300)
    inner = rounded_mask(N, 120, 230)
    band = ImageChops.subtract(outer, inner)
    bronze = radial(N, (246, 206, 120, 255), (110, 70, 26, 255), center=(N * 0.2, N * 0.15), radius=N * 1.15)
    frame.paste(bronze, (0, 0), band)
    edge = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    eg = ImageDraw.Draw(edge)
    eg.rounded_rectangle([40, 40, N - 41, N - 41], radius=300, outline=(40, 24, 6, 255), width=10)
    eg.rounded_rectangle([120, 120, N - 121, N - 121], radius=230, outline=(30, 18, 4, 255), width=12)
    eg.rounded_rectangle([60, 60, N - 61, N - 61], radius=282, outline=(255, 236, 180, 140), width=6)
    canvas = Image.alpha_composite(canvas, frame)
    canvas = Image.alpha_composite(canvas, edge)

    # everything inside the rounded tile only
    clip = rounded_mask(N, 40, 300)
    a = ImageChops.multiply(canvas.getchannel("A"), clip)
    canvas.putalpha(a)

    os.makedirs("store", exist_ok=True)
    canvas.resize((1024, 1024), Image.LANCZOS).save("store/icon_1024.png")
    canvas.resize((400, 400), Image.LANCZOS).save("store/icon_400.png")
    canvas.resize((64, 64), Image.LANCZOS).save("media/icon.tga")
    print("store/icon_1024.png store/icon_400.png media/icon.tga")


if __name__ == "__main__":
    main()
