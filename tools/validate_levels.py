#!/usr/bin/env python3
"""독립 BFS로 스테이지의 규칙, 해결 가능성 및 최단 이동 수를 확인한다."""
import argparse
from collections import deque
import json
from pathlib import Path
from textwrap import indent
from time import monotonic
from typing import Any

if __package__:
    from .mechanics import Board, DIRECTIONS, MechanicMove, Position, State, parse_mechanics
else:
    from mechanics import Board, DIRECTIONS, MechanicMove, Position, State, parse_mechanics

ROOT = Path(__file__).resolve().parents[1]
LEVELS_FILE = ROOT / 'assets/levels/levels.json'
COURSE2_BASELINE_FILE = ROOT / 'assets/levels/course2_baseline.json'
SAGA_FILE = ROOT / 'assets/worlds/saga.json'
Move = tuple[str, Position, Position] | tuple[str, Position, Position, str]

# 확장 세계 권능. lib/domain/puzzle.dart 의 PuzzlePower 순서·규칙과 같다.
LEAP, SWAP, SEAL, WIND = 'moonflower_leap', 'light_swap', 'seal', 'wind'
POWERS = (LEAP, SWAP, SEAL, WIND)


class SearchBudgetExceeded(RuntimeError):
    """상태 예산으로 탐색을 중단했다. 해가 없다는 뜻과 구분한다."""


def validate_level(
    level: dict[str, Any], *, use_echo: bool = True, gate_locked: bool = False,
    disabled_rule: str | None = None,
    stats: dict[str, int] | None = None, max_states: int = 200000,
    powers: tuple[str, ...] | frozenset[str] = (),
    must_use: str | None = None,
    deadline: float | None = None,
) -> list[Move]:
    """powers 는 아직 쓰지 않은 권능이다. 각 권능은 한 번, 한 수로 센다.
    must_use 가 있으면 그 권능을 쓴 해만 정답으로 본다(강조 권능 확인용)."""
    def check_deadline() -> None:
        if deadline is not None and monotonic() >= deadline:
            raise TimeoutError(f"Level {level['id']} search deadline exceeded")

    check_deadline()
    width, height = level['boardWidth'], level['boardHeight']
    assert type(width) is int and type(height) is int and width > 0 and height > 0

    def point(value: dict[str, int]) -> Position:
        assert isinstance(value, dict), 'Invalid position'
        x, y = value.get('x'), value.get('y')
        assert type(x) is int and type(y) is int and 0 <= x < width and 0 <= y < height
        return x, y

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
    mechanics = parse_mechanics(level, point, walls=walls, disabled_rule=disabled_rule,
                                gate_locked=gate_locked)
    board = Board(width, height, exit_point, walls, ('goal', *ids), mechanics)
    assert all(power in POWERS for power in powers)

    def successors(state: State):
        """기믹 변환 전의 일반/권능 착지를 Dart solver와 같은 순서로 낸다."""
        for index, source in enumerate(state.positions):
            for d in DIRECTIONS:
                dest = (source[0] + d[0], source[1] + d[1])
                if state.canOccupy(index, dest) and state.canLeave(source, d):
                    yield MechanicMove(index, dest, None)
        for power in POWERS:
            if power not in state.powers:
                continue
            for index, source in enumerate(state.positions):
                if power == SWAP:
                    # 블록이 잔상 칸으로 옮겨 가고 떠난 칸이 새 잔상이 된다. 방향·화살표는 보지 않는다.
                    if state.echo is not None and state._replace(echo=None).canOccupy(index, state.echo):
                        yield MechanicMove(index, state.echo, power)
                    continue
                for d in DIRECTIONS:
                    step = (source[0] + d[0], source[1] + d[1])
                    if power == LEAP:
                        land = (step[0] + d[0], step[1] + d[1])
                        if step in walls and state.canLeave(source, d) and state.canOccupy(index, land):
                            yield MechanicMove(index, land, power)
                    elif power == SEAL:
                        if state.echo is not None and state.canLeave(source, d) and state.canOccupy(index, step):
                            yield MechanicMove(index, step, power)
                    else:  # WIND: 막히거나 화살표가 다른 칸, 목표는 출구에서 멈춘다.
                        current = source
                        while state.canLeave(current, d):
                            nxt = (current[0] + d[0], current[1] + d[1])
                            if not state.canOccupy(index, nxt):
                                break
                            current = nxt
                            if index == 0 and current == exit_point:
                                break
                        if current != source:
                            yield MechanicMove(index, current, power)

    def apply(state: State, move: MechanicMove) -> State:
        index, dest, power = move
        source = state.positions[index]
        positions = state.positions[:index] + (dest,) + state.positions[index + 1:]
        # 일반/권능 착지 → 기믹 배치 변환 → 잔상. 봉인·교대의 잔상 규칙이 우선한다.
        for mechanic in mechanics:
            positions = mechanic.transformMove(state, move, positions)
        echo = source
        for mechanic in mechanics:
            echo = mechanic.nextEcho(state, move, positions, echo)
        if power == SEAL:
            echo = state.echo
        elif power == SWAP:
            echo = source
        return State(positions, echo if use_echo else None,
                     state.powers - {power} if power else state.powers, state.moves + 1, board)

    def state_key(state: State) -> tuple:
        key = (state.positions, state.echo, state.powers)
        extra = tuple((mechanic.type, value) for mechanic in mechanics
                      if (value := mechanic.stateKey(state)) is not None)
        return (*key, extra) if extra else key

    initial = State((start, *blocks), None, frozenset(powers), 0, board)
    initial_key = state_key(initial)
    parents: dict[tuple, tuple[tuple, Move] | None] = {initial_key: None}
    pending = deque([(initial, initial_key)])
    expanded = 0
    while pending:
        if deadline is not None:
            if expanded % 128 == 0:
                check_deadline()
            expanded += 1
        state, key = pending.popleft()
        for candidate in successors(state):
            next_state = apply(state, candidate)
            next_key = state_key(next_state)
            if next_key in parents:
                continue
            index, dest, power = candidate
            push = (board.block_ids[index], state.positions[index], dest)
            move = push if power is None else (*push, power)
            parents[next_key] = (key, move)
            if len(parents) > max_states:
                raise SearchBudgetExceeded(f"Level {level['id']} search budget exceeded: {max_states}")
            if next_state.positions[0] == exit_point:
                if must_use is not None and must_use in next_state.powers:
                    continue  # 권능을 쓰지 않은 도착은 이 탐색에서 정답이 아니다.
                check_deadline()
                if stats is not None:
                    stats['visited'] = len(parents)
                path = []
                cursor = next_key
                while (link := parents[cursor]) is not None:
                    cursor, step_move = link
                    path.append(step_move)
                return path[::-1]
            pending.append((next_state, next_key))
    check_deadline()
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
    assert len(set(allowed)) == len(allowed) and all(p in POWERS for p in allowed)
    return tuple(p for p in POWERS if p in allowed)


def power_profile(
    level: dict, max_states: int = 2_000_000, *, deadline: float | None = None,
) -> dict:
    """그 스테이지의 권능을 모두 가진 최소 수, 맨손 최소 수, 꼭 필요한 권능을 계산한다."""
    powers = available_powers(level)
    best = validate_level(level, powers=powers, max_states=max_states, deadline=deadline)
    bare = solve_or_none(level, max_states=max_states, deadline=deadline) if powers else best
    required = [p for p in powers
                if solve_or_none(level, powers=tuple(q for q in powers if q != p),
                                 max_states=max_states, deadline=deadline) is None]
    return {'minimumMoves': len(best), 'bareHandedMoves': None if bare is None else len(bare),
            'requiredPowers': required, 'solution': best}


def decorative_mechanic(
    level: dict, minimum: int, *, powers: tuple[str, ...] = (),
    max_states: int = 200_000, deadline: float | None = None,
) -> str | None:
    """하나씩 끄고 다시 풀어도 최단 수가 같은 첫 기믹을 찾는다."""
    for rule in level['specialRules']:
        kind = rule['type']
        alternative = solve_or_none(
            level, powers=powers, disabled_rule=kind, gate_locked=kind == 'echoGate',
            max_states=max_states, deadline=deadline,
        )
        if alternative is not None and len(alternative) == minimum:
            return kind
    return None


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


def record_solution(level: dict, moves: list[Move], *, write: bool) -> None:
    solution = []
    for block_id, _, (x, y), *power in moves:
        step = {'blockId': block_id, 'target': {'x': x, 'y': y}}
        if power:
            step['power'] = power[0]
        solution.append(step)
    if write:
        level['solution'] = solution
    elif 'solution' in level:
        assert level['solution'] == solution, (
            f"Level {level['id']}: run --write-solutions to refresh the recorded path")


def write_levels(path: Path, levels: list[dict]) -> None:
    entries = []
    for level in levels:
        if 'solution' not in level:
            entries.append(indent(json.dumps(level, ensure_ascii=False, indent=2), '  '))
            continue
        board = {key: value for key, value in level.items() if key != 'solution'}
        body = json.dumps(board, ensure_ascii=False, indent=2).removesuffix('\n}')
        moves = ',\n'.join('    ' + json.dumps(move, ensure_ascii=False)
                           for move in level['solution'])
        entries.append(indent(body + ',\n  "solution": [\n' + moves + '\n  ]\n}', '  '))
    path.write_text('[\n' + ',\n'.join(entries) + '\n]\n', encoding='utf-8')


def check_world(
    levels: list[dict], world: int, *, write_solutions: bool = False,
    budgets: tuple[int, ...] | None = None,
) -> None:
    first = first_level_id(world)
    assert len(levels) == 25, f'World {world} needs 25 stages'
    assert [level['id'] for level in levels] == list(range(first, first + len(levels)))
    for index, level in enumerate(levels):
        budget = budgets[index] if budgets is not None else 2_000_000
        assert level.get('world') == world
        if world == 2:
            assert 4 <= level['boardWidth'] <= 5 and 4 <= level['boardHeight'] <= 5
        profile = power_profile(level, max_states=budget)
        for key in ('minimumMoves', 'bareHandedMoves', 'requiredPowers'):
            assert level.get(key, [] if key == 'requiredPowers' else None) == profile[key], (
                f"Level {level['id']}: {key} expected {level.get(key)}, got {profile[key]}")
        record_solution(level, profile['solution'], write=write_solutions)
        powers = available_powers(level)
        featured = level.get('featuredPower')
        assert featured is None or featured in powers
        if featured is not None:
            # 강조한 권능은 최단 수를 줄이거나, 적어도 최단 해 하나에 쓰인다.
            without = solve_or_none(level, powers=tuple(p for p in powers if p != featured), max_states=budget)
            used = solve_or_none(level, powers=powers, must_use=featured, max_states=budget)
            assert (without is None or len(without) > profile['minimumMoves']
                    or (used is not None and len(used) == profile['minimumMoves'])), (
                f"Level {level['id']}: featured {featured} has no effect")
        decorative = decorative_mechanic(level, profile['minimumMoves'], powers=powers, max_states=budget)
        assert decorative is None, f"Level {level['id']}: {decorative} has no effect on optimum"
        bare = profile['bareHandedMoves']
        types = ', '.join(rule['type'] for rule in level['specialRules']) or 'basic'
        print(f"World{world} {level['id']}: minimum={profile['minimumMoves']}, bare={bare}, "
              f"powers={','.join(powers)}, required={','.join(profile['requiredPowers']) or '-'}, "
              f"featured={featured}, {types}")
    print(f'{len(levels)}/{len(levels)} world {world} levels valid; recorded power profiles match BFS.')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write-solutions', action='store_true',
                        help='공개 캠페인 레벨 JSON에 검증한 최단 풀이를 기록한다')
    args = parser.parse_args()
    levels = json.loads(LEVELS_FILE.read_text(encoding='utf-8'))
    assert [level['id'] for level in levels] == list(range(1, len(levels) + 1))
    for level in levels:
        moves = validate_level(level)
        assert len(moves) == level['minimumMoves'], (
            f"Level {level['id']}: expected {level['minimumMoves']}, got {len(moves)}"
        )
        record_solution(level, moves, write=args.write_solutions)
        # 각 기믹의 실질적 영향: 비활성화 시 최단 해가 달라지거나 해가 없어야 한다.
        decorative = decorative_mechanic(level, len(moves))
        assert decorative is None, f"Level {level['id']}: {decorative} has no effect on optimum"
        types = ', '.join(rule['type'] for rule in level['specialRules']) or 'basic'
        print(f"Level {level['id']}: minimum={len(moves)}, {types}")
    print(f'{len(levels)}/{len(levels)} levels valid and solvable; recorded minima match BFS.')
    verified = {LEVELS_FILE: levels}
    for world, path in expansion_worlds():
        world_levels = json.loads(path.read_text(encoding='utf-8'))
        check_world(world_levels, world, write_solutions=args.write_solutions)
        verified[path] = world_levels

    # 공개판과 같은 JSON 스키마를 쓰는 보관본도 해당 revision의 해를 기록한다.
    archived = json.loads(COURSE2_BASELINE_FILE.read_text(encoding='utf-8'))
    for level in archived:
        moves = validate_level(level)
        assert len(moves) == level['minimumMoves'], f"Archived level {level['id']}: minimum mismatch"
        record_solution(level, moves, write=args.write_solutions)
    verified[COURSE2_BASELINE_FILE] = archived
    print(f'{len(archived)} archived levels valid.')

    if args.write_solutions:
        for path, verified_levels in verified.items():
            write_levels(path, verified_levels)
        print(f'Wrote {sum(map(len, verified.values()))} solutions to {len(verified)} level files.')


if __name__ == '__main__':
    main()
