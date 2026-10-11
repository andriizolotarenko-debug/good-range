"""Draws media/needle.tga: the gold centre needle of the range tape.

The texture is 64x64, 4 texels per UI pixel at 1x (16x16 logical units). Rows are sliced in
Lua: head = logical rows 0-9, stem = rows 9.5-11 (uniform, stretched), tip = rows 12-16.
Run from the repo root: python3 tools/make_art.py
"""
from PIL import Image, ImageDraw

SS = 16          # supersampling: logical unit -> 16 px, then downsampled 4x to 64x64
L = 16           # logical size
CX = 8.0         # centre
HEAD_W, HEAD_H, STEM, TIP_TOP, TIP_Y, TOP = 5.5, 7.5, 1.0, 12.0, 15.0, 1.5
OUTLINE = (20, 12, 0, 220)

def P(x, y):
    return (x * SS, y * SS)

shape = [P(CX - HEAD_W, TOP), P(CX + HEAD_W, TOP), P(CX + STEM, HEAD_H), P(CX + STEM, TIP_TOP),
         P(CX, TIP_Y), P(CX - STEM, TIP_TOP), P(CX - STEM, HEAD_H)]

size = L * SS
outline = Image.new("L", (size, size), 0)
d = ImageDraw.Draw(outline)
d.polygon(shape, fill=255)
# grow the shape by one logical pixel for the dark outline
outline = outline.resize((size, size))
from PIL import ImageFilter
grown = outline.filter(ImageFilter.MaxFilter(2 * SS + 1))

fill = Image.new("L", (size, size), 0)
ImageDraw.Draw(fill).polygon(shape, fill=255)

# horizontal gold gradient across the head
stops = [(0.0, (255, 244, 194)), (0.42, (255, 209, 0)), (0.58, (240, 180, 0)), (1.0, (156, 106, 8))]
def gold(t):
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            k = (t - t0) / (t1 - t0) if t1 > t0 else 0
            return tuple(round(a + (b - a) * k) for a, b in zip(c0, c1))
    return stops[-1][1]

grad = Image.new("RGBA", (size, size))
x0, x1 = (CX - HEAD_W) * SS, (CX + HEAD_W) * SS
for x in range(size):
    t = min(1, max(0, (x - x0) / (x1 - x0)))
    c = gold(t)
    for y in range(size):
        grad.putpixel((x, y), c + (255,))
# bevel: a light line along the top of the head
bevel = ImageDraw.Draw(grad)
bevel.rectangle([P(CX - HEAD_W + 1.5, TOP + 0.4), P(CX + HEAD_W - 1.5, TOP + 1.1)], fill=(255, 250, 220, 255))

img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
img.paste(Image.new("RGBA", (size, size), OUTLINE), (0, 0), grown)
img.paste(grad, (0, 0), fill)
img = img.resize((64, 64), Image.LANCZOS)
img.save("media/needle.tga")
print("media/needle.tga", img.size)
