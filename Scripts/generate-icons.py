#!/usr/bin/env python3
"""Generate AFK menu bar icon — atomic style with a twist."""

from PIL import Image, ImageDraw
import math

RESOURCE_DIR = "Sources/AFK/Resources"


def draw_atom(draw, size):
    f = size / 36.0
    lw = max(2, int(2 * f))

    cx, cy = 18 * f, 18 * f
    rx, ry = 15 * f, 6 * f

    for idx, angle_deg in enumerate([0, 60, 120]):
        pts = []
        for t in range(0, 361, 3):
            rad = math.radians(t)
            x = rx * math.cos(rad)
            y = ry * math.sin(rad)
            rot = math.radians(angle_deg)
            rx2 = x * math.cos(rot) - y * math.sin(rot)
            ry2 = x * math.sin(rot) + y * math.cos(rot)
            pts.append((cx + rx2, cy + ry2))

        # Third orbit: break it open (the "away" gap)
        if idx == 2:
            gap_start, gap_end = 40, 70
            for i in range(len(pts) - 1):
                t = (i * 360) / len(pts)
                if gap_start < t < gap_end:
                    continue
                draw.line([pts[i], pts[i + 1]], fill="black", width=lw)
        else:
            for i in range(len(pts) - 1):
                draw.line([pts[i], pts[i + 1]], fill="black", width=lw)

    # Electron dot on the broken orbit's gap edge
    gap_t = math.radians(40)
    rot = math.radians(120)
    ex = rx * math.cos(gap_t)
    ey = ry * math.sin(gap_t)
    dot_x = cx + ex * math.cos(rot) - ey * math.sin(rot)
    dot_y = cy + ex * math.sin(rot) + ey * math.cos(rot)
    dot_r = 2.2 * f
    draw.ellipse([dot_x - dot_r, dot_y - dot_r, dot_x + dot_r, dot_y + dot_r], fill="black")

    # Core — small diamond/sparkle instead of circle
    sr = 3.5 * f
    ir = 1.2 * f
    core_pts = [
        (cx, cy - sr), (cx + ir, cy - ir),
        (cx + sr, cy), (cx + ir, cy + ir),
        (cx, cy + sr), (cx - ir, cy + ir),
        (cx - sr, cy), (cx - ir, cy - ir),
    ]
    draw.polygon(core_pts, fill="black")


for size, suffix in [(18, ""), (36, "@2x")]:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw_atom(draw, size)
    path = f"{RESOURCE_DIR}/menubar-atom{suffix}.png"
    img.save(path)
    print(f"{path} ({size}x{size})")
