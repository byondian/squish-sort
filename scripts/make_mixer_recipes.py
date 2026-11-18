#!/usr/bin/env python3
"""Makes Content/mixer-recipes.json: what each collectible lends to the Squishy Mixer.

For every squishy in Content/roster.json it reads the squishy's own picture and writes
the Workshop mould whose outline is closest to it, its two main colours and its feel.
No parts: a collectible only lends its look. Run again whenever the roster or its art changes;
the unit tests fail if a roster squishy has no recipe.
"""
import colorsys
import json
import os
from collections import Counter

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
N = 48


def shape(alpha):
    """The picture's solid part, cut to its own box and scaled to N x N, as a list of 0/1."""
    box = alpha.point(lambda a: 255 if a > 96 else 0).getbbox()
    if not box:
        return [0] * (N * N)
    cut = alpha.crop(box).resize((N, N), Image.BILINEAR)
    return [1 if a > 96 else 0 for a in cut.tobytes()]


def overlap(a, b):
    both = sum(1 for x, y in zip(a, b) if x and y)
    either = sum(1 for x, y in zip(a, b) if x or y)
    return both / either if either else 0


def colours(image):
    """The two most common body colours, leaving out the dark outline and the white shine."""
    small = image.convert("RGBA").resize((64, 64), Image.BILINEAR)
    seen = Counter()
    raw = small.tobytes()
    for i in range(0, len(raw), 4):
        r, g, b, a = raw[i], raw[i + 1], raw[i + 2], raw[i + 3]
        if a < 200:
            continue
        h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
        if l < 0.42 or (l > 0.93 and s < 0.3):
            continue
        seen[(r >> 4, g >> 4, b >> 4)] += 1
    if not seen:
        return ["#FF9EB5", "#FF9EB5"]
    picks = []
    for (r, g, b), _ in seen.most_common():
        rgb = (r * 16 + 8, g * 16 + 8, b * 16 + 8)
        # The second colour has to look different from the first.
        if all(sum(abs(x - y) for x, y in zip(rgb, p)) > 90 for p in picks):
            picks.append(rgb)
        if len(picks) == 2:
            break
    if len(picks) == 1:
        picks.append(picks[0])
    return ["#%02X%02X%02X" % p for p in picks]


def main():
    roster = json.load(open(os.path.join(ROOT, "Content/roster.json")))
    parts = json.load(open(os.path.join(ROOT, "Content/workshop-parts.json")))
    moulds = {}
    for name in parts["moulds"]:
        path = os.path.join(ROOT, "Content/workshop", "mould-%s.png" % name)
        if os.path.exists(path):
            moulds[name] = shape(Image.open(path).convert("RGBA").getchannel("A"))
    out = {}
    for squishy in roster["collectibles"] + roster["squishRoomToys"]:
        folder = os.path.join(ROOT, "App/Resources/Squishies.xcassets", "squishy-%s.imageset" % squishy["id"])
        files = sorted(f for f in os.listdir(folder) if f.endswith(".png")) if os.path.isdir(folder) else []
        if not files:
            raise SystemExit("no picture for " + squishy["id"])
        image = Image.open(os.path.join(folder, files[0])).convert("RGBA")
        own = shape(image.getchannel("A"))
        best = max(sorted(moulds), key=lambda m: overlap(own, moulds[m]))
        feel = squishy.get("feel", "jelly")
        out[squishy["id"]] = {
            "mould": best,
            "colours": colours(image),
            "feel": feel if feel in ("jelly", "foam", "gel", "mochi") else "jelly",
        }
    with open(os.path.join(ROOT, "Content/mixer-recipes.json"), "w") as f:
        json.dump(out, f, indent=1, sort_keys=True)
        f.write("\n")
    print(len(out), "recipes;", Counter(v["mould"] for v in out.values()).most_common())


if __name__ == "__main__":
    main()
