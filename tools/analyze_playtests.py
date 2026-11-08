"""사용자가 내보낸 로컬 기록만 분석한다. 미회수 로그를 미복귀로 간주하지 않는다."""
from __future__ import annotations

import argparse
from collections import defaultdict
from datetime import date, timedelta
import json
from pathlib import Path
from statistics import median


def analyze(exports: list[dict], *, as_of: date | None = None) -> dict:
    participants: dict[str, dict] = {}
    warnings = []
    duplicate_count = 0
    for export in exports:
        identity = export.get('participantId')
        if export.get('version') != 1 or not isinstance(identity, str) or not identity:
            warnings.append('Skipped export without a supported schema/participant ID')
            continue
        try:
            first = date.fromisoformat(export['firstObservedDate'])
            exported = date.fromisoformat(export['exportedLocalDate'])
        except (ValueError, KeyError, TypeError):
            warnings.append('Skipped export with an invalid date')
            continue
        participant = participants.setdefault(identity, {'first': first, 'exports': [], 'events': {}, 'conflict': False})
        if participant['first'] != first:
            participant['conflict'] = True
        participant['exports'].append((exported, export.get('droppedEvents', 0), export.get('collectionInterrupted') is False))
        for event in export.get('events', []):
            if not isinstance(event, dict) or not isinstance(event.get('id'), str):
                continue
            if event['id'] in participant['events']:
                duplicate_count += 1
                if participant['events'][event['id']] != event:
                    participant['conflict'] = True
            else:
                participant['events'][event['id']] = event
    if as_of is None:
        as_of = max((day for p in participants.values() for day, _, _ in p['exports']), default=date.today())
    cohorts: dict[str, dict] = {}
    for first in sorted({p['first'] for p in participants.values()}):
        members = [p for p in participants.values() if p['first'] == first]
        cohort = {'participants': len(members)}
        for offset in (1, 7):
            target = first + timedelta(days=offset)
            eligible = len(members) if as_of > target else 0
            returned = known_absent = 0
            if eligible:
                for participant in members:
                    if participant['conflict']:
                        continue
                    if any(e.get('name') == 'session_start' and e.get('localDate') == target.isoformat() for e in participant['events'].values()):
                        returned += 1
                    elif any(day > target and dropped == 0 and continuous for day, dropped, continuous in participant['exports']):
                        known_absent += 1
            unknown = eligible - returned - known_absent
            known = returned + known_absent
            cohort[f'D{offset}'] = {'eligible': eligible, 'returned': returned, 'known_absent': known_absent,
                                      'unknown': unknown, 'known_followup_rate': known / eligible if eligible else None,
                                      'observed_subset_retention': returned / known if known else None,
                                      'full_cohort_bounds': [returned / eligible, (returned + unknown) / eligible] if eligible else None}
        cohorts[first.isoformat()] = cohort
    levels: dict[tuple, dict] = defaultdict(lambda: {'attempts': 0, 'completed': 0, 'undo': 0, 'restart': 0, 'completion_active_ms': [], 'final_moves': [], 'valid_inputs': 0, 'started_runs': set(), 'ended_runs': set()})
    tutorial_started = set()
    tutorial_completed = set()
    sessions = []
    for identity, participant in participants.items():
        for event in participant['events'].values():
            name = event.get('name')
            if name == 'tutorial_start' and not event.get('replay'):
                tutorial_started.add(identity)
            if name == 'tutorial_complete' and not event.get('replay'):
                tutorial_completed.add(identity)
            if name == 'session_end' and isinstance(event.get('activeMs'), (int, float)):
                sessions.append(event['activeMs'])
            if not isinstance(event.get('levelId'), int):
                continue
            item = levels[(event.get('mode', 'unknown'), event['levelId'], event.get('revision', 1))]
            run = (identity, event.get('runId'))
            if name == 'level_start':
                item['attempts'] += 1
                item['started_runs'].add(run)
            if name == 'undo_used':
                item['undo'] += 1
            if name == 'restart_used':
                item['restart'] += 1
            if name in ('level_complete', 'daily_complete', 'level_end'):
                item['ended_runs'].add(run)
                item['valid_inputs'] += event.get('validMoves', 0)
            if name in ('level_complete', 'daily_complete'):
                item['completed'] += 1
                item['completion_active_ms'].append(event.get('activeMs', 0))
                item['final_moves'].append(event.get('moves', 0))
    level_rows = []
    for (mode, level_id, revision), item in sorted(levels.items()):
        row = {'mode': mode, 'levelId': level_id, 'revision': revision,
               'attempts': item['attempts'], 'completed': item['completed'], 'undo': item['undo'], 'restart': item['restart'],
               'valid_inputs': item['valid_inputs'], 'unconfirmed_attempts': len(item['started_runs'] - item['ended_runs']),
               'median_completion_active_ms': median(item['completion_active_ms']) if item['completion_active_ms'] else None,
               'median_final_moves': median(item['final_moves']) if item['final_moves'] else None}
        level_rows.append(row)
    return {'as_of': as_of.isoformat(), 'participants': len(participants), 'duplicate_events_removed': duplicate_count,
            'cohorts': cohorts, 'levels': level_rows, 'tutorial_observed': {'started': len(tutorial_started), 'completed': len(tutorial_completed & tutorial_started)},
            'observed_completed_session_mean_ms': sum(sessions) / len(sessions) if sessions else None,
            'warnings': warnings,
            'limitations': ['Consented first-observed-use cohorts; not all installs or all users.',
                            'Observed-subset rates have followup/response bias. Missing exports remain unknown.',
                            'Forced termination may omit end events. No crash-free-user rate is inferred.']}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('exports', nargs='+', type=Path)
    parser.add_argument('--as-of', type=date.fromisoformat)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = analyze([json.loads(path.read_text(encoding='utf-8')) for path in args.exports], as_of=args.as_of)
    raw = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.output:
        args.output.write_text(raw, encoding='utf-8')
    else:
        print(raw)


if __name__ == '__main__':
    main()
