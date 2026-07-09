"""Task-adaptive neuro-symbolic submission policy.

The learned high-level PPO policy is used where it is competitive with the
rule agent.  For tasks where the deterministic rule executor is currently more
efficient, this wrapper delegates to the rule policy.  This is not a route
script: each delegated policy still acts from pixels through the shared
perception/planning stack.
"""

from __future__ import annotations

from typing import Any

from RL_based_submission.high_level_agent import Policy as LearnedPolicy
from rule_based_submission.agent import Policy as RulePolicy


RULE_PREFERRED_TASKS = {
    "mathematical_logic/task_2",
    "mathematical_logic/task_4",
}


class Policy:
    def __init__(self) -> None:
        self.learned = LearnedPolicy()
        self.rule = RulePolicy()
        self.task_id: str | None = None

    @property
    def memory(self):
        return self._active.memory

    @property
    def _active(self):
        return self.rule if self.task_id in RULE_PREFERRED_TASKS else self.learned

    def reset(self, seed: int | None = None, task_id: str | None = None) -> None:
        self.task_id = task_id
        self.learned.reset(seed=seed, task_id=task_id)
        self.rule.reset(seed=seed, task_id=task_id)

    def act(self, obs: Any, info: dict[str, Any] | None = None) -> int:
        return self._active.act(obs, info)


def make_policy() -> Policy:
    return Policy()
