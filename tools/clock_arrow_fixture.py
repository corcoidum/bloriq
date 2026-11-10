"""세계 4-A의 solver 비교 표본과 독립 Python 측정치를 만든다."""
from __future__ import annotations

import argparse
import json
import random
from pathlib import Path

from tools.mechanics import ClockArrow, MirrorPair
from tools.power_fuzz_fixture import ROOT, measure_solver, random_mechanic_level
from tools.validate_levels import POWERS

SEED = 442026
COST_COUNT = 200
COUNT = 320
FIXTURE = ROOT / 'test/fixtures/clock_arrow_fuzz.json'


def generate_levels() -> list[dict]:
    rng = random.Random(SEED)
    kinds = ('echoEraser', 'echoHold', 'oneWay', 'goalOnly', 'echoGate', 'mirrorPair')
    # 비용 표본에서 다른 기믹을 33~34개씩, 권능을 맨손 100개와 각 25개로 섞는다.
    power_options = [()] * (COST_COUNT // 2) + [(p,) for p in POWERS] * (COST_COUNT // 8)
    rng.shuffle(power_options)
    levels = []
    for index in range(COUNT):
        if index < COST_COUNT:
            size = (5, 5)
            extra = [kinds[index % len(kinds)]]
            powers = power_options[index]
        else:
            size = rng.choice([(4, 4), (5, 4)])
            extra = [MirrorPair.type] if index % 2 == 0 else []
            powers = rng.choice([(), *((power,) for power in POWERS)])
        level = random_mechanic_level([ClockArrow.type, *extra], rng, size=size)
        level.update(id=1000 + index, world=4, minimumMoves=0, difficulty='fuzz',
                     availablePowers=list(powers))
        levels.append(level)
    return levels


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=FIXTURE)
    parser.add_argument('--benchmark-output', type=Path)
    args = parser.parse_args()
    cases, costs = [], []
    levels = generate_levels()
    for index, level in enumerate(levels):
        moves, cost = measure_solver(level)
        cases.append({'level': level, 'outcome': cost['outcome'], 'solution': moves})
        if index < COST_COUNT:
            costs.append(cost)
        if (index + 1) % 20 == 0:
            peak = max(row['visited'] for row in costs)
            print(f'{index + 1}/{COUNT}, cost sample peak {peak:,} states', flush=True)
    rows = ',\n'.join('  ' + json.dumps(case, separators=(',', ':')) for case in cases)
    args.output.write_text('[\n' + rows + '\n]\n', encoding='utf-8')

    if args.benchmark_output:
        world2 = json.loads((ROOT / 'assets/levels/world2.json').read_text(encoding='utf-8'))
        baseline = [measure_solver(level)[1] for level in world2]
        no_clock = [measure_solver(level, disabled_rule=ClockArrow.type)[1]
                    for level in levels[:COST_COUNT]]
        args.benchmark_output.parent.mkdir(parents=True, exist_ok=True)
        args.benchmark_output.write_text(
            json.dumps({'clock': costs, 'world2': baseline, 'noClock': no_clock}, indent=2),
            encoding='utf-8',
        )


if __name__ == '__main__':
    main()
