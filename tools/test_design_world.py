"""공통 생성기의 예산·재개 검증."""
import json
import tempfile
import unittest
from pathlib import Path
from time import monotonic
from unittest.mock import patch

from tools.design_world import Job, checkpoint, design, load_existing, pt
from tools.validate_levels import (
    SearchBudgetExceeded,
    decorative_mechanic,
    expansion_worlds,
    published_worlds,
    solve_or_none,
    validate_level,
)
from tools.worlds import Slot


def board(level_id: int) -> dict:
    return {
        'id': level_id,
        'world': 3,
        'boardWidth': 3,
        'boardHeight': 2,
        'startPosition': pt((0, 0)),
        'exitPosition': pt((2, 0)),
        'blocks': [],
        'obstacles': [],
        'specialRules': [],
    }


class WorldGeneratorTest(unittest.TestCase):
    def test_budget_and_deadline_do_not_mean_unsolvable(self):
        level = board(201)
        self.assertEqual(len(validate_level(level)), 2)
        with self.assertRaises(SearchBudgetExceeded):
            validate_level(level, max_states=1)
        with self.assertRaises(TimeoutError):
            validate_level(level, deadline=monotonic() - 1)

    def test_move_limit_includes_solutions_on_its_boundary(self):
        level = board(201)
        self.assertIsNone(solve_or_none(level, max_moves=1))
        self.assertEqual(validate_level(level, max_moves=2), validate_level(level))

    def test_validation_discovers_drafts_separately_from_publication(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            saga = root / 'saga.json'
            saga.write_text(json.dumps({'worlds': [
                {'number': 2, 'status': 'playable', 'levels': 'world2.json'},
                {'number': 3, 'status': 'planned'},
            ]}))
            draft = root / 'world3.json'
            draft.write_text('[]')
            with patch.multiple('tools.validate_levels', ROOT=root,
                                LEVELS_FILE=root / 'levels.json', SAGA_FILE=saga):
                published = [(2, root / 'world2.json')]
                self.assertEqual(published_worlds(), published)
                self.assertEqual(expansion_worlds(), published + [(3, draft)])

    def test_unused_mechanic_is_decorative(self):
        level = board(201)
        level['specialRules'] = [{'type': 'goalOnly', 'positions': [pt((1, 1))]}]
        self.assertEqual(decorative_mechanic(level, 2), 'goalOnly')

    def test_unpowered_slot_records_a_shortest_solution(self):
        slot = Slot(2, (3, 2), 0, (0, 0), (), None, False, 'fixture', (), 'test',
                    quick_states=100, full_states=100, max_seconds=5)
        result = design(Job(3, 6, slot, 30, frozenset()))
        self.assertIsNotNone(result.level)
        level = result.level
        self.assertEqual(level['id'], 207)
        self.assertEqual(level['availablePowers'], [])
        self.assertEqual(level['minimumMoves'], level['bareHandedMoves'])
        self.assertEqual(len(level['solution']), level['minimumMoves'])

    def test_checkpoint_keeps_previous_slots_if_a_write_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'world3.json'
            checkpoint(path, {6: board(207), 0: board(201)})
            self.assertEqual(list(load_existing(path, 3, 25)), [0, 6])
            saved = path.read_bytes()
            with patch('tools.design_world.write_levels', side_effect=OSError('disk error')):
                with self.assertRaises(OSError):
                    checkpoint(path, {0: board(201)})
            self.assertEqual(path.read_bytes(), saved)
            resumed = load_existing(path, 3, 25)
            resumed[1] = board(202)
            checkpoint(path, resumed)
            self.assertEqual([row['id'] for row in json.loads(path.read_text())], [201, 202, 207])


if __name__ == '__main__':
    unittest.main()
