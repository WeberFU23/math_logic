from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np

from RL_based_submission.advanced_perception import AdvancedPerceptor
from RL_based_submission.high_level_core import (
    GoalResolver,
    encode_high_level_state,
    oriented_action_for_goal,
    unstick_nudge,
    task5_defensive_action,
)
from RL_based_submission.task5_learning import Task5GoalResolver, encode_task5_state
from rule_based_submission.shield import combat_reflex, shield
from rule_based_submission.symbolic import (
    ACTION_NOOP,
    MOVE_DELTAS,
    SymbolicState,
    globalize,
    next_position,
)

try:
    from sb3_contrib import MaskablePPO
except Exception:  # pragma: no cover - lets submission import before optional deps
    MaskablePPO = None


PROJECT_ROOT = Path(__file__).resolve().parent.parent
MODEL_DIR = PROJECT_ROOT / "RL_based_submission" / "high_level_models"


class Policy:
    """Final-inference policy using only pixels plus explicit inventory."""

    def __init__(self) -> None:
        self.perceptor = AdvancedPerceptor()
        self.resolver = GoalResolver()
        self.model = None
        self.task_id: str | None = None
        self.last_option: int | None = None
        self._queued_action = ACTION_NOOP
        self._queued_ticks = 0
        self._transition_start: tuple[tuple[int, int], int] | None = None
        self._state: SymbolicState | None = None
        self._queued_start_px: tuple[float, float] | None = None
        self._blocked_action: int | None = None
        self._bypass_alignment_once = False
        self._defense_cooldown = 0
        self._env_steps = 0

    @property
    def memory(self):
        return self.perceptor.memory

    def reset(self, seed: int | None = None, task_id: str | None = None) -> None:
        del seed
        self.task_id = task_id
        self.perceptor.reset(task_id=task_id)
        self.resolver = (
            Task5GoalResolver()
            if task_id == "mathematical_logic/task_5"
            else GoalResolver()
        )
        self.model = _load_model(task_id)
        self.last_option = None
        self._queued_action = ACTION_NOOP
        self._queued_ticks = 0
        self._transition_start = None
        self._state = None
        self._queued_start_px = None
        self._blocked_action = None
        self._bypass_alignment_once = False
        self._defense_cooldown = 0
        self._env_steps = 0

    def act(self, obs: Any, info: dict[str, Any] | None = None) -> int:
        elapsed_steps = self._env_steps
        self._env_steps += 1
        if self._queued_ticks > 0:
            state = self._perceive_and_update(obs, info)
            urgent = combat_reflex(state, self.memory.facing_action,
                                   state.has_sword, state.has_shield)
            if urgent is not None:
                self._queued_ticks = 0
                self._queued_action = ACTION_NOOP
                self.memory.last_action = urgent
                if urgent in MOVE_DELTAS:
                    self.memory.facing_action = urgent
                return urgent
            self._queued_ticks -= 1
            return self._queued_action

        if self.model is None:
            self.model = _load_model(self.task_id)
        if self.model is None:
            return ACTION_NOOP

        state = self._perceive_and_update(obs, info)
        if self._queued_start_px is not None and state.player_position_px is not None:
            moved = (
                abs(self._queued_start_px[0] - state.player_position_px[0])
                + abs(self._queued_start_px[1] - state.player_position_px[1])
            )
            self._blocked_action = self._queued_action if moved < 0.5 else None
        self._queued_start_px = None
        mask = self.resolver.action_mask(state, self.memory)
        inventory = self.perceptor.inventory_features(info)
        features = (
            encode_task5_state(
                state,
                self.memory,
                inventory=inventory,
                action_mask=mask,
                last_option=self.last_option,
                elapsed_steps=elapsed_steps,
            )
            if self.task_id == "mathematical_logic/task_5"
            else encode_high_level_state(
                state,
                self.memory,
                inventory=inventory,
                action_mask=mask,
                last_option=self.last_option,
            )
        )
        option, _ = self.model.predict(
            features,
            deterministic=True,
            action_masks=mask,
        )
        self.last_option = int(np.asarray(option).item())
        goal = self.resolver.resolve(self.last_option, state, self.memory)
        if goal is None:
            return ACTION_NOOP

        if self._defense_cooldown > 0:
            self._defense_cooldown -= 1
        defensive_action = (
            None
            if self.resolver.is_attack(self.last_option) or self._defense_cooldown > 0
            else task5_defensive_action(state, self.memory)
        )
        if defensive_action is not None:
            # One block is enough to break the monster's interception line.
            # Keep advancing afterwards; alternating shield/move wastes the
            # task's strict 180-step health budget.
            self._defense_cooldown = 8
        if defensive_action is not None:
            raw_action, facing_only = defensive_action, True
        else:
            raw_action, facing_only = oriented_action_for_goal(
                state,
                goal,
                self.memory,
                skip_alignment=self._bypass_alignment_once,
            )
        self._bypass_alignment_once = False
        nudge_action = (
            unstick_nudge(state, self._blocked_action)
            if defensive_action is None and self._blocked_action == raw_action
            else None
        )
        if nudge_action is not None:
            raw_action = nudge_action
            facing_only = True
            self._blocked_action = None
            self._bypass_alignment_once = True
        action = raw_action if facing_only else shield(raw_action, state)
        self.memory.last_goal = goal
        self.memory.last_action = action
        if action in MOVE_DELTAS:
            self.memory.facing_action = action

        if action in MOVE_DELTAS and nudge_action is not None:
            self._queued_action = action
            self._queued_ticks = 3
        elif action in MOVE_DELTAS and not facing_only:
            candidate = next_position(state.player, action)
            leaving = state.player in state.all_exits and not (
                0 <= candidate[0] < 10 and 0 <= candidate[1] < 8
            )
            self._queued_action = action
            self._queued_ticks = (
                0 if leaving and self.task_id == "mathematical_logic/task_5"
                else 23 if leaving
                else
                1 if self.task_id == "mathematical_logic/task_5" and state.monsters
                and min(
                    abs(state.player[0] - monster[0]) + abs(state.player[1] - monster[1])
                    for monster in state.monsters
                ) <= 3
                else 7 if self.task_id == "mathematical_logic/task_5"
                else self._move_queue_ticks(state)
            )
            self._queued_start_px = state.player_position_px
            if _transition_possible(state.player, action):
                self._transition_start = (state.player, action)
        else:
            self._queued_action = ACTION_NOOP
            self._queued_ticks = 0
        return action

    def _perceive_and_update(self, obs: Any, info: dict[str, Any] | None) -> SymbolicState:
        """Perceive a frame and update room memory after confirmed transitions.

        The final policy repeats a chosen movement for several primitive game
        steps.  A doorway crossing can therefore happen while we are still
        inside that repeat queue.  We first perceive the current frame, then
        mark a room transition only if the player visibly jumped from an exit
        edge to the opposite entry side.  This uses pixels plus our own last
        action; it does not read hidden room coordinates or object maps.
        """

        previous = self._state
        previous_action = self._queued_action
        state = self.perceptor.perceive(obs, info)
        if previous is not None and previous_action in MOVE_DELTAS and (
            (
                self._is_leaving_current_room(previous, previous_action)
                and _transition_succeeded(previous.player, state.player)
            )
            or (
                self._transition_start is not None
                and _transition_succeeded(self._transition_start[0], state.player)
            )
        ):
            exit_start = (
                self._transition_start[0]
                if self._transition_start is not None
                else previous.player
            )
            exit_action = (
                self._transition_start[1]
                if self._transition_start is not None
                else previous_action
            )
            _mark_transition(
                self.memory,
                _transition_exit_pos(exit_start, exit_action),
            )
            self.perceptor.reset_room_vision()
            state = self.perceptor.perceive(obs, info)
            self._transition_start = None
        self.memory.update(state)
        self._state = state
        return state

    @staticmethod
    def _is_leaving_current_room(state: SymbolicState, action: int) -> bool:
        if action not in MOVE_DELTAS or state.player not in state.all_exits:
            return False
        candidate = next_position(state.player, action)
        return not (0 <= candidate[0] < 10 and 0 <= candidate[1] < 8)

    @staticmethod
    def _move_queue_ticks(state: SymbolicState) -> int:
        if not state.monsters:
            return 15
        nearest_monster = min(
            abs(state.player[0] - monster[0]) + abs(state.player[1] - monster[1])
            for monster in state.monsters
        )
        if nearest_monster <= 2:
            return 1
        return 3


def _load_model(task_id: str | None):
    if MaskablePPO is None or not task_id:
        return None
    path = MODEL_DIR / f"{task_id.replace('/', '_')}.zip"
    if not path.exists():
        return None
    return MaskablePPO.load(path, device="cpu")


def _transition_succeeded(start: tuple[int, int], end: tuple[int, int]) -> bool:
    col, row = start
    if row <= 1:
        return end[1] >= 5
    if row >= 6:
        return end[1] <= 2
    if col <= 1:
        return end[0] >= 7
    if col >= 8:
        return end[0] <= 2
    return False


def _transition_possible(start: tuple[int, int], action: int) -> bool:
    col, row = start
    return bool(
        (action == 3 and col <= 1)
        or (action == 4 and col >= 8)
        or (action == 1 and row <= 1)
        or (action == 2 and row >= 6)
    )


def _transition_exit_pos(
    start: tuple[int, int],
    action: int,
) -> tuple[int, int]:
    col, row = start
    if action == 3:
        return (0, row)
    if action == 4:
        return (9, row)
    if action == 1:
        return (col, 0)
    if action == 2:
        return (col, 7)
    return start


def _mark_transition(memory, exit_pos: tuple[int, int]) -> None:
    room = memory.room
    _mark_exit_pair(memory, room, exit_pos)
    col, row = exit_pos
    if row == 0:
        delta = (0, -1)
        arrival = (col, 7)
    elif row == 7:
        delta = (0, 1)
        arrival = (col, 0)
    elif col == 0:
        delta = (-1, 0)
        arrival = (9, row)
    elif col == 9:
        delta = (1, 0)
        arrival = (0, row)
    else:
        return
    destination = (room[0] + delta[0], room[1] + delta[1])
    memory.pending_room_delta = delta
    _mark_exit_pair(memory, destination, arrival)


def _mark_exit_pair(memory, room: tuple[int, int], pos: tuple[int, int]) -> None:
    memory.used_exits.add(globalize(room, pos))
    col, row = pos
    if row in {0, 7}:
        for other_col in (col - 1, col + 1):
            if 0 <= other_col < 10:
                memory.used_exits.add(globalize(room, (other_col, row)))
    if col in {0, 9}:
        for other_row in (row - 1, row + 1):
            if 0 <= other_row < 8:
                memory.used_exits.add(globalize(room, (col, other_row)))


def make_policy() -> Policy:
    return Policy()
