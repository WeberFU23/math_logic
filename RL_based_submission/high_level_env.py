from __future__ import annotations

from collections import Counter
from typing import Any

import gymnasium as gym
import numpy as np
from gymnasium import spaces

from nesylink.env import make_env
from RL_based_submission.advanced_perception import AdvancedPerceptor
from RL_based_submission.high_level_core import (
    GoalResolver,
    encode_high_level_state,
    oriented_action_for_goal,
    unstick_nudge,
    task5_defensive_action,
)
from RL_based_submission.task5_learning import Task5GoalResolver, encode_task5_state
from rule_based_submission.shield import shield
from rule_based_submission.symbolic import (
    ACTION_NOOP,
    MOVE_DELTAS,
    Goal,
    GoalKind,
    SymbolicState,
    globalize,
    next_position,
    manhattan,
)


TASK_MAX_MACRO_STEPS = {
    "mathematical_logic/task_1": 128,
    "mathematical_logic/task_2": 160,
    "mathematical_logic/task_3": 256,
    "mathematical_logic/task_4": 320,
    "mathematical_logic/task_5": 640,
}

EVENT_BONUSES = {
    "chest_opened": 3.0,
    "key_collected": 4.0,
    "item_collected": 4.0,
    "monster_killed": 0.5,
    # Mechanisms are intermediate topology changes, not repeatable progress.
    # Their official reward remains (scaled by base_reward_scale), while the
    # valuable consequences they unlock are rewarded below.
    "switch_activated": 0.0,
    "button_pressed": 0.0,
    "bridge_rotated": 0.0,
    # Crossing an already-known doorway is not progress.  Rewarding every
    # room_changed/exit_reached event lets PPO farm reward by walking back and
    # forth through the same door.
    "room_changed": 0.0,
    "door_opened": 3.0,
    "exit_reached": 0.0,
    "gold_collected": 0.5,
    "agent_healed": 3.0,
}

TASK5_EVENT_BONUSES = {
    **EVENT_BONUSES,
    "chest_opened": 4.0,
    "key_collected": 8.0,
    # Cancel the official combat incentive: combat becomes worthwhile only
    # when it enables later progress.
    "monster_damaged": -0.5,
    "monster_killed": -1.0,
    "button_pressed": 4.0,
    "agent_healed": 6.0,
}


class HighLevelOptionEnv(gym.Env):
    """PPO environment whose actions select symbolic goals.

    A high-level action is resolved into one concrete goal.  Existing BFS,
    executor, and shield code then performs one tile move or one interaction.
    Thus the learned policy decides *what to pursue*, while deterministic and
    verifiable code decides *how to take the next safe step*.
    """

    metadata = {"render_modes": ["rgb_array"]}

    def __init__(
        self,
        task_id: str,
        *,
        seed: int | None = None,
        render_mode: str | None = None,
        max_macro_steps: int | None = None,
        base_reward_scale: float = 0.1,
        training_drain_interval: int | None = None,
    ) -> None:
        super().__init__()
        self.task_id = task_id
        self.seed_value = seed
        self.base_reward_scale = float(base_reward_scale)
        if training_drain_interval is not None and task_id == "mathematical_logic/task_5":
            # Training-only curriculum knob.  Final evaluation constructs this
            # environment without it and therefore always uses the official
            # 180-step interval.
            from nesylink.rewards.mathematical_logic import task_5 as task5_reward
            task5_reward._DRAIN_INTERVAL = int(training_drain_interval)
        self.max_macro_steps = int(
            max_macro_steps or TASK_MAX_MACRO_STEPS.get(task_id, 256)
        )
        self.env = make_env(
            task_id=task_id,
            observation_mode="pixels",
            render_mode=render_mode,
            action_repeat=1,
        )
        self.resolver = (
            Task5GoalResolver()
            if task_id == "mathematical_logic/task_5"
            else GoalResolver()
        )
        self.action_space = spaces.Discrete(self.resolver.action_count)
        self.observation_space = spaces.Box(
            low=-1.0,
            high=1.0,
            shape=(self.resolver.feature_dim,),
            dtype=np.float32,
        )
        self.perceptor = AdvancedPerceptor()
        self.state: SymbolicState | None = None
        self.last_obs: np.ndarray | None = None
        self.last_info: dict[str, Any] = {}
        self.last_option: int | None = None
        self.macro_steps = 0
        self.blocked_action: int | None = None
        self.bypass_alignment_once = False
        self.defense_cooldown = 0
        self.primitive_steps_total = 0

    @property
    def memory(self):
        return self.perceptor.memory

    def reset(self, *, seed: int | None = None, options: dict[str, Any] | None = None):
        del options
        effective_seed = self.seed_value if seed is None else seed
        self.perceptor.reset(task_id=self.task_id)
        self.last_option = None
        self.macro_steps = 0
        self.blocked_action = None
        self.bypass_alignment_once = False
        self.defense_cooldown = 0
        self.primitive_steps_total = 0
        obs, info = self.env.reset(seed=effective_seed)
        self.last_obs = np.asarray(obs)
        self.last_info = info
        # Set the initial room coordinate from the game info so that all
        # subsequent used_exits / room_memory global positions are consistent
        # with the actual dungeon coordinate system.
        if isinstance(info, dict):
            env_info = info.get("env", {})
            if isinstance(env_info, dict):
                raw = env_info.get("room_coord")
                if isinstance(raw, (list, tuple)) and len(raw) == 2:
                    self.memory.room = (int(raw[0]), int(raw[1]))
        self.state = self.perceptor.perceive(obs, info)
        self.memory.update(self.state)
        return self._encoded(), self._public_info(info)

    def action_masks(self) -> np.ndarray:
        if self.state is None:
            return np.ones(ACTION_COUNT, dtype=bool)
        return self.resolver.action_mask(self.state, self.memory)

    def step(self, action: int):
        if self.state is None or self.last_obs is None:
            raise RuntimeError("reset() must be called before step()")
        if not self.action_space.contains(action):
            raise ValueError(f"invalid high-level action: {action}")

        self.macro_steps += 1
        self.last_option = int(action)
        start_state = self.state
        goal = self.resolver.resolve(action, start_state, self.memory)
        invalid_option = goal is None
        task5_attack_progress = bool(
            self.task_id == "mathematical_logic/task_5"
            and self.resolver.is_attack(int(action))
            and hasattr(self.resolver, "attack_is_progress")
            and self.resolver.attack_is_progress(start_state, self.memory)
        )
        task5_selected_conditional_exit = bool(
            self.task_id == "mathematical_logic/task_5"
            and goal is not None
            and goal.kind == GoalKind.GO_TO_EXIT
            and goal.target in start_state.conditional_exits
        )
        task5_ignored_conditional_exit = bool(
            self.task_id == "mathematical_logic/task_5"
            and goal is not None
            and goal.kind == GoalKind.GO_TO_EXIT
            and goal.target not in start_state.conditional_exits
            and any(
                pos in start_state.conditional_exits
                and globalize(start_state.room, pos) not in self.memory.used_exits
                for pos in start_state.all_exits
            )
        )
        if goal is None:
            goal = Goal(kind=self._wait_kind())

        if self.defense_cooldown > 0:
            self.defense_cooldown -= 1
        defensive_action = (
            None
            if self.resolver.is_attack(int(action)) or self.defense_cooldown > 0
            else task5_defensive_action(start_state, self.memory)
        )
        if defensive_action is not None:
            # One block is enough to break the monster's interception line.
            # Keep advancing afterwards; alternating shield/move wastes the
            # task's strict 180-step health budget.
            self.defense_cooldown = 8
        if defensive_action is not None:
            raw_action, facing_only = defensive_action, True
        else:
            raw_action, facing_only = oriented_action_for_goal(
                start_state,
                goal,
                self.memory,
                skip_alignment=self.bypass_alignment_once,
            )
        self.bypass_alignment_once = False
        nudge_action = (
            unstick_nudge(start_state, self.blocked_action)
            if defensive_action is None and self.blocked_action == raw_action
            else None
        )
        if nudge_action is not None:
            raw_action = nudge_action
            facing_only = True
            self.blocked_action = None
            self.bypass_alignment_once = True
        primitive_action = raw_action if facing_only else shield(raw_action, start_state)
        leaving_attempt = self._leaving_attempt(start_state, primitive_action)
        transition_possible = self._transition_possible(start_state.player, primitive_action)
        repeats = 1
        if primitive_action in MOVE_DELTAS and not facing_only:
            repeats = (
                1 if leaving_attempt and self.task_id == "mathematical_logic/task_5"
                else 24 if leaving_attempt
                else
                2 if self.task_id == "mathematical_logic/task_5" and start_state.monsters
                and min(manhattan(start_state.player, monster) for monster in start_state.monsters) <= 3
                else 8 if self.task_id == "mathematical_logic/task_5"
                else 16
            )
        elif primitive_action in MOVE_DELTAS and nudge_action is not None:
            repeats = 4

        base_reward = 0.0
        events: Counter[str] = Counter()
        terminated = False
        truncated = False
        obs = self.last_obs
        info = self.last_info
        primitive_steps = 0
        room_changed_via_game = False
        for _ in range(repeats):
            obs, reward, terminated, truncated, info = self.env.step(primitive_action)
            primitive_steps += 1
            base_reward += float(reward)
            events.update(_event_names(info))
            if info.get("game", {}).get("room_changed", False):
                room_changed_via_game = True
            if terminated or truncated:
                break
        self.primitive_steps_total += primitive_steps

        # A room change requires clean static visual memory.  Use both the
        # pre-move heuristic and the ground-truth game flag so that vision is
        # reset even when the agent was not at the exact door edge at the
        # start of the macro action (e.g. it walked 2 tiles then crossed).
        if transition_possible or room_changed_via_game:
            self.perceptor.reset_room_vision()
        if primitive_action in MOVE_DELTAS:
            self.memory.facing_action = primitive_action
        next_state = self.perceptor.perceive(obs, info)
        if primitive_action in MOVE_DELTAS and nudge_action is None:
            before_px = start_state.player_position_px
            after_px = next_state.player_position_px
            if before_px is not None and after_px is not None:
                moved = abs(before_px[0] - after_px[0]) + abs(before_px[1] - after_px[1])
                self.blocked_action = primitive_action if moved < 0.5 else None
        # Use game info as ground truth; fall back to visual heuristic only when
        # the game flag was never set (e.g. the transition completed before any
        # step in *this* macro action, or the info dict was unavailable).
        room_changed = (
            room_changed_via_game
            or (
                transition_possible
                and self._transition_succeeded(start_state.player, next_state.player)
            )
        )
        discovered_exit = False
        if room_changed:
            discovered_exit = self._mark_transition(
                self._transition_exit_pos(start_state.player, primitive_action)
            )

        self.memory.last_goal = goal
        self.memory.last_action = primitive_action
        self.memory.update(next_state)
        self.state = next_state
        self.last_obs = np.asarray(obs)
        self.last_info = info

        high_level_truncated = self.macro_steps >= self.max_macro_steps
        truncated = bool(truncated or (high_level_truncated and not terminated))
        shaped_reward = self._shape_reward(
            base_reward=base_reward,
            events=events,
            invalid_option=invalid_option,
            info=info,
            terminated=terminated,
            discovered_exit=discovered_exit,
            room_changed=room_changed,
            task5_attack_progress=task5_attack_progress,
            task5_selected_conditional_exit=task5_selected_conditional_exit,
            task5_ignored_conditional_exit=task5_ignored_conditional_exit,
        )
        public_info = self._public_info(info)
        public_info["high_level"] = {
            "option": self.resolver.action_name(int(action)),
            "goal": goal.kind.value,
            "target": goal.target,
            "primitive_action": primitive_action,
            "primitive_steps": primitive_steps,
            "invalid_option": invalid_option,
            "base_reward": base_reward,
            "event_counts": dict(events),
            "room_changed_inferred": room_changed,
        }
        return self._encoded(), shaped_reward, bool(terminated), truncated, public_info

    def render(self):
        return self.env.render()

    def close(self) -> None:
        self.env.close()

    def _encoded(self) -> np.ndarray:
        if self.state is None:
            raise RuntimeError("no state available")
        mask = self.resolver.action_mask(self.state, self.memory)
        inventory = self.perceptor.inventory_features(self.last_info)
        if self.task_id == "mathematical_logic/task_5":
            return encode_task5_state(
                self.state,
                self.memory,
                inventory=inventory,
                action_mask=mask,
                last_option=self.last_option,
                elapsed_steps=self.primitive_steps_total,
            )
        return encode_high_level_state(
            self.state,
            self.memory,
            inventory=inventory,
            action_mask=mask,
            last_option=self.last_option,
        )

    def _shape_reward(
        self,
        *,
        base_reward: float,
        events: Counter[str],
        invalid_option: bool,
        info: dict[str, Any],
        terminated: bool,
        discovered_exit: bool,
        room_changed: bool,
        task5_attack_progress: bool,
        task5_selected_conditional_exit: bool,
        task5_ignored_conditional_exit: bool,
    ) -> float:
        reward = self.base_reward_scale * base_reward - 0.02
        if room_changed and not discovered_exit:
            # Remove the positive official transition reward and apply a small
            # cost.  Known-door crossings must not be profitable, but they also
            # cannot be punished heavily: tasks 3/4 require returning through
            # previously used doors after collecting a key or item.
            reward -= self.base_reward_scale * base_reward + 0.25
        if invalid_option:
            reward -= 0.5
        ineffective_attacks = events.get("action_attack", 0)
        effective_attacks = events.get("monster_damaged", 0) + events.get("monster_killed", 0)
        if ineffective_attacks > 0 and effective_attacks <= 0:
            reward -= 0.15 * ineffective_attacks
        if self.task_id == "mathematical_logic/task_5" and effective_attacks > 0:
            if task5_attack_progress:
                reward += 2.0 * effective_attacks
            else:
                reward -= 3.0 * effective_attacks
        bonuses = TASK5_EVENT_BONUSES if self.task_id == "mathematical_logic/task_5" else EVENT_BONUSES
        for name, count in events.items():
            reward += bonuses.get(name, 0.0) * count
        if self.task_id == "mathematical_logic/task_5":
            if task5_selected_conditional_exit and room_changed:
                reward += 5.0
            elif task5_selected_conditional_exit:
                reward += 0.1
            if task5_ignored_conditional_exit:
                reward -= 0.4
        # HP-aware healing: low HP → healing is worth more.  Teaches the policy
        # to seek healing chests when running low on health (critical under the
        # task-5 drain mechanic where the model cannot see HP in its features).
        if events.get("agent_healed", 0) > 0 and isinstance(info, dict):
            hp = info.get("agent", {}).get("hp", 99)
            if hp <= 2:
                reward += 2.0  # emergency heal bonus
            elif hp <= 3:
                reward += 1.0  # caution heal bonus
        if discovered_exit:
            reward += 1.0

        reason = info.get("terminal_reason") if isinstance(info, dict) else None
        completed = bool(
            info.get("game", {}).get("world_completed", False)
            if isinstance(info, dict)
            else False
        ) or reason == "world_completed"
        if completed:
            reward += 50.0 if self.task_id == "mathematical_logic/task_5" else 25.0
        elif terminated and reason == "agent_dead":
            reward -= 30.0 if self.task_id == "mathematical_logic/task_5" else 15.0
        return float(reward)

    def _leaving_attempt(self, state: SymbolicState, action: int) -> bool:
        if action not in MOVE_DELTAS or state.player not in state.all_exits:
            return False
        candidate = next_position(state.player, action)
        return not (0 <= candidate[0] < 10 and 0 <= candidate[1] < 8)

    def _transition_succeeded(
        self,
        start: tuple[int, int],
        end: tuple[int, int],
    ) -> bool:
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

    def _transition_possible(self, start: tuple[int, int], action: int) -> bool:
        col, row = start
        return bool(
            (action == 3 and col <= 1)
            or (action == 4 and col >= 8)
            or (action == 1 and row <= 1)
            or (action == 2 and row >= 6)
        )

    def _transition_exit_pos(
        self,
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

    def _mark_transition(self, exit_pos: tuple[int, int]) -> bool:
        room = self.memory.room
        departure = globalize(room, exit_pos)
        discovered = departure not in self.memory.used_exits
        self._mark_exit_pair(room, exit_pos)
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
            return discovered
        destination = (room[0] + delta[0], room[1] + delta[1])
        self.memory.pending_room_delta = delta
        # The same physical doorway must be remembered from both rooms.  If
        # the arrival side remains "new", TAKE_NEW_EXIT immediately chooses
        # it and creates a two-room loop.
        self._mark_exit_pair(destination, arrival)
        return discovered

    def _mark_exit_pair(self, room: tuple[int, int], pos: tuple[int, int]) -> None:
        self.memory.used_exits.add(globalize(room, pos))
        col, row = pos
        if row in {0, 7}:
            for other_col in (col - 1, col + 1):
                if 0 <= other_col < 10:
                    self.memory.used_exits.add(globalize(room, (other_col, row)))
        if col in {0, 9}:
            for other_row in (row - 1, row + 1):
                if 0 <= other_row < 8:
                    self.memory.used_exits.add(globalize(room, (col, other_row)))

    def _public_info(self, info: dict[str, Any]) -> dict[str, Any]:
        # Returning diagnostic info from the environment is fine; observations
        # consumed by the model remain pixels-derived features + inventory only.
        clean = dict(info)
        if "episode" in clean:
            clean["nesylink_episode"] = clean.pop("episode")
        return clean

    @staticmethod
    def _wait_kind():
        from rule_based_submission.symbolic import GoalKind

        return GoalKind.WAIT


def _event_names(info: dict[str, Any]) -> list[str]:
    records = info.get("events", {}).get("records", []) if isinstance(info, dict) else []
    return [
        str(record.get("name"))
        for record in records
        if isinstance(record, dict) and record.get("name") is not None
    ]
