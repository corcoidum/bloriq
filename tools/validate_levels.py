#!/usr/bin/env python3
"""독립 BFS로 스테이지의 규칙, 해결 가능성 및 최단 이동 수를 확인한다."""
from collections import deque
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
LEVELS_FILE = ROOT / 'assets/levels/levels.json'
SAGA_FILE = ROOT / 'assets/worlds/saga.json'
Position = tuple[int, int]
Move = tuple[str, Position, Position] | tuple[str, Position, Position, str]

# 확장 세계 권능. lib/domain/puzzle.dart 의 PuzzlePower 순서·규칙과 같다.
LEAP, SWAP, SEAL, WIND = 'moonflower_leap', 'light_swap', 'seal', 'wind'
POWERS = (LEAP, SWAP, SEAL, WIND)
DIRECTIONS = ((1, 0), (-1, 0), (0, 1), (0, -1))


def validate_level(
    level: dict[str, Any], *, use_echo: bool = True, gate_locked: bool = False,
    disabled_rule: str | None = None,
    stats: dict[str, int] | None = None, max_states: int = 200000,
    powers: tuple[str, ...] | frozenset[str] = (),
    must_use: str | None = None,
) -> list[Move]:
    """powers 는 아직 쓰지 않은 권능이다. 각 권능은 한 번, 한 수로 센다.
    must_use 가 있으면 그 권능을 쓴 해만 정답으로 본다(강조 권능 확인용)."""
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

    assert all(power in POWERS for power in powers)

    def inside(p: Position) -> bool:
        return 0 <= p[0] < width and 0 <= p[1] < height

    def gate_open(echo) -> bool:
        return not gate_locked and switch is not None and echo == switch

    def can_occupy(index: int, dest: Position, positions, echo) -> bool:
        if not inside(dest) or dest in walls or dest == echo or dest in positions:
            return False
        if index != 0 and dest == exit_point:
            return False
        if disabled_rule != 'goalOnly' and index != 0 and dest in goal_only:
            return False
        if dest == gate and not gate_open(echo):
            return False
        return True

    def arrow_at(p: Position):
        return None if disabled_rule == 'oneWay' else arrows.get(p)

    def echo_after(source: Position, echo):
        # 지우기·유지는 출발 칸을 확인하고 유효한 이동 뒤에만 적용한다.
        if not use_echo or (disabled_rule != 'echoEraser' and source in erasers):
            return None
        if disabled_rule != 'echoHold' and source in holds:
            return echo
        return source

    def successors(positions, echo, left):
        """(block_index, dest, next_echo, power) 를 Dart solver 와 같은 순서로 낸다."""
        for index, source in enumerate(positions):
            for d in DIRECTIONS:
                dest = (source[0] + d[0], source[1] + d[1])
                if not can_occupy(index, dest, positions, echo):
                    continue
                arrow = arrow_at(source)
                if arrow is not None and arrow != d:
                    continue
                yield index, dest, echo_after(source, echo), None
        for power in POWERS:
            if power not in left:
                continue
            for index, source in enumerate(positions):
                arrow = arrow_at(source)
                if power == SWAP:
                    # 블록이 잔상 칸으로 옮겨 가고 떠난 칸이 새 잔상이 된다. 방향·화살표는 보지 않는다.
                    if echo is None or echo == gate:
                        continue
                    others = positions[:index] + positions[index + 1:]
                    if can_occupy(index, echo, others, None):
                        yield index, echo, source, power
                    continue
                for d in DIRECTIONS:
                    step = (source[0] + d[0], source[1] + d[1])
                    if power == LEAP:
                        if arrow is not None and arrow != d:
                            continue
                        land = (step[0] + d[0], step[1] + d[1])
                        if step in walls and can_occupy(index, land, positions, echo):
                            yield index, land, echo_after(source, echo), power
                    elif power == SEAL:
                        if echo is None or (arrow is not None and arrow != d):
                            continue
                        if can_occupy(index, step, positions, echo):
                            yield index, step, echo, power
                    else:  # WIND: 막히거나 화살표가 다른 칸, 목표는 출구에서 멈춘다.
                        current = source
                        while True:
                            current_arrow = arrow_at(current)
                            if current_arrow is not None and current_arrow != d:
                                break
                            nxt = (current[0] + d[0], current[1] + d[1])
                            if not can_occupy(index, nxt, positions, echo):
                                break
                            current = nxt
                            if index == 0 and current == exit_point:
                                break
                        if current != source:
                            yield index, current, echo_after(source, echo), power

    initial = ((start, *blocks), None, frozenset(powers))
    if start == exit_point:
        return []
    parents: dict = {initial: None}
    pending = deque([initial])
    while pending:
        state = pending.popleft()
        positions, echo, left = state
        for index, dest, next_echo, power in successors(positions, echo, left):
            updated = list(positions)
            updated[index] = dest
            next_state = (tuple(updated), next_echo, left - {power} if power else left)
            if next_state in parents:
                continue
            block_id = 'goal' if index == 0 else ids[index - 1]
            move = (block_id, positions[index], dest) if power is None else (block_id, positions[index], dest, power)
            parents[next_state] = (state, move)
            if len(parents) > max_states:
                raise RuntimeError(f"Level {level['id']} search budget exceeded: {max_states}")
            if index == 0 and dest == exit_point:
                if must_use is not None and must_use in next_state[2]:
                    continue  # 권능을 쓰지 않은 도착은 이 탐색에서 정답이 아니다.
                if stats is not None:
                    stats['visited'] = len(parents)
                path = []
                cursor = next_state
                while parents[cursor] is not None:
                    cursor, step_move = parents[cursor]
                    path.append(step_move)
                return path[::-1]
            pending.append(next_state)
    raise ValueError(f"Level {level['id']} has no solution")


def solve_or_none(level: dict, **kwargs) -> list[Move] | None:
    try:
        return validate_level(level, **kwargs)
    except ValueError:
        return None


def available_powers(level: dict) -> tuple[str, ...]:
    """스테이지에서 쓸 수 있는 권능. 없으면 네 권능 모두다."""
    allowed = level.get('availablePowers')
    if allowed is None:
        return POWERS
    assert allowed and len(set(allowed)) == len(allowed) and all(p in POWERS for p in allowed)
    return tuple(p for p in POWERS if p in allowed)


def power_profile(level: dict, max_states: int = 2_000_000) -> dict:
    """그 스테이지의 권능을 모두 가진 최소 수, 맨손 최소 수, 꼭 필요한 권능을 계산한다."""
    powers = available_powers(level)
    best = validate_level(level, powers=powers, max_states=max_states)
    bare = solve_or_none(level, max_states=max_states)
    required = [p for p in powers
                if solve_or_none(level, powers=tuple(q for q in powers if q != p), max_states=max_states) is None]
    return {'minimumMoves': len(best), 'bareHandedMoves': None if bare is None else len(bare),
            'requiredPowers': required, 'solution': best}


def first_level_id(world: int) -> int:
    """lib/world/world_catalog.dart 의 Worlds.firstLevelId 와 같다."""
    return (world - 1) * 100 + 1


def expansion_worlds() -> list[tuple[int, Path]]:
    """saga.json 에서 공개된 확장 세계(세계 2부터)의 번호와 레벨 파일."""
    if not SAGA_FILE.exists():
        return []
    saga = json.loads(SAGA_FILE.read_text(encoding='utf-8'))
    return [(world['number'], ROOT / world['levels']) for world in saga['worlds']
            if world['status'] == 'playable' and world['number'] >= 2]


def check_world(levels: list[dict], world: int) -> None:
    first = first_level_id(world)
    assert len(levels) == 25, f'World {world} needs 25 stages'
    assert [level['id'] for level in levels] == list(range(first, first + len(levels)))
    for level in levels:
        assert level.get('world') == world
        assert 4 <= level['boardWidth'] <= 5 and 4 <= level['boardHeight'] <= 5
        profile = power_profile(level)
        for key in ('minimumMoves', 'bareHandedMoves', 'requiredPowers'):
            assert level.get(key, [] if key == 'requiredPowers' else None) == profile[key], (
                f"Level {level['id']}: {key} expected {level.get(key)}, got {profile[key]}")
        powers = available_powers(level)
        featured = level.get('featuredPower')
        assert featured is None or featured in powers
        if featured is not None:
            # 강조한 권능은 실제로 최단 해를 줄이거나 해를 가능하게 해야 한다.
            # 강조한 권능은 최단 수를 줄이거나, 적어도 최단 해 하나에 쓰인다.
            without = solve_or_none(level, powers=tuple(p for p in powers if p != featured), max_states=2_000_000)
            used = solve_or_none(level, powers=powers, must_use=featured, max_states=2_000_000)
            assert (without is None or len(without) > profile['minimumMoves']
                    or (used is not None and len(used) == profile['minimumMoves'])), (
                f"Level {level['id']}: featured {featured} has no effect")
        for rule in level['specialRules']:
            kind = rule['type']
            without = solve_or_none(level, powers=powers, gate_locked=kind == 'echoGate', disabled_rule=kind,
                                    max_states=2_000_000)
            assert without is None or len(without) != profile['minimumMoves'], (
                f"Level {level['id']}: {kind} has no effect on optimum")
        bare = profile['bareHandedMoves']
        types = ', '.join(rule['type'] for rule in level['specialRules']) or 'basic'
        print(f"World{world} {level['id']}: minimum={profile['minimumMoves']}, bare={bare}, "
              f"powers={','.join(powers)}, required={','.join(profile['requiredPowers']) or '-'}, "
              f"featured={featured}, {types}")
    print(f'{len(levels)}/{len(levels)} world {world} levels valid; recorded power profiles match BFS.')


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
    for world, path in expansion_worlds():
        check_world(json.loads(path.read_text(encoding='utf-8')), world)


if __name__ == '__main__':
    main()
