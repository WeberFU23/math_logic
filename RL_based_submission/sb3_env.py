from __future__ import annotations

from typing import Any

import gymnasium as gym
import numpy as np
from gymnasium import spaces

from nesylink.env import make_env
from RL_based_submission.features import FEATURE_DIM, FeatureState

TASK_MAX_STEPS = {
    "mathematical_logic/task_1": 500,
    "mathematical_logic/task_2": 500,
    "mathematical_logic/task_3": 1500,
    "mathematical_logic/task_4": 2000,
    "mathematical_logic/task_5": 2000,
}


class SymbolicFeatureEnv(gym.Env):
    metadata = {"render_modes": ["rgb_array"]}

    def __init__(
        self,
        task_id: str,
        *,
        seed: int | None = None,
        max_steps: int | None = None,
        reward_kwargs: dict[str, float] | None = None,
        action_repeat: int = 16,
    ) -> None:
        super().__init__()
        self.task_id = task_id
        self.seed_value = seed
        self.action_repeat = int(action_repeat)
        effective_max_steps = max_steps
        if effective_max_steps is None:
            task_max = TASK_MAX_STEPS.get(task_id)
            effective_max_steps = None if task_max is None else task_max * self.action_repeat
        self.env = make_env(
            task_id=task_id,
            observation_mode="pixels",
            render_mode="rgb_array",
            max_steps=effective_max_steps,
            reward_kwargs=reward_kwargs,
            action_repeat=self.action_repeat,
        )
        self.features = FeatureState.create()
        self.action_space = self.env.action_space
        self.observation_space = spaces.Box(low=-1.0, high=1.0, shape=(FEATURE_DIM,), dtype=np.float32)
        self._last_info: dict[str, Any] = {}

    @property
    def last_info(self) -> dict[str, Any]:
        return self._last_info

    def reset(self, *, seed: int | None = None, options: dict[str, Any] | None = None):
        del options
        self.features.reset(task_id=self.task_id)
        obs, info = self.env.reset(seed=self.seed_value if seed is None else seed)
        clean = _clean_info(info)
        self._last_info = clean
        return self.features.encode(obs, info), clean

    def step(self, action: int):
        obs, reward, terminated, truncated, info = self.env.step(int(action))
        clean = _clean_info(info)
        self._last_info = clean
        return self.features.encode(obs, info), float(reward), bool(terminated), bool(truncated), clean

    def render(self):
        return self.env.render()

    def close(self) -> None:
        self.env.close()


def _clean_info(info: dict[str, Any]) -> dict[str, Any]:
    clean = dict(info)
    if "episode" in clean:
        clean["nesylink_episode"] = clean.pop("episode")
    return clean
