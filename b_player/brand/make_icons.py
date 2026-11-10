#!/usr/bin/env python3
"""B端 应用图标生成：绿色小写 e + 八分音符，铺到 Android / iOS / Windows / Web。

改设计只需要动下面的坐标常量，然后 `python brand/make_icons.py` 重跑一次。
"""
from __future__ import annotations

import json
import math
import pathlib

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parents[1]

BG_TOP = (12, 33, 25, 255)
BG_BOT = (5, 16, 13, 255)
INK_TOP = (75, 232, 154, 255)
INK_BOT = (28, 178, 104, 255)

# 1024 设计坐标。左边几何小写 e（右下开口），音符嵌在开口里、留一条可见的缝。
E_C = (348, 500)
E_ROUT, E_RIN = 186, 115
E_BAR = (232, 534, 464, 536)           # 横杠 left, right, top, bottom
E_APERTURE = (8, 60)                   # 开口角度（度，y 轴向下）
STEM = (660, 726)                      # 符干 x 区间
NOTE_TOP, NOTE_BOT = 150, 636
HEAD_CENTER = (634, 618)
HEAD_SIZE = (164, 114)                 # 符头外接框（旋转前）
HEAD_TILT = 22
# 符尾：上厚下尖的一条外弯钩（二次贝塞尔）
FLAG_OUT = ((726, 150), (854, 178), (826, 344))
FLAG_IN = ((826, 344), (794, 240), (726, 240))

SS = 3


def _bez(p0, p1, p2, n=24):
    pts = []
    for i in range(n + 1):
        t = i / n
        mt = 1 - t
        pts.append((mt * mt * p0[0] + 2 * mt * t * p1[0] + t * t * p2[0],
                    mt * mt * p0[1] + 2 * mt * t * p1[1] + t * t * p2[1]))
    return pts


def _rot_ellipse(c, size, tilt_deg, k, n=120):
    """长轴右高、按 tilt 逆时针倾斜的实心椭圆（音符头），返回缩放后的多边形顶点。"""
    a, b, phi = size[0] / 2 * k, size[1] / 2 * k, math.radians(tilt_deg)
    cx, cy = c[0] * k, c[1] * k
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        pts.append((cx + a * math.cos(t) * math.cos(phi) + b * math.sin(t) * math.sin(phi),
                    cy - a * math.cos(t) * math.sin(phi) + b * math.sin(t) * math.cos(phi)))
    return pts


def _vgrad(size, top, bottom):
    w, h = size
    ramp = Image.linear_gradient("L").resize((w, h))
    return Image.composite(
        Image.new("RGBA", size, bottom), Image.new("RGBA", size, top), ramp
    )


def _point(angle, radius):
    return (E_C[0] + radius * math.cos(math.radians(angle)),
            E_C[1] + radius * math.sin(math.radians(angle)))


def _ink_mask(S):
    k = S / 1024
    x = lambda v: v * k
    y = lambda v: v * k
    ink = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(ink)

    # e：圆环 -> 挖掉右下开口 -> 补上中间横杠
    d.ellipse([x(E_C[0] - E_ROUT), y(E_C[1] - E_ROUT), x(E_C[0] + E_ROUT), y(E_C[1] + E_ROUT)], fill=255)
    d.ellipse([x(E_C[0] - E_RIN), y(E_C[1] - E_RIN), x(E_C[0] + E_RIN), y(E_C[1] + E_RIN)], fill=0)
    a0, a1 = E_APERTURE
    wedge = [_point(t, 0) for t in [a0 - 4]] + [_point(t, E_ROUT + 90) for t in
               [a0 + i for i in range(0, int(a1 - a0) + 1, 4)]] + [_point(a1 + 4, 0)]
    d.polygon([(x(a), y(b)) for a, b in wedge], fill=0)
    l, r, t, b = E_BAR
    d.rectangle([x(l), y(t), x(r), y(b)], fill=255)

    # 音符：符干 + 弯钩符尾 + 斜符头
    d.rectangle([x(STEM[0]), y(NOTE_TOP), x(STEM[1]), y(NOTE_BOT)], fill=255)
    flag = _bez(*FLAG_OUT) + _bez(*FLAG_IN)[1:]
    d.polygon([(x(a), y(b)) for a, b in flag], fill=255)
    d.polygon(_rot_ellipse(HEAD_CENTER, HEAD_SIZE, HEAD_TILT, k), fill=255)
    return ink


def mark():
    S = 1024 * SS
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    layer.paste(_vgrad((S, S), INK_TOP, INK_BOT), (0, 0), _ink_mask(S))
    return layer.crop(layer.getbbox())


def icon(size, fill_ratio, shape="square", alpha=False):
    """size x size 图标；fill_ratio = 图形高度占图标的比例。"""
    s = int(size * SS)
    canvas = Image.new("RGBA", (s, s), (0, 0, 0, 0)) if alpha else _vgrad((s, s), BG_TOP, BG_BOT)
    m = mark()
    h = int(s * fill_ratio)
    m = m.resize((int(m.width * h / m.height), h), Image.LANCZOS)
    canvas.paste(m, ((s - m.width) // 2, (s - m.height) // 2), m)

    if shape != "square":
        mask = Image.new("L", (s, s), 0)
        d = ImageDraw.Draw(mask)
        if shape == "circle":
            d.ellipse([0, 0, s - 1, s - 1], fill=255)
        else:
            d.rounded_rectangle([0, 0, s - 1, s - 1], radius=s * 0.2237, fill=255)
        out = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        out.paste(canvas, (0, 0), mask)
        canvas = out

    canvas = canvas.resize((int(size), int(size)), Image.LANCZOS)
    return canvas if (alpha or shape != "square") else canvas.convert("RGB")


def save(img, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    print("wrote", path.relative_to(ROOT))


def main():
    android_fill, adaptive_fill = 0.54, 0.42
    res = ROOT / "android" / "app" / "src" / "main" / "res"
    for folder, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        save(icon(px, android_fill), res / f"mipmap-{folder}" / "ic_launcher.png")
        save(icon(px, android_fill, shape="circle"), res / f"mipmap-{folder}" / "ic_launcher_round.png")
    for folder, px in {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}.items():
        save(icon(px, adaptive_fill, alpha=True), res / f"drawable-{folder}" / "ic_launcher_foreground.png")

    (res / "drawable" / "ic_launcher_background.xml").write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android">
    <gradient
        android:angle="270"
        android:startColor="#0C2119"
        android:endColor="#05100D" />
</shape>
""",
        encoding="utf-8",
    )
    adaptive = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
"""
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        (res / "mipmap-anydpi-v26" / name).write_text(adaptive, encoding="utf-8")

    appicon = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    contents = json.loads((appicon / "Contents.json").read_text(encoding="utf-8"))
    for entry in contents["images"]:
        side = int(round(float(entry["size"].split("x")[0]) * int(entry.get("scale", "1x").strip("@x") or 1)))
        save(icon(side, 0.58), appicon / entry["filename"])

    win = ROOT / "windows" / "runner" / "resources"
    icon(256, 0.60).save(win / "app_icon.ico", sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])
    print("wrote", (win / "app_icon.ico").relative_to(ROOT))

    # 托盘图标走 Flutter asset，路径要与 pubspec.yaml 的 assets 一致。
    tray = ROOT / "assets" / "icons"
    tray.mkdir(parents=True, exist_ok=True)
    icon(64, 0.72).save(tray / "enode.ico", sizes=[(s, s) for s in (16, 24, 32, 48, 64)])
    print("wrote", (tray / "enode.ico").relative_to(ROOT))

    web = ROOT / "web"
    save(icon(192, 0.58), web / "icons" / "Icon-192.png")
    save(icon(512, 0.58), web / "icons" / "Icon-512.png")
    save(icon(192, 0.50), web / "icons" / "Icon-maskable-192.png")
    save(icon(512, 0.50), web / "icons" / "Icon-maskable-512.png")
    save(icon(48, 0.66), web / "favicon.png")

    brand = ROOT / "brand"
    save(icon(1024, 0.58, shape="squircle"), brand / "enode-logo-1024.png")
    save(icon(1024, 0.50, alpha=True), brand / "enode-mark-1024.png")

    sheet = Image.new("RGBA", (1600 * SS, 620 * SS), (244, 246, 247, 255))
    sheet.paste(Image.new("RGBA", (800 * SS, 620 * SS), (11, 14, 16, 255)), (800 * SS, 0))
    sizes = [(40, 300), (380, 168), (600, 96), (720, 48)]
    for cx, side in sizes:
        art = icon(side, 0.54, shape="squircle")
        sheet.paste(art, (cx * SS, (620 - side) // 2 * SS), art)
    for cx, side in sizes:
        art = icon(side, 0.54, shape="circle")
        sheet.paste(art, ((800 + cx) * SS, (620 - side) // 2 * SS), art)
    sheet.resize((1600, 620), Image.LANCZOS).save(brand / "preview.png")
    print("wrote", (brand / "preview.png").relative_to(ROOT))


if __name__ == "__main__":
    main()
