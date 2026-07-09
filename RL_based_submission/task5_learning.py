"""Learnable, map-agnostic high-level interface for the timed chest task.

Unlike the legacy seven-option interface, exits are separate directional
actions.  PPO therefore chooses the route; the resolver only checks whether a
requested action is currently executable and converts it to a BFS goal.
"""

from __future__ import annotations

from dataclasses import replace
from enum import IntEnum

import numpy as np

from rule_based_submission.planner import bfs_path, goal_tiles, is_reachable
from rule_based_submission.symbolic import AgentMemory, Goal, GoalKind, SymbolicState, globalize, manhattan

from RL_based_submission.high_level_core import GRID_HEIGHT, GRID_WIDTH


class Task5Action(IntEnum):
    OPEN_CHEST = 0
    ATTACK_MONSTER = 1
    ACTIVATE_MECHANISM = 2
    EXIT_NORTH = 3
    EXIT_EAST = 4
    EXIT_SOUTH = 5
    EXIT_WEST = 6
    EXPLORE_ROOM = 7
    WAIT = 8


TASK5_ACTION_COUNT = len(Task5Action)
TASK5_FEATURE_DIM = 122


class Task5GoalResolver:
    action_count = TASK5_ACTION_COUNT
    feature_dim = TASK5_FEATURE_DIM

    @staticmethod
    def action_name(action: int) -> str:
        return Task5Action(int(action)).name

    @staticmethod
    def is_attack(action: int) -> bool:
        return int(action) == int(Task5Action.ATTACK_MONSTER)

    def action_mask(self, state: SymbolicState, memory: AgentMemory) -> np.ndarray:
        mask = np.asarray(
            [self.resolve(action, state, memory) is not None for action in Task5Action],
            dtype=bool,
        )
        direction_options = (
            Task5Action.EXIT_NORTH, Task5Action.EXIT_EAST,
            Task5Action.EXIT_SOUTH, Task5Action.EXIT_WEST,
        )
        used_direction: dict[Task5Action, bool] = {}
        for option in direction_options:
            goal = self.resolve(option, state, memory)
            used_direction[option] = bool(
                goal is not None
                and goal.target is not None
                and globalize(state.room, goal.target) in memory.used_exits
            )
        has_new_exit = any(
            mask[int(option)] and not used_direction[option]
            for option in direction_options
        )
        has_used_exit = any(
            mask[int(option)] and used_direction[option]
            for option in direction_options
        )
        local_resource = bool(
            mask[int(Task5Action.OPEN_CHEST)]
            or mask[int(Task5Action.ACTIVATE_MECHANISM)]
        )
        attack_is_progress = self.attack_is_progress(state, memory)

        # Generic door semantics.  A key makes locked frontiers urgent; without
        # such a frontier, conditional doors outrank ordinary exits.  This uses
        # visually classified door types, not room coordinates.
        locked_directions = self._directions_for_exit_type(
            state, memory, direction_options, mask, state.locked_exits
        ) if state.keys > 0 else set()
        conditional_directions = self._directions_for_exit_type(
            state, memory, direction_options, mask, state.conditional_exits
        )
        preferred_directions = locked_directions or conditional_directions
        if preferred_directions:
            for option in direction_options:
                if option not in preferred_directions:
                    mask[int(option)] = False
            has_new_exit = True
        # Generic anti-loop constraint: do not immediately backtrack when an
        # unseen frontier or an unfinished local resource exists.  PPO still
        # chooses freely among every new direction and whether combat is useful.
        if has_new_exit or local_resource:
            for option in direction_options:
                if used_direction[option]:
                    mask[int(option)] = False
        # Do not abandon a visibly unfinished room.  This is deliberately
        # content- and coordinate-agnostic; PPO still chooses the ordering of
        # local goals and, once they are done, the next compass direction.
        if local_resource:
            for option in direction_options:
                mask[int(option)] = False
            if mask[int(Task5Action.OPEN_CHEST)] and not attack_is_progress:
                mask[int(Task5Action.ACTIVATE_MECHANISM)] = False
            if not attack_is_progress:
                mask[int(Task5Action.ATTACK_MONSTER)] = False
            elif mask[int(Task5Action.ATTACK_MONSTER)]:
                # If a monster blocks the route to visible local progress,
                # clear it before trying to interact.  If the monster is merely
                # elsewhere in the room, attacking is masked out above.
                mask[int(Task5Action.OPEN_CHEST)] = False
                mask[int(Task5Action.ACTIVATE_MECHANISM)] = False
        # Once a leaf room's resources are finished, fighting cannot reveal
        # further progress.  Returning strictly dominates optional cleanup.
        if not local_resource and not has_new_exit and has_used_exit and not attack_is_progress:
            mask[int(Task5Action.ATTACK_MONSTER)] = False
        elif (has_new_exit or has_used_exit) and not attack_is_progress:
            # When a room has no unfinished local resource, visible monsters
            # are optional cleanup.  Exits are the only generic source of new
            # information/progress; combat remains available in resource rooms
            # above, where a nearby monster can actually block interaction.
            mask[int(Task5Action.ATTACK_MONSTER)] = False
        # Exploration and waiting are recovery actions.  This is a generic
        # legality guard, not a route choice: PPO remains free to choose among
        # chests, combat, mechanisms, and every reachable door direction.
        if bool(mask[: int(Task5Action.EXPLORE_ROOM)].any()):
            mask[int(Task5Action.EXPLORE_ROOM)] = False
            mask[int(Task5Action.WAIT)] = False
        elif mask[int(Task5Action.EXPLORE_ROOM)]:
            mask[int(Task5Action.WAIT)] = False
        if not bool(mask.any()):
            mask[int(Task5Action.WAIT)] = True
        return mask

    def attack_is_progress(self, state: SymbolicState, memory: AgentMemory) -> bool:
        """Return True when a monster is an obstacle to visible progress.

        This is intentionally geometric rather than task-scripted: remove
        monsters from the map, compute a shortest path to unfinished resources
        or usable exits, and check whether a monster lies on or adjacent to that
        corridor.  Such monsters are worth killing; distant optional monsters
        are not.
        """

        if not state.has_sword or not state.monsters:
            return False
        has_unfinished_resource = any(
            globalize(state.room, pos) not in memory.opened_chests
            for pos in state.chests
        ) or any(
            globalize(state.room, pos) not in memory.activated_switches
            for pos in state.buttons
        ) or any(
            globalize(state.room, pos) not in memory.visit_activated_switches
            for pos in state.switches
        )
        if has_unfinished_resource and any(manhattan(state.player, monster) <= 2 for monster in state.monsters):
            return True
        targets: list[Goal] = []
        for pos in state.chests:
            if globalize(state.room, pos) not in memory.opened_chests:
                targets.append(Goal(GoalKind.OPEN_CHEST, pos))
        for pos in state.buttons:
            if globalize(state.room, pos) not in memory.activated_switches:
                targets.append(Goal(GoalKind.PRESS_BUTTON, pos))
        for pos in state.switches:
            if globalize(state.room, pos) not in memory.visit_activated_switches:
                targets.append(Goal(GoalKind.ACTIVATE_SWITCH, pos))
        for pos in state.all_exits:
            if self._usable(pos, state):
                targets.append(Goal(GoalKind.GO_TO_EXIT, pos))

        open_state = replace(state, monsters=set())
        for goal in targets:
            if (
                goal.kind in {GoalKind.OPEN_CHEST, GoalKind.ACTIVATE_SWITCH, GoalKind.PRESS_BUTTON}
                and goal.target is not None
                and any(manhattan(goal.target, monster) <= 2 for monster in state.monsters)
            ):
                return True
            path = bfs_path(open_state, goal_tiles(goal, open_state))
            if path and self._path_blocked_by_monster(path, state.monsters):
                return True
        return False

    def resolve(self, action: int | Task5Action, state: SymbolicState, memory: AgentMemory) -> Goal | None:
        option = Task5Action(int(action))
        if option == Task5Action.WAIT:
            return Goal(GoalKind.WAIT)
        if option == Task5Action.OPEN_CHEST:
            positions = {
                pos for pos in state.chests
                if globalize(state.room, pos) not in memory.opened_chests
            }
            return self._nearest(state, GoalKind.OPEN_CHEST, positions)
        if option == Task5Action.ATTACK_MONSTER:
            return None if not state.has_sword else self._nearest(
                state, GoalKind.ATTACK_MONSTER, set(state.monsters)
            )
        if option == Task5Action.ACTIVATE_MECHANISM:
            buttons = {
                pos for pos in state.buttons
                if globalize(state.room, pos) not in memory.activated_switches
            }
            goal = self._nearest(state, GoalKind.PRESS_BUTTON, buttons)
            if goal is not None:
                return goal
            switches = {
                pos for pos in state.switches
                if globalize(state.room, pos) not in memory.visit_activated_switches
            }
            return self._nearest(state, GoalKind.ACTIVATE_SWITCH, switches)
        if option in {
            Task5Action.EXIT_NORTH,
            Task5Action.EXIT_EAST,
            Task5Action.EXIT_SOUTH,
            Task5Action.EXIT_WEST,
        }:
            positions = {
                pos for pos in state.all_exits
                if self._on_side(pos, option) and self._usable(pos, state)
            }
            return self._nearest(state, GoalKind.GO_TO_EXIT, positions)
        if option == Task5Action.EXPLORE_ROOM:
            target = self._exploration_target(state)
            return None if target is None else Goal(GoalKind.EXPLORE, target)
        return None

    @staticmethod
    def _on_side(pos: tuple[int, int], option: Task5Action) -> bool:
        col, row = pos
        return bool(
            (option == Task5Action.EXIT_NORTH and row == 0)
            or (option == Task5Action.EXIT_EAST and col == GRID_WIDTH - 1)
            or (option == Task5Action.EXIT_SOUTH and row == GRID_HEIGHT - 1)
            or (option == Task5Action.EXIT_WEST and col == 0)
        )

    def _directions_for_exit_type(
        self,
        state: SymbolicState,
        memory: AgentMemory,
        direction_options: tuple[Task5Action, ...],
        mask: np.ndarray,
        exits: set[tuple[int, int]],
    ) -> set[Task5Action]:
        return {
            option for option in direction_options
            if mask[int(option)]
            and any(
                pos in exits
                and self._on_side(pos, option)
                and self._usable(pos, state)
                and globalize(state.room, pos) not in memory.used_exits
                for pos in state.all_exits
            )
        }

    @staticmethod
    def _usable(pos: tuple[int, int], state: SymbolicState) -> bool:
        # Key possession is explicitly allowed inventory information.  Other
        # door requirements are deliberately not guessed from a known map: a
        # failed attempt remains experience from which PPO can learn.
        return not (pos in state.locked_exits and state.keys <= 0)

    @staticmethod
    def _nearest(
        state: SymbolicState,
        kind: GoalKind,
        positions: set[tuple[int, int]],
    ) -> Goal | None:
        goals = [Goal(kind, pos) for pos in positions]
        goals = [goal for goal in goals if is_reachable(state, goal) or state.player == goal.target]
        if not goals:
            return None
        return min(goals, key=lambda goal: (manhattan(state.player, goal.target or state.player), goal.target))

    @staticmethod
    def _path_blocked_by_monster(path: list[tuple[int, int]], monsters: set[tuple[int, int]]) -> bool:
        return bool((set(path) - {path[0]}) & monsters)

    @staticmethod
    def _exploration_target(state: SymbolicState) -> tuple[int, int] | None:
        blockers = state.walls | state.traps | state.gaps | state.chests | state.monsters
        candidates: list[tuple[int, tuple[int, int]]] = []
        for row in range(GRID_HEIGHT):
            for col in range(GRID_WIDTH):
                pos = (col, row)
                if pos == state.player or pos in blockers or pos in state.all_exits:
                    continue
                path = bfs_path(state, {pos})
                if path is not None:
                    candidates.append((len(path), pos))
        return None if not candidates else max(candidates, key=lambda item: (item[0], item[1]))[1]


def encode_task5_state(
    state: SymbolicState,
    memory: AgentMemory,
    *,
    inventory: tuple[int, int, bool, bool, bool],
    action_mask: np.ndarray,
    last_option: int | None,
    elapsed_steps: int,
) -> np.ndarray:
    grid = np.zeros((GRID_HEIGHT, GRID_WIDTH), dtype=np.float32)
    for positions, value in (
        (state.walls, 1), (state.chests, 2), (state.monsters, 3),
        (state.normal_exits, 4), (state.locked_exits, 5), (state.conditional_exits, 6),
        (state.traps, 7), (state.buttons | state.switches, 8), (state.gaps, 9),
        (state.bridges, 10), (state.npcs, 11),
    ):
        for col, row in positions:
            if 0 <= col < GRID_WIDTH and 0 <= row < GRID_HEIGHT:
                grid[row, col] = value
    if 0 <= state.player[0] < GRID_WIDTH and 0 <= state.player[1] < GRID_HEIGHT:
        grid[state.player[1], state.player[0]] = 0

    features: list[float] = (grid.reshape(-1) / 11.0).tolist()
    features.extend([state.player[0] / 9.0, state.player[1] / 7.0])
    monsters = sorted(state.monsters, key=lambda pos: (manhattan(pos, state.player), pos))[:4]
    for index in range(4):
        features.extend(
            [monsters[index][0] / 9.0, monsters[index][1] / 7.0]
            if index < len(monsters) else [-1.0, -1.0]
        )
    keys, gold, has_sword, has_shield, has_heal = inventory
    features.extend([min(keys, 3) / 3.0, min(gold, 10) / 10.0,
                     float(has_sword), float(has_shield), float(has_heal)])
    features.extend(action_mask.astype(np.float32).tolist())
    last = np.zeros(TASK5_ACTION_COUNT, dtype=np.float32)
    if last_option is not None and 0 <= last_option < TASK5_ACTION_COUNT:
        last[last_option] = 1.0
    features.extend(last.tolist())
    features.extend([
        min(len(memory.room_memory), 10) / 10.0,
        min(len(memory.opened_chests), 10) / 10.0,
        min(len(memory.killed_monsters), 10) / 10.0,
        min(len(memory.activated_switches), 10) / 10.0,
        min(len(memory.used_exits), 20) / 20.0,
        min(memory.room_steps, 50) / 50.0,
        float(np.clip(memory.room[0] / 4.0, -1.0, 1.0)),
        float(np.clip(memory.room[1] / 4.0, -1.0, 1.0)),
        min(elapsed_steps, 1080) / 1080.0,
    ])
    encoded = np.asarray(features, dtype=np.float32)
    if encoded.shape != (TASK5_FEATURE_DIM,):
        raise RuntimeError(f"task-5 feature shape mismatch: {encoded.shape}")
    return encoded
