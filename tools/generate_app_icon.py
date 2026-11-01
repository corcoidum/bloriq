"""리크 캐릭터 앱 아이콘을 생성한다.

Android legacy/adaptive 아이콘과 웹 아이콘을 같은 원본에서 만든다.
Pillow가 필요하다: python3 -m pip install Pillow
사용: python3 tools/generate_app_icon.py
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
RIQ = ROOT / "assets/art/last_echo/riq.png"
RES = ROOT / "android/app/src/main/res"
WEB = ROOT / "web"
SIZE = 1024

NIGHT_TOP = (16, 28, 56)
NIGHT_BOTTOM = (46, 54, 112)
MINT = (153, 224, 191)
MINT_DEEP = (88, 176, 146)
GOLD = (243, 209, 139)


def lerp(a: tuple[int, ...], b: tuple[int, ...], t: float) -> tuple[int, ...]:
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def star_points(cx: float, cy: float, outer: float, inner: float):
    return [
        (
            cx + math.cos(-math.pi / 2 + i * math.pi / 5) * (outer if i % 2 == 0 else inner),
            cy + math.sin(-math.pi / 2 + i * math.pi / 5) * (outer if i % 2 == 0 else inner),
        )
        for i in range(10)
    ]


def background(size: int = SIZE) -> Image.Image:
    """밤하늘 그라데이션, 달, 별가루."""
    image = Image.new("RGBA", (size, size))
    draw = ImageDraw.Draw(image)
    for y in range(size):
        draw.line([(0, y), (size, y)], fill=lerp(NIGHT_TOP, NIGHT_BOTTOM, y / size))
    s = size / SIZE

    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse(
        [size * 0.18, size * 0.28, size * 0.82, size * 0.92], fill=(*MINT, 70)
    )
    image.alpha_composite(glow.filter(ImageFilter.GaussianBlur(90 * s)))

    moon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    moon_draw = ImageDraw.Draw(moon)
    moon_draw.ellipse([735 * s, 95 * s, 905 * s, 265 * s], fill=(*GOLD, 255))
    moon_draw.ellipse([785 * s, 70 * s, 950 * s, 235 * s], fill=(0, 0, 0, 0))
    halo = moon.filter(ImageFilter.GaussianBlur(28 * s))
    image.alpha_composite(halo)
    image.alpha_composite(moon)

    sparkle = ImageDraw.Draw(image)
    for x, y, r in [(255, 210, 6), (300, 105, 4), (560, 150, 5), (650, 300, 3), (120, 420, 4), (905, 430, 5)]:
        sparkle.ellipse([(x - r) * s, (y - r) * s, (x + r) * s, (y + r) * s], fill=(255, 241, 211, 220))
    sparkle.polygon(star_points(150 * s, 150 * s, 36 * s, 15 * s), fill=(*GOLD, 255))
    return image


def riq_on_tile(size: int = SIZE, scale: float = 1.0) -> Image.Image:
    """민트 목표 블록 위의 리크. 투명 배경이다."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    s = size / SIZE * scale
    cx, cy = size / 2, size / 2

    tile_w, tile_h = 760 * s, 680 * s
    top = cy - tile_h / 2 + 60 * s
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [cx - tile_w / 2 + 30 * s, top + 120 * s, cx + tile_w / 2 - 30 * s, top + tile_h + 50 * s],
        radius=150 * s,
        fill=(6, 10, 30, 150),
    )
    layer.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(30 * s)))

    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle(
        [cx - tile_w / 2, top + 26 * s, cx + tile_w / 2, top + tile_h + 26 * s],
        radius=150 * s,
        fill=(*MINT_DEEP, 255),
    )
    draw.rounded_rectangle(
        [cx - tile_w / 2, top, cx + tile_w / 2, top + tile_h],
        radius=150 * s,
        fill=(*MINT, 255),
    )
    shine = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(shine).rounded_rectangle(
        [cx - tile_w / 2 + 60 * s, top + 26 * s, cx + tile_w / 2 - 60 * s, top + 62 * s],
        radius=18 * s,
        fill=(255, 255, 255, 90),
    )
    layer.alpha_composite(shine)

    riq = Image.open(RIQ).convert("RGBA")
    riq = riq.crop(riq.getbbox())
    width = round(700 * s)
    riq = riq.resize((width, round(riq.height * width / riq.width)), Image.LANCZOS)
    x = round(cx - riq.width / 2)
    y = round(top + tile_h * 0.9 - riq.height)
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow.paste((255, 241, 211, 150), (x, y), riq)
    layer.alpha_composite(glow.filter(ImageFilter.GaussianBlur(26 * s)))
    layer.alpha_composite(riq, (x, y))
    return layer


def rounded_mask(size: int, radius: float) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def full_icon(size: int = SIZE, rounded: bool = True) -> Image.Image:
    icon = background(size)
    icon.alpha_composite(riq_on_tile(size, scale=0.92))
    if rounded:
        icon.putalpha(ImageChops.multiply(icon.getchannel("A"), rounded_mask(size, size * 0.22)))
    return icon


def save(image: Image.Image, path: Path, px: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.resize((px, px), Image.LANCZOS).save(path, optimize=True)


def main() -> None:
    master = full_icon()
    square = full_icon(rounded=False)
    # Adaptive 전경은 108dp 중 가운데 66dp가 안전 영역이므로 작게 둔다.
    foreground = riq_on_tile(SIZE, scale=0.54)
    sky = background()

    densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for name, factor in densities.items():
        save(master, RES / f"mipmap-{name}/ic_launcher.png", round(48 * factor))
        save(foreground, RES / f"mipmap-{name}/ic_launcher_foreground.png", round(108 * factor))
        save(sky, RES / f"mipmap-{name}/ic_launcher_background.png", round(108 * factor))

    adaptive = RES / "mipmap-anydpi-v26/ic_launcher.xml"
    adaptive.parent.mkdir(parents=True, exist_ok=True)
    adaptive.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@mipmap/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        "</adaptive-icon>\n",
        encoding="utf-8",
    )

    save(master, WEB / "icons/Icon-192.png", 192)
    save(master, WEB / "icons/Icon-512.png", 512)
    save(square, WEB / "icons/Icon-maskable-192.png", 192)
    save(square, WEB / "icons/Icon-maskable-512.png", 512)
    save(master, WEB / "favicon.png", 64)
    save(master, ROOT / "docs/design/app_icon_riq.png", 512)


if __name__ == "__main__":
    main()
