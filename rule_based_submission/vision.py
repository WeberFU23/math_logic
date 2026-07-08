from __future__ import annotations

from collections import Counter
from typing import Any

import numpy as np

from rule_based_submission.symbolic import (
    GRID_HEIGHT,
    GRID_WIDTH,
    TILE_SIZE,
    AgentMemory,
    Position,
    SymbolicState,
)


Color = tuple[int, int, int]

OUTLINE = (8, 8, 16)
HIGHLIGHT = (255, 244, 112)
SHADOW = (42, 45, 88)
PLAYER_COLORS: set[Color] = {(36, 198, 72), (126, 248, 82)}
WALL_COLORS: set[Color] = {(255, 86, 146), (219, 18, 82), (88, 0, 36), (255, 44, 112)}
CHEST_WOOD = (152, 82, 36)
CHEST_OPEN_INNER = (42, 18, 16)
MONSTER_COLORS: set[Color] = {(238, 126, 28), (255, 180, 48), (200, 78, 16), (126, 44, 0)}
NPC_COLOR = (240, 154, 52)
TRAP_COLORS: set[Color] = {(238, 238, 236), (112, 112, 126), (0, 0, 0)}
EXIT_COLORS: set[Color] = {OUTLINE, HIGHLIGHT, SHADOW, (96, 48, 26), (255, 216, 80)}
BUTTON_COLORS: set[Color] = {(40, 190, 74), (28, 112, 52), (86, 146, 104)}
SWITCH_COLORS: set[Color] = {(255, 216, 80), (184, 124, 42)}
GAP_COLORS: set[Color] = {(16, 22, 48), (0, 0, 0)}
BRIDGE_COLORS: set[Color] = {(172, 104, 48), (96, 48, 26)}


def perceive(obs: Any, memory: AgentMemory, info: dict[str, Any] | None = None) -> SymbolicState:
    frame = _frame_from_obs(obs)
    grid_frame = frame[: GRID_HEIGHT * TILE_SIZE, : GRID_WIDTH * TILE_SIZE, :]

    walls: set[Position] = set()
    chests: set[Position] = set()
    monsters: set[Position] = set()
    exits: set[Position] = set()
    traps: set[Position] = set()
    buttons: set[Position] = set()
    switches: set[Position] = set()
    gaps: set[Position] = set()
    bridges: set[Position] = set()
    npcs: set[Position] = set()
    player: Position | None = None

    for row in range(GRID_HEIGHT):
        for col in range(GRID_WIDTH):
            tile = grid_frame[row * TILE_SIZE : (row + 1) * TILE_SIZE, col * TILE_SIZE : (col + 1) * TILE_SIZE]
            pos = (col, row)
            counts = _color_counts(tile)

            if _count_any(counts, PLAYER_COLORS) >= 10:
                player = pos
            if _count_any(counts, WALL_COLORS) >= 60:
                walls.add(pos)
            if _is_chest(counts):
                chests.add(pos)
            if _count_any(counts, MONSTER_COLORS) >= 16:
                monsters.add(pos)
            if _is_trap(counts):
                traps.add(pos)
            if _is_exit(counts, pos):
                exits.add(pos)
            if _is_switch(counts):
                switches.add(pos)
            elif _is_button(counts):
                buttons.add(pos)
            if _count_any(counts, GAP_COLORS) >= 80:
                gaps.add(pos)
            if _count_any(counts, BRIDGE_COLORS) >= 45 and _count_any(counts, {CHEST_WOOD}) < 20:
                bridges.add(pos)
            if counts.get(NPC_COLOR, 0) >= 40:
                npcs.add(pos)

    if player is None:
        player = _fallback_player(memory)

    room = memory.room
    exits = exits - walls - chests - traps
    if memory.switch_cooldown > 0:
        switches.clear()
        buttons.clear()
    keys, has_sword, has_shield = _inventory(info, memory)
    health = _health(info, frame)
    return SymbolicState(
        player=player,
        room=room,
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


def _frame_from_obs(obs: Any) -> np.ndarray:
    if isinstance(obs, dict):
        if "frame" in obs:
            obs = obs["frame"]
        elif "pixels" in obs:
            obs = obs["pixels"]
    frame = np.asarray(obs)
    if frame.ndim != 3 or frame.shape[2] < 3:
        raise ValueError(f"expected an RGB frame, got shape {frame.shape!r}")
    return frame[:, :, :3].astype(np.uint8, copy=False)


def _color_counts(tile: np.ndarray) -> Counter[Color]:
    flat = tile.reshape(-1, 3)
    return Counter(tuple(int(channel) for channel in pixel) for pixel in flat)


def _count_any(counts: Counter[Color], colors: set[Color]) -> int:
    return sum(counts.get(color, 0) for color in colors)


def _is_chest(counts: Counter[Color]) -> bool:
    return counts.get(CHEST_WOOD, 0) >= 35 and counts.get(OUTLINE, 0) >= 15


def _is_trap(counts: Counter[Color]) -> bool:
    spike = counts.get((238, 238, 236), 0) + counts.get((112, 112, 126), 0)
    abyss = counts.get((0, 0, 0), 0)
    return spike >= 12 or abyss >= 180


def _is_exit(counts: Counter[Color], pos: Position) -> bool:
    col, row = pos
    if col not in {0, GRID_WIDTH - 1} and row not in {0, GRID_HEIGHT - 1}:
        return False
    exit_pixels = _count_any(counts, EXIT_COLORS)
    # Normal doors are mostly outline/shadow/highlight, locked/conditional doors add wood/yellow.
    return exit_pixels >= 55 and counts.get(OUTLINE, 0) >= 20


def _is_button(counts: Counter[Color]) -> bool:
    return _count_any(counts, BUTTON_COLORS) >= 20 and counts.get(OUTLINE, 0) >= 15


def _is_switch(counts: Counter[Color]) -> bool:
    return _count_any(counts, SWITCH_COLORS) >= 28 and counts.get(OUTLINE, 0) >= 20


def _fallback_player(memory: AgentMemory) -> Position:
    return (4, 4)


def _inventory(info: dict[str, Any] | None, memory: AgentMemory) -> tuple[int, bool, bool]:
    keys = memory.previous_keys
    has_sword = memory.has_sword
    has_shield = memory.has_shield
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
    return keys, has_sword, has_shield


def _health(info: dict[str, Any] | None, frame: np.ndarray) -> int | None:
    if isinstance(info, dict):
        agent = info.get("agent", {})
        if isinstance(agent, dict) and "hp" in agent:
            try:
                return int(agent["hp"])
            except (TypeError, ValueError):
                pass
    return _extract_health_from_hud(frame)


def _extract_health_from_hud(frame: np.ndarray) -> int | None:
    hud = frame[GRID_HEIGHT * TILE_SIZE :, :, :]
    heart_pixels = np.all(hud == np.array((172, 8, 64), dtype=np.uint8), axis=2).sum()
    if heart_pixels <= 0:
        return None
    return max(1, int(round(heart_pixels / 18)))



