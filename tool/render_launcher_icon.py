# Usage: python tool/render_launcher_icon.py android/app/src/main/res <preview.png>
# Legacy launcher PNGs (pre-API 26), same geometry as
# drawable/ic_launcher_foreground.xml: a doorway (home) outlined, with two
# figures standing in it side by side (the two of you), on a rounded square.
import sys
from PIL import Image, ImageDraw
res, preview = sys.argv[1], sys.argv[2]
BG, FRAME, A, B = (0x1C,0x18,0x15,255), (0xE9,0xA0,0x8A,255), (0xE9,0xA0,0x8A,255), (0xC0,0x57,0x3F,255)
def render(px):
    k = 8; n = px*k
    img = Image.new("RGBA", (n, n), (0,0,0,0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0,0,n-1,n-1], radius=int(n*0.22), fill=BG)
    s = n/108*1.35; o = n/2 - 54*s
    X = lambda v: o + v*s
    # Doorway: outer x 34..74, arch centre (54,48) r 20, base y 82, stroke 5.
    d.ellipse([X(34), X(28), X(74), X(68)], fill=FRAME)
    d.rectangle([X(34), X(48), X(74), X(82)], fill=FRAME)
    d.ellipse([X(39), X(33), X(69), X(63)], fill=BG)
    d.rectangle([X(39), X(48), X(69), X(82)], fill=BG)
    # Two figures: head + rounded body, side by side.
    for cx, col in ((47.5, A), (60.5, B)):
        d.ellipse([X(cx-4), X(53), X(cx+4), X(61)], fill=col)
        d.rounded_rectangle([X(cx-5.5), X(63), X(cx+5.5), X(82)], radius=5.5*s, fill=col)
    return img.resize((px,px), Image.LANCZOS)
if res != "-":
    for name, px in [("mdpi",48),("hdpi",72),("xhdpi",96),("xxhdpi",144),("xxxhdpi",192)]:
        render(px).save(f"{res}/mipmap-{name}/ic_launcher.png", optimize=True)
render(512).save(preview)
