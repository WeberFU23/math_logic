from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np

from rule_based_submission.symbolic import AgentMemory, SymbolicState
from rule_based_submission.vision import perceive

GRID_WIDTH = 10
GRID_HEIGHT = 8
LABELS = (
    "floor",
    "wall",
    "chest",
    "monster",
    "exit",
    "trap",
    "button",
    "switch",
    "gap",
    "bridge",
    "npc",
)
FEATURE_DIM = GRID_WIDTH * GRID_HEIGHT + 2 + 4 * 2 + 6


@dataclass
class FeatureState:
    memory: AgentMemory

    @classmethod
    def create(cls) -> "FeatureState":
        return cls(memory=AgentMemory())

    def reset(self, *, task_id: str | None = None) -> None:
        self.memory.reset(task_id=task_id)

    def encode(self, obs: Any, info: dict[str, Any] | None = None) -> np.ndarray:
        state = perceive(obs, self.memory, info)
        return encode_state(state, info)


def encode_state(state: SymbolicState, info: dict[str, Any] | None = None) -> np.ndarray:
    grid = np.zeros((GRID_HEIGHT, GRID_WIDTH), dtype=np.float32)
    _fill(grid, state.walls, 1)
    _fill(grid, state.chests, 2)
    _fill(grid, state.monsters, 3)
    _fill(grid, state.exits, 4)
    _fill(grid, state.traps, 5)
    _fill(grid, state.buttons, 6)
    _fill(grid, state.switches, 7)
    _fill(grid, state.gaps, 8)
    _fill(grid, state.bridges, 9)
    _fill(grid, state.npcs, 10)
    grid[state.player[1], state.player[0]] = 0

    features: list[float] = (grid.reshape(-1) / (len(LABELS) - 1)).tolist()
    features.extend([state.player[0] / (GRID_WIDTH - 1), state.player[1] / (GRID_HEIGHT - 1)])

    monsters = sorted(state.monsters, key=lambda pos: abs(pos[0] - state.player[0]) + abs(pos[1] - state.player[1]))[:4]
    for index in range(4):
        if index < len(monsters):
            mx, my = monsters[index]
            features.extend([mx / (GRID_WIDTH - 1), my / (GRID_HEIGHT - 1)])
        else:
            features.extend([-1.0, -1.0])

    inventory = _inventory(info, state)
    features.extend(
        [
            min(inventory["keys"], 3) / 3.0,
            min(inventory["gold"], 10) / 10.0,
            1.0 if inventory["has_sword"] else 0.0,
            1.0 if inventory["has_shield"] else 0.0,
            min(inventory["hp"], 5) / 5.0,
            1.0 if inventory["has_potion"] else 0.0,
        ]
    )
    return np.asarray(features, dtype=np.float32)


def _fill(grid: np.ndarray, positions: set[tuple[int, int]], value: int) -> None:
    for col, row in positions:
        if 0 <= col < GRID_WIDTH and 0 <= row < GRID_HEIGHT:
            grid[row, col] = value


def _inventory(info: dict[str, Any] | None, state: SymbolicState) -> dict[str, Any]:
    result = {
        "keys": int(state.keys),
        "gold": 0,
        "hp": int(state.health or 5),
        "has_sword": bool(state.has_sword),
        "has_shield": bool(state.has_shield),
        "has_potion": False,
    }
    if not isinstance(info, dict):
        return result
    inventory = info.get("inventory", {})
    if isinstance(inventory, dict):
        try:
            result["gold"] = int(inventory.get("gold", result["gold"]))
        except (TypeError, ValueError):
            pass
        text = f"{inventory.get('equipped', {})} {inventory.get('items', [])}".lower()
        result["has_potion"] = "potion" in text or "heal" in text
    return result
