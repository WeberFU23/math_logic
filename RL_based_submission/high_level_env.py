from __future__ import annotations

from collections import Counter
from typing import Any

import gymnasium as gym
import numpy as np
from gymnasium import spaces

from nesylink.env import make_env
from RL_based_submission.advanced_perception import AdvancedPerceptor
from RL_based_submission.high_level_core import (
    ACTION_COUNT,
    FEATURE_DIM,
    GoalResolver,
    HighLevelAction,
    encode_high_level_state,
    oriented_action_for_goal,
)
from rule_based_submission.shield import shield
from rule_based_submission.symbolic import (
    ACTION_NOOP,
    MOVE_DELTAS,
    Goal,
    SymbolicState,
    globalize,
    next_position,
)


TASK_MAX_MACRO_STEPS = {
    "mathematical_logic/task_1": 128,
    "mathematical_logic/task_2": 160,
    "mathematical_logic/task_3": 256,
    "mathematical_logic/task_4": 320,
    "mathematical_logic/task_5": 320,
}

EVENT_BONUSES = {
    "chest_opened": 1.5,
    "key_collected": 4.0,
    "item_collected": 4.0,
    "monster_killed": 4.0,
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
    "agent_healed": 1.0,
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
    ) -> None:
        super().__init__()
        self.task_id = task_id
        self.seed_value = seed
        self.base_reward_scale = float(base_reward_scale)
        self.max_macro_steps = int(
            max_macro_steps or TASK_MAX_MACRO_STEPS.get(task_id, 256)
        )
        self.env = make_env(
            task_id=task_id,
            observation_mode="pixels",
            render_mode=render_mode,
            action_repeat=1,
        )
        self.action_space = spaces.Discrete(ACTION_COUNT)
        self.observation_space = spaces.Box(
            low=-1.0,
            high=1.0,
            shape=(FEATURE_DIM,),
            dtype=np.float32,
        )
        self.perceptor = AdvancedPerceptor()
        self.resolver = GoalResolver()
        self.state: SymbolicState | None = None
        self.last_obs: np.ndarray | None = None
        self.last_info: dict[str, Any] = {}
        self.last_option: int | None = None
        self.macro_steps = 0

    @property
    def memory(self):
        return self.perceptor.memory

    def reset(self, *, seed: int | None = None, options: dict[str, Any] | None = None):
        del options
        effective_seed = self.seed_value if seed is None else seed
        self.perceptor.reset(task_id=self.task_id)
        self.last_option = None
        self.macro_steps = 0
        obs, info = self.env.reset(seed=effective_seed)
        self.last_obs = np.asarray(obs)
        self.last_info = info
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
        if goal is None:
            goal = Goal(kind=self._wait_kind())

        raw_action, facing_only = oriented_action_for_goal(start_state, goal, self.memory)
        primitive_action = raw_action if facing_only else shield(raw_action, start_state)
        leaving_attempt = self._leaving_attempt(start_state, primitive_action)
        transition_possible = self._transition_possible(start_state.player, primitive_action)
        repeats = 1
        if primitive_action in MOVE_DELTAS and not facing_only:
            repeats = 24 if leaving_attempt else 16

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

        # A room change requires clean static visual memory.  Use both the
        # pre-move heuristic and the ground-truth game flag so that vision is
        # reset even when the agent was not at the exact door edge at the
        # start of the macro action (e.g. it walked 2 tiles then crossed).
        if transition_possible or room_changed_via_game:
            self.perceptor.reset_room_vision()
        if primitive_action in MOVE_DELTAS:
            self.memory.facing_action = primitive_action
        next_state = self.perceptor.perceive(obs, info)
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
        )
        public_info = self._public_info(info)
        public_info["high_level"] = {
            "option": HighLevelAction(int(action)).name,
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
        for name, count in events.items():
            reward += EVENT_BONUSES.get(name, 0.0) * count
        if discovered_exit:
            reward += 1.0

        reason = info.get("terminal_reason") if isinstance(info, dict) else None
        completed = bool(
            info.get("game", {}).get("world_completed", False)
            if isinstance(info, dict)
            else False
        ) or reason == "world_completed"
        if completed:
            reward += 25.0
        elif terminated and reason == "agent_dead":
            reward -= 15.0
        return float(reward)

    def _leaving_attempt(self, state: SymbolicState, action: int) -> bool:
        if action not in MOVE_DELTAS or state.player not in state.exits:
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
