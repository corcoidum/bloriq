"""공개 캠페인에서 echo 시련 목록을 만들고 최단 수를 확인한다."""

from __future__ import annotations

import argparse
import json
import random

from tools.level_audit import orientations
from tools.validate_levels import LEVELS_FILE, available_powers, published_worlds, validate_level

SEED = 936241
OUTPUT = LEVELS_FILE.with_name('trials_v1.json')


def design_trials() -> dict:
    rng = random.Random(SEED)
    trials = []
    for world, path in [(1, LEVELS_FILE), *published_worlds()]:
        levels = json.loads(path.read_text(encoding='utf-8'))
        if len(levels) != 25:
            raise ValueError(f'World {world}: expected five chapters of five stages')
        chapters = [levels[start:start + 5] for start in range(0, 25, 5)]
        # 캠페인에서도 권능을 쓸 수 없는 판에는 이동 제한이나 되돌리기 금지를 붙인다.
        power_sources = [[level for level in chapter
                          if world > 1 and available_powers(level)
                          and level.get('bareHandedMoves') is not None]
                         for chapter in chapters]
        eligible = [index for index, sources in enumerate(power_sources) if sources]
        power_chapters = set(rng.sample(eligible, min(3, len(eligible))))
        for chapter, candidates in enumerate(chapters):
            if chapter in power_chapters:
                restricted = rng.choice(power_sources[chapter])
                other = rng.choice([level for level in candidates if level is not restricted])
                pairs = [('noPowers', restricted),
                         ('noUndo' if chapter % 2 == 0 else 'moveLimit', other)]
            else:
                first, second = rng.sample(candidates, 2)
                pairs = [('moveLimit', first), ('noUndo', second)]
            rng.shuffle(pairs)
            for condition, source in pairs:
                bare = condition == 'noPowers' or world == 1
                variants = orientations(source)
                symmetry = rng.choice([i for i, variant in enumerate(variants)
                                       if variant != variants[0]])
                minimum = (source['bareHandedMoves'] if bare and world > 1
                           else source['minimumMoves'])
                powers = () if bare else available_powers(source)
                solution = validate_level(source, powers=powers, max_states=2_000_000)
                if len(solution) != minimum:
                    raise ValueError(f"Trial {source['id']}: {minimum} moves expected, got {len(solution)}")
                trials.append({'sourceId': source['id'],
                               'sourceRevision': source.get('revision', 1),
                               'symmetry': symmetry,
                               'condition': condition,
                               'minimumMoves': minimum})
    return {'version': 1, 'seed': SEED, 'trials': trials}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='저장된 목록과 생성 결과를 비교한다')
    args = parser.parse_args()
    manifest = design_trials()
    text = json.dumps(manifest, ensure_ascii=False, indent=2) + '\n'
    if args.check:
        if OUTPUT.read_text(encoding='utf-8') != text:
            raise SystemExit('Trial catalog differs. Run python -m tools.design_trials to refresh it.')
    else:
        OUTPUT.write_text(text, encoding='utf-8')
    print(f"{len(manifest['trials'])} fixed trials verified (seed {SEED}).")


if __name__ == '__main__':
    main()
