import copy
from datetime import date
import json
from pathlib import Path
import unittest
from tools.analyze_playtests import analyze
from tools.level_audit import canonical, inspect

ROOT = Path(__file__).resolve().parents[1]


class HybridToolsTest(unittest.TestCase):
    def test_optout_gap_cannot_be_interpreted_as_absence(self):
        export = {'version':1,'participantId':'gapped','firstObservedDate':'2026-10-01',
                  'exportedLocalDate':'2026-10-10','droppedEvents':0,'collectionInterrupted':True,'events':[]}
        result = analyze([export],as_of=date(2026,10,10))
        self.assertEqual(1,result['cohorts']['2026-10-01']['D1']['unknown'])
        self.assertEqual(1,result['cohorts']['2026-10-01']['D7']['unknown'])

    def test_duplicate_under_mirror_and_block_id_rename(self):
        original = json.loads((ROOT / 'assets/levels/levels.json').read_text())[1]
        mirror = copy.deepcopy(original)
        for point in [mirror['startPosition'], mirror['exitPosition'], *mirror['blocks'], *mirror['obstacles']]:
            point['x'] = mirror['boardWidth'] - 1 - point['x']
        mirror['blocks'][0]['id'] = 'renamed'
        self.assertEqual(canonical(original), canonical(mirror))
        mirror['id'] = 99
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            inspect([original, mirror])

    def test_all_candidates_are_distinct_solvable_and_unpublished(self):
        active = json.loads((ROOT / 'assets/levels/levels.json').read_text())
        drafts = json.loads((ROOT / 'assets/levels/draft_levels_26_40.json').read_text(encoding='utf-8'))
        self.assertEqual(list(range(26, 41)), [level['id'] for level in drafts])
        self.assertTrue(all(level['reviewStatus'] == 'awaiting_manual_play' for level in drafts))
        self.assertEqual(40, len(inspect(active + drafts)))
        self.assertEqual(25, len(active))

    def test_missing_followup_is_unknown_and_duplicate_exports_are_deduplicated(self):
        def export(identity, day, events, dropped=0):
            return {'version': 1, 'participantId': identity, 'firstObservedDate': '2026-10-01',
                    'exportedLocalDate': day, 'droppedEvents': dropped, 'collectionInterrupted':False, 'events': events}
        start = {'id': 'start', 'name': 'session_start', 'localDate': '2026-10-01'}
        back = {'id': 'return', 'name': 'session_start', 'localDate': '2026-10-02'}
        first = export('a', '2026-10-03', [start, back])
        result = analyze([first, first, export('b', '2026-10-01', [start]), export('c', '2026-10-03', [start])], as_of=date(2026,10,9))
        d1 = result['cohorts']['2026-10-01']['D1']
        self.assertEqual((3,1,1,1), (d1['eligible'],d1['returned'],d1['known_absent'],d1['unknown']))
        self.assertEqual(.5, d1['observed_subset_retention'])
        self.assertEqual([1/3,2/3],d1['full_cohort_bounds'])
        self.assertEqual(2,result['duplicate_events_removed'])
        self.assertEqual(3,result['cohorts']['2026-10-01']['D7']['unknown'])

    def test_immature_and_truncated_exports_do_not_make_false_negative_retention(self):
        export = {'version':1,'participantId':'a','firstObservedDate':'2026-02-28','exportedLocalDate':'2026-03-10','droppedEvents':4,'events':[]}
        self.assertEqual(0,analyze([export],as_of=date(2026,3,1))['cohorts']['2026-02-28']['D1']['eligible'])
        self.assertEqual(1,analyze([export],as_of=date(2026,3,10))['cohorts']['2026-02-28']['D7']['unknown'])


if __name__ == '__main__':
    unittest.main()
