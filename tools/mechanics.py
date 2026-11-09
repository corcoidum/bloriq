"""Dart BoardMechanic과 같은 순서로 적용하는 독립 검증기의 기믹."""
from __future__ import annotations

from dataclasses import dataclass
from random import Random
from typing import Callable, ClassVar, Iterable, NamedTuple

Position = tuple[int, int]
Positions = tuple[Position, ...]
PointParser = Callable[[dict], Position]
AuditToken = Callable[[str, dict], str]
AuditDirection = Callable[[int, int], Position]
DIRECTIONS = ((1, 0), (-1, 0), (0, 1), (0, -1))


class State(NamedTuple):
    positions: Positions
    echo: Position | None
    powers: frozenset[str]
    moves: int
    board: Board

    def canOccupy(self, index: int, target: Position, *,
                  positions: Positions | None = None, allow_non_goal_exit: bool = False) -> bool:
        board = self.board
        x, y = target
        if not (0 <= x < board.width and 0 <= y < board.height):
            return False
        occupied = self.positions if positions is None else positions
        if target in board.walls or target == self.echo or target in occupied:
            return False
        if not allow_non_goal_exit and index != 0 and target == board.exit_point:
            return False
        for mechanic in board.mechanics:
            if not mechanic.canEnter(self, index, target):
                return False
        return True

    def canLeave(self, source: Position, direction: Position) -> bool:
        for mechanic in self.board.mechanics:
            if not mechanic.canLeave(self, source, direction):
                return False
        return True


class MechanicMove(NamedTuple):
    index: int
    target: Position
    power: str | None


class BoardMechanic:
    # 훅 이름은 Dart의 BoardMechanic과 맞춘다.
    type: ClassVar[str]
    max_instances: ClassVar[int] = 1
    cells: Positions = ()

    def combine(self, other: BoardMechanic) -> BoardMechanic:
        raise AssertionError(f'Duplicate special rule: {self.type}')

    def validate(self, level: dict) -> None:
        pass

    def canEnter(self, state: State, index: int, target: Position) -> bool:
        return True

    def canLeave(self, state: State, source: Position, direction: Position) -> bool:
        return True

    def transformMove(self, before: State, move: MechanicMove, blocks: Positions) -> Positions:
        return blocks

    def nextEcho(self, before: State, move: MechanicMove, blocks: Positions,
                 echo: Position | None) -> Position | None:
        return echo

    def stateKey(self, state: State) -> int | None:
        return None

    @classmethod
    def auditTokens(cls, level: dict, rule: dict, token: AuditToken,
                    direction: AuditDirection) -> Iterable[str]:
        """회전·대칭에서 같은 판을 찾기 위한 칸별 표식."""
        return (token(cls.type, point) for point in rule['positions'])


class Board(NamedTuple):
    width: int
    height: int
    exit_point: Position
    walls: frozenset[Position]
    block_ids: tuple[str, ...]
    mechanics: tuple[BoardMechanic, ...]


@dataclass(frozen=True)
class _TileMechanic(BoardMechanic):
    positions: frozenset[Position]

    @property
    def cells(self) -> Positions:
        return tuple(self.positions)

    @classmethod
    def parse(cls, rule: dict, point: PointParser) -> _TileMechanic:
        raw = rule.get('positions')
        assert isinstance(raw, list) and raw, 'Mechanism rule requires positions'
        positions = frozenset(map(point, raw))
        assert len(positions) == len(raw), 'Duplicate mechanism tile'
        return cls(positions)

    @classmethod
    def randomRule(cls, level: dict, rng: Random, take: Callable[[], dict]) -> dict:
        return {'type': cls.type, 'positions': [take() for _ in range(rng.randint(1, 2))]}


class EchoEraser(_TileMechanic):
    type = 'echoEraser'

    def nextEcho(self, before, move, blocks, echo):
        return None if before.positions[move.index] in self.positions else echo


class EchoHold(_TileMechanic):
    type = 'echoHold'

    def nextEcho(self, before, move, blocks, echo):
        return before.echo if before.positions[move.index] in self.positions else echo


class GoalOnly(_TileMechanic):
    type = 'goalOnly'

    def canEnter(self, state, index, target):
        return index == 0 or target not in self.positions


@dataclass(frozen=True)
class OneWay(BoardMechanic):
    type = 'oneWay'
    arrows: dict[Position, Position]

    @property
    def cells(self) -> Positions:
        return tuple(self.arrows)

    @classmethod
    def parse(cls, rule: dict, point: PointParser) -> OneWay:
        raw = rule.get('tiles')
        assert isinstance(raw, list) and raw, 'One-way rule requires tiles'
        arrows = {}
        for tile in raw:
            pos = point(tile)
            direction = tile.get('dx'), tile.get('dy')
            assert all(type(component) is int for component in direction) and direction in DIRECTIONS
            assert pos not in arrows, 'Duplicate one-way tile'
            arrows[pos] = direction
        return cls(arrows)

    def canLeave(self, state, source, direction):
        arrow = self.arrows.get(source)
        return arrow is None or arrow == direction

    @classmethod
    def randomRule(cls, level: dict, rng: Random, take: Callable[[], dict]) -> dict:
        return {'type': cls.type, 'tiles': [
            {**take(), 'dx': dx, 'dy': dy}
            for dx, dy in rng.sample(DIRECTIONS, rng.randint(1, 2))
        ]}

    @classmethod
    def auditTokens(cls, level: dict, rule: dict, token: AuditToken,
                    direction: AuditDirection) -> Iterable[str]:
        for tile in rule['tiles']:
            dx, dy = direction(tile['dx'], tile['dy'])
            yield token(f'arrow{dx},{dy}', tile)


@dataclass(frozen=True)
class EchoGate(BoardMechanic):
    type = 'echoGate'
    switch: Position
    gate: Position
    locked: bool = False

    @property
    def cells(self) -> Positions:
        return self.switch, self.gate

    @classmethod
    def parse(cls, rule: dict, point: PointParser) -> EchoGate:
        return cls(point(rule.get('switch')), point(rule.get('gate')))

    def validate(self, level):
        def point(raw):
            return raw['x'], raw['y']

        exit_point = point(level['exitPosition'])
        assert self.switch != exit_point and self.gate != exit_point
        assert self.gate != point(level['startPosition'])
        assert all(self.gate != point(block) for block in level['blocks'])

    def canEnter(self, state, index, target):
        return target != self.gate or (not self.locked and state.echo == self.switch)

    @classmethod
    def randomRule(cls, level: dict, rng: Random, take: Callable[[], dict]) -> dict:
        return {'type': cls.type, 'switch': take(), 'gate': take()}

    @classmethod
    def auditTokens(cls, level: dict, rule: dict, token: AuditToken,
                    direction: AuditDirection) -> Iterable[str]:
        return (token('switch', rule['switch']), token('gate', rule['gate']))


@dataclass(frozen=True)
class MirrorPair(BoardMechanic):
    type = 'mirrorPair'
    max_instances = 2
    pairs: tuple[tuple[str, str], ...]

    @classmethod
    def parse(cls, rule: dict, point: PointParser) -> MirrorPair:
        ids = rule.get('blocks')
        assert isinstance(ids, list) and len(ids) == 2 and all(isinstance(id_, str) for id_ in ids), (
            'A mirror pair requires two block IDs')
        return cls(((ids[0], ids[1]),))

    def combine(self, other: BoardMechanic) -> MirrorPair:
        assert isinstance(other, MirrorPair)
        return MirrorPair(self.pairs + other.pairs)

    def validate(self, level: dict) -> None:
        assert len(self.pairs) <= self.max_instances, 'At most two mirror pairs are allowed'
        ids = {'goal', *(block['id'] for block in level['blocks'])}
        for first, second in self.pairs:
            assert first != second and first in ids and second in ids, 'Invalid or repeated mirror pair block ID'
            ids.difference_update((first, second))

    def transformMove(self, before: State, move: MechanicMove, blocks: Positions) -> Positions:
        if move.power is not None:
            return blocks
        ids = before.board.block_ids
        moved = ids[move.index]
        for first, second in self.pairs:
            if moved == first:
                partner = ids.index(second)
                break
            if moved == second:
                partner = ids.index(first)
                break
        else:
            return blocks
        source = before.positions[move.index]
        direction = source[0] - move.target[0], source[1] - move.target[1]
        start = blocks[partner]
        target = start[0] + direction[0], start[1] + direction[1]
        # 새 잔상 자리와 이동 전 잔상은 짝이 밟을 수 없다.
        if (target == source
                or not before.canOccupy(partner, target, positions=blocks, allow_non_goal_exit=True)
                or not before.canLeave(start, direction)):
            return blocks
        return blocks[:partner] + (target,) + blocks[partner + 1:]

    @classmethod
    def randomRule(cls, level: dict, rng: Random, take: Callable[[], dict]) -> dict:
        paired = {id_ for rule in level['specialRules'] if rule['type'] == cls.type
                  for id_ in rule['blocks']}
        ids = ['goal', *(block['id'] for block in level['blocks'])]
        return {'type': cls.type, 'blocks': rng.sample([id_ for id_ in ids if id_ not in paired], 2)}

    @classmethod
    def auditTokens(cls, level: dict, rule: dict, token: AuditToken,
                    direction: AuditDirection) -> Iterable[str]:
        starts = {'goal': level['startPosition'], **{block['id']: block for block in level['blocks']}}
        endpoints = sorted(token('member', starts[id_]) for id_ in rule['blocks'])
        return (f"{cls.type}:{'/'.join(endpoints)}",)


# 순서는 Dart MechanicRegistry와 같아야 한다.
REGISTRY = {
    mechanic.type: mechanic
    for mechanic in (EchoEraser, EchoHold, OneWay, GoalOnly, EchoGate, MirrorPair)
}


def populate_random_rules(level: dict, kinds: Iterable[str], rng: Random,
                          take: Callable[[], dict]) -> None:
    rules: list[dict] = []
    level['specialRules'] = rules
    for kind in kinds:
        rules.append(REGISTRY[kind].randomRule(level, rng, take))


def parse_mechanics(level: dict, point: PointParser, *, walls: frozenset[Position],
                    disabled_rule: str | None, gate_locked: bool) -> tuple[BoardMechanic, ...]:
    rules = level['specialRules']
    assert isinstance(rules, list), 'Special rules must be a list'
    parsed: dict[str, BoardMechanic] = {}
    occupied = set(walls)
    for rule in rules:
        assert isinstance(rule, dict) and isinstance(rule.get('type'), str)
        kind = rule['type']
        assert kind in REGISTRY, f'Unknown rule: {kind}'
        mechanic = REGISTRY[kind].parse(rule, point)
        if kind in parsed:
            mechanic = parsed[kind].combine(mechanic)
        for tile in mechanic.cells:
            assert tile not in occupied, 'Overlapping mechanism tile'
            occupied.add(tile)
        if isinstance(mechanic, EchoGate) and gate_locked:
            mechanic = EchoGate(mechanic.switch, mechanic.gate, locked=True)
        parsed[kind] = mechanic
    for mechanic in parsed.values():
        mechanic.validate(level)
    # 문 효과를 비교할 때는 문을 없애지 않고 잠근 채로 둔다.
    return tuple(parsed[kind] for kind in REGISTRY
                 if kind in parsed and (kind != disabled_rule or kind == EchoGate.type))
