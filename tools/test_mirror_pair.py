"""거울 짝의 Python 판정과 생성기·감사 연결을 확인한다."""
import copy
import random
import unittest

from tools.design_world import pt, random_level
from tools.level_audit import canonical
from tools.mechanics import Board, MechanicMove, State, parse_mechanics
from tools.worlds import Slot


def _level() -> dict:
    return {
        'id': 201,
        'boardWidth': 5,
        'boardHeight': 5,
        'startPosition': pt((0, 0)),
        'exitPosition': pt((4, 0)),
        'blocks': [{'id': 'b1', **pt((1, 2))}, {'id': 'b2', **pt((4, 2))}],
        'obstacles': [],
        'specialRules': [{'type': 'mirrorPair', 'blocks': ['b1', 'b2']}],
    }


def _state(level: dict, echo=None) -> State:
    def point(raw: dict) -> tuple[int, int]:
        return raw['x'], raw['y']

    walls = frozenset(map(point, level['obstacles']))
    mechanics = parse_mechanics(level, point, walls=walls, disabled_rule=None, gate_locked=False)
    ids = ('goal', *(block['id'] for block in level['blocks']))
    board = Board(level['boardWidth'], level['boardHeight'], point(level['exitPosition']),
                  walls, ids, mechanics)
    return State((point(level['startPosition']), *map(point, level['blocks'])),
                 echo, frozenset(), 0, board)


class MirrorPairTest(unittest.TestCase):
    def test_two_pairs_are_disjoint_and_use_known_ids(self):
        level = _level()
        level['specialRules'].append({'type': 'mirrorPair', 'blocks': ['goal', 'b3']})
        with self.assertRaisesRegex(AssertionError, 'mirror pair block ID'):
            _state(level)
        level['blocks'].append({'id': 'b3', **pt((4, 4))})
        self.assertEqual(len(_state(level).board.mechanics), 1)
        level['specialRules'][1]['blocks'] = ['goal', 'b1']
        with self.assertRaisesRegex(AssertionError, 'mirror pair block ID'):
            _state(level)

    def test_entry_uses_current_echo_landing_and_registered_tile_rules(self):
        level = _level()
        move = MechanicMove(1, (2, 2), None)
        after_landing = ((0, 0), (2, 2), (4, 2))
        state = _state(level)
        self.assertEqual(state.board.mechanics[0].transformMove(state, move, after_landing),
                         ((0, 0), (2, 2), (3, 2)))
        shifted_landing = ((0, 0), (3, 2), (2, 2))
        self.assertIs(state.board.mechanics[0].transformMove(state, move, shifted_landing),
                      shifted_landing)
        blocked = _state(level, echo=(3, 2))
        self.assertIs(blocked.board.mechanics[0].transformMove(blocked, move, after_landing),
                      after_landing)
        level['specialRules'].append({'type': 'goalOnly', 'positions': [pt((3, 2))]})
        clover = _state(level)
        self.assertIs(clover.board.mechanics[-1].transformMove(clover, move, after_landing),
                      after_landing)

    def test_generator_and_audit_preserve_pair_members_under_reflection(self):
        slot = Slot(5, (5, 4), 3, (2, 2), ('mirrorPair', 'mirrorPair'),
                    None, False, 'test', (), 'test')
        level = random_level(3, 0, slot, random.Random(44))
        pairs = level['specialRules']
        self.assertEqual(len({id_ for pair in pairs for id_ in pair['blocks']}), 4)
        _state(level)
        flipped = copy.deepcopy(level)
        for point in [flipped['startPosition'], flipped['exitPosition'],
                      *flipped['blocks'], *flipped['obstacles']]:
            point['x'] = flipped['boardWidth'] - 1 - point['x']
        flipped['specialRules'].reverse()
        for pair in flipped['specialRules']:
            pair['blocks'].reverse()
        self.assertEqual(canonical(flipped), canonical(level))
        first, second = flipped['specialRules']
        first['blocks'][0], second['blocks'][0] = second['blocks'][0], first['blocks'][0]
        self.assertNotEqual(canonical(flipped), canonical(level))


if __name__ == '__main__':
    unittest.main()
