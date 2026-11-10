"""세계 6-A의 solver 비교판과 비용 표본을 고정한다."""
from __future__ import annotations

import argparse
import json
import random
from pathlib import Path

from tools.mechanics import ClockArrow, Ice, MirrorPair, ShelfDoor
from tools.power_fuzz_fixture import ROOT, measure_solver, random_mechanic_level
from tools.validate_levels import POWERS


SEED = 662026
COST_COUNT = 200
COUNT = 320
FIXTURE = ROOT / 'test/fixtures/shelf_door_fuzz.json'
MIXES = (
    (), (Ice.type,), (MirrorPair.type,), (Ice.type, MirrorPair.type),
    (ClockArrow.type,), (Ice.type, ClockArrow.type),
    (Ice.type, MirrorPair.type, ClockArrow.type), ('echoGate',),
)


def generate_levels() -> list[dict]:
    rng = random.Random(SEED)
    powers = [()] * 100 + [(power,) for power in POWERS] * 25
    rng.shuffle(powers)
    levels = []
    for index in range(COUNT):
        if index < COST_COUNT:
            size = (5, 5) if index < 160 else (6, 5)
            available = powers[index]
        else:
            size = rng.choice([(5, 4), (5, 5)])
            available = rng.choice([(), *((power,) for power in POWERS)])
        level = random_mechanic_level([ShelfDoor.type, *MIXES[index % len(MIXES)]], rng, size=size)
        level.update(id=3000 + index, world=6, minimumMoves=0,
                     difficulty='fuzz', availablePowers=list(available))
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
        solution, cost = measure_solver(level)
        cases.append({'level': level, 'outcome': cost['outcome'], 'solution': solution})
        if index < COST_COUNT:
            costs.append(cost)
        if (index + 1) % 20 == 0:
            peak = max(row['visited'] for row in costs)
            print(f'{index + 1}/{COUNT}, cost sample peak {peak:,} states', flush=True)
    rows = ',\n'.join('  ' + json.dumps(case, separators=(',', ':')) for case in cases)
    args.output.write_text('[\n' + rows + '\n]\n', encoding='utf-8')
    if args.benchmark_output:
        baseline = [measure_solver(level, disabled_rule=ShelfDoor.type)[1]
                    for level in levels[:COST_COUNT]]
        args.benchmark_output.parent.mkdir(parents=True, exist_ok=True)
        args.benchmark_output.write_text(
            json.dumps({'shelfDoor': costs, 'noShelfDoor': baseline}, indent=2),
            encoding='utf-8',
        )


if __name__ == '__main__':
    main()
