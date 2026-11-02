#!/usr/bin/env python3
"""Printable A5-ish "Scan to order" poster for the shop counter.
python3 tools/make_poster.py <order-url> <out.png>"""
import sys
from pathlib import Path

import qrcode
from qrcode.constants import ERROR_CORRECT_H
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "assets" / "fonts"
GREEN, DARK, SAFFRON = (20, 135, 74), (12, 17, 15), (255, 153, 51)


def font(weight, size):
    return ImageFont.truetype(str(FONT / f"Mukta-{weight}.ttf"), size, layout_engine=ImageFont.Layout.RAQM)


def centered(draw, y, text, f, fill, width):
    w = draw.textlength(text, font=f)
    draw.text(((width - w) / 2, y), text, font=f, fill=fill)


def main():
    url, out = sys.argv[1], sys.argv[2]
    W, H = 1240, 1754  # A5 at 300 dpi-ish proportions
    img = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, 330], fill=GREEN)
    centered(d, 60, "Chhabra General Store", font("Bold", 92), "white", W)
    centered(d, 175, "छाबड़ा जनरल स्टोर", font("SemiBold", 78), (230, 255, 238), W)
    centered(d, 400, "घर बैठे सामान मँगाएँ", font("Bold", 84), DARK, W)
    centered(d, 505, "Scan karke order karein · Scan to order", font("Regular", 46), (70, 80, 75), W)

    qr = qrcode.QRCode(error_correction=ERROR_CORRECT_H, box_size=20, border=2)
    qr.add_data(url)
    qr.make(fit=True)
    q = qr.make_image(fill_color=DARK, back_color="white").convert("RGB").resize((760, 760), Image.NEAREST)
    qx, qy = (W - 760) // 2, 600
    d.rounded_rectangle([qx - 24, qy - 24, qx + 784, qy + 784], radius=36, outline=SAFFRON, width=10)
    img.paste(q, (qx, qy))
    # Shop monogram in the middle of the QR (high error correction keeps it scannable)
    c = 150
    cx, cy = W // 2 - c // 2, qy + 380 - c // 2
    d.rounded_rectangle([cx, cy, cx + c, cy + c], radius=36, fill=GREEN, outline="white", width=8)
    centered(d, cy + 8, "C", font("Bold", 112), "white", W)

    y = 1430
    for line in ["1. Phone ke camera se QR scan karein", "2. Saman chunein  >  Cart  >  Order",
                 "3. Order ki live jaankari phone par"]:
        centered(d, y, line, font("SemiBold", 44), DARK, W)
        y += 66
    centered(d, H - 70, url, font("Regular", 30), (110, 120, 115), W)
    img.save(out, dpi=(300, 300))
    print("poster →", out)


if __name__ == "__main__":
    main()
