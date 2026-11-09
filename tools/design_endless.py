"""별바다 항해(끝없는 모드) 판 묶음 생성기.

항해는 깊이(몇 번째 판인지)에 따라 네 단계(tier)의 판을 꺼내 쓴다. 판은 권능 없이 맨손으로
풀어야 하고, 들어간 기믹은 모두 최단 풀이에 영향을 줘야 한다(기믹을 빼면 최단 수가 달라짐).
앱은 판을 돌리고 뒤집어(8가지) 다시 쓰므로, 같은 판의 회전·대칭은 한 번만 넣는다.

    python3 -m tools.design_endless                 # 목표 수가 찰 때까지 생성(이어서 생성)
    python3 -m tools.design_endless --tier 4 --count 20
    python3 -m tools.design_endless --check         # 묶음 전체를 다시 푼다

결과: assets/levels/endless_pool_v1.json. 생성 중에도 주기적으로 저장하므로 끊겨도 이어서 만든다.
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
from tools.validate_levels import decorative_mechanic, validate_level

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'assets/levels/endless_pool_v1.json'
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


def random_level(tier: int, rng: random.Random) -> dict:
    _, _, sizes, blocks, walls, mechanics, _ = TIERS[tier]
    w, h = rng.choice(sizes)
    if rng.random() < .5:
        w, h = h, w
    free = cells(w, h)
    rng.shuffle(free)
    take = free.pop
    level = {'id': 1, 'boardWidth': w, 'boardHeight': h,
             'startPosition': pt(take()), 'exitPosition': pt(take()),
             'blocks': [], 'obstacles': [], 'specialRules': []}
    for index in range(rng.randint(*blocks)):
        level['blocks'].append({'id': f'b{index + 1}', **pt(take())})
    for _ in range(rng.randint(*walls)):
        level['obstacles'].append(pt(take()))
    for kind in rng.sample(MECHANICS, rng.randint(*mechanics)):
        if kind == 'echoGate':
            level['specialRules'].append({'type': 'echoGate', 'switch': pt(take()), 'gate': pt(take())})
        elif kind == 'oneWay':
            level['specialRules'].append({'type': 'oneWay', 'tiles': [
                {**pt(take()), 'dx': d[0], 'dy': d[1]}
                for d in rng.sample([(1, 0), (-1, 0), (0, 1), (0, -1)], rng.randint(1, 2))]})
        else:
            level['specialRules'].append({'type': kind, 'positions': [pt(take()) for _ in range(rng.randint(1, 2))]})
    return level


def mutate(level: dict, tier: int, rng: random.Random) -> dict:
    walls = TIERS[tier][4]
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


def minimum(level: dict, budget: int) -> int | None:
    try:
        return len(validate_level(level, max_states=budget))
    except (ValueError, AssertionError, RuntimeError):
        return None


def accept(level: dict, tier: int) -> int | None:
    """단계 범위에 들고 모든 기믹이 풀이에 영향을 주면 최단 수를, 아니면 None 을 돌려준다."""
    low, high = TIERS[tier][:2]
    best = minimum(level, FULL_BUDGET)
    if best is None or not low <= best <= high:
        return None
    try:
        return best if decorative_mechanic(level, best, max_states=FULL_BUDGET) is None else None
    except (AssertionError, RuntimeError):
        return None


def design(tier: int, seed: int) -> dict | None:
    """최단 수를 단계 범위로 끌어올리는 언덕 오르기."""
    rng = random.Random(seed)
    low, high = TIERS[tier][:2]
    goal = rng.randint(low, high)
    started = time.time()
    while time.time() - started < JOB_SECONDS:
        current = random_level(tier, rng)
        score = None
        stale = 0
        while stale < 250 and time.time() - started < JOB_SECONDS:
            candidate = mutate(current, tier, rng)
            moves = minimum(candidate, QUICK_BUDGET)
            if moves is None:
                stale += 1
                continue
            candidate_score = abs(goal - moves)
            if score is None or candidate_score <= score:
                stale = 0 if score is None or candidate_score < score else stale + 1
                current, score = candidate, candidate_score
                if low <= moves <= high:
                    best = accept(current, tier)
                    if best is not None:
                        return finish(current, tier, best)
            else:
                stale += 1
    return None


def finish(level: dict, tier: int, best: int) -> dict:
    out = {'tier': tier, 'boardWidth': level['boardWidth'], 'boardHeight': level['boardHeight'],
           'startPosition': level['startPosition'], 'exitPosition': level['exitPosition'],
           'blocks': level['blocks'], 'obstacles': level['obstacles'], 'specialRules': level['specialRules'],
           'minimumMoves': best}
    return out


def _job(args: tuple[int, int]) -> tuple[int, dict | None]:
    tier, seed = args
    return tier, design(tier, seed)


def _check(level: dict) -> str | None:
    probe = {**level, 'id': level['id']}
    best = accept(probe, level['tier'])
    if best != level['minimumMoves']:
        return f"board {level['id']}: recorded {level['minimumMoves']}, solver {best}"
    return None


def check(workers: int) -> None:
    """묶음 전체를 다시 푼다: 단계 범위, 기록한 최단 수, 기믹의 쓸모, 중복."""
    pool = load()
    keys = [canonical(level) for level in pool]
    assert len(keys) == len(set(keys)), 'duplicate boards in the pool'
    with ProcessPoolExecutor(max_workers=workers) as executor:
        problems = [p for p in executor.map(_check, pool, chunksize=8) if p]
    for problem in problems:
        print(problem)
    counts = {t: sum(1 for level in pool if level['tier'] == t) for t in sorted(TIERS)}
    print(f'{len(pool)} boards checked {counts}: {len(problems)} problems')
    if problems:
        raise SystemExit(1)


def load() -> list[dict]:
    return json.loads(OUTPUT.read_text(encoding='utf-8')) if OUTPUT.exists() else []


def save(pool: list[dict]) -> None:
    """판 id 는 한 번 정하면 바꾸지 않는다. 저장된 항해가 판을 id 로 가리키기 때문이다.
    새 판은 지금까지의 가장 큰 id 다음 번호를 받는다."""
    next_id = max([level.get('id', 10000) for level in pool] + [10000]) + 1
    for level in pool:
        if 'id' not in level:
            level['id'] = next_id
            next_id += 1
    ordered = sorted(pool, key=lambda level: level['id'])
    lines = ',\n'.join(json.dumps({'id': level['id'], **{k: v for k, v in level.items() if k != 'id'}},
                                   ensure_ascii=False, separators=(',', ':'))
                       for level in ordered)
    OUTPUT.write_text('[\n' + lines + '\n]\n', encoding='utf-8')


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--tier', type=int, nargs='*', choices=sorted(TIERS))
    parser.add_argument('--count', type=int, help='단계마다 이만큼만 더 만든다')
    parser.add_argument('--seed', type=int, default=int(time.time()))
    parser.add_argument('--workers', type=int, default=8)
    parser.add_argument('--check', action='store_true', help='만든 묶음을 다시 검증만 한다')
    args = parser.parse_args()
    if args.check:
        return check(args.workers)
    pool = load()
    campaign = []
    for path in ['assets/levels/levels.json', 'assets/levels/world2.json']:
        campaign += json.loads((ROOT / path).read_text(encoding='utf-8'))
    seen = {canonical(level) for level in campaign} | {canonical(level) for level in pool}
    tiers = args.tier or sorted(TIERS)
    want = {t: (args.count if args.count is not None
                else max(0, TIERS[t][6] - sum(1 for level in pool if level['tier'] == t))) for t in tiers}
    print('need', want, flush=True)
    seed = args.seed
    last_save = time.time()
    with ProcessPoolExecutor(max_workers=args.workers) as executor:
        running = {}

        def submit() -> None:
            nonlocal seed
            def flying(t: int) -> int:
                return sum(1 for f in running.values() if f == t)

            open_tiers = [t for t in tiers if want[t] > flying(t)]
            if not open_tiers:
                return
            # 단계마다 목표 대비 채운 비율이 가장 낮은 단계부터 돌린다. 오래 걸리는 단계는
            # 일꾼이 오래 붙잡혀 있으므로 자연히 더 많은 일꾼이 몰린다.
            have = {t: sum(1 for level in pool if level['tier'] == t) for t in tiers}
            tier = min(open_tiers, key=lambda t: (have[t] + flying(t)) / TIERS[t][6])
            seed += 7919
            running[executor.submit(_job, (tier, seed))] = tier

        for _ in range(args.workers * 2):
            submit()
        while running:
            future = next(as_completed(list(running)))
            running.pop(future)
            tier, level = future.result()
            if level is not None and want[tier] > 0:
                key = canonical(level)
                if key not in seen:
                    seen.add(key)
                    pool.append(level)
                    want[tier] -= 1
                    print(f'tier {tier}: +1 ({level["minimumMoves"]} moves) left {want[tier]}', flush=True)
            if time.time() - last_save > 30:
                save(pool)
                last_save = time.time()
            if any(want[t] > 0 for t in tiers):
                submit()
    save(pool)
    counts = {t: sum(1 for level in pool if level['tier'] == t) for t in sorted(TIERS)}
    print(f'{len(pool)} endless boards written to {OUTPUT.relative_to(ROOT)}: {counts}')


if __name__ == '__main__':
    main()
