#!/usr/bin/env python3
"""Draws the App Store product page header (21:9, 3840x1646) and search results image (3:2, 3840x2560).

    python3 store_assets.py <screenshots dir> <out dir>

Reads <locale>-0.png, -1.png, -2.png (Upcoming, Week, class details; the 1320x2868 App Store
screenshots) for each locale in TEXT and writes header-<locale>.png and search-<locale>.png:
the screenshots in phone frames (frame.py) on the app icon's blue gradient, with a short phrase.
Images have no alpha channel, as App Store Connect requires. Needs Pillow.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, str(Path(__file__).parent))
from frame import STYLES, frame  # noqa: E402

SHOTS, OUT = Path(sys.argv[1]), Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)

BLUE_LIGHT, BLUE_DARK, ORANGE = (0, 112, 208), (0, 56, 132), (242, 167, 53)
FONT = "/System/Library/Fonts/SFNS.ttf"

TEXT = {
    "pl": dict(header=("Plan zajęć", "zawsze pod ręką"), search=("Następne zajęcia", "jednym spojrzeniem")),
    "en-US": dict(header=("Your timetable,", "always at hand"), search=("Your next class", "at a glance")),
}


def font(size, weight=b"Bold"):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def background(w, h):
    """Diagonal blue gradient like the app icon, with two soft orange/blue glows."""
    small = Image.new("RGB", (64, 64))
    px = small.load()
    for y in range(64):
        for x in range(64):
            t = (x / 63 * 0.6 + y / 63 * 0.4)
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(BLUE_LIGHT, BLUE_DARK))
    bg = small.resize((w, h), Image.BICUBIC)
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(glow)
    r = h * 0.55
    d.ellipse((w * 0.78 - r, h * 0.15 - r, w * 0.78 + r, h * 0.15 + r), fill=ORANGE + (70,))
    d.ellipse((w * 0.12 - r, h * 1.0 - r, w * 0.12 + r, h * 1.0 + r), fill=(80, 170, 255, 60))
    glow = glow.filter(ImageFilter.GaussianBlur(h * 0.25))
    return Image.alpha_composite(bg.convert("RGBA"), glow)


def phone(locale, index, height, angle=0.0):
    shot = Image.open(SHOTS / f"{locale}-{index}.png").convert("RGB")
    p = frame(shot, STYLES["ios"])
    p = p.resize((round(p.width * height / p.height), height), Image.LANCZOS)
    if angle:
        p = p.rotate(angle, resample=Image.BICUBIC, expand=True)
    return p


def paste_with_shadow(canvas, img, x, y, blur=60, offset=30, opacity=110):
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    alpha = img.getchannel("A").point(lambda a: a * opacity // 255)
    shadow.paste((0, 20, 60, 255), (x, y + offset), alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(img, (x, y))


def headline(d, lines, x, y, size, anchor="la", spacing=1.12):
    first, second = lines
    d.text((x, y), first, font=font(size), fill="white", anchor=anchor)
    d.text((x, y + size * spacing), second, font=font(size), fill=ORANGE, anchor=anchor)


def header(locale):
    W, H = 3840, 1646
    c = background(W, H)
    # Phones on the right half, bleeding off the bottom.
    ph = 1560
    left, mid, right = phone(locale, 1, round(ph * 0.9), 8), phone(locale, 0, ph), phone(locale, 2, round(ph * 0.9), -8)
    cx = 2930
    paste_with_shadow(c, left, cx - 430 - left.width // 2, 330)
    paste_with_shadow(c, right, cx + 430 - right.width // 2, 330)
    paste_with_shadow(c, mid, cx - mid.width // 2, 200)
    d = ImageDraw.Draw(c)
    # Text on the left, inside the middle 70% of the width.
    headline(d, TEXT[locale]["header"], 500, H // 2 - 225, 200)
    return c.convert("RGB")


def search(locale):
    W, H = 3840, 2560
    c = background(W, H)
    d = ImageDraw.Draw(c)
    first, second = TEXT[locale]["search"]
    d.text((W // 2, 330), first, font=font(260), fill="white", anchor="mm")
    d.text((W // 2, 330 + 290), second, font=font(260), fill=ORANGE, anchor="mm")
    ph = 2350
    left, mid, right = phone(locale, 1, round(ph * 0.92), 6), phone(locale, 0, ph), phone(locale, 2, round(ph * 0.92), -6)
    paste_with_shadow(c, left, W // 2 - 1150 - left.width // 2, 1030)
    paste_with_shadow(c, right, W // 2 + 1150 - right.width // 2, 1030)
    paste_with_shadow(c, mid, W // 2 - mid.width // 2, 880)
    return c.convert("RGB")


for locale in TEXT:
    header(locale).save(OUT / f"header-{locale}.png", optimize=True)
    search(locale).save(OUT / f"search-{locale}.png", optimize=True)
    print("wrote", locale)
