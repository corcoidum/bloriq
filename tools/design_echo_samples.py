"""잔상이 풀이를 실제로 바꾸는 시험용 판 10개를 만든다.

캠페인 판을 바꾸기 전에 사람이 먼저 해 보는 묶음이다. 모든 판은 세계 1 규칙만 쓰고,
잔상을 끄면 최단 수가 2수 이상 달라지거나 아예 풀 수 없어야 한다.

    python -m tools.design_echo_samples            # 빈 자리를 채운다
    python -m tools.design_echo_samples --check    # 저장된 판만 검증한다
"""
from __future__ import annotations

import argparse
import json
from multiprocessing import get_context
from pathlib import Path

from tools.design_world import Job, design
from tools.level_audit import SIMILARITY_THRESHOLD, canonical, similarity
from tools.validate_levels import (
    ECHO_SAMPLE_FIRST_ID,
    ECHO_SAMPLE_GAIN,
    ECHO_SAMPLES_FILE,
    check_echo_samples,
    write_levels,
)
from tools.worlds import Slot


def _slot(moves: int, size: tuple[int, int], blocks: int, walls: tuple[int, int],
          mechanics: tuple[str, ...], intent: str, seconds: float = 240) -> Slot:
    return Slot(
        moves, size, blocks, walls, mechanics, None, False, intent, (), 'echo-sample',
        max_seconds=seconds, move_tolerance=1, min_echo_gain=ECHO_SAMPLE_GAIN,
    )


# (목표 최소 수, (가로, 세로), 일반 블록 수, 바위 수 범위, 기믹, 의도)
# 앞의 네 판과 마지막 판은 기믹 없이 잔상만으로 길이 달라진다.
# 넓은 판은 돌아갈 길이 많아 잔상의 영향이 약해진다. 바위를 늘려 통로를 좁히고 시간을 더 준다.
SLOTS = (
    _slot(6, (4, 4), 2, (2, 5), (), '잔상이 돌아갈 길을 막는다'),
    _slot(7, (4, 4), 3, (1, 4), (), '다른 블록의 잔상을 피해 순서 정하기'),
    _slot(8, (4, 4), 2, (2, 5), (), '잔상이 사라질 한 수를 벌기'),
    _slot(9, (5, 4), 2, (4, 8), (), '좁은 통로에서 잔상을 비켜 가기', 480),
    _slot(7, (4, 4), 2, (1, 4), ('echoGate',), '수정 위에 잔상을 남기고 바로 지나가기'),
    _slot(9, (5, 4), 2, (2, 5), ('echoGate',), '문을 여는 잔상과 길을 막는 잔상'),
    _slot(8, (4, 4), 2, (1, 4), ('echoHold',), '호박석으로 잔상을 붙잡아 두기'),
    _slot(8, (4, 4), 2, (1, 4), ('echoGate', 'echoEraser'), '민들레를 피해 문을 여는 잔상 남기기', 480),
    _slot(10, (5, 4), 2, (2, 6), ('echoGate', 'echoHold'), '붙잡은 잔상으로 문 열어 두기', 480),
    _slot(11, (5, 5), 2, (6, 11), (), '넓은 판에서 잔상 순서 읽기', 480),
)


def _load() -> dict[int, dict]:
    if not ECHO_SAMPLES_FILE.exists():
        return {}
    levels = json.loads(ECHO_SAMPLES_FILE.read_text(encoding='utf-8'))
    return {level['id'] - ECHO_SAMPLE_FIRST_ID: level for level in levels}


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='저장된 판만 검증')
    parser.add_argument('--only', type=int, nargs='+', help='1부터 센 슬롯 번호')
    parser.add_argument('--replace', action='store_true', help='선택한 슬롯을 새 판으로 교체')
    parser.add_argument('--workers', type=int, default=5)
    parser.add_argument('--seed', type=int, default=20261117)
    args = parser.parse_args(argv)

    levels = _load()
    if args.check:
        check_echo_samples([levels[index] for index in sorted(levels)], expected=len(SLOTS))
        return

    wanted = [number - 1 for number in args.only] if args.only else list(range(len(SLOTS)))
    if any(not 0 <= index < len(SLOTS) for index in wanted):
        parser.error(f'슬롯 번호는 1부터 {len(SLOTS)}까지입니다')
    if args.replace:
        for index in wanted:
            levels.pop(index, None)
    todo = [index for index in wanted if index not in levels]
    seen = frozenset(canonical(level) for level in levels.values())
    jobs = [
        Job(1, index, SLOTS[index], args.seed + index * 7919, seen, tuple(levels.values()))
        for index in todo
    ]
    if jobs:
        with get_context('spawn').Pool(min(args.workers, len(jobs))) as pool:
            for index, level, over_budget in pool.imap_unordered(design, jobs):
                if level is None:
                    print(f'슬롯 {index + 1}: 시간 안에 찾지 못함 (예산 초과 후보 {over_budget}개)', flush=True)
                    continue
                level['id'] = ECHO_SAMPLE_FIRST_ID + index
                clash = next((other for other in levels.values()
                              if similarity(level, other) >= SIMILARITY_THRESHOLD), None)
                if clash is not None:
                    print(f"슬롯 {index + 1}: 판 {clash['id']}와 비슷해 버림", flush=True)
                    continue
                levels[index] = level
                print(f"슬롯 {index + 1}: {level['minimumMoves']}수", flush=True)
                write_levels(ECHO_SAMPLES_FILE, [levels[key] for key in sorted(levels)])
    missing = [index + 1 for index in range(len(SLOTS)) if index not in levels]
    print(f'{len(levels)}/{len(SLOTS)}판 저장' + (f', 빈 슬롯 {missing}' if missing else ''))


if __name__ == '__main__':
    main()
