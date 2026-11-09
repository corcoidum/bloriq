"""세계 설정에 맞춰 비어 있는 슬롯만 생성한다. --check는 공개 판을 읽어서 검증한다."""
from __future__ import annotations

import argparse
import copy
import json
import logging
import os
import random
import signal
from contextlib import contextmanager
from multiprocessing import TimeoutError as WorkerTimeout
from multiprocessing import get_context
from pathlib import Path
from tempfile import TemporaryDirectory
from time import monotonic
from typing import Iterator, NamedTuple

from tools.level_audit import canonical, similarity
from tools.mechanics import DIRECTIONS, REGISTRY, Position
from tools.validate_levels import (
    SearchBudgetExceeded,
    available_powers,
    check_world,
    decorative_mechanic,
    first_level_id,
    power_profile,
    record_solution,
    solve_or_none,
    write_levels,
)
from tools.worlds import Slot, load_slots

ROOT = Path(__file__).resolve().parents[1]
CHECKPOINT_SECONDS = 30


def cells(width: int, height: int) -> list[Position]:
    return [(x, y) for y in range(height) for x in range(width)]


def pt(position: Position) -> dict[str, int]:
    return {'x': position[0], 'y': position[1]}


def _rule_points(value: object) -> Iterator[dict]:
    if isinstance(value, dict):
        if 'x' in value and 'y' in value:
            yield value
        else:
            for field in value.values():
                yield from _rule_points(field)
    elif isinstance(value, list):
        for field in value:
            yield from _rule_points(field)


def _handles(level: dict) -> list[dict]:
    return [level['startPosition'], level['exitPosition'], *level['blocks'],
            *level['obstacles'], *_rule_points(level['specialRules'])]


def occupied(level: dict) -> set[Position]:
    return {(handle['x'], handle['y']) for handle in _handles(level)}


def random_level(world: int, index: int, slot: Slot, rng: random.Random) -> dict:
    width, height = slot.size
    free = cells(width, height)
    rng.shuffle(free)

    def take() -> dict:
        if not free:
            raise ValueError('Slot has no space for its mechanics')
        return pt(free.pop())

    level = {
        'id': first_level_id(world) + index,
        'world': world,
        'boardWidth': width,
        'boardHeight': height,
        'startPosition': take(),
        'exitPosition': take(),
        'blocks': [{'id': f'b{i + 1}', **take()} for i in range(slot.blocks)],
        'obstacles': [take() for _ in range(rng.randint(*slot.walls))],
    }
    level['specialRules'] = [REGISTRY[kind].randomRule(level, rng, take) for kind in slot.mechanics]
    level['availablePowers'] = list(slot.powers)
    return level


def mutate(level: dict, slot: Slot, rng: random.Random) -> dict:
    level = copy.deepcopy(level)
    handles = _handles(level)
    used = {(handle['x'], handle['y']) for handle in handles}
    empty = [cell for cell in cells(*slot.size) if cell not in used]
    if not empty:
        return level

    choice = rng.random()
    walls = level['obstacles']
    if choice < .12 and len(walls) < slot.walls[1]:
        walls.append(pt(rng.choice(empty)))
    elif choice < .22 and len(walls) > slot.walls[0]:
        walls.pop(rng.randrange(len(walls)))
    else:
        handle = rng.choice(handles)
        if rng.random() < .15 and 'dx' in handle:
            handle['dx'], handle['dy'] = rng.choice(DIRECTIONS)
        else:
            handle.update(pt(rng.choice(empty)))
    return level


def full_check(level: dict, slot: Slot, minimum: int, relaxed: bool, deadline: float) -> dict | None:
    profile = power_profile(level, max_states=slot.full_states, deadline=deadline)
    bare = profile['bareHandedMoves']
    if slot.featured is not None:
        if slot.required or bare is None:
            if bare is not None or not (slot.required or relaxed):
                return None
            if slot.featured not in profile['requiredPowers']:
                return None
        else:
            if not minimum < bare <= 40:
                return None
            without = solve_or_none(
                level, powers=tuple(power for power in slot.powers if power != slot.featured),
                max_states=slot.full_states, deadline=deadline,
            )
            if without is not None and len(without) <= minimum:
                return None
    if decorative_mechanic(
        level, minimum, powers=slot.powers, max_states=slot.full_states, deadline=deadline,
    ) is not None:
        return None
    return profile


class Job(NamedTuple):
    world: int
    index: int
    slot: Slot
    seed: int
    seen: frozenset[str]


class Result(NamedTuple):
    index: int
    level: dict | None
    over_budget: int


def design(job: Job) -> Result:
    """최단 수를 키우는 언덕 오르기. 슬롯 한도에 가까워지면 목표를 완화한다."""
    world, index, slot, seed, seen = job
    rng = random.Random(seed)
    started = monotonic()
    deadline = started + slot.max_seconds
    over_budget = 0
    try:
        while monotonic() < deadline:
            try:
                current = random_level(world, index, slot, rng)
            except ValueError:
                continue
            score = None
            stale = 0
            while stale < 400 and monotonic() < deadline:
                candidate = mutate(current, slot, rng)
                elapsed = monotonic() - started
                low = max(1, slot.target_moves - min(3, int(elapsed / (slot.max_seconds / 6))))
                try:
                    quick = solve_or_none(
                        candidate, powers=slot.powers, max_states=slot.quick_states,
                        deadline=deadline,
                    )
                    if quick is None:
                        stale += 1
                        continue
                    minimum = len(quick)
                    candidate_score = max(0, slot.target_moves - minimum)
                    if score is not None and candidate_score > score:
                        stale += 1
                        continue
                    profile = (
                        full_check(candidate, slot, minimum, elapsed > slot.max_seconds * .6, deadline)
                        if low <= minimum <= slot.target_moves + 2 else None
                    )
                except SearchBudgetExceeded:
                    # 예산 초과는 해가 없다는 증거가 아니다. 후보만 버린다.
                    over_budget += 1
                    stale += 1
                    continue
                except AssertionError:
                    stale += 1
                    continue
                stale = 0 if score is None or candidate_score < score else stale + 1
                current, score = candidate, candidate_score
                if profile is not None and canonical(candidate) not in seen:
                    solution = profile.pop('solution')
                    level = {
                        **candidate, **profile, 'revision': 1, 'featuredPower': slot.featured,
                        'difficulty': slot.difficulty, 'learningIntent': slot.intent,
                        'reviewStatus': 'awaiting_manual_play',
                    }
                    record_solution(level, solution, write=True)
                    return Result(index, level, over_budget)
    except TimeoutError:
        pass
    return Result(index, None, over_budget)


def load_existing(path: Path, world: int, count: int) -> dict[int, dict]:
    if not path.exists():
        return {}
    levels = {}
    for level in json.loads(path.read_text(encoding='utf-8')):
        index = level['id'] - first_level_id(world)
        if level['world'] != world or not 0 <= index < count or index in levels:
            raise ValueError(f"Invalid world {world} slot for level {level['id']}")
        levels[index] = level
    return levels


def previous_levels(root: Path, world: int) -> list[dict]:
    directory = root / 'assets/levels'
    paths = [directory / 'levels.json', *(directory / f'world{n}.json' for n in range(2, world))]
    return [level for path in paths if path.exists()
            for level in json.loads(path.read_text(encoding='utf-8'))]


def signatures(existing: dict[int, dict], previous: list[dict]) -> dict[str, int]:
    seen = {canonical(level): level['id'] for level in previous}
    for level in existing.values():
        signature = canonical(level)
        if signature in seen:
            raise ValueError(f"Duplicate levels: {seen[signature]} and {level['id']}")
        seen[signature] = level['id']
    return seen


def check_existing(existing: dict[int, dict], world: int, slots: tuple[Slot, ...]) -> None:
    if len(existing) != len(slots):
        raise ValueError(f'World {world}: {len(existing)}/{len(slots)} stages present')
    for index, slot in enumerate(slots):
        level = existing[index]
        if ((level['boardWidth'], level['boardHeight']) != slot.size
                or len(level['blocks']) != slot.blocks
                or not slot.walls[0] <= len(level['obstacles']) <= slot.walls[1]
                or set(available_powers(level)) != set(slot.powers)
                or {rule['type'] for rule in level['specialRules']} != set(slot.mechanics)
                or level.get('featuredPower') != slot.featured
                or 'solution' not in level):
            raise ValueError(f"Level {level['id']}: slot metadata or solution mismatch")
    # 공개판은 생성 당시의 하한 완화와 수동 검토 결과를 보존한다.
    check_world(list(existing.values()), world,
                budgets=tuple(slot.full_states for slot in slots))


def checkpoint(path: Path, levels: dict[int, dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # 기록 중 종료되어도 직전 체크포인트의 JSON은 읽을 수 있다.
    with TemporaryDirectory(prefix='.world-checkpoint-', dir=path.parent) as directory:
        temporary = Path(directory) / path.name
        write_levels(temporary, [levels[i] for i in sorted(levels)])
        temporary.replace(path)


@contextmanager
def generation_lock(path: Path) -> Iterator[None]:
    # 서로 다른 --only 실행이 같은 세계를 동시에 덮어쓰지 않게 한다.
    with path.open('a+b') as lock:
        try:
            if os.name == 'nt':
                import msvcrt
                lock.seek(0)
                msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            raise ValueError(f'Cannot acquire generator lock {path.name}') from error
        yield


def _worker_setup() -> None:
    signal.signal(signal.SIGINT, signal.SIG_IGN)


def generate(
    jobs: list[Job], levels: dict[int, dict], seen: dict[str, int], output: Path,
    workers: int, logger: logging.Logger,
) -> bool:
    if not jobs:
        logger.info('선택한 슬롯이 모두 저장되어 있습니다.')
        return True

    accepted = 0
    dirty = False
    remaining = len(jobs)
    checkpoint_at = monotonic() + CHECKPOINT_SECONDS
    try:
        with get_context('spawn').Pool(min(workers, len(jobs)), initializer=_worker_setup) as pool:
            results = pool.imap_unordered(design, jobs)
            while remaining:
                try:
                    index, level, over_budget = results.next(timeout=max(0, checkpoint_at - monotonic()))
                except WorkerTimeout:
                    pass
                else:
                    remaining -= 1
                    if level is None:
                        logger.info('슬롯 %d 시간 한도 도달, 예산 초과 후보 %d개 폐기', index + 1, over_budget)
                    else:
                        signature = canonical(level)
                        if signature in seen:
                            logger.info('슬롯 %d 중복 판 %d 제외, 예산 초과 후보 %d개 폐기',
                                        index + 1, seen[signature], over_budget)
                        else:
                            for other in levels.values():
                                if similarity(level, other) >= .8:
                                    logger.info('유사 판 %d, %d', level['id'], other['id'])
                            levels[index] = level
                            seen[signature] = level['id']
                            accepted += 1
                            dirty = True
                            logger.info('슬롯 %d 완료 (%d수), 예산 초과 후보 %d개 폐기',
                                        index + 1, level['minimumMoves'], over_budget)
                if monotonic() >= checkpoint_at:
                    if dirty:
                        checkpoint(output, levels)
                        dirty = False
                        logger.info('체크포인트 %d판 저장, %d슬롯 탐색 중', len(levels), remaining)
                    else:
                        logger.info('저장된 판 %d개, %d슬롯 탐색 중', len(levels), remaining)
                    checkpoint_at = monotonic() + CHECKPOINT_SECONDS
    finally:
        if dirty:
            checkpoint(output, levels)
            logger.info('체크포인트 %d판 저장', len(levels))
    return accepted == len(jobs)


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--world', type=int, required=True)
    parser.add_argument('--only', type=int, nargs='+', help='1부터 센 슬롯 번호')
    parser.add_argument('--workers', type=int, default=8)
    parser.add_argument('--seed', type=int, default=20261107)
    parser.add_argument('--check', action='store_true', help='기존 판만 검증')
    args = parser.parse_args(argv)
    if args.world < 2 or args.workers < 1:
        parser.error('--world는 2 이상, --workers는 1 이상이어야 합니다.')
    if args.check and args.only is not None:
        parser.error('--check는 세계 전체를 검증합니다.')
    try:
        slots = load_slots(args.world)
        for index, slot in enumerate(slots, 1):
            unknown = set(slot.mechanics) - REGISTRY.keys()
            if unknown:
                raise ValueError(f'Slot {index}: unknown mechanics {sorted(unknown)}')
        selected = sorted(set(args.only or range(1, len(slots) + 1)))
        if any(not 1 <= number <= len(slots) for number in selected):
            parser.error(f'슬롯 번호는 1..{len(slots)}입니다.')
        output = ROOT / f'assets/levels/world{args.world}.json'
        previous = previous_levels(ROOT, args.world)
        if args.check:
            levels = load_existing(output, args.world, len(slots))
            signatures(levels, previous)
            check_existing(levels, args.world, slots)
            return

        log_dir = ROOT / 'build/design_logs'
        log_dir.mkdir(parents=True, exist_ok=True)
        with generation_lock(log_dir / f'w{args.world}.lock'):
            logging.basicConfig(
                level=logging.INFO, format='%(asctime)s %(message)s',
                handlers=[logging.FileHandler(log_dir / f'w{args.world}.log', encoding='utf-8'),
                          logging.StreamHandler()],
            )
            logger = logging.getLogger(__name__)
            levels = load_existing(output, args.world, len(slots))
            seen = signatures(levels, previous)
            jobs = [Job(args.world, index, slots[index], args.seed + 7919 * index, frozenset(seen))
                    for index in (number - 1 for number in selected) if index not in levels]
            logger.info('세계 %d, %d슬롯 생성, 기존 %d판 유지', args.world, len(jobs), len(levels))
            if not generate(jobs, levels, seen, output, args.workers, logger):
                parser.exit(1, '완료된 판을 저장했습니다. 같은 명령으로 남은 슬롯을 이어서 생성할 수 있습니다.\n')
    except KeyboardInterrupt:
        parser.exit(130, '생성을 중단했습니다. 저장된 슬롯부터 이어서 진행할 수 있습니다.\n')
    except (AssertionError, KeyError, ValueError, SearchBudgetExceeded) as error:
        parser.exit(1, f'세계 {args.world} 검사 실패: {error}\n')


if __name__ == '__main__':
    main()
