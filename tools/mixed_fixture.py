"""세계 7-A의 혼합 solver 비교판과 힌트 비용 표본을 생성한다."""
from __future__ import annotations

import argparse
import json
import random
from concurrent.futures import ProcessPoolExecutor
from itertools import combinations, product
from pathlib import Path

from tools.design_world import cells, pt
from tools.mechanics import REGISTRY, populate_random_rules
from tools.power_fuzz_fixture import ROOT, measure_solver, random_mechanic_level
from tools.validate_levels import POWERS
from tools.worlds.large_board_limits import APP_HINT_STATES

FIXTURE = ROOT / 'test/fixtures/mixed_fuzz.json'
BENCHMARK = ROOT / 'build/design_logs/w7-mixed-python.json'
FIXTURE_SEED = 772026
BENCHMARK_SEED = 772027


def _level(level: dict, number: int, powers: tuple[str, ...]) -> dict:
    return {**level, 'id': number, 'world': 7, 'minimumMoves': 0,
            'difficulty': 'fuzz', 'availablePowers': list(powers)}


def _agreement_case(job: tuple[int, tuple[str, ...], tuple[str, ...]]) -> dict:
    index, kinds, powers = job
    rng = random.Random(FIXTURE_SEED + 7919 * index)
    for _ in range(30):
        raw = random_mechanic_level(list(kinds), rng, size=rng.choice([(5, 4), (5, 5)]))
        level = _level(raw, 7000 + index, powers)
        solution, cost = measure_solver(level, max_states=APP_HINT_STATES)
        if cost['outcome'] != 'limited':
            return {'level': level, 'outcome': cost['outcome'], 'solution': solution}
    raise RuntimeError(f'Could not compare board {7000 + index}: {kinds}, {powers}')


def _agreement_jobs() -> list[tuple[int, tuple[str, ...], tuple[str, ...]]]:
    rng = random.Random(FIXTURE_SEED)
    powers = [(), *((power,) for power in POWERS)]
    pairs = list(product(combinations(REGISTRY, 2), powers))
    triples = list(combinations(REGISTRY, 3))
    mixes = pairs * 2 + [(kinds, rng.choice(powers))
                         for kinds in triples + rng.sample(triples, 140 - len(triples))]
    rng.shuffle(mixes)
    return [(index, kinds, available) for index, (kinds, available) in enumerate(mixes)]


def _corner_level(kinds: tuple[str, ...], rng: random.Random) -> dict:
    """빈 공간이 넓고 리크가 대각선 반대편 별문까지 가야 하는 6×6 표본."""
    start = rng.choice([(0, 0), (0, 5), (5, 0), (5, 5)])
    exit_point = (5 - start[0], 5 - start[1])
    free = [cell for cell in cells(6, 6) if cell not in (start, exit_point)]
    rng.shuffle(free)

    def take() -> dict:
        return pt(free.pop())

    level = {'boardWidth': 6, 'boardHeight': 6,
             'startPosition': pt(start), 'exitPosition': pt(exit_point),
             'blocks': [{'id': f'b{index}', **take()} for index in range(1, 4)],
             'obstacles': [take() for _ in range(rng.randint(3, 5))]}
    populate_random_rules(level, kinds, rng, take)
    return level


def _benchmark_levels() -> list[tuple[dict, str]]:
    rng = random.Random(BENCHMARK_SEED)
    levels = []
    for size in ((5, 5), (6, 5), (6, 6)):
        for kinds, power in product(combinations(REGISTRY, 2), POWERS):
            raw = random_mechanic_level(list(kinds), rng, size=size)
            levels.append((_level(raw, 8000 + len(levels), (power,)), 'random'))
            if size == (6, 6):
                raw = _corner_level(kinds, rng)
                levels.append((_level(raw, 8000 + len(levels), (power,)), 'corners'))
    return levels


def _measure_case(job: tuple[dict, str]) -> dict:
    level, sample = job
    solution, cost = measure_solver(level, max_states=APP_HINT_STATES)
    return {'level': level, 'sample': sample, 'solution': solution, 'python': cost}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--benchmark', action='store_true', help='크기별 비용 표본 생성')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--workers', type=int, default=4)
    args = parser.parse_args()
    if args.workers < 1:
        parser.error('--workers must be positive')
    if args.benchmark:
        jobs, run = _benchmark_levels(), _measure_case
    else:
        jobs, run = _agreement_jobs(), _agreement_case
    output = args.output or (BENCHMARK if args.benchmark else FIXTURE)
    rows = []
    with ProcessPoolExecutor(max_workers=args.workers) as pool:
        for case in pool.map(run, jobs):
            rows.append('  ' + json.dumps(case, separators=(',', ':')))
            if len(rows) % 50 == 0:
                print(f'{len(rows)}/{len(jobs)} mixed boards', flush=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text('[\n' + ',\n'.join(rows) + '\n]\n', encoding='utf-8')
    print(f'{len(rows)} mixed boards written to {output}', flush=True)


if __name__ == '__main__':
    main()
