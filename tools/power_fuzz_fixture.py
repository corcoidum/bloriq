"""Dart PuzzleSolver 와 Python validate_level 의 권능 규칙 일치를 확인할 무작위 판을 고정한다.

    python3 -m tools.power_fuzz_fixture   # → test/fixtures/power_fuzz.json
"""
from __future__ import annotations

import json
import random
from pathlib import Path

from tools.design_world2 import SLOTS, random_level
from tools.validate_levels import POWERS, solve_or_none

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    rng = random.Random(4242)
    cases = []
    while len(cases) < 40:
        slot = rng.randrange(15)  # 4x4·5x4 위주의 작은 판
        level = random_level(slot, rng)
        level.update(id=900 + len(cases), minimumMoves=0, difficulty='fuzz')
        powered = solve_or_none(level, powers=POWERS, max_states=400_000)
        if powered is None:
            continue
        bare = solve_or_none(level, max_states=400_000)
        single = {p: (lambda s: None if s is None else len(s))(solve_or_none(level, powers=(p,), max_states=400_000))
                  for p in POWERS}
        cases.append({'level': level, 'powered': len(powered), 'bare': None if bare is None else len(bare),
                      'single': single})
    (ROOT / 'test/fixtures/power_fuzz.json').write_text(json.dumps(cases, ensure_ascii=False) + '\n', encoding='utf-8')
    print(f'{len(cases)} cases; powered<bare in {sum(1 for c in cases if c["bare"] is None or c["powered"] < c["bare"])}')


if __name__ == '__main__':
    main()
