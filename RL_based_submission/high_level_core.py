from __future__ import annotations

from enum import IntEnum

import numpy as np

from rule_based_submission.planner import bfs_path, is_reachable
from rule_based_submission.executor import action_for_goal
from rule_based_submission.strategy import RuleBasedPolicy
from rule_based_submission.symbolic import (
    AgentMemory,
    ACTION_A,
    ACTION_B,
    ACTION_DOWN,
    ACTION_LEFT,
    ACTION_RIGHT,
    ACTION_UP,
    Goal,
    GoalKind,
    SymbolicState,
    globalize,
    manhattan,
    action_from_step,
    next_position,
)


GRID_WIDTH = 10
GRID_HEIGHT = 8


class HighLevelAction(IntEnum):
    OPEN_CHEST = 0
    ATTACK_MONSTER = 1
    ACTIVATE_MECHANISM = 2
    TAKE_NEW_EXIT = 3
    RETURN_OR_REVISIT = 4
    EXPLORE_ROOM = 5
    WAIT = 6


ACTION_COUNT = len(HighLevelAction)
FEATURE_DIM = 115


def task5_defensive_action(state: SymbolicState, memory: AgentMemory) -> int | None:
    if memory.task_id != "mathematical_logic/task_5" or not state.has_shield:
        return None
    if any(manhattan(state.player, monster) <= 2 for monster in state.monsters):
        return ACTION_B
    return None


def unstick_nudge(state: SymbolicState, blocked_action: int) -> int | None:
    """Choose a short perpendicular pixel nudge after a visually stalled move."""

    col, row = state.player
    blockers = state.walls | state.npcs | state.chests | state.monsters
    if blocked_action in {ACTION_UP, ACTION_DOWN}:
        next_row = row - 1 if blocked_action == ACTION_UP else row + 1
        if (col + 1, row) in blockers or (col + 1, next_row) in blockers:
            return ACTION_LEFT
        if (col - 1, row) in blockers or (col - 1, next_row) in blockers:
            return ACTION_RIGHT
        candidates = (ACTION_LEFT, ACTION_RIGHT)
    elif blocked_action in {ACTION_LEFT, ACTION_RIGHT}:
        next_col = col - 1 if blocked_action == ACTION_LEFT else col + 1
        if (col, row + 1) in blockers or (next_col, row + 1) in blockers:
            return ACTION_UP
        if (col, row - 1) in blockers or (next_col, row - 1) in blockers:
            return ACTION_DOWN
        candidates = (ACTION_UP, ACTION_DOWN)
    else:
        return None

    for candidate in candidates:
        target = next_position(state.player, candidate)
        if 0 <= target[0] < GRID_WIDTH and 0 <= target[1] < GRID_HEIGHT and target not in blockers:
            return candidate
    return None


def oriented_action_for_goal(
    state: SymbolicState,
    goal: Goal,
    memory: AgentMemory,
    *,
    skip_alignment: bool = False,
) -> tuple[int, bool]:
    """Return a primitive action and whether it is a one-pixel setup step.

    Interactions act in the player's facing direction.  If an adjacent target
    is not in that direction, first issue the blocked movement toward it; the
    game updates facing even though the occupied tile prevents translation.
    """

    if (
        goal.kind in {
            GoalKind.OPEN_CHEST,
            GoalKind.ATTACK_MONSTER,
            GoalKind.ACTIVATE_SWITCH,
        }
        and goal.target is not None
        and manhattan(state.player, goal.target) == 1
    ):
        desired_facing = action_from_step(state.player, goal.target)
        if memory.facing_action != desired_facing:
            return desired_facing, True
        return ACTION_A, False
    action = action_for_goal(state, goal)
    # When already standing on an exit tile the only valid move is to push
    # through the doorway.  Alignment at the exit boundary risks walking
    # into the adjacent wall (the pixel-level offset check in
    # _alignment_action can suggest DOWN/UP even though the neighbouring
    # tile in that direction is solid).
    if goal.kind == GoalKind.GO_TO_EXIT and state.player == goal.target:
        return action, False
    if skip_alignment:
        return action, False
    alignment = _alignment_action(state, action)
    if alignment is not None:
        return alignment, True
    return action, False


def _alignment_action(state: SymbolicState, intended_action: int) -> int | None:
    if state.player_position_px is None:
        return None
    left, top = state.player_position_px
    if intended_action in {ACTION_UP, ACTION_DOWN}:
        offset = int(round(left)) % 16
        if offset:
            return ACTION_LEFT if offset <= 8 else ACTION_RIGHT
    if intended_action in {ACTION_LEFT, ACTION_RIGHT}:
        offset = int(round(top)) % 16
        if offset:
            return ACTION_UP if offset <= 8 else ACTION_DOWN
    return None


class GoalResolver:
    """Turn a fixed high-level action into a concrete symbolic goal."""

    action_count = ACTION_COUNT
    feature_dim = FEATURE_DIM

    @staticmethod
    def action_name(action: int) -> str:
        return HighLevelAction(int(action)).name

    @staticmethod
    def is_attack(action: int) -> bool:
        return int(action) == int(HighLevelAction.ATTACK_MONSTER)

    def __init__(self) -> None:
        self._rule_helpers = RuleBasedPolicy()

    def action_mask(self, state: SymbolicState, memory: AgentMemory) -> np.ndarray:
        mask = np.asarray(
            [self.resolve(action, state, memory) is not None for action in HighLevelAction],
            dtype=bool,
        )

        new_exit = bool(mask[int(HighLevelAction.TAKE_NEW_EXIT)])
        local_progress = bool(
            mask[int(HighLevelAction.OPEN_CHEST)]
            or mask[int(HighLevelAction.ATTACK_MONSTER)]
            or mask[int(HighLevelAction.ACTIVATE_MECHANISM)]
        )

        # A reachable frontier dominates backtracking.  Keeping both choices
        # enabled allowed task 4 to bounce between west and center after the
        # first bridge rotation instead of taking the newly reachable east/south
        # branch.
        if new_exit:
            mask[int(HighLevelAction.RETURN_OR_REVISIT)] = False
        # If a room has concrete work but no frontier, do that work before
        # retreating through an old doorway (key-room return remains available
        # because its opened chest is filtered out by resolve()).
        elif local_progress:
            mask[int(HighLevelAction.RETURN_OR_REVISIT)] = False

        # Monsters are only obstacles, not objectives.  When there are chests or
        # mechanisms in the room, force the policy to deal with them first.
        # Combat reflex handles safety during movement so the agent never needs
        # to proactively hunt monsters.
        if mask[int(HighLevelAction.OPEN_CHEST)] or mask[int(HighLevelAction.ACTIVATE_MECHANISM)]:
            mask[int(HighLevelAction.ATTACK_MONSTER)] = False

        # EXPLORE and WAIT are recovery actions, not alternatives to known
        # progress.  Leaving them enabled beside a chest, monster, mechanism,
        # frontier exit, or required return lets PPO learn a locally cheap
        # deadlock (most visibly: WAIT forever after collecting task-4's key).
        if bool(mask[: int(HighLevelAction.EXPLORE_ROOM)].any()):
            mask[int(HighLevelAction.EXPLORE_ROOM)] = False
            mask[int(HighLevelAction.WAIT)] = False
        elif mask[int(HighLevelAction.EXPLORE_ROOM)]:
            mask[int(HighLevelAction.WAIT)] = False

        # WAIT is therefore enabled only when no concrete or exploratory goal
        # can be resolved.  Keep this final fallback so the mask is never empty.
        if not bool(mask.any()):
            mask[int(HighLevelAction.WAIT)] = True
        return mask

    def resolve(
        self,
        action: int | HighLevelAction,
        state: SymbolicState,
        memory: AgentMemory,
    ) -> Goal | None:
        option = HighLevelAction(int(action))
        if option == HighLevelAction.WAIT:
            return Goal(GoalKind.WAIT)

        if option == HighLevelAction.OPEN_CHEST:
            positions = {
                pos for pos in state.chests
                if globalize(state.room, pos) not in memory.opened_chests
            }
            return self._nearest_reachable(state, GoalKind.OPEN_CHEST, positions)

        if option == HighLevelAction.ATTACK_MONSTER:
            if not state.has_sword:
                return None
            positions = set(state.monsters)
            return self._nearest_reachable(state, GoalKind.ATTACK_MONSTER, positions)

        if option == HighLevelAction.ACTIVATE_MECHANISM:
            available_buttons = {
                pos for pos in state.buttons
                if globalize(state.room, pos) not in memory.activated_switches
            }
            button_goal = self._nearest_reachable(
                state, GoalKind.PRESS_BUTTON, available_buttons
            )
            if button_goal is not None:
                return button_goal

            all_positions = state.switches
            # A rotating mechanism may be used again after leaving and coming
            # back, but never repeatedly during the same room visit.  Without
            # this guard PPO can alternate ACTIVATE/WAIT forever and farm the
            # bridge-rotation reward without exploring.
            positions = {
                pos for pos in all_positions
                if globalize(state.room, pos) not in memory.visit_activated_switches
            }
            return self._nearest_reachable(state, GoalKind.ACTIVATE_SWITCH, positions)

        exits = {
            pos for pos in self._door_exits(state)
            if self._exit_is_currently_usable(pos, state, memory)
        }
        reachable_exits = self._reachable(state, GoalKind.GO_TO_EXIT, exits)

        if option == HighLevelAction.TAKE_NEW_EXIT:
            new_exits = [
                goal for goal in reachable_exits
                if goal.target is not None
                and globalize(state.room, goal.target) not in memory.used_exits
            ]
            if not new_exits:
                return None
            return self._best_exit_goal(state, memory, new_exits)

        if option == HighLevelAction.RETURN_OR_REVISIT:
            progress = self._rule_helpers._route_to_known_progress_room(state, memory)
            if progress is not None:
                return progress
            used = [
                goal for goal in reachable_exits
                if goal.target is not None
                and globalize(state.room, goal.target) in memory.used_exits
            ]
            if not used:
                return None
            return self._best_exit_goal(state, memory, used, allow_used=True)

        if option == HighLevelAction.EXPLORE_ROOM:
            target = self._exploration_target(state)
            return None if target is None else Goal(GoalKind.EXPLORE, target)

        return None

    def _best_exit_goal(
        self,
        state: SymbolicState,
        memory: AgentMemory,
        goals: list[Goal],
        *,
        allow_used: bool = False,
    ) -> Goal:
        """Stable exit refinement for trained high-level policies.

        The rule agent may evolve its tactical exit ranking independently.  A
        trained RL option, however, must keep the same deterministic refinement
        semantics it was trained against or an unchanged weight can select a
        different physical doorway tile.
        """

        candidates = goals if allow_used else [goal for goal in goals if goal.target is not None]
        forward = self._rule_helpers._avoid_entry_side(state, memory, candidates)
        candidates = forward or candidates

        def rank(goal: Goal) -> tuple[int, int, int, int, int, tuple[int, int]]:
            target = goal.target or state.player
            neighbor = self._rule_helpers._neighbor_room(state.room, target)
            unvisited = 0 if neighbor is not None and neighbor not in memory.room_memory else 1
            used = 1 if globalize(state.room, target) in memory.used_exits else 0
            key_bonus = 0 if state.keys > 0 and target[0] == 9 else 1
            entry = 1 if self._rule_helpers._is_entry_side(state, goal) and memory.room_steps <= 4 else 0
            return (used, unvisited, entry, key_bonus, manhattan(state.player, target), target)

        return min(candidates, key=rank)

    def _nearest_reachable(
        self,
        state: SymbolicState,
        kind: GoalKind,
        positions: set[tuple[int, int]],
    ) -> Goal | None:
        goals = self._reachable(state, kind, positions)
        if not goals:
            return None
        return min(
            goals,
            key=lambda goal: (
                manhattan(state.player, goal.target or state.player),
                goal.target or (0, 0),
            ),
        )

    def _reachable(
        self,
        state: SymbolicState,
        kind: GoalKind,
        positions: set[tuple[int, int]],
    ) -> list[Goal]:
        goals = [Goal(kind, pos) for pos in positions]
        return [goal for goal in goals if is_reachable(state, goal) or state.player == goal.target]

    def _door_exits(self, state: SymbolicState) -> set[tuple[int, int]]:
        return {
            (col, row)
            for col, row in state.all_exits
            if (row in {0, 7} and col in {4, 5})
            or (col in {0, 9} and row in {3, 4})
        }

    def _exit_is_currently_usable(
        self,
        pos: tuple[int, int],
        state: SymbolicState,
        memory: AgentMemory,
    ) -> bool:
        label = state.exit_labels.get(pos, "")
        if "locked_key_closed" in label and state.keys <= 0:
            return False
        if "conditional" in label:
            unopened_chests = any(
                globalize(state.room, target) not in memory.opened_chests
                for target in state.chests
            )
            live_monsters = bool(state.monsters)
            unused_mechanisms = any(
                globalize(state.room, target) not in memory.activated_switches
                for target in (state.buttons | state.switches)
            )
            if unopened_chests or live_monsters or unused_mechanisms:
                return False
        return True

    def _exploration_target(self, state: SymbolicState) -> tuple[int, int] | None:
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
        if not candidates:
            return None
        # A distant point creates useful motion when no explicit affordance is
        # available.  Tie-breaking keeps runs reproducible.
        return max(candidates, key=lambda item: (item[0], item[1]))[1]


def encode_high_level_state(
    state: SymbolicState,
    memory: AgentMemory,
    *,
    inventory: tuple[int, int, bool, bool, bool],
    action_mask: np.ndarray,
    last_option: int | None,
) -> np.ndarray:
    grid = np.zeros((GRID_HEIGHT, GRID_WIDTH), dtype=np.float32)
    _fill(grid, state.walls, 1)
    _fill(grid, state.chests, 2)
    _fill(grid, state.monsters, 3)
    _fill(grid, state.all_exits, 4)
    _fill(grid, state.traps, 5)
    _fill(grid, state.buttons | state.switches, 6)
    _fill(grid, state.gaps, 7)
    _fill(grid, state.bridges, 8)
    _fill(grid, state.npcs, 9)
    if 0 <= state.player[0] < GRID_WIDTH and 0 <= state.player[1] < GRID_HEIGHT:
        grid[state.player[1], state.player[0]] = 0

    features: list[float] = (grid.reshape(-1) / 9.0).tolist()
    features.extend(
        [
            state.player[0] / (GRID_WIDTH - 1),
            state.player[1] / (GRID_HEIGHT - 1),
        ]
    )

    monsters = sorted(
        state.monsters,
        key=lambda pos: (manhattan(pos, state.player), pos),
    )[:4]
    for index in range(4):
        if index < len(monsters):
            col, row = monsters[index]
            features.extend([col / (GRID_WIDTH - 1), row / (GRID_HEIGHT - 1)])
        else:
            features.extend([-1.0, -1.0])

    keys, gold, has_sword, has_shield, has_heal = inventory
    features.extend(
        [
            min(keys, 3) / 3.0,
            min(gold, 10) / 10.0,
            float(has_sword),
            float(has_shield),
            float(has_heal),
        ]
    )
    features.extend(action_mask.astype(np.float32).tolist())

    last_one_hot = np.zeros(ACTION_COUNT, dtype=np.float32)
    if last_option is not None and 0 <= last_option < ACTION_COUNT:
        last_one_hot[last_option] = 1.0
    features.extend(last_one_hot.tolist())

    features.extend(
        [
            min(len(memory.room_memory), 10) / 10.0,
            min(len(memory.opened_chests), 10) / 10.0,
            min(len(memory.killed_monsters), 10) / 10.0,
            min(len(memory.activated_switches), 10) / 10.0,
            min(len(memory.used_exits), 20) / 20.0,
            min(memory.room_steps, 50) / 50.0,
        ]
    )

    encoded = np.asarray(features, dtype=np.float32)
    if encoded.shape != (FEATURE_DIM,):
        raise RuntimeError(f"high-level feature shape mismatch: {encoded.shape} != {(FEATURE_DIM,)}")
    return encoded


def _fill(grid: np.ndarray, positions: set[tuple[int, int]], value: int) -> None:
    for col, row in positions:
        if 0 <= col < GRID_WIDTH and 0 <= row < GRID_HEIGHT:
            grid[row, col] = value
