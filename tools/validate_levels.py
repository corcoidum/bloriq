#!/usr/bin/env python3
"""JSON 레벨의 유효성과 최소 블록 이동 횟수를 독립적으로 검증한다.

사용법: python3 tools/validate_levels.py
퍼즐 탐색은 추가 패키지 없이 BFS로 수행한다. 앱의 Dart solver 검증을 대체하지 않는다.
"""
from collections import deque
import json
from pathlib import Path
from typing import Any

LEVELS_FILE = Path(__file__).resolve().parents[1] / 'assets/levels/levels.json'


def validate_level(level: dict[str, Any]) -> tuple[int, list[tuple[tuple[int, int], tuple[int, int]]]]:
    width, height = level['boardWidth'], level['boardHeight']
    assert width > 0 and height > 0

    def point(value: dict[str, int]) -> tuple[int, int]:
        x, y = value['x'], value['y']
        assert isinstance(x, int) and isinstance(y, int)
        assert 0 <= x < width and 0 <= y < height
        return x, y

    def adjacent(p: tuple[int, int]):
        x, y = p
        for q in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= q[0] < width and 0 <= q[1] < height:
                yield q

    start, exit_point = point(level['startPosition']), point(level['exitPosition'])
    assert start != exit_point
    raw_blocks = level['blocks']
    block_ids = [block['id'] for block in raw_blocks]
    assert len(block_ids) == len(set(block_ids))
    blocks = frozenset(point(block) for block in raw_blocks)
    obstacles = frozenset(point(obstacle) for obstacle in level['obstacles'])
    assert len(blocks) == len(raw_blocks) and len(obstacles) == len(level['obstacles'])
    assert not (blocks & obstacles)
    assert not ({start, exit_point} & (blocks | obstacles))
    assert level['specialRules'] == [], '이 검증기는 Phase 1 기본 블록만 지원합니다.'

    def has_path(current: frozenset[tuple[int, int]]) -> bool:
        # 이동한 블록과 고정 장애물을 제외하고 출구에 도달할 수 있는지 확인한다.
        seen = {start}
        pending = deque([start])
        while pending:
            here = pending.popleft()
            if here == exit_point:
                return True
            for nxt in adjacent(here):
                if nxt not in seen and nxt not in current and nxt not in obstacles:
                    seen.add(nxt)
                    pending.append(nxt)
        return False

    # 같은 종류 블록의 순서를 무시해 중복 상태를 줄인다.
    pending = deque([(blocks, [])])
    seen = {blocks}
    while pending:
        state, moves = pending.popleft()
        if has_path(state):
            return len(moves), moves
        for source in sorted(state):
            for dest in adjacent(source):
                if dest in state or dest in obstacles or dest in (start, exit_point):
                    continue
                next_state = state - {source} | {dest}
                if next_state not in seen:
                    seen.add(next_state)
                    pending.append((next_state, moves + [(source, dest)]))
    raise ValueError(f"Level {level['id']} has no solution")


def main() -> None:
    levels = json.loads(LEVELS_FILE.read_text(encoding='utf-8'))
    assert len(levels) == 10
    assert [level['id'] for level in levels] == list(range(1, 11))
    for level in levels:
        minimum, moves = validate_level(level)
        assert minimum == level['minimumMoves'], f"Level {level['id']}: expected {level['minimumMoves']}, got {minimum}"
        assert minimum > 0, f"Level {level['id']} already has an open route"
        print(f"Level {level['id']:2}: minimum={minimum}, moves={moves}")
    print('10/10 levels valid and solvable; recorded minima match BFS.')


if __name__ == '__main__':
    main()
