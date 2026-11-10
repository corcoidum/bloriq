import unittest

from tools.level_audit import orientations
from tools.mechanics import Board, ClockArrow, DIRECTIONS, State
from tools.validate_levels import validate_level


def waiting_board() -> dict:
    def point(x, y):
        return {'x': x, 'y': y}

    return {
        'id': 1, 'boardWidth': 4, 'boardHeight': 2,
        'startPosition': point(0, 0), 'exitPosition': point(1, 0),
        'blocks': [{'id': 'b1', **point(2, 1)}],
        'obstacles': [point(0, 1), point(1, 1), point(2, 0), point(3, 0)],
        'specialRules': [
            {'type': 'clockArrow', 'tiles': [{**point(0, 0), 'dx': -1, 'dy': 0}]},
            {'type': 'echoEraser', 'positions': [point(2, 1), point(3, 1)]},
        ],
    }


class ClockArrowTest(unittest.TestCase):
    def test_rotates_clockwise_in_screen_coordinates(self):
        clockwise = ((1, 0), (0, 1), (-1, 0), (0, -1))
        for index, direction in enumerate(clockwise):
            clock = ClockArrow({(0, 0): direction})
            board = Board(3, 3, (2, 2), frozenset(), ('goal',), (clock,))
            for turn in range(5):
                state = State(((0, 0),), None, frozenset(), turn, board)
                self.assertEqual(clock.stateKey(state), turn % 4)
                self.assertEqual(
                    [d for d in DIRECTIONS if state.canLeave((0, 0), d)],
                    [clockwise[(index + turn) % 4]],
                )

    def test_same_arrangement_at_a_new_phase_is_not_pruned(self):
        board = waiting_board()
        self.assertEqual(validate_level(board), [
            ('b1', (2, 1), (3, 1)), ('b1', (3, 1), (2, 1)), ('goal', (0, 0), (1, 0)),
        ])
        self.assertEqual(len(validate_level(board, disabled_rule='clockArrow')), 1)
        self.assertEqual(len(orientations(board)), 4)

    def test_rejects_non_cardinal_or_duplicate_tiles(self):
        board = waiting_board()
        tile = board['specialRules'][0]['tiles'][0]
        for tiles in [[], [dict(tile, dy=1)], [tile, tile]]:
            with self.subTest(tiles=tiles), self.assertRaises(AssertionError):
                board['specialRules'][0]['tiles'] = tiles
                validate_level(board)


if __name__ == '__main__':
    unittest.main()
