# -*- coding: utf-8 -*-
"""生成 GL 字体图集: assets/font_atlas.png + font_atlas.json
把 UI 全部文案的字符烤进一张图集，运行时 GL 查 UV 画 quad。
"""
import json, os
from PIL import Image, ImageDraw, ImageFont

SIZE = 40          # 图集字形像素高
CELL_W = 40
CELL_H = 44
COLS = 16
ROWS = 16          # 256 格

TEXTS = (
    "压缩器 Compressor 增益 Gain 阈值 Threshold 比率 Ratio "
    "仅图形不音频 打开文件 播放 暂停 文件 未加载 dB :1 x Hz GLSpeaker "
    "0123456789 .-:,()x/ "
    "!\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`"
    "abcdefghijklmnopqrstuvwxyz{|}~"
)

FONTS = [
    r"C:\Windows\Fonts\msyh.ttc",
    r"C:\Windows\Fonts\msyh.ttf",
    r"C:\Windows\Fonts\simhei.ttf",
    r"C:\Windows\Fonts\arial.ttf",
]

font = None
for p in FONTS:
    if os.path.exists(p):
        try:
            font = ImageFont.truetype(p, SIZE)
            print("using font:", p)
            break
        except Exception as e:
            print("skip", p, e)
if font is None:
    raise SystemExit("no font found")

chars = []
for ch in TEXTS:
    if ch != ' ' and ch not in chars:
        chars.append(ch)
print("chars:", len(chars))
if len(chars) > COLS * ROWS:
    raise SystemExit("too many chars for atlas")

img = Image.new("RGBA", (COLS * CELL_W, ROWS * CELL_H), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

meta = {"size": SIZE, "cellW": CELL_W, "cellH": CELL_H, "cols": COLS, "rows": ROWS, "chars": {}}
for idx, ch in enumerate(chars):
    col = idx % COLS
    row = idx // COLS
    x = col * CELL_W
    y = row * CELL_H
    draw.text((x + 2, y + 2), ch, font=font, fill=(255, 255, 255, 255))
    bbox = draw.textbbox((x + 2, y + 2), ch, font=font)
    adv = draw.textlength(ch, font=font)
    meta["chars"][ch] = {
        "u": x, "v": y,
        "w": bbox[2] - bbox[0],
        "h": bbox[3] - bbox[1],
        "ox": bbox[0] - x,
        "oy": bbox[1] - y,
        "adv": adv,
    }

img.save("assets/font_atlas.png")
with open("assets/font_atlas.json", "w", encoding="utf-8") as f:
    json.dump(meta, f, ensure_ascii=False)
print("atlas:", img.size, "chars:", len(meta["chars"]))
