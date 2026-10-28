"""Draws the app icon (green tile, white "C", saffron bar) with the Mukta font.
Run: python3 tools/make_icon.py  → assets/icon/*.png (then flutter_launcher_icons)."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "icon"
FONT = ROOT / "assets" / "fonts" / "Mukta-Bold.ttf"
GREEN_TOP, GREEN_BOTTOM, SAFFRON = (31, 164, 90), (14, 122, 62), (255, 153, 51)


def gradient(size):
    img = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        d.line([(0, y), (size, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(GREEN_TOP, GREEN_BOTTOM)))
    return img


def mark(draw, size, scale):
    """White C + saffron bar, centred; scale < 1 keeps it inside the adaptive-icon safe zone."""
    font = ImageFont.truetype(str(FONT), int(size * 0.62 * scale))
    box = draw.textbbox((0, 0), "C", font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    x, y = (size - w) / 2 - box[0], (size - h) / 2 - box[1] - size * 0.04 * scale
    draw.text((x, y), "C", font=font, fill="white")
    bw, bh = size * 0.40 * scale, size * 0.065 * scale
    by = size / 2 + size * 0.27 * scale
    draw.rounded_rectangle([(size - bw) / 2, by, (size + bw) / 2, by + bh], radius=bh / 2, fill=SAFFRON)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    size = 1024
    # Full icon with rounded corners (legacy launchers, web, download page).
    full = gradient(size)
    mark(ImageDraw.Draw(full), size, 1.0)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size, size], radius=int(size * 0.22), fill=255)
    rounded = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    rounded.paste(full, (0, 0), mask)
    rounded.save(OUT / "app_icon.png")
    # Square (no transparency) for Play Store / maskable web icon.
    full.save(OUT / "app_icon_square.png")
    # Adaptive icon foreground: transparent, mark inside the 66% safe zone.
    fg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mark(ImageDraw.Draw(fg), size, 0.62)
    fg.save(OUT / "app_icon_foreground.png")
    print("icons written to", OUT)


if __name__ == "__main__":
    main()
