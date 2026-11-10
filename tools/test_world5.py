"""생성기에 넣은 얼음 상한과 최단 풀이 조건을 검증한다."""
import unittest

from tools.design_world import pt
from tools.validate_levels import WIND, trace_solution, validate_level
from tools.worlds.w5 import ICE_CAP, SLOTS, sliding_blocks


def mirror_level(exit_point: tuple[int, int], ice: list[tuple[int, int]]) -> dict:
    return {
        'id': 411, 'world': 5, 'boardWidth': 5, 'boardHeight': 5,
        'startPosition': pt((0, 1)), 'exitPosition': pt(exit_point),
        'blocks': [{'id': 'b1', **pt((4, 3))}], 'obstacles': [],
        'availablePowers': [],
        'specialRules': [
            {'type': 'ice', 'positions': list(map(pt, ice))},
            {'type': 'mirrorPair', 'blocks': ['goal', 'b1']},
        ],
    }


class IceWorldTest(unittest.TestCase):
    def test_ice_cap_is_floor_of_thirty_percent(self):
        limit = SLOTS[0].rule_filter
        self.assertEqual(ICE_CAP, 7)
        for count, accepted in [(0, False), (7, True), (8, False)]:
            with self.subTest(count=count):
                rule = {'type': 'ice', 'positions': [pt((i % 5, i // 5)) for i in range(count)]}
                self.assertEqual(limit([rule]), accepted)

    def test_a_shared_slide_counts_as_one_turn(self):
        match = SLOTS[10].solution_filter
        pair_ice = [(1, 1), (2, 1), (3, 3), (2, 3)]
        one_turn = mirror_level((3, 1), pair_ice)
        solution = validate_level(one_turn)
        self.assertEqual([sliding_blocks(*turn) for turn in trace_solution(one_turn, solution)], [(0, 1)])
        self.assertFalse(match(one_turn, solution))

        two_turns = mirror_level((3, 4), [*pair_ice, (3, 2)])
        solution = validate_level(two_turns)
        self.assertEqual([sliding_blocks(*turn) for turn in trace_solution(two_turns, solution)], [(0, 1), (0,)])
        self.assertTrue(match(two_turns, solution))

    def test_wind_travel_is_not_an_extra_ice_slide(self):
        level = {
            'id': 406, 'world': 5, 'boardWidth': 5, 'boardHeight': 1,
            'startPosition': pt((0, 0)), 'exitPosition': pt((4, 0)),
            'blocks': [], 'obstacles': [], 'availablePowers': [WIND],
            'specialRules': [{'type': 'ice', 'positions': [pt((1, 0))]}],
        }
        solution = validate_level(level, powers=(WIND,))
        self.assertEqual(solution, [('goal', (0, 0), (4, 0), WIND)])
        self.assertEqual([sliding_blocks(*turn) for turn in trace_solution(level, solution)], [()])
