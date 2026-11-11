"""별바다 항해 등불 수치 모의 플레이.

판마다 낭비하는 수(최단 수보다 더 민 수)를 기하 분포로 뽑아, 등불 규칙에 따라 몇 판까지
가는지 센다. lib/endless/endless_rules.dart 의 수치를 바꾸기 전에 돌려 본다(docs/ENDLESS.md).

    python3 -m tools.endless_sim
"""
from __future__ import annotations

import random
import statistics

START, MAX, CLEAR, PERFECT = 10, 15, 1, 2

# 단계(1~4)별 판당 평균 낭비 수. 쉬운 바다에서는 대부분 완벽하게 깨고, 깊어질수록 헤맨다.
PLAYERS = {
    'casual': (1.0, 2.5, 4.5, 7.0),
    'average': (.5, 1.5, 2.8, 4.5),
    'skilled': (.15, .5, 1.1, 2.0),
}


def tier(depth: int) -> int:
    if depth <= 3:
        return 1
    if depth <= 10:
        return 2
    if depth <= 22:
        return 3
    return 4


def waste(mean: float, rng: random.Random) -> int:
    p, k = 1 / (1 + mean), 0
    while rng.random() > p:
        k += 1
    return k


def voyage(player: str, rng: random.Random, start=START, cap=MAX, clear=CLEAR, perfect=PERFECT) -> int:
    lantern, depth = start, 0
    while depth < 2000:
        depth += 1
        w = waste(PLAYERS[player][tier(depth) - 1], rng)
        if w >= lantern:
            return depth - 1
        lantern = min(cap, lantern - w + clear + (perfect if w == 0 else 0))
    return depth


def main() -> None:
    rng = random.Random(1)
    for player in PLAYERS:
        runs = sorted(voyage(player, rng) for _ in range(4000))
        print(f'{player:8} median {statistics.median(runs):4.0f} boards · '
              f'p90 {runs[int(.9 * len(runs))]:4d} · p10 {runs[int(.1 * len(runs))]:4d}')


if __name__ == '__main__':
    main()
