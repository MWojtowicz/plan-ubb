#!/usr/bin/env python3
"""Draws a phone frame around simulator/emulator screenshots for the README.

    python3 frame.py ios     raw/ios-*.png
    python3 frame.py android raw/android-*.png

Writes <name>.png next to this script: the screenshot with rounded corners inside a black
bezel and a metal edge, with side buttons and the Dynamic Island / punch-hole camera, on a
transparent background (so it looks right on both light and dark GitHub themes).
Needs Pillow (`pip install Pillow`).

Taking the raw screenshots:
- iOS: `TEST_RUNNER_SCREENSHOT_DIR=raw xcodebuild -scheme PlanUbb -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
  -only-testing:PlanUbbUITests/ScreenshotTests test` (from ios/; `xcrun simctl status_bar … override` for a full battery).
- Android: a Pixel 10 Pro emulator with the debug build, opened with `--ei plan 142113`, the system's demo mode for
  the status bar, then `adb exec-out screencap -p` on Upcoming, Week and a class's details.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

# Sizes are fractions of the screenshot width, so any resolution works.
STYLES = {
    "ios": dict(  # iPhone 18 Pro
        screen_radius=0.155, bezel=0.032, edge=0.012, edge_color=(150, 152, 158), body_color=(12, 12, 14),
        # Dynamic Island: a pill centred near the top.
        cutout=("pill", 0.313, 0.092, 0.027),
        buttons=[("left", 0.17, 0.035), ("left", 0.24, 0.07), ("left", 0.325, 0.07), ("right", 0.26, 0.11)],
    ),
    "android": dict(  # Pixel 10 Pro
        screen_radius=0.11, bezel=0.03, edge=0.012, edge_color=(170, 172, 178), body_color=(12, 12, 14),
        # Punch-hole camera: a circle centred in the status bar.
        cutout=("circle", 0.044, 0.044, 0.039),
        buttons=[("right", 0.2, 0.06), ("right", 0.31, 0.12)],
    ),
}
OUTPUT_WIDTH = 600


def frame(shot: Image.Image, style: dict) -> Image.Image:
    w, h = shot.size
    bezel, edge = round(style["bezel"] * w), round(style["edge"] * w)
    button_depth = edge
    margin = bezel + edge
    radius = round(style["screen_radius"] * w)
    W, H = w + 2 * margin + 2 * button_depth, h + 2 * margin
    ox = button_depth  # the body starts after the left buttons

    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(out)

    # Side buttons stick out of the metal edge.
    for side, top, length in style["buttons"]:
        y0, y1 = round(top * h) + margin, round((top + length) * h) + margin
        x0, x1 = (0, ox + edge) if side == "left" else (W - button_depth - edge, W)
        d.rounded_rectangle((x0, y0, x1, y1), radius=button_depth, fill=style["edge_color"])

    # Metal edge, then the black bezel inside it.
    body = (ox, 0, ox + w + 2 * margin - 1, H - 1)
    d.rounded_rectangle(body, radius=radius + margin, fill=style["edge_color"])
    d.rounded_rectangle((body[0] + edge, edge, body[2] - edge, H - 1 - edge), radius=radius + bezel, fill=style["body_color"])

    # The screenshot with rounded corners.
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, fill=255)
    out.paste(shot.convert("RGBA"), (ox + margin, margin), mask)

    # Dynamic Island or camera hole, drawn over the status bar.
    kind, cw, ch, top = style["cutout"]
    cw, ch, top = round(cw * w), round(ch * w), round(top * w)
    x0, y0 = ox + margin + (w - cw) // 2, margin + top
    if kind == "pill":
        d.rounded_rectangle((x0, y0, x0 + cw, y0 + ch), radius=ch // 2, fill=(0, 0, 0))
    else:
        d.ellipse((x0, y0, x0 + cw, y0 + ch), fill=(0, 0, 0))

    return out.resize((OUTPUT_WIDTH, round(H * OUTPUT_WIDTH / W)), Image.LANCZOS)


def main():
    style = STYLES[sys.argv[1]]
    for path in map(Path, sys.argv[2:]):
        target = Path(__file__).with_name(path.name)
        frame(Image.open(path), style).save(target, optimize=True)
        print(target)


if __name__ == "__main__":
    main()
