from __future__ import annotations

from typing import Any

from rule_based_submission.executor import action_for_goal
from rule_based_submission.shield import shield
from rule_based_submission.strategy import HighLevelPolicy, RuleBasedPolicy
from rule_based_submission.symbolic import AgentMemory, GoalKind, MOVE_DELTAS, globalize, next_position
from rule_based_submission.vision import perceive


class Policy:
    def __init__(self, high_level_policy: HighLevelPolicy | None = None) -> None:
        self.memory = AgentMemory()
        self.high_level_policy = high_level_policy or RuleBasedPolicy()
        self._queued_action = 0
        self._queued_ticks = 0

    def reset(self, seed: int | None = None, task_id: str | None = None) -> None:
        del seed
        self.memory.reset(task_id=task_id)
        self._queued_action = 0
        self._queued_ticks = 0

    def act(self, obs: Any, info: dict[str, Any] | None = None) -> int:
        self._observe_events(info)
        if self._queued_ticks > 0:
            state = perceive(obs, self.memory, info)
            candidate = next_position(state.player, self._queued_action)
            if self._is_door_exit(state.player) and state.player in state.exits and not (0 <= candidate[0] < 10 and 0 <= candidate[1] < 8):
                self._mark_exit_used(state.room, state.player)
            self._queued_ticks -= 1
            self.memory.last_action = self._queued_action
            return self._queued_action

        state = perceive(obs, self.memory, info)
        self.memory.update(state)
        goal = self.high_level_policy.choose_goal(state, self.memory)
        raw_action = action_for_goal(state, goal)
        action = shield(raw_action, state)
        if action in MOVE_DELTAS:
            candidate = next_position(state.player, action)
            leaving_through_exit = self._is_door_exit(state.player) and state.player in state.exits and not (0 <= candidate[0] < 10 and 0 <= candidate[1] < 8)
            if leaving_through_exit:
                self._mark_exit_used(state.room, state.player)
            self._queued_action = action
            self._queued_ticks = 23 if leaving_through_exit else 15
        else:
            self._queued_action = 0
            self._queued_ticks = 0
        self.memory.last_goal = goal
        self.memory.last_action = action
        return action


    def _observe_events(self, info: dict[str, Any] | None) -> None:
        if not isinstance(info, dict):
            return
        records = info.get("events", {}).get("records", [])
        door_events = sum(
            1
            for record in records
            if isinstance(record, dict) and record.get("name") == "door_opened"
        )
        if door_events <= self.memory.handled_door_events:
            return
        spent = door_events - self.memory.handled_door_events
        self.memory.spent_keys += spent
        self.memory.previous_keys = max(0, self.memory.previous_keys - spent)
        self.memory.handled_door_events = door_events

    def _is_door_exit(self, pos) -> bool:
        col, row = pos
        return ((row in {0, 7} and col in {4, 5}) or (col in {0, 9} and row in {3, 4}))
    def _mark_exit_used(self, room, pos) -> None:
        self.memory.used_exits.add(globalize(room, pos))
        if room == (0, 0) and self.memory.previous_keys > 0:
            self.memory.previous_keys -= 1
            self.memory.spent_keys += 1
        col, row = pos
        if row == 0:
            self.memory.pending_room_delta = (0, -1)
        elif row == 7:
            self.memory.pending_room_delta = (0, 1)
        elif col == 0:
            self.memory.pending_room_delta = (-1, 0)
        elif col == 9:
            self.memory.pending_room_delta = (1, 0)
        if row in {0, 7}:
            for other_col in (col - 1, col + 1):
                if 0 <= other_col < 10:
                    self.memory.used_exits.add(globalize(room, (other_col, row)))
        if col in {0, 9}:
            for other_row in (row - 1, row + 1):
                if 0 <= other_row < 8:
                    self.memory.used_exits.add(globalize(room, (col, other_row)))
def make_policy() -> Policy:
    return Policy()








