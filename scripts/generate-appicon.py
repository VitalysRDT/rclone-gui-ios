#!/usr/bin/env python3
"""
Generate Rclone GUI iOS AppIcon (1024×1024 light + dark + tinted variants).

iOS 18+ AppIconSet model:
  - light (default appearance)
  - luminosity:dark
  - luminosity:tinted (grayscale, system tints it)

Design: stacked cloud silhouette with circular sync arrows. Solid, minimal,
recognizable at small sizes. iOS auto-derives all smaller sizes from 1024.

This produces a placeholder-quality but clean icon. Replace with branded art
before public App Store release if desired.
"""

import os
import math
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APPICON = os.path.join(ROOT, "Rclone GUI", "Assets.xcassets", "AppIcon.appiconset")
SIZE = 1024


def draw_icon(bg_top, bg_bottom, fg, fname):
    """Draw a 1024 PNG with a vertical gradient background + foreground glyph."""
    img = Image.new("RGB", (SIZE, SIZE), bg_top)
    draw = ImageDraw.Draw(img)

    # Vertical gradient
    for y in range(SIZE):
        t = y / (SIZE - 1)
        r = int(bg_top[0] * (1 - t) + bg_bottom[0] * t)
        g = int(bg_top[1] * (1 - t) + bg_bottom[1] * t)
        b = int(bg_top[2] * (1 - t) + bg_bottom[2] * t)
        draw.line([(0, y), (SIZE, y)], fill=(r, g, b))

    cx, cy = SIZE / 2, SIZE / 2

    # Cloud silhouette (filled), built from overlapping circles + a base bar
    cloud_y = cy - 60
    bumps = [
        (cx - 220, cloud_y + 40, 150),
        (cx - 80, cloud_y - 30, 175),
        (cx + 80, cloud_y - 10, 165),
        (cx + 230, cloud_y + 50, 140),
    ]
    for bx, by, br in bumps:
        draw.ellipse(
            [(bx - br, by - br), (bx + br, by + br)],
            fill=fg,
        )
    # base rectangle to flatten the bottom of the cloud
    draw.rectangle(
        [(cx - 360, cloud_y + 30), (cx + 360, cloud_y + 200)],
        fill=fg,
    )

    # Sync arrow ring around the cloud — circular arc with two arrow heads
    ring_r = 380
    ring_w = 56
    # Top half of ring (clockwise arrow)
    draw.arc(
        [(cx - ring_r, cy - ring_r), (cx + ring_r, cy + ring_r)],
        start=200, end=340,
        fill=fg, width=ring_w,
    )
    # Arrowhead at end of top arc (right side, pointing down)
    a_angle = math.radians(340)
    ax = cx + ring_r * math.cos(a_angle)
    ay = cy + ring_r * math.sin(a_angle)
    head = 60
    draw.polygon(
        [
            (ax + head, ay - head * 0.2),
            (ax - head * 0.3, ay - head),
            (ax - head * 0.2, ay + head * 0.9),
        ],
        fill=fg,
    )

    out = os.path.join(APPICON, fname)
    img.save(out, "PNG", optimize=True)
    print(f"  wrote {fname}")


def main():
    os.makedirs(APPICON, exist_ok=True)
    print(f"Writing AppIcon variants to {APPICON}")

    # Light: deep navy gradient + white glyph
    draw_icon(
        bg_top=(20, 50, 95),
        bg_bottom=(8, 22, 45),
        fg=(245, 248, 255),
        fname="AppIcon-1024.png",
    )
    # Dark: pure black to charcoal + cream glyph
    draw_icon(
        bg_top=(22, 24, 28),
        bg_bottom=(0, 0, 0),
        fg=(220, 226, 235),
        fname="AppIcon-1024-dark.png",
    )
    # Tinted: medium gray bg + white glyph (system applies tint over this)
    draw_icon(
        bg_top=(60, 60, 60),
        bg_bottom=(30, 30, 30),
        fg=(255, 255, 255),
        fname="AppIcon-1024-tinted.png",
    )

    # Update Contents.json to reference the files and drop Mac platform slots
    # (this app is iOS-only). Three iOS universal slots remain.
    contents = '''{
  "images" : [
    {
      "filename" : "AppIcon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "AppIcon-1024-dark.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "tinted"
        }
      ],
      "filename" : "AppIcon-1024-tinted.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
'''
    with open(os.path.join(APPICON, "Contents.json"), "w", encoding="utf-8") as f:
        f.write(contents)
    print("  wrote Contents.json (iOS-only, references PNGs)")


if __name__ == "__main__":
    main()
