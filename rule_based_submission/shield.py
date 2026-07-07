from __future__ import annotations

from rule_based_submission.planner import is_walkable
from rule_based_submission.symbolic import (
    ACTION_A,
    ACTION_B,
    ACTION_NOOP,
    MOVE_DELTAS,
    SymbolicState,
    next_position,
)


def shield(action: int, state: SymbolicState) -> int:
    if action in {ACTION_NOOP, ACTION_A, ACTION_B}:
        return action
    if action not in MOVE_DELTAS:
        return ACTION_NOOP
    candidate = next_position(state.player, action)
    if state.player in state.exits and not (0 <= candidate[0] < 10 and 0 <= candidate[1] < 8):
        return action
    if not is_walkable(candidate, state, allow_goal=True):
        return ACTION_NOOP
    return action


