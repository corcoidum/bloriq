import unittest

from tools.mechanics import Board, MechanicMove, State, parse_mechanics
from tools.validate_levels import LEAP, validate_level


def point(x: int, y: int = 0) -> dict[str, int]:
    return {'x': x, 'y': y}


def lane(*ice: int) -> dict:
    return {
        'id': 401, 'boardWidth': 5, 'boardHeight': 1,
        'startPosition': point(0), 'exitPosition': point(3),
        'blocks': [], 'obstacles': [],
        'specialRules': [{'type': 'ice', 'positions': [point(x) for x in ice]}],
    }


class IceTest(unittest.TestCase):
    def test_ice_at_exit_stops_riq_and_records_the_raw_landing(self):
        level = lane(1, 2, 3, 4)
        self.assertEqual(validate_level(level), [('goal', (0, 0), (1, 0))])
        self.assertEqual(len(validate_level(level, disabled_rule='ice')), 3)

    def test_closed_gate_blocks_until_the_departure_echo_opens_it(self):
        level = lane(1, 2)
        level['exitPosition'] = point(4)
        level['specialRules'].append({'type': 'echoGate', 'switch': point(0), 'gate': point(3)})
        self.assertEqual(validate_level(level), [
            ('goal', (0, 0), (1, 0)), ('goal', (2, 0), (3, 0)), ('goal', (3, 0), (4, 0)),
        ])

    def test_leap_extends_from_ice_and_costs_one_turn(self):
        level = lane(2, 3, 4)
        level['obstacles'] = [point(1)]
        self.assertEqual(validate_level(level, powers=(LEAP,)), [
            ('goal', (0, 0), (2, 0), LEAP),
        ])

    def test_pair_reads_final_primary_position_regardless_of_json_order(self):
        level = {
            'startPosition': point(0, 0), 'exitPosition': point(4, 2),
            'blocks': [{'id': 'b1', **point(0, 1)}, {'id': 'b2', **point(4, 1)}],
            'specialRules': [
                {'type': 'mirrorPair', 'blocks': ['b1', 'b2']},
                {'type': 'ice', 'positions': [point(1, 1), point(2, 1), point(3, 1)]},
            ],
        }
        def coord(value: dict) -> tuple[int, int]:
            return value['x'], value['y']

        rules = parse_mechanics(level, coord, walls=frozenset(),
                                disabled_rule=None, gate_locked=False)
        board = Board(5, 3, (4, 2), frozenset(), ('goal', 'b1', 'b2'), rules)
        before = State(((0, 0), (0, 1), (4, 1)), None, frozenset(), 0, board)
        move = MechanicMove(1, (1, 1), None)
        after = ((0, 0), (1, 1), (4, 1))
        for rule in rules:
            after = rule.transformMove(before, move, after)
        self.assertEqual(after, ((0, 0), (3, 1), (4, 1)))

    def test_rejects_ice_overlap_and_bad_positions(self):
        for kind in ('oneWay', 'clockArrow'):
            with self.subTest(kind=kind), self.assertRaises(AssertionError):
                level = lane(1, 2)
                level['specialRules'].append({'type': kind, 'tiles': [{**point(2), 'dx': 1, 'dy': 0}]})
                validate_level(level)
        for positions in ((), (2, 2), (5,)):
            with self.subTest(positions=positions), self.assertRaises(AssertionError):
                validate_level(lane(*positions))


if __name__ == '__main__':
    unittest.main()
