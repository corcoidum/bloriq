"""세계 7-A 실측을 바탕으로 한 6×6 생성 제한."""
from itertools import combinations

SIX_BY_SIX = (6, 6)
APP_HINT_STATES = 200_000  # lib/game/hint_search.dart
SIX_BY_SIX_QUICK_STATES = 120_000
SIX_BY_SIX_CANDIDATE_SECONDS = 8.0

# 시드 772027의 6×6 isolate 초기·중간 판 실측 결과(docs/MECHANIC_COST.md).
BLOCKED_6X6: dict[tuple[str, str], frozenset[str]] = {
    ('clockArrow', 'echoEraser'): frozenset({'seal'}),
    ('clockArrow', 'echoGate'): frozenset({'light_swap', 'seal'}),
    ('clockArrow', 'echoHold'): frozenset({'wind'}),
    ('clockArrow', 'goalOnly'): frozenset({'moonflower_leap', 'seal'}),
    ('clockArrow', 'ice'): frozenset({'light_swap', 'moonflower_leap', 'seal'}),
    ('clockArrow', 'mirrorPair'): frozenset({'moonflower_leap', 'seal', 'wind'}),
    ('clockArrow', 'oneWay'): frozenset({'seal'}),
    ('clockArrow', 'shelfDoor'): frozenset({'seal'}),
    ('echoEraser', 'echoGate'): frozenset({'seal'}),
    ('echoEraser', 'echoHold'): frozenset({'moonflower_leap', 'seal'}),
    ('echoEraser', 'goalOnly'): frozenset({'light_swap', 'moonflower_leap', 'seal'}),
    ('echoEraser', 'ice'): frozenset({'light_swap', 'seal', 'wind'}),
    ('echoEraser', 'mirrorPair'): frozenset({'light_swap', 'seal'}),
    ('echoEraser', 'oneWay'): frozenset({'moonflower_leap', 'seal'}),
    ('echoEraser', 'shelfDoor'): frozenset({'seal'}),
    ('echoGate', 'echoHold'): frozenset({'moonflower_leap', 'seal'}),
    ('echoGate', 'goalOnly'): frozenset({'seal'}),
    ('echoGate', 'mirrorPair'): frozenset({'light_swap', 'moonflower_leap', 'seal'}),
    ('echoGate', 'oneWay'): frozenset({'light_swap', 'moonflower_leap', 'seal'}),
    ('echoHold', 'goalOnly'): frozenset({'moonflower_leap', 'seal'}),
    ('echoHold', 'mirrorPair'): frozenset({'moonflower_leap', 'seal'}),
    ('echoHold', 'oneWay'): frozenset({'moonflower_leap', 'seal'}),
    ('goalOnly', 'ice'): frozenset({'seal'}),
    ('ice', 'mirrorPair'): frozenset({'light_swap', 'seal'}),
    ('ice', 'oneWay'): frozenset({'light_swap', 'seal'}),
    ('mirrorPair', 'oneWay'): frozenset({'light_swap', 'moonflower_leap', 'seal'}),
    ('mirrorPair', 'shelfDoor'): frozenset({'moonflower_leap', 'seal'}),
}


def blocked_mix(kinds: tuple[str, ...], powers: tuple[str, ...]) -> bool:
    """기믹을 셋 섞어도 금지된 쌍과 권능을 함께 넣지 않는다."""
    return any(
        not BLOCKED_6X6[pair].isdisjoint(powers)
        for pair in combinations(sorted(set(kinds)), 2)
        if pair in BLOCKED_6X6
    )
