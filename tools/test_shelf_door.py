from __future__ import annotations

import unittest

from tools.level_audit import canonical
from tools.mechanics import EchoGate, MechanicMove, ShelfDoor, State
from tools.validate_levels import LEAP, SWAP, WIND, _read_board, _transition, decorative_mechanic, validate_level


START, A, B, EXIT = (0, 1), (1, 1), (4, 3), (5, 0)


def point(cell: tuple[int, int]) -> dict[str, int]:
    return {'x': cell[0], 'y': cell[1]}


def level(*, start=START, blocks=(), walls=(), pairs=((A, B),), extras=()) -> dict:
    return {
        'id': 501, 'boardWidth': 6, 'boardHeight': 5,
        'startPosition': point(start), 'exitPosition': point(EXIT),
        'blocks': [{'id': f'b{i + 1}', **point(block)} for i, block in enumerate(blocks)],
        'obstacles': list(map(point, walls)),
        'specialRules': [*extras, {'type': 'shelfDoor', 'pairs': [
            {'a': point(a), 'b': point(b)} for a, b in pairs
        ]}],
    }


def initial(data: dict, *, echo=None, power=None) -> State:
    board, positions = _read_board(data)
    return State(positions, echo, frozenset([power]) if power else frozenset(), 0, board)


def step(before: State, target, *, index=0, power=None) -> State:
    return _transition(before.board)(before, MechanicMove(index, target, power))


class ShelfDoorTest(unittest.TestCase):
    def test_single_teleport_and_exit_reentry(self):
        after = step(initial(level(blocks=((0, 4),))), A)
        self.assertEqual((after.positions[0], after.moves, after.echo), (B, 1, START))
        floor = (5, 3)
        after = step(after, floor)
        self.assertEqual((after.positions[0], after.echo), (floor, B))
        self.assertFalse(after.canOccupy(0, B))
        after = step(step(after, (1, 4), index=1), B)
        self.assertEqual((after.positions[0], after.moves, after.echo), (A, 4, floor))

    def test_rock_block_old_echo_and_vacated_origin(self):
        for before in (
            initial(level(walls=(B,))), initial(level(blocks=(B,))),
            initial(level(), echo=B), initial(level(pairs=((A, START),))),
        ):
            with self.subTest(before=before):
                after = step(before, A)
                self.assertEqual((after.positions[0], after.moves, after.echo), (A, 1, START))

    def test_clover_and_closed_gate_use_entry_predicates(self):
        clover = {'type': 'goalOnly', 'positions': [point(B)]}
        riq = initial(level(extras=(clover,)))
        rune = initial(level(start=(0, 0), blocks=(START,), extras=(clover,)))
        self.assertEqual(step(riq, A).positions[0], B)
        self.assertEqual(step(rune, A, index=1).positions[1], A)

        # 데이터 검증은 문과 책장의 겹침을 거부한다. 훅 자체의 방어 판정도 검사한다.
        shelf = ShelfDoor(((A, B),))
        crystal = (3, 3)
        board = riq.board._replace(mechanics=(EchoGate(crystal, B),))
        closed = riq._replace(board=board)
        self.assertEqual(shelf.finish_teleport(closed, (A,), 0, START), A)
        self.assertEqual(shelf.finish_teleport(closed._replace(echo=crystal), (A,), 0, START), B)

    def test_ice_and_clock(self):
        entrance = (3, 1)
        ice = {'type': 'ice', 'positions': [point(A), point((2, 1)), point((5, 3))]}
        clock = {'type': 'clockArrow', 'tiles': [{**point((5, 4)), 'dx': 1, 'dy': 0}]}
        after = step(initial(level(pairs=((entrance, B),), extras=(clock, ice))), A)
        self.assertEqual((after.positions[0], after.moves, after.echo), (B, 1, START))
        self.assertEqual(after.board.mechanics[-1].stateKey(after), 1)

    def test_twin_uses_primary_end_and_can_teleport_after_ice(self):
        mirror = {'type': 'mirrorPair', 'blocks': ['goal', 'b1']}
        same = step(initial(level(blocks=((2, 1),), extras=(mirror,))), A)
        self.assertEqual((same.positions, same.echo), ((B, A), START))

        ice = {'type': 'ice', 'positions': [point((4, 2)), point((3, 2))]}
        other = step(initial(level(blocks=((5, 2),), pairs=((A, B), ((2, 2), (2, 3))),
                                   extras=(mirror, ice))), A)
        self.assertEqual((other.positions, other.echo, other.moves), ((B, (2, 3)), START, 1))

        returns = step(initial(level(blocks=(B,), pairs=(((3, 3), B),), extras=(mirror,))), A)
        self.assertEqual((returns.positions, returns.echo), ((A, B), START))

    def test_power_landings(self):
        leap = level(walls=(A,), pairs=(((2, 1), B),))
        wind = level(walls=((4, 1),), pairs=(((3, 1), B), (A, (1, 4))))
        for data, target, power, echo in (
            (leap, (2, 1), LEAP, None), (wind, (3, 1), WIND, None), (level(), B, SWAP, B),
        ):
            with self.subTest(power=power):
                after = step(initial(data, power=power, echo=echo), target, power=power)
                self.assertEqual((after.positions[0], after.moves, after.echo), (B, 1, START))
                self.assertFalse(after.powers)

    def test_invalid_endpoints_and_overlaps(self):
        for pairs in ((), ((A, A),), ((A, EXIT),), ((A, (6, 4)),),
                      ((A, B), (A, (2, 2))), ((A, B), ((2, 2), (2, 3)), ((3, 2), (3, 3)))):
            with self.subTest(pairs=pairs), self.assertRaises(AssertionError):
                _read_board(level(pairs=pairs))
        for rule in (
            {'type': 'ice', 'positions': [point(B)]},
            *({'type': kind, 'tiles': [{**point(B), 'dx': 1, 'dy': 0}]}
              for kind in ('oneWay', 'clockArrow')),
            {'type': 'echoGate', 'switch': point(B), 'gate': point((3, 4))},
            {'type': 'echoGate', 'switch': point((3, 4)), 'gate': point(B)},
        ):
            with self.subTest(rule=rule), self.assertRaisesRegex(AssertionError, 'Overlapping shelf'):
                _read_board(level(extras=(rule,)))

    def test_audit_groups_endpoints_without_using_pair_order(self):
        c, d = (2, 0), (3, 2)
        original = canonical(level(pairs=((A, B), (c, d))))
        self.assertEqual(original, canonical(level(pairs=((d, c), (B, A)))))
        self.assertNotEqual(original, canonical(level(pairs=((A, c), (B, d)))))

    def test_audit_rejects_an_unused_pair_even_when_the_other_shortens_the_path(self):
        draft = level(pairs=((A, B), ((0, 4), (1, 4))))
        minimum = len(validate_level(draft))
        self.assertLess(minimum, len(validate_level(draft, disabled_rule=ShelfDoor.type)))
        self.assertEqual(decorative_mechanic(draft, minimum), 'shelfDoor #2')
