"""Draws the Good Range icon: gold "GR" letters in the middle of the coloured range rings (blue
melee, red dead zone, green your range, grey out of range).

Writes media/icon.tga (64x64, addon list and minimap), store/icon_400.png and store/icon_1024.png
(rounded corners), and store/icon_square_400.png / store/icon_square_1024.png (square, no
transparent corners, for CurseForge and other square slots). Run from the repo root:
python3 tools/make_icon.py
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


def main(square=False):
    # outer edge and inner edge of the bronze frame: (inset, corner radius)
    out_i, out_r = (0, 0) if square else (40, 300)
    in_i, in_r = (80, 40) if square else (120, 230)
    canvas = Image.new("RGBA", (N, N), (0, 0, 0, 0))

    # tile: dark slate, lighter in the middle
    tile = radial(N, (38, 48, 66, 255), (8, 10, 16, 255), radius=N * 0.72)
    canvas.paste(tile, (0, 0), rounded_mask(N, out_i, out_r))

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

    # "GR" in gold: Changa Bold (the addon's font), a top-to-bottom gold gradient, a bevel
    # highlight, a dark rim and a soft glow
    from PIL import ImageFont
    font = ImageFont.truetype("media/Changa-Bold.ttf", 820)
    text = "GR"
    mask = Image.new("L", (N, N), 0)
    md = ImageDraw.Draw(mask)
    x0, y0, x1, y1 = md.textbbox((0, 0), text, font=font)
    tx, ty = C - (x0 + x1) / 2, C - (y0 + y1) / 2
    md.text((tx, ty), text, font=font, fill=255)
    top, bottom = ty + y0, ty + y1

    def vertical(stops):
        g = Image.new("RGBA", (N, N))
        px = g.load()
        for y in range(N):
            t = min(1, max(0, (y - top) / (bottom - top)))
            for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
                if t <= t1:
                    k = (t - t0) / (t1 - t0) if t1 > t0 else 0
                    c = tuple(round(u + (v - u) * k) for u, v in zip(c0, c1))
                    break
            for x in range(N):
                px[x, y] = c + (255,)
        return g

    gold = vertical([(0.0, (255, 246, 196)), (0.38, (255, 212, 72)), (0.62, (226, 150, 24)),
                     (1.0, (120, 66, 10))])
    rim = mask.filter(ImageFilter.MaxFilter(41))
    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    shadow.paste((10, 6, 0, 230), (0, 0), rim.filter(ImageFilter.GaussianBlur(26)))
    canvas = Image.alpha_composite(canvas, shadow)
    dark = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    dark.paste((34, 20, 2, 255), (0, 0), rim)
    canvas = Image.alpha_composite(canvas, dark)
    body = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    body.paste(gold, (0, 0), mask)
    canvas = Image.alpha_composite(canvas, body)
    # bevel: light on the upper-left edges, shade on the lower-right ones
    inner = mask.filter(ImageFilter.MinFilter(25))
    light = ImageChops.subtract(mask, ImageChops.offset(inner, 10, 10))
    light = ImageChops.multiply(light, ImageChops.subtract(mask, inner))
    hl = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    hl.paste((255, 252, 225, 200), (0, 0), light.filter(ImageFilter.GaussianBlur(3)))
    canvas = Image.alpha_composite(canvas, hl)
    dk = ImageChops.subtract(mask, ImageChops.offset(inner, -10, -10))
    dk = ImageChops.multiply(dk, ImageChops.subtract(mask, inner))
    sh = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    sh.paste((90, 46, 4, 170), (0, 0), dk.filter(ImageFilter.GaussianBlur(3)))
    canvas = Image.alpha_composite(canvas, sh)

    # bronze bevelled frame
    frame = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    outer = rounded_mask(N, out_i, out_r)
    inner = rounded_mask(N, in_i, in_r)
    band = ImageChops.subtract(outer, inner)
    bronze = radial(N, (246, 206, 120, 255), (110, 70, 26, 255), center=(N * 0.2, N * 0.15), radius=N * 1.15)
    frame.paste(bronze, (0, 0), band)
    edge = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    eg = ImageDraw.Draw(edge)
    eg.rounded_rectangle([out_i, out_i, N - 1 - out_i, N - 1 - out_i], radius=out_r, outline=(40, 24, 6, 255), width=10)
    eg.rounded_rectangle([in_i, in_i, N - 1 - in_i, N - 1 - in_i], radius=in_r, outline=(30, 18, 4, 255), width=12)
    eg.rounded_rectangle([out_i + 20, out_i + 20, N - 21 - out_i, N - 21 - out_i], radius=max(0, out_r - 18),
                         outline=(255, 236, 180, 140), width=6)
    canvas = Image.alpha_composite(canvas, frame)
    canvas = Image.alpha_composite(canvas, edge)

    # everything inside the rounded tile only
    clip = rounded_mask(N, out_i, out_r)
    a = ImageChops.multiply(canvas.getchannel("A"), clip)
    canvas.putalpha(a)

    os.makedirs("store", exist_ok=True)
    if square:
        flat = Image.new("RGBA", (N, N), (8, 10, 16, 255))
        canvas = Image.alpha_composite(flat, canvas).convert("RGB")
        canvas.resize((1024, 1024), Image.LANCZOS).save("store/icon_square_1024.png")
        canvas.resize((400, 400), Image.LANCZOS).save("store/icon_square_400.png")
        print("store/icon_square_1024.png store/icon_square_400.png")
        return
    canvas.resize((1024, 1024), Image.LANCZOS).save("store/icon_1024.png")
    canvas.resize((400, 400), Image.LANCZOS).save("store/icon_400.png")
    canvas.resize((64, 64), Image.LANCZOS).save("media/icon.tga")
    print("store/icon_1024.png store/icon_400.png media/icon.tga")


if __name__ == "__main__":
    main()
    main(square=True)
