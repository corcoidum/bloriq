"""리크 캐릭터 앱 아이콘을 생성한다.

Android legacy/adaptive 아이콘과 웹 아이콘을 같은 원본에서 만든다.
Pillow가 필요하다: python3 -m pip install Pillow
사용: python3 tools/generate_app_icon.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
RIQ_FACE = ROOT / "docs/design/riq_icon_face.png"
RES = ROOT / "android/app/src/main/res"
WEB = ROOT / "web"
SIZE = 1024

NIGHT_TOP = (75, 108, 170)
NIGHT_BOTTOM = (30, 46, 91)


def lerp(a: tuple[int, ...], b: tuple[int, ...], t: float) -> tuple[int, ...]:
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def background(size: int = SIZE) -> Image.Image:
    """작은 아이콘에서도 리크의 밝은 얼굴과 구분되는 밤하늘 배경."""
    image = Image.new("RGBA", (size, size))
    draw = ImageDraw.Draw(image)
    for y in range(size):
        draw.line([(0, y), (size, y)], fill=lerp(NIGHT_TOP, NIGHT_BOTTOM, y / size))
    return image


def face_layer(size: int, scale: float) -> Image.Image:
    with Image.open(RIQ_FACE) as source:
        riq = source.convert("RGBA")
    riq = riq.crop(riq.getchannel("A").getbbox())
    width = round(size * scale)
    riq = riq.resize((width, round(riq.height * width / riq.width)), Image.LANCZOS)
    layer = Image.new("RGBA", (size, size))
    layer.alpha_composite(riq, ((size - riq.width) // 2, (size - riq.height) // 2))
    return layer


def rounded_mask(size: int, radius: float) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def full_icon(size: int = SIZE, *, scale: float = .94, rounded: bool = True) -> Image.Image:
    icon = background(size)
    icon.alpha_composite(face_layer(size, scale))
    if rounded:
        icon.putalpha(rounded_mask(size, size * .22))
    return icon


def save(image: Image.Image, path: Path, px: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.resize((px, px), Image.LANCZOS).save(path, optimize=True)


def main() -> None:
    master = full_icon()
    square = full_icon(scale=.8, rounded=False)
    # 108dp 레이어의 가운데 72dp를 마스크가 보여 준다. 눈과 볼의 별은 중앙에 들어온다.
    foreground = face_layer(SIZE, scale=.63)
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
