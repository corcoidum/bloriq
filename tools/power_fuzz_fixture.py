"""Dart와 Python solver의 기믹·권능 일치를 확인할 무작위 판을 고정한다.

    python3 -m tools.power_fuzz_fixture   # → test/fixtures/power_fuzz.json
    python3 -m tools.power_fuzz_fixture --mechanics echoGate oneWay --count 100 --output /tmp/mixed.json
"""
from __future__ import annotations

import argparse
import json
import random
from pathlib import Path

from tools.design_world2 import cells, pt, random_level
from tools.mechanics import REGISTRY
from tools.validate_levels import POWERS, solve_or_none

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / 'test/fixtures/power_fuzz.json'
MAX_STATES = 400_000


def random_mechanic_level(kinds: list[str], rng: random.Random) -> dict:
    width, height = rng.choice([(4, 4), (5, 4), (5, 5)]) if len(kinds) < 5 else (5, 5)
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
    level['specialRules'] = [REGISTRY[kind].randomRule(level, rng, take) for kind in kinds]
    return level


def generate_cases(count: int, seed: int, mechanics: list[str] | None) -> list[dict]:
    rng = random.Random(seed)
    cases = []
    for _ in range(count * 100):
        # 인자가 없으면 기존 월드 2 생성기로 권능 교차 검증 표본을 만든다.
        level = (random_level(rng.randrange(15), rng) if mechanics is None
                 else random_mechanic_level(mechanics, rng))
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
    if args.mechanics is not None and len(args.mechanics) != len(set(args.mechanics)):
        parser.error('--mechanics cannot contain duplicates')
    cases = generate_cases(args.count, args.seed, args.mechanics)
    args.output.write_text(json.dumps(cases, ensure_ascii=False) + '\n', encoding='utf-8')
    print(f'{len(cases)} cases; powered<bare in {sum(1 for c in cases if c["bare"] is None or c["powered"] < c["bare"])}')


if __name__ == '__main__':
    main()
