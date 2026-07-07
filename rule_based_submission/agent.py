from __future__ import annotations

from typing import Any

from rule_based_submission.executor import action_for_goal
from rule_based_submission.planner import is_walkable
from rule_based_submission.shield import shield
from rule_based_submission.strategy import HighLevelPolicy, RuleBasedPolicy
from rule_based_submission.symbolic import (
    ACTION_A,
    ACTION_B,
    ACTION_NOOP,
    ACTION_DOWN,
    ACTION_LEFT,
    ACTION_RIGHT,
    ACTION_UP,
    AgentMemory,
    Goal,
    GoalKind,
    MOVE_DELTAS,
    Position,
    SymbolicState,
    globalize,
    manhattan,
    next_position,
)
from rule_based_submission.vision import perceive


class Policy:
    def __init__(self, high_level_policy: HighLevelPolicy | None = None) -> None:
        self.memory = AgentMemory()
        self.high_level_policy = high_level_policy or RuleBasedPolicy()
        self._queued_action = 0
        self._queued_ticks = 0
        self._blocked_action: int | None = None
        self._blocked_ticks = 0
        self._force_fight_ticks = 0

    def reset(self, seed: int | None = None, task_id: str | None = None) -> None:
        del seed
        self.memory.reset(task_id=task_id)
        self._queued_action = 0
        self._queued_ticks = 0

    def act(self, obs: Any, info: dict[str, Any] | None = None) -> int:
        self._observe_events(info)
        if self._queued_ticks > 0:
            state = perceive(obs, self.memory, info)
            urgent_action = self._combat_reflex(state)
            if urgent_action is not None:
                self._queued_action = ACTION_NOOP
                self._queued_ticks = 0
                self.memory.last_action = urgent_action
                return urgent_action
            candidate = next_position(state.player, self._queued_action)
            if self._is_door_exit(state.player) and state.player in state.exits and not (0 <= candidate[0] < 10 and 0 <= candidate[1] < 8):
                self._mark_exit_used(state.room, state.player)
            self._queued_ticks -= 1
            self.memory.last_action = self._queued_action
            return self._queued_action

        state = perceive(obs, self.memory, info)
        self.memory.update(state)
        urgent_action = self._combat_reflex(state)
        if urgent_action is not None:
            self._queued_action = ACTION_NOOP
            self._queued_ticks = 0
            self.memory.last_goal = None
            self.memory.last_action = urgent_action
            return urgent_action
        goal = self._forced_combat_goal(state) or self.high_level_policy.choose_goal(state, self.memory)
        raw_action = action_for_goal(state, goal)
        if self._blocked_action == raw_action and self._blocked_ticks > 0:
            raw_action = self._unstick_action(state, goal, raw_action)
        action = shield(raw_action, state)
        if action in MOVE_DELTAS:
            candidate = next_position(state.player, action)
            leaving_through_exit = self._is_door_exit(state.player) and state.player in state.exits and not (0 <= candidate[0] < 10 and 0 <= candidate[1] < 8)
            if leaving_through_exit:
                self._mark_exit_used(state.room, state.player)
            self._queued_action = action
            self._queued_ticks = 23 if leaving_through_exit else self._move_queue_ticks(state)
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
        blocked = any(
            isinstance(record, dict) and record.get("name") == "action_blocked"
            for record in records
        )
        if blocked:
            self._blocked_action = self.memory.last_action
            self._blocked_ticks = min(6, self._blocked_ticks + 1)
            self._queued_action = ACTION_NOOP
            self._queued_ticks = 0
        elif self._blocked_ticks > 0:
            self._blocked_ticks -= 1
            if self._blocked_ticks == 0:
                self._blocked_action = None

        if any(
            isinstance(record, dict) and record.get("name") in {"shield_block", "agent_damaged", "monster_damaged"}
            for record in records
        ):
            self._force_fight_ticks = 240

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



    def _forced_combat_goal(self, state: SymbolicState) -> Goal | None:
        if self._force_fight_ticks <= 0:
            return None
        self._force_fight_ticks -= 1
        if not state.has_sword or not state.monsters:
            return None
        if state.health is not None and state.health <= 1:
            return None
        target = min(state.monsters, key=lambda monster: self._monster_rank(state, monster))
        return Goal(GoalKind.ATTACK_MONSTER, target)

    def _unstick_action(self, state: SymbolicState, goal: Goal, blocked_action: int) -> int:
        if blocked_action not in MOVE_DELTAS:
            return blocked_action
        candidates = [
            action for action in (ACTION_UP, ACTION_DOWN, ACTION_LEFT, ACTION_RIGHT)
            if action != blocked_action
        ]
        target = goal.target if getattr(goal, "target", None) is not None else state.player

        best: tuple[int, int, int, Position] | None = None
        best_action = blocked_action
        for action in candidates:
            pos = next_position(state.player, action)
            if not is_walkable(pos, state, allow_goal=True):
                continue
            if state.monsters and min(manhattan(pos, monster) for monster in state.monsters) <= 1:
                continue
            progress = manhattan(pos, target)
            blocked_axis_turn = 0 if self._same_axis(action, blocked_action) else 1
            score = (progress, -blocked_axis_turn, action, pos)
            if best is None or score < best:
                best = score
                best_action = action
        return best_action

    def _same_axis(self, left: int, right: int) -> bool:
        return {left, right} <= {ACTION_UP, ACTION_DOWN} or {left, right} <= {ACTION_LEFT, ACTION_RIGHT}

    def _move_queue_ticks(self, state: SymbolicState) -> int:
        if not state.monsters:
            return 15
        nearest_monster = min(manhattan(state.player, monster) for monster in state.monsters)
        if nearest_monster <= 2:
            return 1
        return 3

    def _combat_reflex(self, state: SymbolicState) -> int | None:
        if not state.monsters:
            return None

        adjacent = [monster for monster in state.monsters if manhattan(state.player, monster) == 1]
        if adjacent:
            target = min(adjacent, key=lambda monster: self._monster_rank(state, monster))
            toward = self._action_toward(state.player, target)
            if state.has_sword and self._last_facing_action() == toward:
                return ACTION_A
            retreat = self._retreat_action(state, target)
            if retreat is not None and (not state.has_sword or self._low_health(state)):
                return retreat
            if state.has_shield and (not state.has_sword or self._low_health(state)):
                return ACTION_B
            # When the sword is available but the facing is wrong, taking a short
            # step away lets the normal planner step back into an attack stance.
            if retreat is not None:
                return retreat
            return ACTION_A if state.has_sword else (ACTION_B if state.has_shield else ACTION_NOOP)

        near_threats = [monster for monster in state.monsters if manhattan(state.player, monster) <= 2]
        if near_threats:
            threat = min(near_threats, key=lambda monster: self._monster_rank(state, monster))
            if self._low_health(state) or not state.has_sword:
                retreat = self._retreat_action(state, threat)
                if retreat is not None:
                    return retreat
                if state.has_shield:
                    return ACTION_B
            engage = self._approach_attack_action(state, threat)
            if engage is not None:
                return engage
            if state.has_shield and self.memory.last_action != ACTION_B:
                return ACTION_B
        return None

    def _approach_attack_action(self, state: SymbolicState, monster: Position) -> int | None:
        if not state.has_sword or manhattan(state.player, monster) != 2:
            return None
        # Only close distance when one step will leave the player adjacent and
        # facing the monster; L-shaped approaches tend to create a wrong-facing
        # melee state, so shield/normal planning is safer there.
        if state.player[0] != monster[0] and state.player[1] != monster[1]:
            return None
        action = self._action_toward(state.player, monster)
        if action is None:
            return None
        pos = next_position(state.player, action)
        if pos in state.monsters or not is_walkable(pos, state, allow_goal=True):
            return None
        if manhattan(pos, monster) != 1:
            return None
        return action

    def _monster_rank(self, state: SymbolicState, monster: Position) -> tuple[int, int, Position]:
        facing_penalty = 0 if self._last_facing_action() == self._action_toward(state.player, monster) else 1
        return (manhattan(state.player, monster), facing_penalty, monster)

    def _low_health(self, state: SymbolicState) -> bool:
        return state.health is not None and state.health <= 2

    def _retreat_action(self, state: SymbolicState, monster: Position) -> int | None:
        toward = self._action_toward(state.player, monster)
        opposite = {
            ACTION_UP: ACTION_DOWN,
            ACTION_DOWN: ACTION_UP,
            ACTION_LEFT: ACTION_RIGHT,
            ACTION_RIGHT: ACTION_LEFT,
        }.get(toward)
        candidates = [opposite] if opposite is not None else []
        candidates.extend(
            action for action in (ACTION_UP, ACTION_DOWN, ACTION_LEFT, ACTION_RIGHT)
            if action != opposite and action != toward
        )

        best: tuple[int, int] | None = None
        best_action: int | None = None
        for action in candidates:
            pos = next_position(state.player, action)
            if not is_walkable(pos, state, allow_goal=True):
                continue
            distance = min(manhattan(pos, other) for other in state.monsters)
            if distance <= manhattan(state.player, monster):
                continue
            score = (distance, 1 if action == opposite else 0)
            if best is None or score > best:
                best = score
                best_action = action
        return best_action

    def _last_facing_action(self) -> int | None:
        return self.memory.last_action if self.memory.last_action in MOVE_DELTAS else None

    def _action_toward(self, start: Position, target: Position) -> int | None:
        dx = target[0] - start[0]
        dy = target[1] - start[1]
        if abs(dx) > abs(dy):
            return ACTION_RIGHT if dx > 0 else ACTION_LEFT
        if dy != 0:
            return ACTION_DOWN if dy > 0 else ACTION_UP
        if dx != 0:
            return ACTION_RIGHT if dx > 0 else ACTION_LEFT
        return None

def make_policy() -> Policy:
    return Policy()








