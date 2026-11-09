"""월드 2 「구름바다 등대」 후보 생성기.

각 슬롯의 목표(최소 이동 수, 판 크기, 기믹, 강조 권능, 권능 필수 여부)에 맞춰
무작위 판에서 출발해 언덕 오르기로 다듬는다. 결과는 tools/validate_levels.py 의
check_world 와 tools/level_audit.py --world 2 로 다시 검증한다.
새 세계는 이 파일을 design_worldN.py 로 복사해 SLOTS·id·world 번호만 바꾼다(docs/SAGA.md).

    python3 -m tools.design_world2            # 전체 25개 생성 → assets/levels/world2.json
    python3 -m tools.design_world2 --only 7   # 7번째 슬롯만 다시 생성해 교체
"""
from __future__ import annotations

import argparse
import copy
import json
import random
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

from tools.level_audit import canonical, similarity
from tools.validate_levels import LEAP, POWERS, SEAL, SWAP, WIND, solve_or_none, validate_level

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'assets/levels/world2.json'
QUICK_BUDGET = 250_000
FULL_BUDGET = 2_000_000
STAGE_SECONDS = 600  # 한 슬롯이 전체 실행을 붙잡지 않도록 하는 상한
WINDOW_STEP_SECONDS = 100  # 이 시간마다 목표 하한을 한 수씩 낮춘다(최대 3수)

# (목표 최소 수, (가로, 세로), 일반 블록 수, 바위 수 범위, 기믹, 강조 권능, 필수 여부, 의도, 쓸 수 있는 권능)
# 스테이지마다 쓸 수 있는 권능을 한두 개로 제한한다. 네 권능을 모두 주면 지름길이 너무 많아
# 5x5 에서도 8수 남짓에 그치므로, 장마다 한 권능(마지막 장은 두 권능)만 열어 퍼즐을 깊게 만든다.
# 목표 최소 수는 그 권능을 쓸 때의 최단 수다. 장마다 첫 판은 새 권능을 익히도록 7~12수로 쉽게 열고,
# 다섯째 수호 정령 판(15~19수)에서 정점을 찍는 톱니 곡선이다(월드 1 마지막은 16수).
SLOTS = [
    # 1장 구름 계단 — 달꽃 도약
    (7, (4, 4), 2, (2, 4), [], LEAP, False, '바위를 뛰어넘으면 돌아가는 길이 짧아진다', (LEAP,)),
    (10, (4, 4), 2, (2, 4), ['echoHold'], LEAP, False, 'Hold 와 도약 중 무엇이 먼저인지', (LEAP,)),
    (11, (5, 4), 2, (3, 5), ['goalOnly'], LEAP, False, '전용 칸 너머로 착지하기', (LEAP,)),
    (12, (5, 4), 2, (3, 5), ['echoEraser'], LEAP, False, '도약한 자리도 잔상이 된다', (LEAP,)),
    (12, (5, 5), 2, (4, 7), [], LEAP, True, '수호 정령: 도약 없이는 닿지 않는 섬', (LEAP,)),
    # 2장 안개 항구 — 빛 교대
    (8, (4, 4), 2, (2, 4), [], SWAP, False, '잔상 자리로 블록을 불러오기', (SWAP,)),
    (11, (5, 4), 2, (2, 5), ['echoHold'], SWAP, False, 'Hold 로 남긴 잔상과 교대', (SWAP,)),
    (12, (5, 4), 2, (3, 5), ['goalOnly'], SWAP, True, '리크만 갈 수 있는 길에서 잔상과 바꾸기', (SWAP,)),
    (12, (5, 4), 2, (3, 5), ['echoEraser'], SWAP, False, '지우개로 잔상을 고르고 교대', (SWAP,)),
    (13, (5, 5), 2, (4, 7), ['echoGate'], SWAP, True, '수호 정령: 문 앞 잔상과 자리를 바꾼다', (SWAP,)),
    # 3장 등대지기의 계단 — 봉인
    (9, (4, 4), 2, (1, 4), ['echoGate'], SEAL, False, '봉인으로 문을 한 턴 더 열어 두기', (SEAL,)),
    (13, (5, 4), 2, (2, 5), ['echoGate'], SEAL, True, '두 번 지나가야 하는 문', (SEAL,)),
    (14, (5, 4), 2, (2, 5), ['echoGate', 'goalOnly'], SEAL, False, '봉인과 전용 칸의 순서', (SEAL,)),
    (13, (4, 4), 2, (1, 4), ['echoGate', 'echoEraser'], SEAL, False, '지우개를 피해 잔상 붙잡기', (SEAL,)),
    (15, (5, 4), 2, (2, 5), ['echoGate', 'echoHold'], SEAL, True, '수호 정령: Hold 와 봉인의 이중 잠금', (SEAL,)),
    # 4장 바람의 회랑 — 바람
    (10, (5, 4), 2, (2, 5), [], WIND, False, '바람으로 긴 복도를 한 번에', (WIND,)),
    (13, (5, 5), 2, (3, 6), ['oneWay'], WIND, False, '화살표 칸에서 멈추는 바람', (WIND,)),
    (14, (5, 5), 2, (4, 7), ['goalOnly'], WIND, False, '바람이 멈출 벽 만들기', (WIND,)),
    (15, (5, 5), 2, (3, 6), ['oneWay', 'echoEraser'], WIND, False, '바람과 지우개의 통로', (WIND,)),
    (16, (5, 5), 2, (4, 7), ['oneWay', 'echoGate'], WIND, True, '수호 정령: 바람만 닿는 문', (WIND,)),
    # 5장 등불의 꼭대기 — 두 권능 조합
    (12, (5, 4), 2, (2, 5), ['echoGate', 'echoHold'], SEAL, False, '봉인과 도약, 무엇을 먼저 쓸까', (LEAP, SEAL)),
    (15, (5, 5), 2, (3, 6), ['oneWay'], WIND, False, '교대한 뒤 바람에 실어 보내기', (SWAP, WIND)),
    (16, (5, 5), 2, (4, 7), ['echoEraser', 'goalOnly'], SWAP, True, '교대 없이는 닫힌 꼭대기', (LEAP, SWAP)),
    (16, (5, 4), 2, (2, 5), ['echoHold', 'oneWay'], WIND, False, '두 권능을 아껴 쓰기', (SEAL, WIND)),
    (18, (5, 5), 2, (4, 7), ['echoGate', 'goalOnly'], LEAP, True, '수호 정령: 등불을 켜는 마지막 길', (LEAP, SWAP)),
]
DIFFICULTY = ['world2-easy'] * 5 + ['world2-medium'] * 5 + ['world2-hard'] * 10 + ['world2-master'] * 5


def cells(w: int, h: int) -> list[tuple[int, int]]:
    return [(x, y) for y in range(h) for x in range(w)]


def pt(p: tuple[int, int]) -> dict:
    return {'x': p[0], 'y': p[1]}


def occupied(level: dict) -> set[tuple[int, int]]:
    used = {(level['startPosition']['x'], level['startPosition']['y']),
            (level['exitPosition']['x'], level['exitPosition']['y'])}
    used |= {(b['x'], b['y']) for b in level['blocks']}
    used |= {(o['x'], o['y']) for o in level['obstacles']}
    for rule in level['specialRules']:
        if rule['type'] == 'echoGate':
            used |= {(rule['switch']['x'], rule['switch']['y']), (rule['gate']['x'], rule['gate']['y'])}
        else:
            used |= {(p['x'], p['y']) for p in rule.get('positions', rule.get('tiles', []))}
    return used


def random_level(slot: int, rng: random.Random) -> dict:
    target, (w, h), block_count, walls, mechanics, featured, required, intent, _ = SLOTS[slot]
    free = cells(w, h)
    rng.shuffle(free)
    take = free.pop
    level = {'id': 101 + slot, 'world': 2, 'boardWidth': w, 'boardHeight': h,
             'startPosition': pt(take()), 'exitPosition': pt(take()),
             'blocks': [], 'obstacles': [], 'specialRules': []}
    for index in range(block_count):
        level['blocks'].append({'id': f'b{index + 1}', **pt(take())})
    for _ in range(rng.randint(*walls)):
        level['obstacles'].append(pt(take()))
    for kind in mechanics:
        if kind == 'echoGate':
            level['specialRules'].append({'type': 'echoGate', 'switch': pt(take()), 'gate': pt(take())})
        elif kind == 'oneWay':
            level['specialRules'].append({'type': 'oneWay', 'tiles': [
                {**pt(take()), 'dx': d[0], 'dy': d[1]} for d in rng.sample([(1, 0), (-1, 0), (0, 1), (0, -1)], rng.randint(1, 2))]})
        else:
            level['specialRules'].append({'type': kind, 'positions': [pt(take()) for _ in range(rng.randint(1, 2))]})
    return level


def mutate(level: dict, slot: int, rng: random.Random) -> dict:
    _, (w, h), _, walls, _, _, _, _, _ = SLOTS[slot]
    level = copy.deepcopy(level)
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


def slot_powers(slot: int) -> tuple[str, ...]:
    return SLOTS[slot][8]


def quick_minimum(level: dict, powers: tuple[str, ...] = POWERS) -> int | None:
    try:
        return len(validate_level(level, powers=powers, max_states=QUICK_BUDGET))
    except (ValueError, AssertionError, RuntimeError):
        return None


def full_check(level: dict, slot: int, low: int, allow_required: bool = False) -> dict | None:
    """슬롯 의도를 만족하면 기록할 프로필을, 아니면 None 을 돌려준다.

    low: 지금 받아들이는 최소 수 하한. allow_required: 맨손 슬롯이라도 오래 못 찾으면
    강조 권능이 꼭 필요한 판을 받아들인다.
    """
    target, _, _, _, mechanics, featured, required, _, powers = SLOTS[slot]
    try:
        best = validate_level(level, powers=powers, max_states=FULL_BUDGET)
        minimum = len(best)
        if not low <= minimum <= target + 2:
            return None
        bare = solve_or_none(level, max_states=FULL_BUDGET)
        without = {p: solve_or_none(level, powers=tuple(q for q in powers if q != p), max_states=FULL_BUDGET)
                   for p in powers}
        required_powers = [p for p in powers if without[p] is None]
        if required or (allow_required and bare is None):
            if bare is not None or featured not in required_powers:
                return None
        else:
            # 맨손으로도 풀리지만 권능이 길을 줄이고, 강조한 권능이 실제로 한 수 이상 아껴 준다.
            if bare is None or len(bare) <= minimum or len(bare) > 40:
                return None
            if len(without[featured]) <= minimum:
                return None
        for rule in level['specialRules']:
            kind = rule['type']
            alt = solve_or_none(level, powers=powers, gate_locked=kind == 'echoGate', disabled_rule=kind,
                                max_states=FULL_BUDGET)
            if alt is not None and len(alt) == minimum:
                return None
    except (ValueError, AssertionError, RuntimeError):
        return None
    return {'minimumMoves': minimum, 'bareHandedMoves': None if bare is None else len(bare),
            'requiredPowers': required_powers}


def design(slot: int, seed: int, deadline: float = STAGE_SECONDS) -> dict | None:
    """최단 수를 키우는 언덕 오르기. 시간이 지날수록 목표 하한을 낮춘다."""
    rng = random.Random(seed)
    target = SLOTS[slot][0]
    started = time.time()
    while time.time() - started < deadline:
        current = random_level(slot, rng)
        score = None
        stale = 0
        while stale < 400 and time.time() - started < deadline:
            elapsed = time.time() - started
            low = target - min(3, int(elapsed // WINDOW_STEP_SECONDS))
            candidate = mutate(current, slot, rng)
            minimum = quick_minimum(candidate, slot_powers(slot))
            if minimum is None:
                stale += 1
                continue
            # 목표보다 짧으면 길게, 목표 근처면 그대로(평평한 이동 허용) 둔다.
            candidate_score = max(0, target - minimum)
            if score is None or candidate_score <= score:
                stale = 0 if score is None or candidate_score < score else stale + 1
                current, score = candidate, candidate_score
                if minimum >= low:
                    profile = full_check(current, slot, low, allow_required=elapsed > deadline * .6)
                    if profile is not None:
                        return finish(current, slot, profile)
            else:
                stale += 1
    return None


def finish(level: dict, slot: int, profile: dict) -> dict:
    _, _, _, _, _, featured, _, intent, powers = SLOTS[slot]
    out = {'id': 101 + slot, 'world': 2, 'revision': 1,
           'boardWidth': level['boardWidth'], 'boardHeight': level['boardHeight'],
           'startPosition': level['startPosition'], 'exitPosition': level['exitPosition'],
           'blocks': level['blocks'], 'obstacles': level['obstacles'], 'specialRules': level['specialRules'],
           'minimumMoves': profile['minimumMoves'], 'bareHandedMoves': profile['bareHandedMoves'],
           'availablePowers': list(powers), 'requiredPowers': profile['requiredPowers'], 'featuredPower': featured,
           'difficulty': DIFFICULTY[slot], 'learningIntent': intent, 'reviewStatus': 'awaiting_manual_play'}
    return out


def _job(args: tuple[int, int]) -> tuple[int, dict | None]:
    slot, seed = args
    return slot, design(slot, seed)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--only', type=int, nargs='*', help='1부터 센 슬롯 번호')
    parser.add_argument('--seed', type=int, default=20261107)
    parser.add_argument('--workers', type=int, default=8)
    args = parser.parse_args()
    existing = json.loads(OUTPUT.read_text(encoding='utf-8')) if OUTPUT.exists() else []
    by_slot = {level['id'] - 101: level for level in existing}
    slots = [n - 1 for n in args.only] if args.only else list(range(len(SLOTS)))
    with ProcessPoolExecutor(max_workers=args.workers) as pool:
        for slot, level in pool.map(_job, [(s, args.seed + 7919 * s) for s in slots]):
            print(f'slot {slot + 1}: {"ok " + str(level["minimumMoves"]) if level else "FAILED"}', flush=True)
            if level:
                by_slot[slot] = level
    ordered = [by_slot[s] for s in sorted(by_slot)]
    world1 = json.loads((ROOT / 'assets/levels/levels.json').read_text(encoding='utf-8'))
    seen = {canonical(level) for level in world1}
    for index, level in enumerate(ordered):
        assert canonical(level) not in seen, f"duplicate {level['id']}"
        seen.add(canonical(level))
        for other in ordered[:index]:
            if similarity(level, other) >= .8:
                print(f"warning: {level['id']} similar to {other['id']}")
    OUTPUT.write_text(json.dumps(ordered, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'{len(ordered)} world 2 levels written to {OUTPUT.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
