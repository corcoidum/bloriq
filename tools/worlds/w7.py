"""세계 7 첫 별의 혼합 판 25개 생성 슬롯."""

from functools import partial
from itertools import combinations
from random import Random

from tools.mechanics import REGISTRY
from tools.validate_levels import LEAP, SEAL, SWAP, WIND
from tools.worlds import Slot
from tools.worlds.w6 import _seed_layout as shelf_layout
from tools.worlds.w6 import _solution_matches as shelf_solution_matches

FOREST = ('echoEraser', 'echoHold', 'oneWay', 'goalOnly', 'echoGate')
LIGHTHOUSES = ('mirrorPair', 'clockArrow', 'ice', 'shelfDoor')
SMALL = (5, 5)
WIDE = (6, 5)
LARGE = (6, 6)


def _mixed_layout(rng: Random) -> dict:
    """책장 진입로를 출발점으로 삼되 세 번째 기믹과 주변 벽은 무작위로 둔다."""
    kinds = rng.choice(tuple(combinations(LIGHTHOUSES, 3)))
    if 'shelfDoor' in kinds:
        chapter = 2 if 'ice' in kinds else 3
        level = shelf_layout(rng, chapter=chapter, size=WIDE, walls=(9, 14))
    else:
        free = [(x, y) for y in range(5) for x in range(6)]
        rng.shuffle(free)

        def take() -> dict:
            x, y = free.pop()
            return {'x': x, 'y': y}

        level = {'startPosition': take(), 'exitPosition': take(),
                 'blocks': [{'id': f'b{index}', **take()} for index in (1, 2)],
                 'obstacles': [take() for _ in range(rng.randint(9, 14))],
                 'specialRules': []}
    # 기존 책장/얼음/짝의 좌표와 새 기믹의 좌표를 분리한다.
    from tools.design_world import occupied, pt

    free = [(x, y) for y in range(5) for x in range(6) if (x, y) not in occupied(level)]
    rng.shuffle(free)

    def take_extra() -> dict:
        if not free:
            raise ValueError('No space for a third mechanic')
        return pt(free.pop())

    present = {rule['type'] for rule in level['specialRules']}
    for kind in kinds:
        if kind not in present:
            level['specialRules'].append(REGISTRY[kind].randomRule(level, rng, take_extra))
    return level


def _slot(chapter: int, target: int, intent: str, *, size: tuple[int, int] = SMALL,
          power: str | None = None, seconds: int = 300, finale: bool = False) -> Slot:
    fixed = ((), ('mirrorPair', 'clockArrow'), ('ice', 'shelfDoor'), (), ())[chapter - 1]
    candidates = FOREST if chapter == 1 else LIGHTHOUSES if chapter >= 4 else ()
    count = 2 if chapter == 1 else 3 if chapter >= 4 else 0
    walls = (13, 18) if size == LARGE else (9, 14) if size == WIDE else (6, 11)
    layout = None
    solution_filter = None
    if chapter == 3:
        layout = partial(shelf_layout, chapter=2, size=size, walls=walls)
        solution_filter = partial(shelf_solution_matches, chapter=2)
    elif chapter == 4:
        layout = _mixed_layout
    return Slot(
        target, size, 2, walls, fixed, power, False, intent,
        (power,) if power else (), f'world7-chapter{chapter}',
        quick_states=100_000, full_states=200_000, max_seconds=seconds,
        move_tolerance=0, reject_similar=True,
        layout_factory=layout, mutate_layout=True, solution_filter=solution_filter,
        mechanic_candidates=candidates, mechanic_count=count,
        fixed_start=(0, 2) if finale else None, fixed_exit=(5, 2) if finale else None,
    )


SLOTS = (
    # 1장 빛길의 시작 — 세계 1 칸 둘과 권능 하나를 모두 사용한다.
    _slot(1, 11, '두 잔상 칸을 구분하고 바람으로 열린 길을 잇는다', power=WIND),
    _slot(1, 13, '잔상 칸의 순서를 맞춘 뒤 달꽃으로 바위를 넘는다', power=LEAP),
    _slot(1, 14, '두 잔상 규칙 사이에 빛 교대의 도착 자리를 만든다', power=SWAP),
    _slot(1, 15, '봉인으로 이전 잔상을 유지하며 두 칸 규칙을 연결한다', power=SEAL),
    _slot(1, 17, '수호판은 잔상 칸 두 종류와 바람의 정지 위치를 함께 읽는다', power=WIND),
    # 2장 거울과 시계 — 짝의 반대 이동과 이동 전 시각을 함께 읽는다.
    _slot(2, 12, '거울 짝을 한 수로 옮겨 바늘을 돌린다'),
    _slot(2, 14, '짝이 비워 주는 칸으로 돌아간 바늘을 지난다'),
    _slot(2, 15, '두 블록의 출발 방향을 같은 시각에서 읽는다'),
    _slot(2, 17, '짝의 착지와 다음 수의 시각을 함께 맞춘다'),
    _slot(2, 19, '수호판은 짝의 막힘과 바늘을 기다리는 수를 엮는다'),
    # 3장 얼음과 책장 — 미끄러짐이 끝나는 책장에서 건너간다.
    _slot(3, 12, '얼음의 끝에 놓인 책장으로 들어간다'),
    _slot(3, 14, '책장 출구를 비우고 같은 얼음길을 다시 쓴다'),
    _slot(3, 16, '미끄러지는 입구와 걸어서 들어갈 입구를 구분한다'),
    _slot(3, 18, '넓은 판에서 얼음과 책장으로 두 통로를 연결한다', size=WIDE),
    _slot(3, 20, '수호판은 얼음의 정지 칸과 건너편 책장을 함께 준비한다', size=WIDE),
    # 4장 다섯 등대의 합창 — 네 등대 기믹 중 정확히 셋을 쓴다.
    _slot(4, 13, '서로 다른 등대 기믹 셋을 한 경로로 잇는다', size=WIDE),
    _slot(4, 15, '첫 기믹의 도착 위치를 다음 두 기믹의 발판으로 쓴다', size=WIDE),
    _slot(4, 17, '블록을 옮기는 수와 리크가 지나가는 수를 나눈다', size=WIDE),
    _slot(4, 19, '세 기믹의 순서를 바꾸어 막힌 경로를 연다', size=WIDE),
    _slot(4, 22, '수호판은 세 등대의 이동 결과를 다음 수까지 읽는다', size=WIDE, seconds=600),
    # 5장 마지막 잔상 — 6×6 상한 안에서 세 기믹을 종합한다.
    _slot(5, 14, '넓은 하늘에서 서로 다른 이동 결과를 차례로 준비한다', size=LARGE),
    _slot(5, 16, '돌아올 길을 남기고 세 기믹의 순서를 정한다', size=LARGE),
    _slot(5, 18, '룬석의 위치로 지름길과 정지 칸을 바꾼다', size=LARGE),
    _slot(5, 20, '출구를 향하기 전에 세 기믹이 잇는 길을 만든다', size=LARGE, seconds=600),
    _slot(5, 24, '처음처럼 왼쪽에서 오른쪽 별문을 향해 마지막 잔상을 잇는다',
          size=LARGE, seconds=900, finale=True),
)
