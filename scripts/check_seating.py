#!/usr/bin/env python3
"""Checks how every squishy picture will sit in a jar.

The board seats a picture by the box around its solid part: bottom on the slot's
baseline, centred, scaled so the longer side fills the slot (PieceNode.swift).
That only looks even if the art is drawn sensibly inside its box, so this fails
when a picture would sit off centre, tiny or stretched.
"""
import glob, os, sys
from PIL import Image

N = 64
problems, rows = [], []
for folder in sorted(glob.glob("App/Resources/Squishies.xcassets/squishy-*.imageset")):
    name = os.path.basename(folder)[len("squishy-"):-len(".imageset")]
    files = sorted(glob.glob(folder + "/*.png"))
    if not files:
        problems.append(f"{name}: no picture")
        continue
    alpha = Image.open(files[-1]).convert("RGBA").resize((N, N), Image.BILINEAR).getchannel("A")
    solid = [(x, y) for y in range(N) for x in range(N) if alpha.getpixel((x, y)) > 40]
    if not solid:
        problems.append(f"{name}: picture is empty")
        continue
    xs, ys = [p[0] for p in solid], [p[1] for p in solid]
    x0, x1, y0, y1 = min(xs), max(xs) + 1, min(ys), max(ys) + 1
    w, h = (x1 - x0) / N, (y1 - y0) / N
    side = min(1.6, 0.96 / max(w, h, 0.4))
    wide, tall = w * side, h * side               # share of the slot it fills
    lean = (sum(xs) / len(xs) + 0.5 - (x0 + x1) / 2) / (x1 - x0)   # weight left or right of the box centre
    rows.append((name, wide, tall, lean))
    if min(wide, tall) < 0.6:
        problems.append(f"{name}: fills only {wide:.2f} x {tall:.2f} of its slot")
    if max(wide, tall) < 0.9:
        problems.append(f"{name}: too small in its slot ({wide:.2f} x {tall:.2f})")
    if abs(lean) > 0.07:
        problems.append(f"{name}: sits off centre by {lean:+.2f} of its width")

print(f"{len(rows)} pictures checked")
for p in problems:
    print("FAIL", p)
sys.exit(1 if problems or not rows else 0)
