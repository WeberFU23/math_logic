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
    def __init__(self, high_level_policy: HighLevelPolicy | None = None, *, debug: bool = False) -> None:
        self.memory = AgentMemory()
        self.high_level_policy = high_level_policy or RuleBasedPolicy(debug=debug)
        self._queued_action = 0
        self._queued_ticks = 0
        self._blocked_action: int | None = None
        self._blocked_ticks = 0
        self._force_fight_ticks = 0
        self._facing: int = ACTION_RIGHT
        self._debug = debug
        self._step = 0

    def reset(self, seed: int | None = None, task_id: str | None = None) -> None:
        del seed
        self.memory.reset(task_id=task_id)
        self._queued_action = 0
        self._queued_ticks = 0
        self._facing = ACTION_RIGHT

    def act(self, obs: Any, info: dict[str, Any] | None = None) -> int:
        self._step += 1
        self._observe_events(info)
        if self._queued_ticks > 0:
            state = perceive(obs, self.memory, info)
            urgent_action = self._combat_reflex(state)
            if urgent_action is not None:
                self._log(f"QUEUE INTERRUPT reflex→{self._ACT_NAMES.get(urgent_action, urgent_action)}  (tick={self._queued_ticks})")
                self._queued_ticks -= 1
                self.memory.last_action = urgent_action
                return urgent_action
            candidate = next_position(state.player, self._queued_action)
            if self._is_door_exit(state.player) and state.player in state.exits and not (0 <= candidate[0] < 10 and 0 <= candidate[1] < 8):
                self._mark_exit_used(state.room, state.player)
            self._queued_ticks -= 1
            self.memory.last_action = self._queued_action
            self._facing = self._queued_action
            return self._queued_action

        state = perceive(obs, self.memory, info)
        self.memory.update(state)
        urgent_action = self._combat_reflex(state)
        if urgent_action is not None:
            self._log(f"PLAN  reflex→{self._ACT_NAMES.get(urgent_action, urgent_action)}  facing={self._ACT_NAMES.get(self._facing, '?')}  mons={state.monsters}  player={state.player}")
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
        if action in MOVE_DELTAS:
            self._facing = action
        self._log(f"PLAN  goal={goal.kind.value}:{goal.target}  raw={self._ACT_NAMES.get(raw_action,'?')}  act={self._ACT_NAMES.get(action,'?')}  queue={self._queued_ticks}  facing={self._ACT_NAMES.get(self._facing,'?')}  mons={state.monsters}  chests={state.chests}  exits={state.exits}  room={state.room}  player={state.player}")
        return action


    def _log(self, msg: str) -> None:
        if self._debug:
            print(f"[step {self._step}] {msg}")

    _ACT_NAMES: dict[int, str] = {
        ACTION_NOOP: "NOOP", ACTION_UP: "UP", ACTION_DOWN: "DOWN",
        ACTION_LEFT: "LEFT", ACTION_RIGHT: "RIGHT", ACTION_A: "A", ACTION_B: "B",
    }

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

    def _is_facing(self, player: Position, target: Position) -> bool:
        """True when the angle between the facing ray and player→target vector is < 90°.

        Equivalent to: dot product of facing direction and (target - player) > 0.
        """
        dx = target[0] - player[0]
        dy = target[1] - player[1]
        if self._facing == ACTION_UP:
            return dy < 0
        if self._facing == ACTION_DOWN:
            return dy > 0
        if self._facing == ACTION_LEFT:
            return dx < 0
        if self._facing == ACTION_RIGHT:
            return dx > 0
        return False

    def _combat_reflex(self, state: SymbolicState) -> int | None:
        if not state.monsters:
            return None

        near_threats = [monster for monster in state.monsters if manhattan(state.player, monster) <= 2]
        if not near_threats:
            return None

        target = min(near_threats, key=lambda monster: self._monster_rank(state, monster))
        dist = manhattan(state.player, target)

        # ── adjacent (dist == 1) ──────────────────────────────────────
        if dist == 1:
            # facing the monster → attack
            if state.has_sword and self._is_facing(state.player, target):
                return ACTION_A
            # not facing → step back to create distance, then re-approach
            retreat = self._step_away(state, target)
            if retreat is not None:
                return retreat
            # can't step back → shield as last resort to push monster away
            if state.has_shield:
                return ACTION_B
            return None

        # ── one tile gap (dist == 2) ──────────────────────────────────
        if state.has_sword:
            approach = self._step_toward_safe(state, target)
            if approach is not None:
                return approach
        if state.has_shield:
            return ACTION_B
        return None

    def _step_away(self, state: SymbolicState, monster: Position) -> int | None:
        """Move one tile directly away from the monster, if walkable."""
        dx = monster[0] - state.player[0]
        dy = monster[1] - state.player[1]
        # prefer the dominant axis for retreat
        candidates = []
        if abs(dx) >= abs(dy):
            candidates = [ACTION_LEFT if dx > 0 else ACTION_RIGHT,
                          ACTION_UP if dy > 0 else ACTION_DOWN]
        else:
            candidates = [ACTION_UP if dy > 0 else ACTION_DOWN,
                          ACTION_LEFT if dx > 0 else ACTION_RIGHT]
        candidates.extend(a for a in (ACTION_UP, ACTION_DOWN, ACTION_LEFT, ACTION_RIGHT) if a not in candidates)
        for action in candidates:
            pos = next_position(state.player, action)
            if not is_walkable(pos, state, allow_goal=True):
                continue
            if pos in state.monsters:
                continue
            if manhattan(pos, monster) > 1:
                return action
        return None

    def _step_toward_safe(self, state: SymbolicState, monster: Position) -> int | None:
        """Move one step toward the monster without walking into any monster."""
        best_action: int | None = None
        best_dist = 999
        for action in (ACTION_UP, ACTION_DOWN, ACTION_LEFT, ACTION_RIGHT):
            pos = next_position(state.player, action)
            if not is_walkable(pos, state, allow_goal=True):
                continue
            if pos in state.monsters:
                continue
            d = manhattan(pos, monster)
            if d < best_dist:
                best_dist = d
                best_action = action
        return best_action

    def _monster_rank(self, state: SymbolicState, monster: Position) -> tuple[int, int, Position]:
        facing_penalty = 0 if self._is_facing(state.player, monster) else 1
        return (manhattan(state.player, monster), facing_penalty, monster)

def make_policy(*, debug: bool = False) -> Policy:
    return Policy(debug=debug)








