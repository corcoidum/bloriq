"""Dart와 Python solver의 기믹·권능 일치를 확인할 무작위 판을 고정한다.

    python3 -m tools.power_fuzz_fixture   # → test/fixtures/power_fuzz.json
    python3 -m tools.power_fuzz_fixture --mechanics echoGate oneWay --count 100 --output /tmp/mixed.json
"""
from __future__ import annotations

import argparse
import json
import random
from collections import Counter
from pathlib import Path
from time import perf_counter

from tools.design_world import cells, pt, random_level
from tools.mechanics import REGISTRY, populate_random_rules
from tools.validate_levels import Move, POWERS, SearchBudgetExceeded, available_powers, solve_or_none
from tools.worlds.w2 import SLOTS as WORLD2_SLOTS

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / 'test/fixtures/power_fuzz.json'
MAX_STATES = 400_000


def random_mechanic_level(kinds: list[str], rng: random.Random,
                          *, size: tuple[int, int] | None = None) -> dict:
    if size is None:
        size = rng.choice([(4, 4), (5, 4), (5, 5)]) if len(kinds) < 5 else (5, 5)
    width, height = size
    unused = cells(width, height)
    rng.shuffle(unused)

    def take() -> dict:
        return pt(unused.pop())

    level = {
        'boardWidth': width,
        'boardHeight': height,
        'startPosition': take(),
        'exitPosition': take(),
        'blocks': [{'id': f'b{i + 1}', **take()} for i in range(rng.randint(2, 3))],
        'obstacles': [take() for _ in range(rng.randint(1, 3))],
    }
    populate_random_rules(level, kinds, rng, take)
    return level


def measure_solver(level: dict, *, disabled_rule: str | None = None,
                   max_states: int = 2_000_000) -> tuple[list[Move] | None, dict]:
    stats: dict[str, int] = {}
    start = perf_counter()
    try:
        moves = solve_or_none(level, powers=available_powers(level), stats=stats,
                              disabled_rule=disabled_rule, max_states=max_states)
        outcome = 'unsolved' if moves is None else 'solved'
    except SearchBudgetExceeded:
        moves, outcome = None, 'limited'
    ms = (perf_counter() - start) * 1000
    return moves, dict(id=level['id'], visited=stats['visited'], ms=ms, outcome=outcome)


def generate_cases(count: int, seed: int, mechanics: list[str] | None) -> list[dict]:
    rng = random.Random(seed)
    cases = []
    for _ in range(count * 100):
        try:
            # 인자가 없으면 기존 월드 2 설정으로 권능 표본을 만든다.
            if mechanics is None:
                index = rng.randrange(15)
                level = random_level(2, index, WORLD2_SLOTS[index], rng)
                level.pop('availablePowers')
            else:
                level = random_mechanic_level(mechanics, rng)
        except ValueError:
            continue  # 두 쌍을 놓을 블록이 모자란 판은 다시 뽑는다.
        level.update(id=900 + len(cases), minimumMoves=0, difficulty='fuzz')
        try:
            powered = solve_or_none(level, powers=POWERS, max_states=MAX_STATES)
            if powered is None:
                continue
            bare = solve_or_none(level, max_states=MAX_STATES)
            single = {}
            for power in POWERS:
                solution = solve_or_none(level, powers=(power,), max_states=MAX_STATES)
                single[power] = None if solution is None else len(solution)
        except RuntimeError:
            continue
        cases.append({'level': level, 'powered': len(powered), 'bare': None if bare is None else len(bare),
                      'single': single})
        if len(cases) == count:
            return cases
    raise RuntimeError(f'Generated {len(cases)}/{count} solvable cases for {mechanics}')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mechanics', nargs='*', choices=REGISTRY)
    parser.add_argument('--count', type=int, default=40)
    parser.add_argument('--seed', type=int, default=4242)
    parser.add_argument('--output', type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    if args.count < 1:
        parser.error('--count must be positive')
    for kind, count in Counter(args.mechanics or []).items():
        if count > REGISTRY[kind].max_instances:
            parser.error(f'--mechanics allows at most {REGISTRY[kind].max_instances} {kind} rules')
    cases = generate_cases(args.count, args.seed, args.mechanics)
    rows = ',\n'.join('  ' + json.dumps(case, ensure_ascii=False) for case in cases)
    args.output.write_text('[\n' + rows + '\n]\n', encoding='utf-8')
    print(f'{len(cases)} cases; powered<bare in {sum(1 for c in cases if c["bare"] is None or c["powered"] < c["bare"])}')


if __name__ == '__main__':
    main()
