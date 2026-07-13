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
    TILE_SIZE,
    manhattan,
    next_position,
)
from rule_based_submission.vision import perceive, reset_vision


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
        self._last_player_center: tuple[float, float] | None = None
        self._stationary_move_ticks = 0

    def reset(self, seed: int | None = None, task_id: str | None = None) -> None:
        del seed
        self.memory.reset(task_id=task_id)
        self._queued_action = ACTION_NOOP
        self._queued_ticks = 0
        self._blocked_action = None
        self._blocked_ticks = 0
        self._force_fight_ticks = 0
        self._facing = ACTION_RIGHT
        self._step = 0
        self._last_player_center = None
        self._stationary_move_ticks = 0
        reset_vision()

    def act(self, obs: Any, info: dict[str, Any] | None = None) -> int:
        self._step += 1
        state = perceive(obs, self.memory, info)
        self._observe_motion(state)
        if self._queued_ticks > 0:
            urgent_action = self._combat_reflex(state)
            if urgent_action is not None:
                self._log(f"QUEUE INTERRUPT reflex->{self._ACT_NAMES.get(urgent_action, urgent_action)}  (tick={self._queued_ticks})")
                if urgent_action == ACTION_A:
                    self._force_fight_ticks = 240
                self._queued_ticks -= 1
                self.memory.last_action = urgent_action
                return urgent_action
            self._queued_ticks -= 1
            self.memory.last_action = self._queued_action
            self._facing = self._queued_action
            return self._queued_action

        transitioned = self.memory.update(state)
        if transitioned:
            reset_vision()
        urgent_action = self._combat_reflex(state)
        if urgent_action is not None:
            self._log(f"PLAN  reflex->{self._ACT_NAMES.get(urgent_action, urgent_action)}  facing={self._ACT_NAMES.get(self._facing, '?')}  mons={state.monsters}  player={state.player}")
            if urgent_action == ACTION_A:
                self._force_fight_ticks = 240
            self.memory.last_action = urgent_action
            return urgent_action
        goal = self._forced_combat_goal(state) or self.high_level_policy.choose_goal(state, self.memory)
        raw_action = action_for_goal(state, goal)
        unstick_nudge = False
        pixel_nudge = False
        if self._blocked_action == raw_action and self._blocked_ticks > 0:
            adjusted_action = self._alignment_action(state, raw_action)
            if adjusted_action is None:
                adjusted_action = self._unstick_action(state, goal, raw_action)
            else:
                pixel_nudge = True
            unstick_nudge = adjusted_action != raw_action
            raw_action = adjusted_action
        align_action = self._alignment_action(state, raw_action)
        if align_action is not None:
            pixel_nudge = True
            raw_action = align_action
        action = shield(raw_action, state)
        if action in MOVE_DELTAS:
            candidate = next_position(state.player, action)
            leaving_through_exit = self._is_door_exit(state.player) and state.player in state.all_exits and not (0 <= candidate[0] < 10 and 0 <= candidate[1] < 8)
            self._queued_action = action
            self._queued_ticks = 23 if leaving_through_exit else (0 if pixel_nudge else (1 if unstick_nudge else self._move_queue_ticks(state)))
        else:
            self._queued_action = 0
            self._queued_ticks = 0
        self.memory.last_goal = goal
        self.memory.last_action = action
        if action in MOVE_DELTAS:
            self._facing = action
        if action == ACTION_A and state.monsters:
            if any(manhattan(state.player, m) <= 2 for m in state.monsters):
                self._force_fight_ticks = 240
        self._log(f"PLAN  goal={goal.kind.value}:{goal.target}  raw={self._ACT_NAMES.get(raw_action,'?')}  act={self._ACT_NAMES.get(action,'?')}  queue={self._queued_ticks}  facing={self._ACT_NAMES.get(self._facing,'?')}  mons={state.monsters}  chests={state.chests}  exits={state.all_exits}  room={state.room}  player={state.player}")
        return action


    def _log(self, msg: str) -> None:
        if self._debug:
            print(f"[step {self._step}] {msg}")

    _ACT_NAMES: dict[int, str] = {
        ACTION_NOOP: "NOOP", ACTION_UP: "UP", ACTION_DOWN: "DOWN",
        ACTION_LEFT: "LEFT", ACTION_RIGHT: "RIGHT", ACTION_A: "A", ACTION_B: "B",
    }

    def _observe_motion(self, state: SymbolicState) -> None:
        """Infer blocked movement from successive player pixels, without debug info."""
        center = state.player_center_px
        previous = self._last_player_center
        self._last_player_center = center
        if center is None or previous is None or self.memory.last_action not in MOVE_DELTAS:
            self._stationary_move_ticks = 0
            return

        dx = center[0] - previous[0]
        dy = center[1] - previous[1]
        wrapped = abs(dx) > TILE_SIZE * 4 or abs(dy) > TILE_SIZE * 3
        expected_progress = {
            ACTION_UP: -dy,
            ACTION_DOWN: dy,
            ACTION_LEFT: -dx,
            ACTION_RIGHT: dx,
        }[self.memory.last_action]
        if wrapped or expected_progress >= 0.5:
            self._stationary_move_ticks = 0
            self._blocked_action = None
            self._blocked_ticks = 0
            return

        self._stationary_move_ticks += 1
        if self._stationary_move_ticks < 2:
            return
        self._blocked_action = self.memory.last_action
        self._blocked_ticks = min(6, self._blocked_ticks + 1)
        self._queued_action = ACTION_NOOP
        self._queued_ticks = 0

    def _is_door_exit(self, pos) -> bool:
        col, row = pos
        return ((row in {0, 7} and col in {4, 5}) or (col in {0, 9} and row in {3, 4}))

    def _forced_combat_goal(self, state: SymbolicState) -> Goal | None:
        if self._force_fight_ticks <= 0:
            return None
        self._force_fight_ticks -= 1
        if not state.has_sword or not state.monsters or (state.health is not None and state.health <= 1):
            self._force_fight_ticks = 0
            return None
        target = min(state.monsters, key=lambda monster: self._monster_rank(state, monster))
        self._log(f"FORCED_COMBAT -> {target}  (ticks_left={self._force_fight_ticks})")
        return Goal(GoalKind.ATTACK_MONSTER, target)

    def _alignment_action(self, state: SymbolicState, action: int) -> int | None:
        if action not in MOVE_DELTAS or state.player_center_px is None:
            return None
        candidate = next_position(state.player, action)
        if state.player in state.all_exits and not (0 <= candidate[0] < 10 and 0 <= candidate[1] < 8):
            return None

        col, row = state.player
        center_x, center_y = state.player_center_px
        target_x = col * TILE_SIZE + TILE_SIZE / 2.0
        target_y = row * TILE_SIZE + TILE_SIZE / 2.0
        corner_margin = 1.0
        center_tolerance = 2.0

        if action in {ACTION_UP, ACTION_DOWN}:
            forward_row = row + (-1 if action == ACTION_UP else 1)
            left_front_blocked = not is_walkable((col - 1, forward_row), state, allow_goal=True)
            right_front_blocked = not is_walkable((col + 1, forward_row), state, allow_goal=True)
            if left_front_blocked and right_front_blocked:
                if center_x < target_x - center_tolerance and self._can_step(state, ACTION_RIGHT):
                    return ACTION_RIGHT
                if center_x > target_x + center_tolerance and self._can_step(state, ACTION_LEFT):
                    return ACTION_LEFT
            elif left_front_blocked:
                if center_x < target_x + corner_margin and self._can_step(state, ACTION_RIGHT):
                    return ACTION_RIGHT
            elif right_front_blocked:
                if center_x > target_x - corner_margin and self._can_step(state, ACTION_LEFT):
                    return ACTION_LEFT
        elif action in {ACTION_LEFT, ACTION_RIGHT}:
            forward_col = col + (-1 if action == ACTION_LEFT else 1)
            up_front_blocked = not is_walkable((forward_col, row - 1), state, allow_goal=True)
            down_front_blocked = not is_walkable((forward_col, row + 1), state, allow_goal=True)
            if up_front_blocked and down_front_blocked:
                if center_y < target_y - center_tolerance and self._can_step(state, ACTION_DOWN):
                    return ACTION_DOWN
                if center_y > target_y + center_tolerance and self._can_step(state, ACTION_UP):
                    return ACTION_UP
            elif up_front_blocked:
                if center_y < target_y + corner_margin and self._can_step(state, ACTION_DOWN):
                    return ACTION_DOWN
            elif down_front_blocked:
                if center_y > target_y - corner_margin and self._can_step(state, ACTION_UP):
                    return ACTION_UP
        return None
    def _unstick_action(self, state: SymbolicState, goal: Goal, blocked_action: int) -> int:
        if blocked_action not in MOVE_DELTAS:
            return blocked_action
        if goal.kind == GoalKind.GO_TO_EXIT and goal.target is not None:
            nudge = self._exit_corner_nudge(state, goal.target, blocked_action)
            if nudge is not None:
                return nudge
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

    def _exit_corner_nudge(self, state: SymbolicState, target: Position, blocked_action: int) -> int | None:
        if blocked_action in {ACTION_LEFT, ACTION_RIGHT} and target[0] in {0, 9}:
            front_col = state.player[0] + (-1 if blocked_action == ACTION_LEFT else 1)
            above_front = (front_col, state.player[1] - 1)
            below_front = (front_col, state.player[1] + 1)
            if not is_walkable(above_front, state, allow_goal=True) and self._can_step(state, ACTION_DOWN):
                return ACTION_DOWN
            if not is_walkable(below_front, state, allow_goal=True) and self._can_step(state, ACTION_UP):
                return ACTION_UP

        if blocked_action in {ACTION_UP, ACTION_DOWN} and target[1] in {0, 7}:
            front_row = state.player[1] + (-1 if blocked_action == ACTION_UP else 1)
            left_front = (state.player[0] - 1, front_row)
            right_front = (state.player[0] + 1, front_row)
            if not is_walkable(left_front, state, allow_goal=True) and self._can_step(state, ACTION_RIGHT):
                return ACTION_RIGHT
            if not is_walkable(right_front, state, allow_goal=True) and self._can_step(state, ACTION_LEFT):
                return ACTION_LEFT
        return None

    def _can_step(self, state: SymbolicState, action: int) -> bool:
        pos = next_position(state.player, action)
        if not is_walkable(pos, state, allow_goal=True):
            return False
        return pos not in state.monsters

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
        """True when the angle between the facing ray and player-target vector is < 90 degrees.

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

        near_threats = [
            monster for monster in state.monsters
            if manhattan(state.player, monster) <= 2
            and not self._wall_between(state, state.player, monster)
        ]
        if not near_threats:
            return None

        target = min(near_threats, key=lambda monster: self._monster_rank(state, monster))
        m_dist = manhattan(state.player, target)

        # -- cardinal adjacent (manhattan == 1) -------------------------
        if m_dist == 1:
            # facing the monster: attack
            if state.has_sword and self._is_facing(state.player, target):
                return ACTION_A
            # not facing: step back to create distance, then re-approach
            retreat = self._step_away(state, target)
            if retreat is not None:
                return retreat
            # can't step back: shield as last resort to push monster away
            if state.has_shield:
                return ACTION_B
            return None

        # -- diagonal adjacent (manhattan == 2, euclidean < 1.5) --------
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

    @staticmethod
    def _euclidean(a: Position, b: Position) -> float:
        return ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2) ** 0.5

    def _wall_between(self, state: SymbolicState, player: Position, monster: Position) -> bool:
        """True when a wall blocks the direct path to the monster."""
        px, py = player
        mx, my = monster
        dist = manhattan(player, monster)
        if dist <= 1:
            return False  # adjacent: no tile can be between
        # same row
        if py == my:
            step = 1 if mx > px else -1
            for x in range(px + step, mx, step):
                if (x, py) in state.walls:
                    return True
        # same column
        elif px == mx:
            step = 1 if my > py else -1
            for y in range(py + step, my, step):
                if (px, y) in state.walls:
                    return True
        # diagonal: both corner tiles must be walls to block
        else:
            return (mx, py) in state.walls and (px, my) in state.walls
        return False

    def _monster_rank(self, state: SymbolicState, monster: Position) -> tuple[int, int, Position]:
        facing_penalty = 0 if self._is_facing(state.player, monster) else 1
        return (manhattan(state.player, monster), facing_penalty, monster)

def make_policy(*, debug: bool = False) -> Policy:
    return Policy(debug=debug)
