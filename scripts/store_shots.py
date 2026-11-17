#!/usr/bin/env python3
"""Turns the raw pictures from StoreShotTests into App Store screenshots (6.9 inch, 1320 x 2868):
a caption on the game's own pink, with the screen underneath in a rounded frame.

Usage: python3 scripts/store_shots.py <xcresult attachments dir> <output dir>
"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont

W, H = 1320, 2868
PLUM = (59, 42, 74)
TOP, BOTTOM = (255, 225, 238), (255, 246, 234)

CAPTIONS = {
    "en": ["Sort the squishies!", "Pop a capsule.\nFind an ultra rare!", "Squeeze, stretch\nand squish", "Your very own\nSquishy Buddy",
           "Collect them all", "Hundreds of levels.\nIt never runs out."],
    "ja": ["スクイーズを\nならべよう！", "カプセルをあけて\nウルトラレアをゲット！", "ぎゅっ、びよーん、\nぷにぷに", "じぶんだけの\nスクイーズバディ",
           "ぜんぶ あつめよう", "数百のレベル。\nずっとあそべる。"],
    "ko": ["말랑이를\n정리해요!", "캡슐을 열고\n울트라 레어를 찾아요!", "꾹 누르고, 쭉 늘리고,\n말랑말랑", "나만의\n말랑이 버디",
           "모두 모아 보세요", "수백 개의 레벨.\n끝이 없어요."],
    "zh-Hant": ["把捏捏樂\n分類整理！", "打開扭蛋\n找到超稀有！", "捏一捏、拉一拉、\n軟綿綿", "專屬於你的\n捏捏夥伴",
                "全部收集起來", "數百個關卡\n永遠玩不完"],
}

FONTS = {
    "en": [("/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf", 0), ("/System/Library/Fonts/Helvetica.ttc", 1)],
    "ja": [("/System/Library/Fonts/ヒラギノ丸ゴ ProN W4.ttc", 0), ("/System/Library/Fonts/ヒラギノ角ゴシック W7.ttc", 0),
           ("/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc", 0)],
    "ko": [("/System/Library/Fonts/AppleSDGothicNeo.ttc", 6), ("/System/Library/Fonts/AppleSDGothicNeo.ttc", 0)],
    "zh-Hant": [("/System/Library/Fonts/PingFang.ttc", 8), ("/System/Library/Fonts/Hiragino Sans GB.ttc", 1),
                ("/System/Library/Fonts/STHeiti Medium.ttc", 0), ("/Library/Fonts/Arial Unicode.ttf", 0)],
}
# Last resort for any language (it has every glyph, plainly drawn).
FALLBACK = [("/Library/Fonts/Arial Unicode.ttf", 0), ("/System/Library/Fonts/Supplemental/Arial Unicode.ttf", 0),
            ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 0)]


def font(language, size):
    for path, index in FONTS[language] + FALLBACK:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size, index=index), path
            except Exception:
                try:
                    return ImageFont.truetype(path, size, index=0), path
                except Exception:
                    continue
    return ImageFont.load_default(), "default"


def compose(shot, language, number):
    canvas = Image.new("RGB", (W, H))
    draw = ImageDraw.Draw(canvas)
    for y in range(H):
        t = y / (H - 1)
        draw.line([(0, y), (W, y)], fill=tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)))
    text = CAPTIONS[language][number - 1]
    size = 118
    while True:
        f, used = font(language, size)
        box = draw.multiline_textbbox((0, 0), text, font=f, spacing=22, align="center")
        if box[2] - box[0] <= W - 140 or size <= 60:
            break
        size -= 6
    text_h = box[3] - box[1]
    band = 520
    draw.multiline_text(((W - (box[2] - box[0])) / 2 - box[0], 110 + (band - 110 - text_h) / 2 - box[1]), text, font=f,
                        fill=PLUM, spacing=22, align="center")
    # The screen, in a rounded frame, running off the bottom edge.
    screen = Image.open(shot).convert("RGB")
    width = 1120
    height = round(screen.height * width / screen.width)
    screen = screen.resize((width, height), Image.LANCZOS)
    radius, edge = 84, 14
    mask = Image.new("L", (width, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, width - 1, height - 1], radius=radius, fill=255)
    x, y = (W - width) // 2, band
    draw.rounded_rectangle([x - edge, y - edge, x + width + edge - 1, y + height + edge - 1], radius=radius + edge, fill=PLUM)
    canvas.paste(screen, (x, y), mask)
    return canvas, used


def main():
    src, out = sys.argv[1], sys.argv[2]
    manifest = json.load(open(os.path.join(src, "manifest.json")))
    made = 0
    for test in manifest:
        for a in test.get("attachments", []):
            name = a.get("suggestedHumanReadableName", "")
            if not name.startswith("store-"):
                continue
            # store-<language>-<number>-<name>_... ; the language may hold a hyphen (zh-Hant)
            stem = name.split("_")[0][len("store-"):]
            language = next((l for l in sorted(CAPTIONS, key=len, reverse=True) if stem.startswith(l + "-")), None)
            if language is None:
                continue
            number = int(stem[len(language) + 1:].split("-")[0])
            picture, used = compose(os.path.join(src, a["exportedFileName"]), language, number)
            folder = os.path.join(out, language)
            os.makedirs(folder, exist_ok=True)
            path = os.path.join(folder, f"{number}-{stem.split('-')[-1]}.png")
            picture.save(path)
            made += 1
            print(f"{path} (caption font: {os.path.basename(used)})")
    print(f"{made} screenshots")
    if made == 0:
        raise SystemExit("no store pictures found")


if __name__ == "__main__":
    main()
