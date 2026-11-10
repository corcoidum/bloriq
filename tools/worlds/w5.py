"""세계 5 얼음 동굴의 25개 생성 슬롯."""

from functools import partial
from random import Random

from tools.mechanics import ClockArrow, DIRECTIONS, EchoGate, EchoHold, Ice, MechanicMove, MirrorPair, OneWay, Position, State
from tools.validate_levels import Move, WIND, trace_solution
from tools.worlds import Slot

ICE = Ice.type
HOLD = EchoHold.type
MIRROR = MirrorPair.type
CLOCK = ClockArrow.type
GATE = EchoGate.type
STREAM = OneWay.type
SIZE = (5, 5)
ICE_CAP = SIZE[0] * SIZE[1] * 3 // 10


def _point(cell: Position) -> dict[str, int]:
    return {'x': cell[0], 'y': cell[1]}


def _distance(a: Position, b: Position) -> int:
    return abs(a[0] - b[0]) + abs(a[1] - b[1])


def _direction(a: Position, b: Position) -> Position:
    x, y = b[0] - a[0], b[1] - a[1]
    return (x > 0) - (x < 0), (y > 0) - (y < 0)


def _ice_limit(rules: list[dict]) -> bool:
    return 1 <= sum(len(rule['positions']) for rule in rules if rule['type'] == ICE) <= ICE_CAP


def sliding_blocks(before: State, move: MechanicMove, after: State) -> tuple[int, ...]:
    """얼음으로 착지가 연장된 블록. 바람의 기본 착지와 짝의 첫 칸은 제외한다."""
    return tuple(
        index for index, (source, end) in enumerate(zip(before.positions, after.positions))
        if (end != move.target if index == move.index else _distance(source, end) > 1)
    )


def _next_after_slide(before: State, after: State, index: int) -> Position:
    x, y = after.positions[index]
    dx, dy = _direction(before.positions[index], (x, y))
    return x + dx, y + dy


def _solution_matches(level: dict, solution: list[Move], *, chapter: int) -> bool:
    ice = next(rule for rule in level['specialRules'] if rule['type'] == ICE)
    tiles = {(tile['x'], tile['y']) for tile in ice['positions']}
    slide_turns = 0
    chapter_idea_used = False
    for before, move, after in trace_solution(level, solution):
        slides = sliding_blocks(before, move, after)
        if slides:
            slide_turns += 1
        if chapter == 1:
            chapter_idea_used |= any(
                after.positions[index] in tiles
                and _next_after_slide(before, after, index) in before.positions[1:]
                for index in slides
            )
        elif chapter == 2:
            if WIND in level['availablePowers']:
                if move.power == WIND:
                    start = before.positions[move.index]
                    dx, dy = _direction(start, move.target)
                    chapter_idea_used |= any(
                        (start[0] + dx * step, start[1] + dy * step) not in tiles
                        for step in range(1, _distance(start, move.target))
                    )
            else:
                chapter_idea_used |= any(
                    after.positions[index] in tiles
                    and _next_after_slide(before, after, index) == before.echo
                    for index in slides
                )
        elif chapter == 3:
            chapter_idea_used |= len(slides) == 2
        elif chapter == 4:
            clock = next(rule for rule in before.board.mechanics if rule.type == CLOCK)
            chapter_idea_used |= any(after.positions[index] in clock.cells for index in slides)
        else:
            gate = next(rule for rule in before.board.mechanics if isinstance(rule, EchoGate))
            chapter_idea_used |= any(
                after.positions[index] == gate.gate
                or (before.echo != gate.switch
                    and _next_after_slide(before, after, index) == gate.gate)
                for index in slides
            )
    return slide_turns >= 2 and chapter_idea_used


def _seed_layout(rng: Random, *, walls: tuple[int, int], extras: tuple[str, ...],
                 chapter: int, target: int) -> dict:
    """두 얼음 줄을 먼저 놓고 주위의 방과 통로를 무작위로 채운다."""
    free = {(x, y) for y in range(SIZE[1]) for x in range(SIZE[0])}

    def rail(directions: tuple[Position, ...]) -> tuple[Position, ...]:
        options = [
            tuple((x + dx * step, y + dy * step) for step in range(4))
            for x, y in sorted(free) for dx, dy in directions
        ]
        line = rng.choice([line for line in options if free.issuperset(line)])
        free.difference_update(line)
        return line

    def take() -> Position:
        cell = rng.choice(sorted(free))
        free.remove(cell)
        return cell

    first = rail(DIRECTIONS)
    dx, dy = _direction(first[0], first[-1])
    second = rail(((-dx, -dy),) if MIRROR in extras else DIRECTIONS)
    ice = [*first[1:-1], *second[1:-1]]
    start = first[0]
    if MIRROR in extras:
        b1 = second[0]
    elif chapter == 1 or HOLD in extras:
        b1 = first[-1]
    else:
        b1 = take()
    b2 = take()
    exit_options = [cell for cell in sorted(free)
                    if _distance(start, cell) >= (5 if target >= 15 else 4)]
    exit_point = rng.choice(exit_options or sorted(free))
    free.remove(exit_point)

    rules = []
    if HOLD in extras:
        rules.append({'type': HOLD, 'positions': [_point(first[0])]})
    if MIRROR in extras:
        rules.append({'type': MIRROR, 'blocks': ['goal', 'b1']})
    if CLOCK in extras:
        arrows = []
        for cell in (first[-1], take()):
            arrow_x, arrow_y = rng.choice(DIRECTIONS)
            arrows.append({**_point(cell), 'dx': arrow_x, 'dy': arrow_y})
        rules.append({'type': CLOCK, 'tiles': arrows})
    if GATE in extras:
        switch = rng.choice([first[0], second[-1]])
        rules.append({'type': GATE, 'switch': _point(switch), 'gate': _point(first[-1])})
    if STREAM in extras:
        arrow_x, arrow_y = _direction(second[0], second[-1])
        rules.append({'type': STREAM, 'tiles': [
            {**_point(second[0]), 'dx': arrow_x, 'dy': arrow_y},
        ]})
    if len(free) > walls[0] and rng.random() < .35:
        ice.append(take())
    wall_count = rng.randint(walls[0], min(walls[1], len(free)))
    return {
        'startPosition': _point(start),
        'exitPosition': _point(exit_point),
        'blocks': [{'id': 'b1', **_point(b1)}, {'id': 'b2', **_point(b2)}],
        'obstacles': [_point(cell) for cell in rng.sample(sorted(free), wall_count)],
        'specialRules': [{'type': ICE, 'positions': list(map(_point, ice))}, *rules],
    }


def _slot(chapter: int, target: int, intent: str, *extra: str,
          wind: bool = False, seconds: int = 240) -> Slot:
    walls = (6, 11) if chapter < 5 else (6, 10)
    return Slot(
        target, SIZE, 2, walls, (ICE, *extra), WIND if wind else None, False,
        intent, (WIND,) if wind else (), f'world5-chapter{chapter}',
        quick_states=100_000, full_states=200_000, max_seconds=seconds,
        move_tolerance=0, reject_similar=True, rule_filter=_ice_limit,
        solution_filter=partial(_solution_matches, chapter=chapter),
        layout_factory=partial(_seed_layout, walls=walls, extras=extra, chapter=chapter, target=target),
        mutate_layout=True,
    )


SLOTS = (
    # 1장 서리 입구 — 룬석을 얼음의 정지벽으로 쓴다.
    _slot(1, 9, '룬석을 벽 삼아 얼음 위에 멈춘다'),
    _slot(1, 11, '얼음 끝을 지나치지 않게 룬석으로 받친다'),
    _slot(1, 12, '룬석을 옮겨 미끄러짐이 끝나는 자리를 바꾼다'),
    _slot(1, 14, '룬석으로 막을 칸과 비울 칸을 나눈다'),
    _slot(1, 15, '수호판: 정지벽과 출구까지 갈 통로를 함께 만든다'),
    # 2장 고드름 회랑 — 두 판에서 바람, 나머지에서 호박석과 잔상.
    _slot(2, 10, '얼음의 첫 바닥과 바람이 닿는 끝을 구분한다', wind=True),
    _slot(2, 12, '잔상이 남는 동안 얼음 위의 정지 칸을 고른다', HOLD),
    _slot(2, 14, '얼음에서는 닿지 않는 칸을 바람으로 건넌다', wind=True),
    _slot(2, 15, '호박석과 이전 잔상으로 정지 칸을 맞춘다', HOLD),
    _slot(2, 17, '수호판: 얼음길에서 남아 있는 잔상과 열린 길을 구분한다', HOLD),
    # 3장 얼음 거울 — 한 턴에 반대 방향으로 두 블록이 미끄러진다.
    _slot(3, 11, '두 블록을 반대쪽 얼음에 동시에 보낸다', MIRROR),
    _slot(3, 13, '짝의 도착 위치를 읽고 다음 통로를 연다', MIRROR),
    _slot(3, 14, '두 얼음길을 연결해 리크와 짝의 자리를 맞춘다', MIRROR),
    _slot(3, 16, '어느 블록을 밀어야 두 정지 위치가 맞는지 고른다', MIRROR),
    _slot(3, 18, '수호판: 한 번의 미끄러짐으로 두 블록의 다음 길을 연다', MIRROR, seconds=300),
    # 4장 눈보라 갈림길 — 얼음의 정지 칸에서 다음 바늘 방향을 읽는다.
    _slot(4, 11, '미끄러진 뒤 시곗바늘 위에서 정지한다', CLOCK),
    _slot(4, 13, '시곗바늘에 닿을 때의 시각을 먼저 맞춘다', CLOCK),
    _slot(4, 15, '정지한 시곗바늘에서 나갈 길을 다른 블록으로 연다', CLOCK),
    _slot(4, 17, '얼음길에서 바늘까지 이어지는 순서를 맞춘다', CLOCK),
    _slot(4, 19, '수호판: 시곗바늘의 정지 칸과 출발 시각을 함께 정한다', CLOCK, seconds=300),
    # 5장 기억 보존 장치 — 문 앞에서 멈추고 물길의 출발 방향을 더한다.
    _slot(5, 12, '얼음길에서 달 수정 문 바로 앞에 멈춘다', GATE),
    _slot(5, 14, '고정 물길로 나간 뒤 얼음과 문을 맞춘다', GATE, STREAM),
    _slot(5, 16, '문이 열리는 한 수에 얼음의 정지 칸을 맞춘다', GATE),
    _slot(5, 18, '고정 물길을 지나 문에 닿기 전 수정을 준비한다', GATE, STREAM, seconds=300),
    _slot(5, 20, '수호판: 얼음과 물길 사이에서 열린 문에 정확히 닿는다', GATE, STREAM, seconds=300),
)
