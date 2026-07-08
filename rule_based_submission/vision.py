from __future__ import annotations

from typing import Any

import numpy as np

from RL_based_submission.vision_extractor import (
    ABYSS,
    BRIDGE,
    BUTTON,
    BUTTON_PRESSED,
    CHEST,
    GAP,
    MAP_HEIGHT_TILES,
    MAP_WIDTH_TILES,
    NPC,
    SWITCH,
    SWITCH_PRESSED,
    TRAP,
    UNKNOWN,
    WALL,
    VisionExtractor,
)

from rule_based_submission.symbolic import AgentMemory, Position, SymbolicState


_extractor = VisionExtractor(use_memory=True)


def reset_vision() -> None:
    _extractor.reset()


def perceive(
    obs: Any, memory: AgentMemory, info: dict[str, Any] | None = None
) -> SymbolicState:
    frame = _map_frame(obs)
    symbolic = _extractor.extract(frame)
    static = symbolic.static  # (8, 10) grid of string labels

    walls: set[Position] = set()
    chests: set[Position] = set()
    exits: set[Position] = set()
    traps: set[Position] = set()
    buttons: set[Position] = set()
    switches: set[Position] = set()
    gaps: set[Position] = set()
    bridges: set[Position] = set()
    npcs: set[Position] = set()

    for row in range(MAP_HEIGHT_TILES):
        for col in range(MAP_WIDTH_TILES):
            label = static[row, col]
            pos = (col, row)
            if label == WALL:
                walls.add(pos)
            elif label == CHEST:
                chests.add(pos)
            elif label in (TRAP, ABYSS):
                traps.add(pos)
            elif label in (BUTTON, BUTTON_PRESSED):
                buttons.add(pos)
            elif label in (SWITCH, SWITCH_PRESSED):
                switches.add(pos)
            elif label == NPC:
                npcs.add(pos)
            elif label == GAP:
                gaps.add(pos)
            elif label == BRIDGE:
                bridges.add(pos)
            elif label.startswith("exit_"):
                exits.add(pos)

    # Player --- anchor tile from pixel centre
    if symbolic.player is not None:
        player: Position = symbolic.player.anchor_tile
    else:
        player = (4, 4)

    # Monsters --- one anchor tile per dynamic entity
    monsters: set[Position] = set()
    for monster in symbolic.monsters:
        monsters.add(monster.anchor_tile)

    # Clean up overlaps
    exits = exits - walls - chests - traps

    keys, has_sword, has_shield, health = _inventory(info, memory)

    return SymbolicState(
        player=player,
        room=memory.room,
        walls=walls,
        chests=chests,
        monsters=monsters,
        exits=exits,
        traps=traps,
        buttons=buttons,
        switches=switches,
        bridges=bridges,
        gaps=gaps - bridges,
        npcs=npcs,
        keys=keys,
        health=health,
        has_sword=has_sword,
        has_shield=has_shield,
    )


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def _map_frame(obs: Any) -> np.ndarray:
    frame = np.asarray(obs)
    if frame.ndim == 4:
        frame = frame[0]
    if frame.ndim != 3 or frame.shape[2] < 3:
        raise ValueError(f"expected RGB observation, got shape {frame.shape}")
    return frame[: MAP_HEIGHT_TILES * 16, : MAP_WIDTH_TILES * 16, :3].astype(
        np.uint8, copy=False
    )


def _inventory(
    info: dict[str, Any] | None, memory: AgentMemory
) -> tuple[int, bool, bool, int | None]:
    keys = memory.previous_keys
    has_sword = memory.has_sword
    has_shield = memory.has_shield
    health: int | None = None
    if isinstance(info, dict):
        inventory = info.get("inventory", {})
        if isinstance(inventory, dict):
            if "keys" in inventory:
                try:
                    keys = max(0, int(inventory["keys"]) - memory.spent_keys)
                except (TypeError, ValueError):
                    pass
            equipped = inventory.get("equipped", {})
            items = inventory.get("items", [])
            text = f"{equipped} {items}".lower()
            has_sword = has_sword or "sword" in text
            has_shield = has_shield or "shield" in text
        agent = info.get("agent", {})
        if isinstance(agent, dict) and "hp" in agent:
            try:
                health = int(agent["hp"])
            except (TypeError, ValueError):
                pass
    return keys, has_sword, has_shield, health
