"""달빛 숲 정원 원본 그림을 게임용 스프라이트로 다듬는다.

생성 원본은 단색 배경 위에 그렸으므로 가장자리에서 배경을 채워 지우고,
내용 영역만 잘라 정사각형 투명 PNG로 저장한다.
Pillow가 필요하다: python3 -m pip install Pillow
사용: python3 tools/process_moon_garden.py <원본 폴더>
"""

from __future__ import annotations

import sys
from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/art/moon_garden"

# 파일 이름: (출력 크기, 내용이 차지할 비율, 배경 허용 오차, 처리 방식)
# flood: 가장자리와 이어진 배경만 지운다. shadow: 회색 바닥 그림자를 반투명 그림자로 바꾼다.
# key: 막대 사이처럼 갇힌 배경도 같은 색이면 모두 지운다.
SPRITES = {
    "floor_1": (384, 1.0, 34, "flood"),
    "floor_2": (384, 1.0, 34, "flood"),
    "floor_3": (384, 1.0, 34, "flood"),
    "floor_4": (384, 1.0, 34, "flood"),
    "rock": (384, 0.96, 30, "shadow"),
    "stump": (384, 0.96, 30, "shadow"),
    "riq_cushion": (384, 0.98, 30, "shadow"),
    "tile_dandelion": (384, 0.96, 32, "flood"),
    "tile_amber": (384, 0.96, 34, "flood"),
    "tile_clover": (384, 0.96, 40, "flood"),
    "switch_crystal": (384, 0.96, 12, "shadow"),
    "gate_closed": (384, 0.96, 40, "key"),
}
SOURCES = {"rock": "rock_2"}


def remove_background(
    image: Image.Image, tolerance: int, mode: str = "flood"
) -> Image.Image:
    """가장자리와 이어진 배경색 영역을 투명하게 만든다."""
    rgb = image.convert("RGB")
    width, height = rgb.size
    pixels = rgb.load()
    border = [pixels[x, 0] for x in range(width)] + [pixels[x, height - 1] for x in range(width)]
    border += [pixels[0, y] for y in range(height)] + [pixels[width - 1, y] for y in range(height)]
    border.sort(key=sum)
    base = border[len(border) // 2]

    def close(color: tuple[int, int, int]) -> bool:
        return sum(abs(a - b) for a, b in zip(color, base)) <= tolerance * 3

    mask = Image.new("L", (width, height), 255)
    alpha = mask.load()
    if mode == "key":
        for y in range(height):
            for x in range(width):
                if close(pixels[x, y]):
                    alpha[x, y] = 0
    queue = deque()
    for x in range(width):
        queue.extend([(x, 0), (x, height - 1)])
    for y in range(height):
        queue.extend([(0, y), (width - 1, y)])
    while queue:
        x, y = queue.popleft()
        if alpha[x, y] == 0 or not close(pixels[x, y]):
            continue
        alpha[x, y] = 0
        if x > 0:
            queue.append((x - 1, y))
        if x < width - 1:
            queue.append((x + 1, y))
        if y > 0:
            queue.append((x, y - 1))
        if y < height - 1:
            queue.append((x, y + 1))
    shade = None
    if mode == "shadow":
        shade = _shadow(rgb, alpha, base)
    # 경계의 배경색 테두리를 한 겹 깎고 부드럽게 만든다.
    mask = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1.2))
    result = rgb.convert("RGBA")
    result.putalpha(mask)
    if shade is not None:
        _darken_ground(result)
        shadow = Image.new("RGBA", (width, height), (6, 12, 30, 0))
        shadow.putalpha(shade.filter(ImageFilter.GaussianBlur(3)))
        shadow.alpha_composite(result)
        result = shadow
    return result


def _darken_ground(image: Image.Image) -> None:
    """물체 아래쪽에 남은 밝은 회색 바닥판을 반투명 그림자로 바꾼다."""
    box = image.getchannel("A").getbbox()
    if box is None:
        return
    pixels = image.load()
    top = box[1] + (box[3] - box[1]) * 0.6
    for y in range(int(top), box[3]):
        for x in range(box[0], box[2]):
            r, g, b, a = pixels[x, y]
            if a and (r + g + b) / 3 > 150 and max(r, g, b) - min(r, g, b) < 40:
                pixels[x, y] = (6, 12, 30, min(a, 70))


def _shadow(rgb: Image.Image, alpha, base) -> Image.Image:
    """배경에 붙은 무채색 회색 영역을 지우고 어두운 정도만큼 그림자 알파로 남긴다."""
    width, height = rgb.size
    pixels = rgb.load()
    base_light = sum(base) / 3
    shade = Image.new("L", (width, height), 0)
    out = shade.load()
    seen = set()
    queue = deque((x, y) for y in range(height) for x in range(width) if alpha[x, y] == 0)
    while queue:
        x, y = queue.popleft()
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if not (0 <= nx < width and 0 <= ny < height) or (nx, ny) in seen:
                continue
            if alpha[nx, ny] == 0:
                continue
            color = pixels[nx, ny]
            light = sum(color) / 3
            if max(color) - min(color) > 36 or light < base_light - 90:
                continue
            seen.add((nx, ny))
            alpha[nx, ny] = 0
            out[nx, ny] = int(min(150, max(0, (base_light - light) * 2.4)))
            queue.append((nx, ny))
    return shade


def fit_square(image: Image.Image, size: int, fill: float) -> Image.Image:
    box = image.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
    content = image.crop(box) if box else image
    scale = size * fill / max(content.size)
    content = content.resize(
        (max(1, round(content.width * scale)), max(1, round(content.height * scale))),
        Image.LANCZOS,
    )
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(content, ((size - content.width) // 2, (size - content.height) // 2))
    return canvas


def stream(source: Path) -> None:
    """물길은 가로로 길게 잘라 칸 너비에 맞춘다."""
    image = remove_background(Image.open(source), 34)
    box = image.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
    strip = image.crop(box)
    strip = strip.resize((384, round(strip.height * 384 / strip.width)), Image.LANCZOS)
    strip.save(OUT / "tile_stream.png", optimize=True)


def plank(source: Path) -> None:
    """상자 그림의 세로 판자 한 장을 가로 테두리 결 재료로 쓴다. 색은 실행 시 입힌다."""
    image = Image.open(source).convert("RGB")
    width, height = image.size
    strip = image.crop((int(width * .44), int(height * .30), int(width * .56), int(height * .70)))
    strip.rotate(90, expand=True).resize((384, 96), Image.LANCZOS).save(OUT / "plank.png", optimize=True)


def main() -> None:
    source = Path(sys.argv[1])
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (size, fill, tolerance, mode) in SPRITES.items():
        raw = source / f"{SOURCES.get(name, name)}.png"
        image = remove_background(Image.open(raw), tolerance, mode)
        fit_square(image, size, fill).save(OUT / f"{name}.png", optimize=True)
    stream(source / "tile_stream.png")
    plank(source / "frame.png")


if __name__ == "__main__":
    main()
