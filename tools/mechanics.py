"""Dart BoardMechanic과 같은 순서로 적용하는 독립 검증기의 기믹."""
from __future__ import annotations

from dataclasses import dataclass
from random import Random
from typing import Callable, ClassVar, NamedTuple

Position = tuple[int, int]
Positions = tuple[Position, ...]
PointParser = Callable[[dict], Position]
DIRECTIONS = ((1, 0), (-1, 0), (0, 1), (0, -1))


class State(NamedTuple):
    positions: Positions
    echo: Position | None
    powers: frozenset[str]
    moves: int
    board: Board

    def canOccupy(self, index: int, target: Position) -> bool:
        board = self.board
        x, y = target
        if not (0 <= x < board.width and 0 <= y < board.height):
            return False
        if target in board.walls or target == self.echo or target in self.positions:
            return False
        if index != 0 and target == board.exit_point:
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
    cells: Positions = ()

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


# 순서는 Dart MechanicRegistry와 같아야 한다.
REGISTRY = {
    mechanic.type: mechanic for mechanic in (EchoEraser, EchoHold, OneWay, GoalOnly, EchoGate)
}


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
        assert kind not in parsed, f'Duplicate special rule: {kind}'
        mechanic = REGISTRY[kind].parse(rule, point)
        for tile in mechanic.cells:
            assert tile not in occupied, 'Overlapping mechanism tile'
            occupied.add(tile)
        mechanic.validate(level)
        if isinstance(mechanic, EchoGate) and gate_locked:
            mechanic = EchoGate(mechanic.switch, mechanic.gate, locked=True)
        parsed[kind] = mechanic
    # 문 효과를 비교할 때는 문을 없애지 않고 잠근 채로 둔다.
    return tuple(parsed[kind] for kind in REGISTRY
                 if kind in parsed and (kind != disabled_rule or kind == EchoGate.type))
