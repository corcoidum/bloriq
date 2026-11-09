"""세계별 생성 슬롯과 탐색 한도를 등록한다."""
from dataclasses import dataclass
from importlib import import_module
from math import isfinite


@dataclass(frozen=True)
class Slot:
    target_moves: int
    size: tuple[int, int]
    blocks: int
    walls: tuple[int, int]
    mechanics: tuple[str, ...]
    featured: str | None
    required: bool
    intent: str
    powers: tuple[str, ...]
    difficulty: str
    quick_states: int = 250_000
    full_states: int = 2_000_000
    max_seconds: float = 600

    def __post_init__(self) -> None:
        width, height = self.size
        low, high = self.walls
        if (self.target_moves < 1 or min(width, height) < 1 or self.blocks < 0
                or not 0 <= low <= high <= width * height - self.blocks - 2):
            raise ValueError('Invalid slot dimensions, piece counts, or target')
        if (not 0 < self.quick_states <= self.full_states
                or not isfinite(self.max_seconds) or self.max_seconds <= 0):
            raise ValueError('A slot needs positive state budgets and a time limit')
        if self.featured not in (None, *self.powers) or (self.required and self.featured is None):
            raise ValueError('A required or featured power must be available in the slot')


def load_slots(world: int) -> tuple[Slot, ...]:
    name = f'{__name__}.w{world}'
    try:
        slots = import_module(name).SLOTS
    except ModuleNotFoundError as error:
        if error.name != name:
            raise
        raise ValueError(f'No generator slots for world {world} ({name})') from error
    if len(slots) != 25:
        raise ValueError(f'World {world} needs 25 generator slots')
    return slots
