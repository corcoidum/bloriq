"""레벨 품질 검토. 난이도 경고는 플레이 시간이나 재미의 실측값이 아니다."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from tools.validate_levels import validate_level

ROOT = Path(__file__).resolve().parents[1]


def orientations(level: dict) -> list[frozenset[str]]:
    result = []
    for mirror in (False, True):
        for rotation in range(4):
            width, height = level['boardWidth'], level['boardHeight']

            def transform(x: int, y: int) -> tuple[int, int]:
                if mirror:
                    x = width - 1 - x
                w, h = width, height
                for _ in range(rotation):
                    x, y, w, h = h - 1 - y, x, h, w
                return x, y

            def token(kind: str, point: dict) -> str:
                return f'{kind}:{transform(point["x"], point["y"])}'

            tokens = {f'size:{(height, width) if rotation % 2 else (width, height)}',
                      token('start', level['startPosition']), token('exit', level['exitPosition'])}
            tokens.update(token('block', block) for block in level['blocks'])
            tokens.update(token('wall', wall) for wall in level['obstacles'])
            for rule in level['specialRules']:
                kind = rule['type']
                if kind == 'echoGate':
                    tokens.update((token('switch', rule['switch']), token('gate', rule['gate'])))
                elif kind == 'oneWay':
                    for tile in rule['tiles']:
                        dx, dy = tile['dx'], tile['dy']
                        if mirror:
                            dx = -dx
                        for _ in range(rotation):
                            dx, dy = -dy, dx
                        tokens.add(token(f'arrow{dx},{dy}', tile))
                else:
                    tokens.update(token(kind, point) for point in rule['positions'])
            result.append(frozenset(tokens))
    return result


def canonical(level: dict) -> str:
    return min('|'.join(sorted(tokens)) for tokens in orientations(level))


def similarity(a: dict, b: dict) -> float:
    left = orientations(a)[0]
    return max(len(left & right) / len(left | right) for right in orientations(b))


def inspect(levels: list[dict]) -> list[dict]:
    seen: dict[str, int] = {}
    reports = []
    known_rules: set[str] = set()
    previous = 0
    previous_states = 0
    for index, level in enumerate(levels):
        stats: dict[str, int] = {}
        solution = validate_level(level, stats=stats)
        if len(solution) != level['minimumMoves']:
            raise ValueError(f"Level {level['id']}: minimumMoves mismatch")
        identity = canonical(level)
        if identity in seen:
            raise ValueError(f"Duplicate levels: {seen[identity]} and {level['id']}")
        seen[identity] = level['id']
        warnings = []
        rules = {rule['type'] for rule in level['specialRules']}
        if len(rules - known_rules) > 1:
            warnings.append('multiple_new_mechanics')
        if previous and len(solution) - previous > max(3, previous * .4):
            warnings.append('minimum_move_jump')
        if previous_states and stats['visited'] > max(previous_states * 4, previous_states + 1000):
            warnings.append('search_space_jump')
        for other in levels[:index]:
            if similarity(level, other) >= .8:
                warnings.append(f"similar_to_{other['id']}")
        for rule in level['specialRules']:
            try:
                alternative = validate_level(level, gate_locked=rule['type'] == 'echoGate', disabled_rule=rule['type'])
            except ValueError:
                continue
            if len(alternative) == len(solution):
                raise ValueError(f"Level {level['id']}: {rule['type']} has no effect")
        reports.append({'id': level['id'], 'revision': level.get('revision', 1), 'minimum': len(solution),
                        'visited': stats['visited'], 'fingerprint': hashlib.sha256(identity.encode()).hexdigest(),
                        'warnings': warnings, 'solution': solution,
                        'manual': level.get('reviewStatus', 'existing_content')})
        known_rules.update(rules)
        previous = len(solution)
        previous_states = stats['visited']
    return reports


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--include-drafts', action='store_true')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    levels = json.loads((ROOT / 'assets/levels/levels.json').read_text(encoding='utf-8'))
    if args.include_drafts:
        levels += json.loads((ROOT / 'assets/levels/draft_levels_26_40.json').read_text(encoding='utf-8'))
    reports = inspect(levels)
    lines = ['# 레벨 자동 검토', '', '경고는 휴리스틱이며 수동 플레이 검토를 대체하지 않습니다.', '',
             '| ID | revision | 최소 이동 | 탐색 상태 | 경고 | 수동 상태 |', '|---|---|---|---|---|---|']
    for report in reports:
        lines.append(f"| {report['id']} | {report['revision']} | {report['minimum']} | {report['visited']} | {', '.join(report['warnings']) or '-'} | {report['manual']} |")
    for level, report in zip(levels, reports):
        lines += ['', f"## {report['id']}", '', level.get('learningIntent', '기존 콘텐츠 또는 초반 Echo 학습'),
                  '', f"- Fingerprint: `{report['fingerprint']}`", f"- 해법: `{report['solution']}`",
                  '- 복구 검토: Undo는 직전 블록·Echo·이동 수, Restart는 초기 상태 복원.',
                  '- [ ] 실제 기기에서 도움 없이 플레이하고 체감 난이도·조작·소요 시간 기록']
    text = '\n'.join(lines) + '\n'
    if args.output:
        args.output.write_text(text, encoding='utf-8')
    else:
        print(text)


if __name__ == '__main__':
    main()
