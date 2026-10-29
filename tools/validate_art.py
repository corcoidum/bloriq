"""런타임 원화의 누락·형식·원본 추적 검증. 외부 Python 패키지가 필요하지 않다."""
from pathlib import Path
import hashlib
import json
import struct

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'assets/art/moonlit'
TILES = ['frame', 'empty', 'blue', 'mint', 'obstacle', 'exit', 'echo', 'ornament', 'button', 'decor_flowers', 'decor_mist', 'decor_stars', 'decor_petals']
REGIONS = ['garden', 'watergate', 'postoffice', 'corridor', 'observatory']


def validate() -> dict:
    season = json.loads((ROOT / 'assets/story/season1.json').read_text())
    expected = ([f'backgrounds/{name}.png' for name in REGIONS]
                + [f'tiles/{name}.png' for name in TILES]
                + ['spirits/riq.png']
                + [f'spirits/{spirit["id"]}.png' for spirit in season['spirits']])
    records = []
    for relative in expected:
        path = ART / relative
        data = path.read_bytes()
        assert data[:8] == b'\x89PNG\r\n\x1a\n', f'Not PNG: {relative}'
        width, height, depth, color = struct.unpack('>IIBB', data[16:26])
        assert width >= 256 and height >= 256, f'Low resolution: {relative}'
        if not relative.startswith('backgrounds/'):
            assert color == 6, f'Expected RGBA alpha: {relative}'
        records.append(dict(path=relative, width=width, height=height,
                            bytes=len(data), sha256=hashlib.sha256(data).hexdigest()))
    assert len(records) == 44, f'Expected 5 backgrounds + 13 tiles/decorations + 26 spirits: {len(records)}'
    assert (ART / 'fonts/OFL.txt').exists()
    assert (ROOT / 'docs/art/moonlit-selected-reference.png').exists()
    return dict(version=1, artDirection='Moonlit Storybook Garden', assets=records,
                totalBytes=sum(record['bytes'] for record in records))


if __name__ == '__main__':
    manifest = validate()
    print(f"{len(manifest['assets'])}/44 assets valid, {manifest['totalBytes']/1024/1024:.1f} MiB original PNG")
