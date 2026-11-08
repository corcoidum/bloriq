"""의도별로 탐색한 후보를 고정한다. 수동 승인 전에는 앱 에셋에 등록하지 않는다."""
from __future__ import annotations

import copy
import json
import random
from pathlib import Path
from tools.level_audit import canonical, inspect
from tools.validate_levels import validate_level

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [6, 2, 3, 4, 5, 7, 8, 12, 17, 20, 14, 15, 16, 21, 24]
INTENTS = ['Gate가 열린 한 턴 사용', 'Eraser 출발 칸의 Echo 삭제', '목표 블록 전용 칸으로 길 정리', 'Hold 위에서 이전 Echo 유지', 'One-way 출구 방향 확인',
           'Eraser와 Gate의 이동 순서', 'Hold와 목표 전용 칸의 순서', 'Eraser와 One-way의 통로', '목표 전용 통로와 Gate', 'Hold와 One-way의 복습',
           '잔상 유지와 Gate 진입 순서', '일반 블록으로 Gate 타이밍 조절', 'One-way 경유 후 문 열기', 'Hold·전용 칸·문 조합', 'Eraser로 잔상 정리 후 Gate 진입']


def main() -> None:
    baseline = json.loads((ROOT / 'assets/levels/course2_baseline.json').read_text(encoding='utf-8'))
    active = json.loads((ROOT / 'assets/levels/levels.json').read_text(encoding='utf-8'))
    used = {canonical(level) for level in active}
    candidates = []
    for number, source_id in enumerate(SOURCES, 26):
        source = baseline[source_id - 1]
        rng = random.Random(20261029 + number * 97)
        special = set()
        for rule in source['specialRules']:
            places = [rule['switch'], rule['gate']] if rule['type'] == 'echoGate' else rule.get('positions', rule.get('tiles', []))
            special.update((p['x'], p['y']) for p in places)
        gate = next(((r['gate']['x'], r['gate']['y']) for r in source['specialRules'] if r['type'] == 'echoGate'), None)
        cells = [(x, y) for y in range(source['boardHeight']) for x in range(source['boardWidth'])]
        for _ in range(5000):
            candidate = copy.deepcopy(source)
            movable = [p for p in cells if p != gate]
            positions = rng.sample(movable, 2 + len(source['blocks']))
            if positions[1] in special:
                continue
            candidate['startPosition'] = dict(zip(('x', 'y'), positions[0]))
            candidate['exitPosition'] = dict(zip(('x', 'y'), positions[1]))
            for block, point in zip(candidate['blocks'], positions[2:]):
                block.update(dict(zip(('x', 'y'), point)))
            wall_cells = [p for p in cells if p not in positions and p not in special]
            if len(wall_cells) < len(source['obstacles']):
                continue
            candidate['obstacles'] = [dict(zip(('x', 'y'), p)) for p in rng.sample(wall_cells, len(source['obstacles']))]
            candidate.update(id=number, revision=1, difficulty='candidate', reviewStatus='awaiting_manual_play', learningIntent=INTENTS[number - 26])
            identity = canonical(candidate)
            if identity in used:
                continue
            try:
                solution = validate_level(candidate)
                lower = [6,3,4,5,5,8,8,8,8,8,10,10,10,10,10][number-26]
                upper = min(20, candidates[-1]['minimumMoves'] + 3) if candidates else 10
                if not lower <= len(solution) <= upper:
                    continue
                candidate['minimumMoves'] = len(solution)
                inspect([candidate])
            except (ValueError, AssertionError, RuntimeError):
                continue
            used.add(identity)
            candidates.append(candidate)
            break
        else:
            raise RuntimeError(f'No suitable candidate for {number}')
    (ROOT / 'assets/levels/draft_levels_26_40.json').write_text(json.dumps(candidates, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'{len(candidates)} candidates written; all remain excluded from the published game.')


if __name__ == '__main__':
    main()
