"""세계 3 거울 호수 등대의 25개 슬롯."""

from tools.mechanics import MirrorPair
from tools.validate_levels import LEAP, SWAP
from tools.worlds import Slot

MIRROR = MirrorPair.type


def _has_goal_pair(rules: list[dict]) -> bool:
    return any('goal' in rule['blocks'] for rule in rules if rule['type'] == MIRROR)


def _rune_pairs(rules: list[dict]) -> bool:
    return not _has_goal_pair(rules)


def _slot(
    chapter: int,
    target: int,
    size: tuple[int, int],
    blocks: int,
    walls: tuple[int, int],
    mechanics: tuple[str, ...],
    intent: str,
    *,
    power: str | None = None,
    tolerance: int = 0,
    seconds: int = 120,
) -> Slot:
    return Slot(
        target, size, blocks, walls, mechanics, power, False, intent,
        (power,) if power else (), f'world3-chapter{chapter}',
        quick_states=40_000,
        full_states=160_000,
        max_seconds=seconds,
        move_tolerance=tolerance,
        rule_filter=_has_goal_pair if chapter == 5 else _rune_pairs,
        reject_similar=True,
    )


SLOTS = (
    # 1장 잔잔한 물가 — 한 쌍의 반대 이동과 홀로 밀기
    _slot(1, 8, (4, 4), 2, (3, 6), (MIRROR,), '한 번 밀어 두 룬석의 반대 이동을 읽는다'),
    _slot(1, 10, (4, 4), 2, (3, 6), (MIRROR,), '짝을 바위나 가장자리에 멈춰 한쪽만 민다'),
    _slot(1, 11, (5, 4), 2, (4, 7), (MIRROR,), '막힌 짝을 두고 통로 쪽 룬석을 먼저 옮긴다'),
    _slot(1, 12, (5, 4), 2, (4, 7), (MIRROR,), '두 룬석이 벌어지는 방향과 모이는 방향을 번갈아 쓴다'),
    _slot(1, 14, (5, 5), 2, (5, 9), (MIRROR,), '수호판: 두 룬석의 배치를 맞춰 리크 길을 만든다'),
    # 2장 수련 징검다리 — 민들레와 호박석을 번갈아 소개
    _slot(2, 9, (5, 4), 2, (4, 7), (MIRROR, 'echoEraser'), '민들레에서 떠나 잔상 없는 통로를 만든다'),
    _slot(2, 11, (5, 4), 2, (4, 7), (MIRROR, 'echoHold'), '호박석에서 출발할 때 남아 있을 잔상을 살핀다'),
    _slot(2, 12, (5, 4), 2, (4, 7), (MIRROR, 'echoEraser'), '민들레와 짝을 써서 막힌 자리를 다시 연다'),
    _slot(2, 13, (5, 5), 2, (4, 8), (MIRROR, 'echoHold'), '호박석에 남긴 잔상으로 짝이 멈출 칸을 고른다', seconds=150),
    _slot(2, 15, (5, 5), 2, (5, 9), (MIRROR, 'echoEraser', 'echoHold'), '수호판: 지울 잔상과 남길 잔상을 구분한다', seconds=180),
    # 3장 물안개 다리 — 물길과 클로버, 두 판에서 달꽃 도약
    _slot(3, 10, (5, 4), 2, (3, 6), (MIRROR, 'oneWay'), '물길이 허락하는 방향에서 짝을 움직인다'),
    _slot(3, 12, (5, 4), 2, (4, 7), (MIRROR, 'goalOnly'), '리크 전용 칸을 살피고 도약으로 바위를 넘는다', power=LEAP),
    _slot(3, 13, (5, 5), 2, (5, 8), (MIRROR, 'goalOnly'), '룬석이 설 수 없는 클로버 옆에 리크 길을 낸다'),
    _slot(3, 14, (5, 5), 2, (5, 8), (MIRROR, 'oneWay'), '물길과 반대 이동을 정리한 뒤 달꽃 도약을 쓴다', power=LEAP, seconds=180),
    _slot(3, 16, (5, 5), 2, (5, 9), (MIRROR, 'oneWay', 'goalOnly'), '수호판: 물길과 클로버가 허락하는 순서를 맞춘다', seconds=180),
    # 4장 뒤집힌 탑 — 두 룬석 짝과 달 수정 문
    _slot(4, 11, (5, 5), 4, (10, 14), (MIRROR, MIRROR, 'echoGate'), '두 짝을 구분하고 수정에 잔상을 남긴다', tolerance=1, seconds=150),
    _slot(4, 13, (5, 5), 4, (10, 13), (MIRROR, MIRROR, 'echoGate'), '문 앞 짝과 수정을 밟을 짝의 역할을 나눈다', seconds=180),
    _slot(4, 14, (5, 5), 4, (10, 13), (MIRROR, MIRROR, 'echoGate'), '수정에 잔상을 남길 때 두 짝의 자리를 맞춘다', seconds=180),
    _slot(4, 15, (5, 5), 4, (11, 14), (MIRROR, MIRROR, 'echoGate'), '빛 교대로 한 룬석을 옮기고 두 짝을 다시 정렬한다', power=SWAP, seconds=210),
    _slot(4, 17, (5, 5), 4, (11, 14), (MIRROR, MIRROR, 'echoGate'), '수호판: 두 짝을 써서 문을 지날 배치를 만든다', tolerance=1, seconds=210),
    # 5장 그림자 리크 — 리크와 룬석을 서로 움직인다
    _slot(5, 12, (5, 5), 2, (4, 8), (MIRROR, 'oneWay'), '리크를 밀어 그림자가 반대편으로 가는 것을 읽는다'),
    _slot(5, 14, (5, 5), 2, (5, 9), (MIRROR, 'echoGate'), '문이 열린 한 수에 그림자를 밀어 리크를 끌어온다'),
    _slot(5, 15, (5, 5), 2, (5, 9), (MIRROR, 'oneWay'), '물길에서 그림자와 리크 중 밀 쪽을 바꾼다'),
    _slot(5, 16, (5, 5), 2, (5, 9), (MIRROR, 'echoGate'), '리크를 끌기 전에 문을 열어 둘 잔상을 마련한다', seconds=150),
    _slot(5, 18, (5, 5), 2, (5, 9), (MIRROR, 'echoGate', 'oneWay'), '수호판: 물길과 문에 맞춰 리크와 그림자를 번갈아 민다', seconds=210),
)
