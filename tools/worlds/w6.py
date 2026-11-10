"""세계 6 꿈의 서고의 25개 생성 슬롯."""

from functools import partial
from random import Random
from typing import NamedTuple

from tools.mechanics import ClockArrow, DIRECTIONS, EchoGate, Ice, MechanicMove, MirrorPair, Position, ShelfDoor, State
from tools.validate_levels import Move, SWAP, trace_solution
from tools.worlds import Slot

SHELF = ShelfDoor.type
ICE = Ice.type
MIRROR = MirrorPair.type
CLOCK = ClockArrow.type
GATE = EchoGate.type
SMALL = (5, 5)
WIDE = (6, 5)


def _point(cell: Position) -> dict[str, int]:
    return {'x': cell[0], 'y': cell[1]}


def _step(cell: Position, direction: Position) -> Position:
    return cell[0] + direction[0], cell[1] + direction[1]


def _distance(a: Position, b: Position) -> int:
    return abs(a[0] - b[0]) + abs(a[1] - b[1])


class _ShelfArrival(NamedTuple):
    block: int
    pair: int
    teleported: bool
    slid: bool


def _shelf_arrivals(before: State, move: MechanicMove, after: State) -> tuple[_ShelfArrival, ...]:
    """서고 슬롯에서 쓴 이동을 변환 전 착지와 실제 정지 칸으로 분류한다."""
    shelf = next(rule for rule in before.board.mechanics if isinstance(rule, ShelfDoor))
    ice = next((rule for rule in before.board.mechanics if isinstance(rule, Ice)), None)
    mirror = next((rule for rule in before.board.mechanics if isinstance(rule, MirrorPair)), None)
    index = move.index
    source = before.positions[index]
    dx, dy = move.target[0] - source[0], move.target[1] - source[1]
    landings = []
    if move.power != SWAP:
        landing = move.target
        if ice is not None:
            positions = before.positions[:index] + (landing,) + before.positions[index + 1:]
            landing = ice.finish_slide(before, positions, index, landing, (dx, dy), source)
        landings.append((index, landing, landing != move.target))
    # 짝 슬롯에는 얼음이 없다. 실제로 자리를 바꾼 상대만 추적한다.
    if mirror is not None:
        for twin, at in enumerate(before.positions):
            if twin != index and after.positions[twin] != at:
                landings.append((twin, _step(at, (-dx, -dy)), False))
    arrivals = []
    for block, landing, slid in landings:
        for pair, (a, b) in enumerate(shelf.pairs):
            if landing in (a, b):
                twin = b if landing == a else a
                arrivals.append(_ShelfArrival(block, pair, after.positions[block] == twin, slid))
    return tuple(arrivals)


def _solution_matches(level: dict, solution: list[Move], *, chapter: int) -> bool:
    used_pairs = set()
    goal_crossed = False
    blocked = False
    clock_departure = False
    gate_passage = False
    for before, move, after in trace_solution(level, solution):
        arrivals = _shelf_arrivals(before, move, after)
        teleports = [entry for entry in arrivals if entry.teleported]
        if chapter == 2 and any(entry.slid for entry in teleports):
            return True
        if chapter == 3 and len({entry.pair for entry in teleports}) == 2:
            return True
        if chapter == 4 and goal_crossed and move.index == 0:
            clock = next(rule for rule in before.board.mechanics if isinstance(rule, ClockArrow))
            clock_departure |= before.positions[0] in clock.cells
        if chapter == 5:
            gate = next(rule for rule in before.board.mechanics if isinstance(rule, EchoGate))
            gate_passage |= after.positions[0] == gate.gate and before.echo == gate.switch
        used_pairs.update(entry.pair for entry in teleports)
        goal_crossed |= any(entry.block == 0 for entry in teleports)
        blocked |= any(not entry.teleported for entry in arrivals)
    if chapter == 1:
        return goal_crossed and blocked
    if chapter == 4:
        return clock_departure
    if chapter == 5:
        return gate_passage and len(used_pairs) == 2
    return False


def _seed_layout(rng: Random, *, chapter: int, size: tuple[int, int],
                 walls: tuple[int, int]) -> dict:
    """통과해야 할 책장과 짧은 진입로를 놓고 주변 통로를 무작위로 만든다."""
    width, height = size
    free = {(x, y) for y in range(height) for x in range(width)}

    def take() -> Position:
        cell = rng.choice(sorted(free))
        free.remove(cell)
        return cell

    def lane(length: int, directions: tuple[Position, ...] = DIRECTIONS) -> tuple[Position, ...]:
        options = [tuple((x + dx * i, y + dy * i) for i in range(length))
                   for x, y in sorted(free) for dx, dy in directions]
        cells = rng.choice([option for option in options if free.issuperset(option)])
        free.difference_update(cells)
        return cells

    extras = []
    pairs = []
    forced_walls = set()
    if chapter == 5:
        # 별문에는 문을 지나서만 닿는다. 둘째 책장으로 문 앞에 옮겨갈 수 있다.
        exit_point = rng.choice([(0, 0), (0, height - 1), (width - 1, 0), (width - 1, height - 1)])
        neighbors = sorted(free.intersection(_step(exit_point, direction) for direction in DIRECTIONS))
        gate = rng.choice(neighbors)
        forced_walls.update(set(neighbors) - {gate})
        free.difference_update({exit_point, gate, *forced_walls})
        gate_front = rng.choice(sorted(free.intersection(_step(gate, direction) for direction in DIRECTIONS)))
        free.remove(gate_front)
        switch, entrance = lane(2)
        pairs.append((take(), take()))
        pairs.append((entrance, gate_front))
        extras.append({'type': GATE, 'switch': _point(switch), 'gate': _point(gate)})
        start = take()
        b1 = take()
    elif chapter == 3:
        start, entrance = lane(2)
        reverse = (start[0] - entrance[0], start[1] - entrance[1])
        b1, twin_entrance = lane(2, (reverse,))
        pairs = [(entrance, take()), (twin_entrance, take())]
        extras.append({'type': MIRROR, 'blocks': ['goal', 'b1']})
    elif chapter == 2:
        start, *ice, entrance = lane(rng.choice((3, 4)))
        pairs.append((entrance, take()))
        ice.append(take())
        extras.append({'type': ICE, 'positions': list(map(_point, ice))})
        b1 = take()
    else:
        a, b = lane(2) if chapter == 1 and rng.random() < .55 else (take(), take())
        pairs.append((a, b))
        start = take()
        b1 = take()
        if chapter == 4:
            choices = sorted(free.intersection(_step(b, direction) for direction in DIRECTIONS))
            clock = rng.choice(choices or sorted(free))
            free.remove(clock)
            arrows = []
            for cell in (clock, take()):
                dx, dy = rng.choice(DIRECTIONS)
                arrows.append({**_point(cell), 'dx': dx, 'dy': dy})
            extras.append({'type': CLOCK, 'tiles': arrows})
    b2 = take()
    if chapter != 5:
        exits = [cell for cell in sorted(free) if _distance(cell, start) >= 4]
        exit_point = rng.choice(exits or sorted(free))
        free.remove(exit_point)
    wall_count = rng.randint(*walls) - len(forced_walls)
    obstacles = sorted(forced_walls) + rng.sample(sorted(free), wall_count)
    return {
        'startPosition': _point(start), 'exitPosition': _point(exit_point),
        'blocks': [{'id': 'b1', **_point(b1)}, {'id': 'b2', **_point(b2)}],
        'obstacles': list(map(_point, obstacles)),
        'specialRules': [{'type': SHELF, 'pairs': [{'a': _point(a), 'b': _point(b)} for a, b in pairs]}, *extras],
    }


def _slot(chapter: int, target: int, intent: str, *, size: tuple[int, int] = SMALL,
          power: str | None = None, seconds: int = 240) -> Slot:
    walls = (8, 13) if size == WIDE else (6, 11)
    extra = ((), (ICE,), (MIRROR,), (CLOCK,), (GATE,))[chapter - 1]
    return Slot(
        target, size, 2, walls, (SHELF, *extra), power, False, intent,
        (power,) if power else (), f'world6-chapter{chapter}',
        quick_states=120_000, full_states=200_000, max_seconds=seconds,
        move_tolerance=0, reject_similar=True,
        solution_filter=partial(_solution_matches, chapter=chapter),
        layout_factory=partial(_seed_layout, chapter=chapter, size=size, walls=walls),
        mutate_layout=True,
    )


SLOTS = (
    # 1장 열람실
    _slot(1, 10, '같은 무늬 책장을 건너가고 막힌 짝에서는 걸어서 나간다'),
    _slot(1, 12, '막힌 책장에서 멈춘 뒤 출구로 갈 자리를 만든다'),
    _slot(1, 13, '룬석이나 잔상이 짝 칸을 막는 수를 이용한다'),
    _slot(1, 14, '책장을 건널 때와 입구에 멈출 때를 나눈다'),
    _slot(1, 16, '수호판은 같은 책장을 이동과 정지에 번갈아 쓴다'),
    # 2장 접힌 복도
    _slot(2, 10, '얼음을 타고 책장 입구까지 닿는다'),
    _slot(2, 12, '어느 쪽에서 미끄러져야 책장에 닿는지 찾는다'),
    _slot(2, 14, '책장에서 나온 위치에 맞춰 다음 이동을 고른다'),
    _slot(2, 15, '룬석을 옮겨 얼음에서 책장으로 이어지는 길을 만든다'),
    _slot(2, 17, '수호판은 얼음의 끝과 책장 출구를 함께 읽는다'),
    # 3장 거꾸로 꽂힌 책
    _slot(3, 11, '두 짝을 같은 수에 서로 다른 책장으로 보낸다'),
    _slot(3, 13, '어느 블록을 움직이면 양쪽 책장에 닿는지 고른다'),
    _slot(3, 15, '짝의 반대 이동으로 서로 다른 통로를 연다'),
    _slot(3, 16, '두 쌍의 책장 출구를 다음 수의 발판으로 삼는다'),
    _slot(3, 18, '수호판은 짝의 두 착지를 한 수로 맞춘다', seconds=300),
    # 4장 시계 서가
    _slot(4, 12, '책장으로 건넌 뒤 바늘이 가리키는 길을 읽는다'),
    _slot(4, 14, '순간 이동이 한 수라는 점을 이용해 시각을 맞춘다'),
    _slot(4, 15, '책장 출구에서 출발할 시각과 바늘을 함께 맞춘다'),
    _slot(4, 17, '넓은 서가에서 순간 이동과 바늘의 순서를 맞춘다', size=WIDE),
    _slot(4, 19, '수호판은 책장과 시곗바늘을 잇는 수를 정렬한다', size=WIDE, seconds=300),
    # 5장 첫 잔상의 책
    _slot(5, 12, '두 쌍의 책장을 지나 열려 있는 문에 닿는다', size=WIDE),
    _slot(5, 15, '책장으로 건너가며 수정에 잔상을 남긴다', size=WIDE),
    _slot(5, 16, '빛 교대로 잔상에 닿고 두 쌍의 책장을 거쳐 문을 통과한다', size=WIDE, power=SWAP),
    _slot(5, 18, '먼저 건널 책장과 문을 열어 둘 수를 구분한다', size=WIDE, seconds=300),
    _slot(5, 21, '수호판은 두 쌍의 책장과 달 수정 문을 한 경로로 연결한다', size=WIDE, seconds=300),
)
