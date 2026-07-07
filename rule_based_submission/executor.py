from __future__ import annotations

from rule_based_submission.planner import next_move_toward
from rule_based_submission.symbolic import (
    ACTION_A,
    ACTION_DOWN,
    ACTION_LEFT,
    ACTION_NOOP,
    ACTION_RIGHT,
    ACTION_UP,
    Goal,
    GoalKind,
    SymbolicState,
    manhattan,
)


def action_for_goal(state: SymbolicState, goal: Goal) -> int:
    if goal.kind == GoalKind.WAIT or goal.target is None:
        return ACTION_NOOP

    if goal.kind in {GoalKind.OPEN_CHEST, GoalKind.ATTACK_MONSTER, GoalKind.ACTIVATE_SWITCH}:
        if manhattan(state.player, goal.target) == 1:
            return ACTION_A
        move = next_move_toward(state, goal)
        return ACTION_NOOP if move is None else move

    if goal.kind == GoalKind.GO_TO_EXIT:
        if state.player == goal.target:
            if goal.target[1] == 0:
                return ACTION_UP
            if goal.target[1] == 7:
                return ACTION_DOWN
            if goal.target[0] == 0:
                return ACTION_LEFT
            if goal.target[0] == 9:
                return ACTION_RIGHT
        move = next_move_toward(state, goal)
        return ACTION_NOOP if move is None else move

    if goal.kind == GoalKind.EXPLORE:
        move = next_move_toward(state, goal)
        return ACTION_NOOP if move is None else move

    return ACTION_NOOP


