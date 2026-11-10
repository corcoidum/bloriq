"""공통 생성기의 예산·재개 검증."""
import json
import random
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path
from time import monotonic
from unittest.mock import patch

from tools.design_world import (
    Job,
    check_existing,
    checkpoint,
    design,
    full_check,
    load_existing,
    mechanic_choices,
    pt,
    random_level,
)
from tools.validate_levels import (
    SEAL,
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


def mixed_corridor(height: int = 2) -> dict:
    return {
        **board(601), 'world': 7, 'boardWidth': 6, 'boardHeight': height,
        'exitPosition': pt((5, 0)),
        'specialRules': [
            {'type': 'shelfDoor', 'pairs': [{'a': pt((2, 0)), 'b': pt((4, 0))}]},
            {'type': 'ice', 'positions': [pt((1, 0))]},
        ],
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

    def test_mixed_slot_samples_exactly_k_distinct_additional_rules(self):
        slot = Slot(5, (5, 5), 2, (2, 3), ('echoEraser',), None, False, 'mix', (), 'test',
                    mechanic_candidates=('echoGate', 'ice', 'shelfDoor'), mechanic_count=2)
        seen = set()
        for seed in range(20):
            level = random_level(7, 0, slot, random.Random(seed))
            kinds = tuple(rule['type'] for rule in level['specialRules'])
            self.assertIn(kinds, mechanic_choices(slot))
            self.assertEqual(len(set(kinds)), 3)
            seen.add(kinds)
        self.assertEqual(seen, set(mechanic_choices(slot)))
        with self.assertRaises(ValueError):
            replace(slot, mechanic_count=4)
        with self.assertRaises(ValueError):
            replace(slot, mechanic_candidates=('ice', 'echoEraser'))

    def test_every_selected_rule_must_change_the_shortest_solution(self):
        slot = Slot(2, (6, 6), 0, (0, 0), ('shelfDoor',), None, False, 'mix', (), 'test',
                    mechanic_candidates=('ice', 'goalOnly'), mechanic_count=1,
                    layout_factory=lambda _: mixed_corridor(6), max_seconds=5)
        result = design(Job(7, 0, slot, 17, frozenset()))
        self.assertEqual(len(result.level['solution']), 2)
        self.assertIsNone(decorative_mechanic(result.level, 2))

        decorative = mixed_corridor(6)
        decorative['specialRules'][1] = {'type': 'goalOnly', 'positions': [pt((1, 1))]}
        solution = validate_level(decorative)
        self.assertIsNone(full_check(decorative, slot, solution, False, monotonic() + 5))

    def test_6x6_excludes_measured_failures_even_inside_a_triple(self):
        slot = Slot(10, (6, 6), 3, (2, 4), ('clockArrow',), None, False, 'mix', (SEAL,), 'test',
                    mechanic_candidates=('shelfDoor', 'echoHold'), mechanic_count=1)
        self.assertEqual(mechanic_choices(slot), (('clockArrow', 'echoHold'),))
        with self.assertRaisesRegex(ValueError, 'No supported 6×6 combination'):
            mechanic_choices(replace(slot, mechanic_count=2))
        self.assertIn(('clockArrow', 'shelfDoor'), mechanic_choices(replace(slot, size=(6, 5))))
        self.assertIn(('clockArrow', 'shelfDoor'), mechanic_choices(replace(slot, powers=())))

        forbidden = random_level(
            7, 0, replace(slot, powers=(), mechanic_candidates=('shelfDoor',)), random.Random(17),
        )
        forbidden.update(availablePowers=[SEAL], solution=[])
        with self.assertRaisesRegex(ValueError, 'slot metadata'):
            check_existing({0: forbidden}, 7, (slot,), [])

    def test_6x6_caps_candidate_searches_and_retries_a_timed_out_candidate(self):
        slot = Slot(2, (6, 6), 0, (0, 0), ('ice', 'shelfDoor'), None, False, 'mix', (), 'test',
                    layout_factory=lambda _: mixed_corridor(6), max_seconds=30)
        path = validate_level(mixed_corridor(6))
        profile = {'minimumMoves': 2, 'bareHandedMoves': 2, 'requiredPowers': [], 'solution': path}
        with (
            patch('tools.design_world.monotonic', return_value=1000),
            patch('tools.design_world.solve_or_none', side_effect=[TimeoutError(), path]) as quick,
            patch('tools.design_world.full_check', return_value=profile) as full,
        ):
            result = design(Job(7, 0, slot, 17, frozenset()))
        self.assertEqual(result.over_budget, 1)
        self.assertEqual(len(result.level['solution']), 2)
        self.assertEqual([call.kwargs['max_states'] for call in quick.call_args_list], [120_000] * 2)
        self.assertEqual([call.kwargs['deadline'] for call in quick.call_args_list], [1008.0] * 2)
        self.assertEqual(full.call_args.args[1].full_states, 200_000)
        self.assertEqual(full.call_args.args[4], 1008.0)

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

    def test_mutation_rechecks_the_slot_rule_filter_before_solving(self):
        slot = Slot(2, (3, 2), 0, (0, 0), (), None, False, 'fixture', (), 'test',
                    max_seconds=5, rule_filter=lambda rules: not rules)
        level = {**board(201), 'availablePowers': []}
        invalid = {**level, 'specialRules': [{'type': 'goalOnly', 'positions': [pt((1, 1))]}]}
        with (
            patch('tools.design_world.random_level', return_value=level),
            patch('tools.design_world.mutate', side_effect=[invalid, level]),
            patch('tools.design_world.solve_or_none', wraps=solve_or_none) as solve,
        ):
            result = design(Job(3, 0, slot, 30, frozenset()))
        self.assertEqual(result.level['specialRules'], [])
        self.assertEqual(solve.call_count, 1)

    def test_slot_layout_factory_produces_a_candidate_without_mutating_it(self):
        fixture = board(201)
        keys = ('startPosition', 'exitPosition', 'blocks', 'obstacles', 'specialRules')
        slot = Slot(2, (3, 2), 0, (0, 0), (), None, False, 'fixture', (), 'test',
                    layout_factory=lambda rng: {key: fixture[key] for key in keys})
        with patch('tools.design_world.mutate') as mutate:
            result = design(Job(3, 0, slot, 30, frozenset()))
        self.assertEqual(result.level['minimumMoves'], 2)
        mutate.assert_not_called()

    def test_slot_can_mutate_a_seeded_layout(self):
        fixture = {**board(201), 'availablePowers': []}
        keys = ('startPosition', 'exitPosition', 'blocks', 'obstacles', 'specialRules')
        slot = Slot(2, (3, 2), 0, (0, 0), (), None, False, 'fixture', (), 'test',
                    layout_factory=lambda rng: {key: fixture[key] for key in keys},
                    mutate_layout=True)
        with patch('tools.design_world.mutate', return_value=fixture) as mutate:
            result = design(Job(3, 0, slot, 30, frozenset()))
        self.assertEqual(result.level['minimumMoves'], 2)
        mutate.assert_called_once()

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
