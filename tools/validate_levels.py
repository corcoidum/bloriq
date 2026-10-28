#!/usr/bin/env python3
"""독립 BFS로 스테이지의 규칙, 해결 가능성 및 최단 이동 수를 확인한다."""
from collections import deque
import json
from pathlib import Path
from typing import Any

LEVELS_FILE = Path(__file__).resolve().parents[1] / 'assets/levels/levels.json'
Position = tuple[int, int]
Move = tuple[str, Position, Position]


def validate_level(
    level: dict[str, Any], *, use_echo: bool = True, gate_locked: bool = False,
    disabled_rule: str | None = None,
) -> list[Move]:
    width, height = level['boardWidth'], level['boardHeight']
    assert type(width) is int and type(height) is int and width > 0 and height > 0

    def point(value: dict[str, int]) -> Position:
        x, y = value['x'], value['y']
        assert type(x) is int and type(y) is int and 0 <= x < width and 0 <= y < height
        return x, y

    def adjacent(p: Position):
        x, y = p
        for q in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= q[0] < width and 0 <= q[1] < height:
                yield q

    start, exit_point = point(level['startPosition']), point(level['exitPosition'])
    assert start != exit_point
    raw_blocks = level['blocks']
    ids = [b['id'] for b in raw_blocks]
    assert all(isinstance(v, str) and v and v != 'goal' for v in ids)
    assert len(ids) == len(set(ids))
    blocks = tuple(point(b) for b in raw_blocks)
    walls = frozenset(point(o) for o in level['obstacles'])
    assert len(set(blocks)) == len(blocks) and len(walls) == len(level['obstacles'])
    assert not (set(blocks) & walls)
    assert not ({start, exit_point} & (set(blocks) | walls))
    rules = level['specialRules']
    assert isinstance(rules, list)
    erasers: set[Position] = set()
    holds: set[Position] = set()
    goal_only: set[Position] = set()
    arrows: dict[Position, Position] = {}
    switch = gate = None
    occupied_tiles: set[Position] = set()
    rule_types: set[str] = set()
    for rule in rules:
        kind = rule['type']
        assert kind not in rule_types
        rule_types.add(kind)
        if kind == 'echoGate':
            switch, gate = point(rule['switch']), point(rule['gate'])
            assert switch != gate and switch != exit_point and gate != exit_point
            assert gate != start and gate not in blocks
            places = [switch, gate]
        elif kind == 'oneWay':
            places = []
            for tile in rule['tiles']:
                loc = point(tile)
                direction = (tile['dx'], tile['dy'])
                assert direction in ((1, 0), (-1, 0), (0, 1), (0, -1))
                assert loc not in arrows
                arrows[loc] = direction
                places.append(loc)
        elif kind in ('echoEraser', 'echoHold', 'goalOnly'):
            places = [point(tile) for tile in rule['positions']]
            assert len(places) == len(set(places))
            target = {'echoEraser': erasers, 'echoHold': holds, 'goalOnly': goal_only}[kind]
            target.update(places)
        else:
            raise AssertionError(f'Unknown rule: {kind}')
        assert places and not (set(places) & (walls | occupied_tiles))
        occupied_tiles.update(places)

    initial = ((start, *blocks), None)
    pending = deque([(initial, [])])
    seen = {initial}
    while pending:
        (positions, echo), moves = pending.popleft()
        if positions[0] == exit_point:
            return moves
        for index, source in enumerate(positions):
            for dest in adjacent(source):
                if dest in positions or dest in walls or dest == echo:
                    continue
                if index != 0 and dest == exit_point:
                    continue
                direction = (dest[0] - source[0], dest[1] - source[1])
                if disabled_rule != 'oneWay' and source in arrows and arrows[source] != direction:
                    continue
                if disabled_rule != 'goalOnly' and index != 0 and dest in goal_only:
                    continue
                if dest == gate and (gate_locked or echo != switch):
                    continue
                updated = list(positions)
                updated[index] = dest
                # 지우기·유지는 출발 칸을 확인하고 유효한 이동 뒤에만 적용한다.
                if not use_echo or (disabled_rule != 'echoEraser' and source in erasers):
                    next_echo = None
                elif disabled_rule != 'echoHold' and source in holds:
                    next_echo = echo
                else:
                    next_echo = source
                next_state = (tuple(updated), next_echo)
                if next_state not in seen:
                    seen.add(next_state)
                    block_id = 'goal' if index == 0 else ids[index - 1]
                    pending.append((next_state, moves + [(block_id, source, dest)]))
    raise ValueError(f"Level {level['id']} has no solution")


def main() -> None:
    levels = json.loads(LEVELS_FILE.read_text(encoding='utf-8'))
    assert [level['id'] for level in levels] == list(range(1, len(levels) + 1))
    for level in levels:
        moves = validate_level(level)
        assert len(moves) == level['minimumMoves'], (
            f"Level {level['id']}: expected {level['minimumMoves']}, got {len(moves)}"
        )
        # 각 기믹의 실질적 영향: 비활성화 시 최단 해가 달라지거나 해가 없어야 한다.
        for rule in level['specialRules']:
            kind = rule['type']
            try:
                without = validate_level(level, gate_locked=kind == 'echoGate', disabled_rule=kind)
            except ValueError:
                continue
            assert len(without) != len(moves), f"Level {level['id']}: {kind} has no effect on optimum"
        types = ', '.join(rule['type'] for rule in level['specialRules']) or 'basic'
        print(f"Level {level['id']}: minimum={len(moves)}, {types}")
    print(f'{len(levels)}/{len(levels)} levels valid and solvable; recorded minima match BFS.')


if __name__ == '__main__':
    main()
