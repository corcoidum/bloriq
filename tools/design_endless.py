"""별바다 항해(끝없는 모드) 판 묶음 생성기.

항해는 깊이(몇 번째 판인지)에 따라 네 단계(tier)의 판을 꺼내 쓴다. 판은 권능 없이 맨손으로
풀어야 하고, 들어간 기믹은 모두 최단 풀이에 영향을 줘야 한다(기믹을 빼면 최단 수가 달라짐).
앱은 판을 돌리고 뒤집어(8가지) 다시 쓰므로, 같은 판의 회전·대칭은 한 번만 넣는다.

    python3 -m tools.design_endless                 # 목표 수가 찰 때까지 생성(이어서 생성)
    python3 -m tools.design_endless --tier 4 --count 20
    python3 -m tools.design_endless --world 3 4 5 6  # 세계 기믹 묶음만 생성
    python3 -m tools.design_endless --check         # 묶음 전체를 다시 푼다

결과: assets/levels/endless_pool_v1.json 및 endless_pool_v2.json.
생성 중에도 주기적으로 저장하므로 끊겨도 이어서 만든다.
"""
from __future__ import annotations

import argparse
import copy
import json
import random
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

from tools.design_world import cells, occupied, pt
from tools.level_audit import canonical
from tools.mechanics import populate_random_rules
from tools.validate_levels import LEVELS_FILE, decorative_mechanic, published_worlds, validate_level

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'assets/levels/endless_pool_v1.json'
WORLD_OUTPUT = OUTPUT.with_name('endless_pool_v2.json')
QUICK_BUDGET = 120_000
FULL_BUDGET = 1_000_000
JOB_SECONDS = 45

MECHANICS = ['echoEraser', 'echoHold', 'oneWay', 'goalOnly', 'echoGate']

# 단계: (최단 수 하한, 상한, 판 크기 후보, 블록 수 범위, 바위 수 범위, 기믹 수 범위, 목표 개수)
TIERS = {
    1: (4, 6, [(4, 4)], (1, 2), (1, 3), (0, 0), 60),
    2: (6, 9, [(4, 4), (5, 4)], (2, 2), (2, 4), (1, 1), 120),
    3: (9, 12, [(5, 4), (5, 5)], (2, 2), (2, 6), (1, 2), 200),
    4: (12, 16, [(5, 5)], (2, 3), (3, 7), (2, 2), 150),
}
WORLD_MECHANICS = {3: 'mirrorPair', 4: 'clockArrow', 5: 'ice', 6: 'shelfDoor'}
WORLD_TIER = (6, 14, [(4, 4), (5, 4), (5, 5)], (2, 2), (2, 5), (1, 2), 120)
Stage = tuple[str, int]
STAGES = {**{('tier', t): spec for t, spec in TIERS.items()},
          **{('mechanicWorld', w): WORLD_TIER for w in WORLD_MECHANICS}}


def random_level(stage: Stage, rng: random.Random) -> dict:
    _, _, sizes, blocks, walls, mechanics, _ = STAGES[stage]
    w, h = rng.choice(sizes)
    if rng.random() < .5:
        w, h = h, w
    free = cells(w, h)
    rng.shuffle(free)
    def take() -> dict:
        return pt(free.pop())

    level = {'id': 1, 'boardWidth': w, 'boardHeight': h,
             'startPosition': take(), 'exitPosition': take(),
             'blocks': [], 'obstacles': [], 'specialRules': []}
    for index in range(rng.randint(*blocks)):
        level['blocks'].append({'id': f'b{index + 1}', **take()})
    for _ in range(rng.randint(*walls)):
        level['obstacles'].append(take())
    primary = [WORLD_MECHANICS[stage[1]]] if stage[0] == 'mechanicWorld' else []
    kinds = primary + rng.sample(MECHANICS, rng.randint(*mechanics) - len(primary))
    populate_random_rules(level, kinds, rng, take)
    return level


def mutate(level: dict, stage: Stage, rng: random.Random) -> dict:
    walls = STAGES[stage][4]
    level = copy.deepcopy(level)
    w, h = level['boardWidth'], level['boardHeight']
    empty = [c for c in cells(w, h) if c not in occupied(level)]
    if not empty:
        return level
    gate = next(((r['gate']['x'], r['gate']['y']) for r in level['specialRules'] if r['type'] == 'echoGate'), None)
    choice = rng.random()
    if choice < .12 and len(level['obstacles']) < walls[1]:
        level['obstacles'].append(pt(rng.choice(empty)))
    elif choice < .22 and len(level['obstacles']) > walls[0]:
        level['obstacles'].pop(rng.randrange(len(level['obstacles'])))
    else:
        handles = [level['startPosition'], level['exitPosition'], *level['blocks'], *level['obstacles']]
        for rule in level['specialRules']:
            if rule['type'] == 'echoGate':
                handles += [rule['switch'], rule['gate']]
            elif rule['type'] == 'shelfDoor':
                handles += [point for pair in rule['pairs'] for point in pair.values()]
            else:
                handles += rule.get('positions', rule.get('tiles', []))
        handle = rng.choice(handles)
        if rng.random() < .15 and 'dx' in handle:
            handle['dx'], handle['dy'] = rng.choice([(1, 0), (-1, 0), (0, 1), (0, -1)])
        else:
            dest = rng.choice(empty)
            if handle in level['blocks'] and dest == gate:
                return level
            handle['x'], handle['y'] = dest
    return level


def minimum(level: dict, budget: int, max_moves: int | None = None) -> int | None:
    try:
        return len(validate_level(level, max_states=budget, max_moves=max_moves))
    except (ValueError, AssertionError, RuntimeError):
        return None


def accept(level: dict, stage: Stage) -> int | None:
    """단계 범위에 들고 모든 기믹이 풀이에 영향을 주면 최단 수를, 아니면 None 을 돌려준다."""
    low, high = STAGES[stage][:2]
    best = minimum(level, FULL_BUDGET, high)
    if best is None or not low <= best <= high:
        return None
    try:
        return best if decorative_mechanic(level, best, max_states=FULL_BUDGET) is None else None
    except (AssertionError, RuntimeError):
        return None


def design(stage: Stage, seed: int) -> dict | None:
    """최단 수를 단계 범위로 끌어올리는 언덕 오르기."""
    rng = random.Random(seed)
    low, high = STAGES[stage][:2]
    goal = rng.randint(low, high)
    started = time.time()
    while time.time() - started < JOB_SECONDS:
        current = random_level(stage, rng)
        score = None
        stale = 0
        while stale < 250 and time.time() - started < JOB_SECONDS:
            candidate = mutate(current, stage, rng)
            moves = minimum(candidate, QUICK_BUDGET, high + 2)
            if moves is None:
                stale += 1
                continue
            candidate_score = abs(goal - moves)
            if score is None or candidate_score <= score:
                stale = 0 if score is None or candidate_score < score else stale + 1
                current, score = candidate, candidate_score
                if low <= moves <= high:
                    best = accept(current, stage)
                    if best is not None:
                        return finish(current, stage, best)
            else:
                stale += 1
    return None


def finish(level: dict, stage: Stage, best: int) -> dict:
    field, number = stage
    out = {field: number, 'boardWidth': level['boardWidth'], 'boardHeight': level['boardHeight'],
           'startPosition': level['startPosition'], 'exitPosition': level['exitPosition'],
           'blocks': level['blocks'], 'obstacles': level['obstacles'], 'specialRules': level['specialRules'],
           'minimumMoves': best}
    if field == 'mechanicWorld':
        out['availablePowers'] = []
    return out


def _job(args: tuple[Stage, int]) -> tuple[Stage, dict | None]:
    stage, seed = args
    return stage, design(stage, seed)


def _check(level: dict) -> str | None:
    stage = stage_of(level)
    if stage[0] == 'mechanicWorld':
        primary = WORLD_MECHANICS[stage[1]]
        kinds = {rule['type'] for rule in level['specialRules']}
        if primary not in kinds or kinds - {*MECHANICS, primary} or level.get('availablePowers') != []:
            return f"board {level['id']}: expected {primary}, only earlier basic mechanics and no powers"
    best = accept(level, stage)
    if best != level['minimumMoves']:
        return f"board {level['id']}: recorded {level['minimumMoves']}, solver {best}"
    return None


def check(workers: int) -> None:
    """묶음 전체를 다시 푼다: 단계 범위, 기록한 최단 수, 기믹의 쓸모, 중복."""
    pool = load()
    ids = {level['id'] for level in pool}
    assert len(ids) == len(pool), 'duplicate board IDs'
    keys = [canonical(level) for level in pool]
    assert len(keys) == len(set(keys)), 'duplicate boards in the pool'
    assert not set(keys) & campaign_keys(), 'duplicate of a campaign board'
    counts = counts_by_stage(pool)
    for stage, spec in STAGES.items():
        target = spec[6]
        count = counts[stage]
        if count < target or (stage[0] == 'mechanicWorld' and count != target):
            raise ValueError(f'{stage}: expected {target} boards, got {count}')
    with ProcessPoolExecutor(max_workers=workers) as executor:
        problems = [p for p in executor.map(_check, pool, chunksize=8) if p]
    for problem in problems:
        print(problem)
    print(f'{len(pool)} boards checked {counts}: {len(problems)} problems')
    if problems:
        raise SystemExit(1)


def load() -> list[dict]:
    pool = []
    for path, field in [(OUTPUT, 'tier'), (WORLD_OUTPUT, 'mechanicWorld')]:
        if path.exists():
            levels = json.loads(path.read_text(encoding='utf-8'))
            if any(stage_of(level)[0] != field for level in levels):
                raise ValueError(f'Wrong stage in {path}')
            pool.extend(levels)
    return pool


def stage_of(level: dict) -> Stage:
    for field in ('tier', 'mechanicWorld'):
        if (field, level.get(field)) in STAGES:
            return field, level[field]
    raise ValueError(f"board {level['id']}: unknown stage")


def counts_by_stage(pool: list[dict]) -> dict[Stage, int]:
    counts = dict.fromkeys(STAGES, 0)
    for level in pool:
        counts[stage_of(level)] += 1
    return counts


def campaign_keys() -> set[str]:
    return {canonical(level) for path in [LEVELS_FILE, *(path for _, path in published_worlds())]
            for level in json.loads(path.read_text(encoding='utf-8'))}


def save(pool: list[dict]) -> None:
    """판 id 는 한 번 정하면 바꾸지 않는다. 저장된 항해가 판을 id 로 가리키기 때문이다.
    새 판은 지금까지의 가장 큰 id 다음 번호를 받는다."""
    next_id = max([level.get('id', 10000) for level in pool] + [10000]) + 1
    for level in pool:
        if 'id' not in level:
            level['id'] = next_id
            next_id += 1
    ordered = sorted(pool, key=lambda level: level['id'])
    for path, field in [(OUTPUT, 'tier'), (WORLD_OUTPUT, 'mechanicWorld')]:
        lines = ',\n'.join(json.dumps({'id': level['id'], **{k: v for k, v in level.items() if k != 'id'}},
                                       ensure_ascii=False, separators=(',', ':'))
                           for level in ordered if stage_of(level)[0] == field)
        if not lines:
            continue
        content = '[\n' + lines + '\n]\n'
        if path.exists() and path.read_text(encoding='utf-8') == content:
            continue
        temporary = path.with_suffix('.tmp')
        temporary.write_text(content, encoding='utf-8')
        temporary.replace(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument('--tier', type=int, nargs='+', choices=sorted(TIERS))
    selection.add_argument('--world', type=int, nargs='+', choices=sorted(WORLD_MECHANICS))
    parser.add_argument('--count', type=int, help='단계마다 이만큼만 더 만든다')
    parser.add_argument('--seed', type=int, default=int(time.time()))
    parser.add_argument('--workers', type=int, default=8)
    parser.add_argument('--check', action='store_true', help='만든 묶음을 다시 검증만 한다')
    args = parser.parse_args()
    if args.check:
        return check(args.workers)
    pool = load()
    seen = campaign_keys() | {canonical(level) for level in pool}
    stages = ([('tier', t) for t in args.tier] if args.tier else
              [('mechanicWorld', w) for w in args.world] if args.world else list(STAGES))
    have = counts_by_stage(pool)
    want = {}
    for stage in stages:
        remaining = max(0, STAGES[stage][6] - have[stage])
        want[stage] = remaining if args.count is None else (
            min(remaining, args.count) if stage[0] == 'mechanicWorld' else args.count)
    print('need', want, flush=True)
    seed = args.seed
    last_save = time.time()
    with ProcessPoolExecutor(max_workers=args.workers) as executor:
        running = {}

        def submit() -> None:
            nonlocal seed
            def flying(stage: Stage) -> int:
                return sum(1 for active in running.values() if active == stage)

            open_stages = [stage for stage in stages if want[stage] > flying(stage)]
            if not open_stages:
                return
            # 단계마다 목표 대비 채운 비율이 가장 낮은 단계부터 돌린다. 오래 걸리는 단계는
            # 일꾼이 오래 붙잡혀 있으므로 자연히 더 많은 일꾼이 몰린다.
            stage = min(open_stages, key=lambda candidate: (have[candidate] + flying(candidate)) / STAGES[candidate][6])
            seed += 7919
            running[executor.submit(_job, (stage, seed))] = stage

        for _ in range(args.workers * 2):
            submit()
        while running:
            future = next(as_completed(list(running)))
            running.pop(future)
            stage, level = future.result()
            if level is not None and want[stage] > 0:
                key = canonical(level)
                if key not in seen:
                    seen.add(key)
                    pool.append(level)
                    want[stage] -= 1
                    have[stage] += 1
                    print(f'{stage}: +1 ({level["minimumMoves"]} moves) left {want[stage]}', flush=True)
            if time.time() - last_save > 30:
                save(pool)
                last_save = time.time()
            if any(want.values()):
                submit()
    save(pool)
    print(f'{len(pool)} endless boards saved: {counts_by_stage(pool)}')


if __name__ == '__main__':
    main()
