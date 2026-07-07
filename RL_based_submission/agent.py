from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np

from RL_based_submission.features import FeatureState

try:
    from stable_baselines3 import PPO
except Exception:  # pragma: no cover
    PPO = None

PROJECT_ROOT = Path(__file__).resolve().parent.parent
MODEL_DIR = PROJECT_ROOT / "RL_based_submission" / "models"
ACTION_WAIT = 0
ACTION_A = 5


class Policy:
    def __init__(self) -> None:
        self.features = FeatureState.create()
        self.model = None
        self.task_id: str | None = None
        self._queued_action = ACTION_WAIT
        self._queued_ticks = 0

    def reset(self, seed: int | None = None, task_id: str | None = None) -> None:
        del seed
        self.features.reset(task_id=task_id)
        self.task_id = task_id
        self.model = _load_model(task_id)
        self._queued_action = ACTION_WAIT
        self._queued_ticks = 0

    def act(self, obs: Any, info: dict[str, Any] | None = None) -> int:
        if self._queued_ticks > 0:
            self._queued_ticks -= 1
            return self._queued_action
        if self.model is None:
            self.model = _load_model(self.task_id)
        if self.model is None:
            return ACTION_WAIT
        features = self.features.encode(np.asarray(obs), info)
        action, _ = self.model.predict(features, deterministic=True)
        chosen = int(np.asarray(action).item())
        self._queued_action = chosen
        self._queued_ticks = 15 if chosen != ACTION_WAIT else 0
        return chosen


def _load_model(task_id: str | None):
    if PPO is None or not task_id:
        return None
    model_path = MODEL_DIR / f"{task_id.replace('/', '_')}.zip"
    if not model_path.exists():
        return None
    return PPO.load(model_path)


def make_policy() -> Policy:
    return Policy()
