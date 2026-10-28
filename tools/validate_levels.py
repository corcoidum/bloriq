#!/usr/bin/env python3
"""Independently validate ECHO BLOCK levels and shortest solutions.

Run: python tools/validate_levels.py
This BFS is independent of the Dart implementation and requires no packages.
"""
from collections import deque
import json
from pathlib import Path
from typing import Any

LEVELS_FILE = Path(__file__).resolve().parents[1] / 'assets/levels/levels.json'
Position = tuple[int, int]
Move = tuple[str, Position, Position]


def validate_level(
    level: dict[str, Any], *, use_echo: bool = True, gate_locked: bool = False
) -> list[Move]:
    width, height = level['boardWidth'], level['boardHeight']
    assert type(width) is int and type(height) is int and width > 0 and height > 0

    def point(value: dict[str, int]) -> Position:
        x, y = value['x'], value['y']
        assert type(x) is int and type(y) is int
        assert 0 <= x < width and 0 <= y < height
        return x, y

    def adjacent(p: Position):
        x, y = p
        for q in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= q[0] < width and 0 <= q[1] < height:
                yield q

    start, exit_point = point(level['startPosition']), point(level['exitPosition'])
    assert start != exit_point
    raw_blocks = level['blocks']
    block_ids = [block['id'] for block in raw_blocks]
    assert all(isinstance(value, str) and value and value != 'goal' for value in block_ids)
    assert len(block_ids) == len(set(block_ids))
    blocks = tuple(point(block) for block in raw_blocks)
    obstacles = frozenset(point(obstacle) for obstacle in level['obstacles'])
    assert len(set(blocks)) == len(blocks)
    assert len(obstacles) == len(level['obstacles'])
    assert not (set(blocks) & obstacles)
    assert not ({start, exit_point} & (set(blocks) | obstacles))
    rules = level['specialRules']
    assert isinstance(rules, list) and len(rules) <= 1
    switch = gate = None
    if rules:
        rule = rules[0]
        assert rule['type'] == 'echoGate'
        switch, gate = point(rule['switch']), point(rule['gate'])
        assert switch != gate
        assert switch not in obstacles and switch != exit_point
        assert gate not in obstacles and gate != exit_point
        assert gate not in blocks and gate != start

    # The target and each ordinary block have stable identities. Echo must be
    # part of the search key: the same positions can allow different next moves.
    initial = ((start, *blocks), None)
    pending = deque([(initial, [])])
    seen = {initial}
    while pending:
        (positions, echo), moves = pending.popleft()
        if positions[0] == exit_point:
            return moves
        for index, source in enumerate(positions):
            for dest in adjacent(source):
                if dest in positions or dest in obstacles or dest == echo:
                    continue
                if dest == gate and (gate_locked or echo != switch):
                    continue
                if index != 0 and dest == exit_point:
                    continue
                updated = list(positions)
                updated[index] = dest
                next_state = (tuple(updated), source if use_echo else None)
                if next_state not in seen:
                    seen.add(next_state)
                    block_id = 'goal' if index == 0 else block_ids[index - 1]
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
        if level['specialRules']:
            try:
                validate_level(level, gate_locked=True)
            except ValueError:
                pass
            else:
                raise AssertionError(f"Level {level['id']}: gate can be bypassed")
            comparison = 'gate required'
        else:
            without_echo = validate_level(level, use_echo=False)
            if level['id'] >= 2:
                assert len(moves) > len(without_echo), 'Echo must matter to these levels'
            comparison = f'without echo={len(without_echo)}'
        print(f"Level {level['id']}: minimum={len(moves)}, {comparison}")
        print(f'  solution: {moves}')
    print(f'{len(levels)}/{len(levels)} levels valid and solvable; recorded minima match BFS.')


if __name__ == '__main__':
    main()
