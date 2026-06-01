from __future__ import annotations

import sys
from collections import deque
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import numpy as np

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from nesylink.core.constants import (
    ACTION_A,
    ACTION_B,
    ACTION_DOWN,
    ACTION_LEFT,
    ACTION_NOOP,
    ACTION_RIGHT,
    ACTION_UP,
    TILE_SIZE,
)
from nesylink.env import make_env


TILE_WALL = 1
TILE_MONSTER = 3
TILE_CHEST = 4
TILE_EXIT = 5
TILE_TRAP = 6

Position = tuple[int, int]


@dataclass(frozen=True)
class SymbolicState:
    player: Position
    exits: set[Position]
    walls: set[Position]
    traps: set[Position]
    monsters: set[Position]
    chests: set[Position]
    health: int
    keys: int


def as_int(value) -> int:
    return int(np.asarray(value).reshape(-1)[0])


def as_position(value) -> Position:
    arr = np.asarray(value).reshape(-1)
    return int(arr[0]), int(arr[1])


def find_tiles(grid: np.ndarray, tile_value: int) -> set[Position]:
    rows, cols = grid.shape
    return {
        (col, row)
        for row in range(rows)
        for col in range(cols)
        if int(grid[row, col]) == tile_value
    }


def extract_symbolic_state(obs: dict) -> SymbolicState:
    grid = np.asarray(obs["grid"])
    return SymbolicState(
        player=as_position(obs["player_tile"]),
        exits=find_tiles(grid, TILE_EXIT),
        walls=find_tiles(grid, TILE_WALL),
        traps=find_tiles(grid, TILE_TRAP),
        monsters=find_tiles(grid, TILE_MONSTER),
        chests=find_tiles(grid, TILE_CHEST),
        health=as_int(obs["health"]),
        keys=as_int(obs["keys"]),
    )


def neighbors(pos: Position) -> Iterable[Position]:
    col, row = pos
    yield (col, row - 1)
    yield (col, row + 1)
    yield (col - 1, row)
    yield (col + 1, row)


def in_bounds(pos: Position, width: int = 10, height: int = 8) -> bool:
    col, row = pos
    return 0 <= col < width and 0 <= row < height


def manhattan(left: Position, right: Position) -> int:
    return abs(left[0] - right[0]) + abs(left[1] - right[1])


def danger_tiles(state: SymbolicState) -> set[Position]:
    return set(state.monsters)


def is_walkable(pos: Position, state: SymbolicState, *, avoid_dynamic: bool = True) -> bool:
    if not in_bounds(pos):
        return False
    if pos in state.walls or pos in state.traps or pos in state.monsters or pos in state.chests:
        return False
    if avoid_dynamic and pos in danger_tiles(state):
        return False
    return True


def bfs_path_to_goal(state: SymbolicState, goals: set[Position]) -> list[Position] | None:
    queue: deque[Position] = deque([state.player])
    parent: dict[Position, Position | None] = {state.player: None}

    while queue:
        current = queue.popleft()
        if current in goals:
            path: list[Position] = []
            while current is not None:
                path.append(current)
                current = parent[current]
            path.reverse()
            return path

        for nxt in neighbors(current):
            if nxt in parent:
                continue
            if not is_walkable(nxt, state) and nxt not in goals:
                continue
            if nxt in danger_tiles(state):
                continue
            parent[nxt] = current
            queue.append(nxt)

    return None


def action_from_step(current: Position, nxt: Position) -> int:
    col, row = current
    next_col, next_row = nxt
    if next_col == col and next_row == row - 1:
        return ACTION_UP
    if next_col == col and next_row == row + 1:
        return ACTION_DOWN
    if next_col == col - 1 and next_row == row:
        return ACTION_LEFT
    if next_col == col + 1 and next_row == row:
        return ACTION_RIGHT
    raise ValueError(f"non-adjacent step: {current} -> {nxt}")


def next_position(current: Position, action: int) -> Position:
    col, row = current
    if action == ACTION_UP:
        return (col, row - 1)
    if action == ACTION_DOWN:
        return (col, row + 1)
    if action == ACTION_LEFT:
        return (col - 1, row)
    if action == ACTION_RIGHT:
        return (col + 1, row)
    return current


def move_one_tile(env, obs: dict, current_tile: Position, next_tile: Position):
    action = action_from_step(current_tile, next_tile)
    target_px = np.array([next_tile[0] * TILE_SIZE, next_tile[1] * TILE_SIZE], dtype=np.float32)
    axis = 0 if action in {ACTION_LEFT, ACTION_RIGHT} else 1
    total_reward = 0.0
    info = {}

    for _ in range(TILE_SIZE * 5):
        current_px = np.asarray(obs["player_position_px"], dtype=np.float32)
        if action == ACTION_UP and current_px[axis] <= target_px[axis]:
            return obs, total_reward, False, False, info
        if action == ACTION_DOWN and current_px[axis] >= target_px[axis]:
            return obs, total_reward, False, False, info
        if action == ACTION_LEFT and current_px[axis] <= target_px[axis]:
            return obs, total_reward, False, False, info
        if action == ACTION_RIGHT and current_px[axis] >= target_px[axis]:
            return obs, total_reward, False, False, info

        obs, reward, terminated, truncated, info = env.step(action)
        total_reward += float(reward)
        if terminated or truncated:
            return obs, total_reward, terminated, truncated, info

    return obs, total_reward, False, False, info


class SymbolicAgent:
    def adjacent_monster(self, state: SymbolicState) -> Position | None:
        for monster in state.monsters:
            if manhattan(state.player, monster) == 1:
                return monster
        return None

    def monster_goal_tiles(self, state: SymbolicState, monster: Position) -> set[Position]:
        return {pos for pos in neighbors(monster) if is_walkable(pos, state, avoid_dynamic=False)}

    def chest_goal_tiles(self, state: SymbolicState) -> set[Position]:
        chest = next(iter(state.chests))
        return {pos for pos in neighbors(chest) if is_walkable(pos, state)}

    def select_goals(self, state: SymbolicState, fixed_exits: set[Position]) -> set[Position]:
        if state.monsters:
            monster = min(state.monsters, key=lambda item: manhattan(state.player, item))
            return self.monster_goal_tiles(state, monster)
        if state.keys == 0 and state.chests:
            return self.chest_goal_tiles(state)
        return fixed_exits

    def act(self, state: SymbolicState, fixed_exits: set[Position]) -> int:
        monster = self.adjacent_monster(state)
        if monster is not None:
            if state.health > 1:
                return ACTION_A
            return ACTION_B

        goals = self.select_goals(state, fixed_exits)
        path = bfs_path_to_goal(state, goals)
        if path and len(path) > 1:
            return action_from_step(path[0], path[1])

        if state.keys == 0 and state.chests:
            return ACTION_A
        return ACTION_NOOP


def run(seed: int = 0, max_steps: int = 500) -> dict:
    env = make_env(task_id="task_2")
    obs, info = env.reset(seed=seed)
    agent = SymbolicAgent()
    fixed_exits = extract_symbolic_state(obs).exits
    total_reward = 0.0
    trace = []
    terminated = False
    truncated = False

    try:
        for step_index in range(1, max_steps + 1):
            state = extract_symbolic_state(obs)
            action = agent.act(state, fixed_exits)

            if action in {ACTION_UP, ACTION_DOWN, ACTION_LEFT, ACTION_RIGHT}:
                obs, reward, terminated, truncated, info = move_one_tile(
                    env,
                    obs,
                    state.player,
                    next_position(state.player, action),
                )
            else:
                obs, reward, terminated, truncated, info = env.step(action)

            total_reward += float(reward)
            next_state = extract_symbolic_state(obs)
            trace.append(
                {
                    "step": step_index,
                    "action": action,
                    "player_before": state.player,
                    "player_after": next_state.player,
                    "health": next_state.health,
                    "keys": next_state.keys,
                    "monsters_remaining": len(next_state.monsters),
                    "events": info.get("events", {}).get("records", []),
                }
            )

            if terminated or truncated:
                break
    finally:
        env.close()

    final_state = extract_symbolic_state(obs)
    return {
        "task_id": "task_2",
        "steps": len(trace),
        "total_reward": total_reward,
        "terminated": terminated,
        "truncated": truncated,
        "terminal_reason": info.get("terminal_reason"),
        "world_completed": info.get("game", {}).get("world_completed"),
        "final_tile": final_state.player,
        "final_health": final_state.health,
        "final_keys": final_state.keys,
        "trace": trace,
    }


if __name__ == "__main__":
    result = run()
    print(
        {
            "task_id": result["task_id"],
            "steps": result["steps"],
            "total_reward": result["total_reward"],
            "terminated": result["terminated"],
            "truncated": result["truncated"],
            "terminal_reason": result["terminal_reason"],
            "world_completed": result["world_completed"],
            "final_tile": result["final_tile"],
            "final_health": result["final_health"],
            "final_keys": result["final_keys"],
        }
    )
