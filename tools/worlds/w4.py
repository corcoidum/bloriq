"""세계 4 시계탑 등대의 25개 생성 슬롯."""

from random import Random
from typing import Callable

from tools.mechanics import ClockArrow, EchoEraser, EchoGate, EchoHold, MirrorPair, OneWay, Position
from tools.validate_levels import SEAL, Move
from tools.worlds import Slot

CLOCK = ClockArrow.type
ERASER = EchoEraser.type
HOLD = EchoHold.type
GATE = EchoGate.type
MIRROR = MirrorPair.type
STREAM = OneWay.type
_CLOCKWISE = ((1, 0), (0, 1), (-1, 0), (0, -1))


def _arrows(rules: list[dict], kind: str) -> dict[tuple[int, int], tuple[int, int]]:
    return {(tile['x'], tile['y']): (tile['dx'], tile['dy'])
            for rule in rules if rule['type'] == kind for tile in rule['tiles']}


def _waits_on_clock(level: dict, moves: list[Move]) -> bool:
    arrows = _arrows(level['specialRules'], CLOCK)
    previous_goal_turn = None
    for turn, (block, source, *_) in enumerate(moves):
        if block != 'goal':
            continue
        if previous_goal_turn is not None and source in arrows:
            # 리크가 도착한 직후에는 못 나가고 다른 블록을 민 뒤에야 나간다.
            wait = turn - previous_goal_turn - 1
            if wait % 4:
                return True
        previous_goal_turn = turn
    return False


def _hands_agree(rules: list[dict]) -> bool:
    return len(set(_arrows(rules, CLOCK).values())) == 1


def _uses_alignment(level: dict, moves: list[Move]) -> bool:
    clock = _arrows(level['specialRules'], CLOCK)
    fixed = _arrows(level['specialRules'], STREAM)
    used_directions = {fixed[source] for _, source, *_ in moves if source in fixed}
    if fixed and not used_directions:
        return False
    # 물길이 있는 판에서는 회전 바늘이 고정 바늘과 같은 방향인 수를 쓴다.
    return any(
        source in clock and (
            not fixed or (target[0] - source[0], target[1] - source[1]) in used_directions
        )
        for _, source, target, *_ in moves
    )


def _echo_corridor(rng: Random) -> dict:
    """리크 통로와 별개로 잔상 없이 왕복할 수 있는 태엽 줄을 생성한다."""
    def point(position: Position) -> dict[str, int]:
        x, y = position
        return {'x': x, 'y': y}

    # 10수의 통로에 3수 대기 지점 두 곳을 만든다. BFS가 최단과 기믹 효과를 확인한다.
    path = [(x, 0) for x in range(5)] + [(4, 1)] + [(x, 2) for x in reversed(range(5))]
    if rng.random() < .5:
        path.reverse()
    lane_x = rng.randrange(4)
    lane = [(lane_x, 4), (lane_x + 1, 4)]
    rng.shuffle(lane)
    eraser, hold = lane
    spare = rng.choice([x for x in (lane_x - 1, lane_x + 2) if 0 <= x < 5]), 4
    free = {*path, *lane, spare}

    waits = dict(zip(rng.sample(path[1:-1], 3), (3, 3, 0)))
    tiles = []
    turn = 0
    for source, target in zip(path, path[1:]):
        if source in waits:
            turn += waits[source]
            direction = target[0] - source[0], target[1] - source[1]
            dx, dy = _CLOCKWISE[(_CLOCKWISE.index(direction) - turn) % 4]
            tiles.append({**point(source), 'dx': dx, 'dy': dy})
        turn += 1
    return {
        'startPosition': point(path[0]),
        'exitPosition': point(path[-1]),
        'blocks': [{'id': 'b1', **point(eraser)}, {'id': 'b2', **point(spare)}],
        'obstacles': [point((x, y)) for y in range(5) for x in range(5) if (x, y) not in free],
        'specialRules': [
            {'type': CLOCK, 'tiles': tiles},
            {'type': ERASER, 'positions': [point(eraser)]},
            {'type': HOLD, 'positions': [point(hold)]},
        ],
    }


def _slot(chapter: int, target: int, size: tuple[int, int], walls: tuple[int, int],
          intent: str, *extra: str, power: str | None = None,
          layout: Callable[[Random], dict] | None = None, seconds: int = 240) -> Slot:
    return Slot(
        target, size, 2, walls, (CLOCK, *extra), power, False, intent,
        (power,) if power else (), f'world4-chapter{chapter}',
        quick_states=100_000, full_states=200_000, max_seconds=seconds,
        move_tolerance=0, reject_similar=True,
        rule_filter=_hands_agree if chapter == 5 else None,
        solution_filter={1: _waits_on_clock, 5: _uses_alignment}.get(chapter),
        layout_factory=layout,
    )


SLOTS = (
    # 1장 태엽 마당 — 리크가 바늘을 기다리는 동안 다른 블록을 움직인다.
    _slot(1, 9, (4, 4), (3, 5), '리크를 시곗바늘 칸에 두고 다른 블록으로 시각을 돌린다'),
    _slot(1, 11, (4, 4), (3, 6), '바늘이 출구 쪽으로 향할 때까지 빈 수를 만든다'),
    _slot(1, 12, (5, 4), (4, 7), '다른 블록의 위치와 시각을 한 수로 맞춘다'),
    _slot(1, 13, (5, 4), (4, 7), '리크가 기다릴 칸과 다른 블록을 움직일 통로를 나눈다'),
    _slot(1, 15, (5, 5), (5, 9), '수호판: 리크를 멈춘 채 바늘과 통로를 함께 맞춘다'),
    # 2장 톱니 회랑 — 시각과 잔상의 지우기·유지.
    _slot(2, 10, (5, 4), (4, 8), '민들레를 떠날 때 잔상을 지워 다음 시각의 길을 연다', ERASER),
    _slot(2, 12, (5, 4), (4, 7), '호박석에서 떠나도 이전 잔상과 돌아간 바늘을 함께 읽는다', HOLD),
    _slot(2, 13, (5, 4), (4, 7), '잔상을 지운 뒤 달라진 시각에 맞춰 통로로 들어간다', ERASER),
    _slot(2, 14, (5, 5), (5, 10), '호박석으로 남길 잔상을 고르고 시각을 한 칸 돌린다', HOLD),
    _slot(2, 16, (5, 5), (11, 11), '수호판: 민들레와 호박석 사이를 왕복하며 시각을 맞춘다', ERASER, HOLD,
          layout=_echo_corridor),
    # 3장 종지기의 다락 — 문이 열린 한 수를 맞춘다.
    _slot(3, 11, (5, 5), (5, 9), '수정에서 떠날 때 돌아가는 바늘과 열리는 문을 함께 읽는다', GATE),
    _slot(3, 13, (5, 5), (5, 9), '문이 열릴 수를 먼저 정하고 그 전에 리크의 길을 만든다', GATE),
    _slot(3, 14, (5, 5), (5, 9), '문을 열기 전에 바늘이 향할 방향을 정리한다', GATE),
    _slot(3, 15, (5, 5), (5, 9), '수정에 잔상을 남길 블록과 열린 문을 지날 블록을 나눈다', GATE),
    _slot(3, 17, (5, 5), (5, 9), '수호판: 수정의 잔상과 바늘의 순서를 맞춰 문을 넘는다', GATE),
    # 4장 추의 계단 — 봉인 두 판, 거울 짝 두 판, 시각 종합 수호판.
    _slot(4, 11, (5, 5), (6, 11), '봉인으로 잔상을 붙잡고 블록을 옮겨 바늘을 돌린다', power=SEAL),
    _slot(4, 13, (5, 5), (5, 9), '거울 짝 두 블록을 옮겨도 바늘은 한 번만 돌아간다', MIRROR),
    _slot(4, 15, (5, 5), (5, 10), '돌아올 길을 위해 직전 잔상을 봉인하고 바늘을 맞춘다', power=SEAL),
    _slot(4, 16, (5, 5), (5, 9), '짝의 출발 방향까지 같은 시각에서 살핀다', MIRROR),
    _slot(4, 18, (5, 5), (5, 9), '수호판: 권능 없이 긴 이동 순서와 바늘 시각을 맞춘다'),
    # 5장 멈춘 자정 — 같은 시각을 가리키는 회전 바늘과 고정된 물길.
    _slot(5, 12, (5, 5), (5, 9), '함께 도는 바늘과 멈춘 물길이 같은 쪽을 가리킬 때 나간다', STREAM),
    _slot(5, 14, (5, 5), (5, 9), '바늘이 한 방향으로 도는 동안 문을 열 수를 마련한다', GATE),
    _slot(5, 16, (5, 5), (5, 9), '고정된 물길 방향을 기준 삼아 돌아가는 바늘을 맞춘다', STREAM),
    _slot(5, 17, (5, 5), (5, 9), '같이 돌아가는 바늘의 출발 시각과 문이 열린 한 수를 맞춘다', GATE),
    _slot(5, 19, (5, 5), (5, 9), '수호판: 문과 고정 물길을 사이에 두고 같은 방향이 되는 수를 쓴다', GATE, STREAM, seconds=480),
)
