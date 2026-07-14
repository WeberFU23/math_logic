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


def action_for_goal(state: SymbolicState, goal: Goal, preferred_action: int | None = None) -> int:
    if goal.kind == GoalKind.WAIT or goal.target is None:
        return ACTION_NOOP

    if goal.kind in {GoalKind.OPEN_CHEST, GoalKind.ATTACK_MONSTER}:
        if manhattan(state.player, goal.target) == 1:
            return ACTION_A
        move = next_move_toward(state, goal, preferred_action=preferred_action)
        return ACTION_NOOP if move is None else move

    if goal.kind == GoalKind.ACTIVATE_SWITCH:
        # button: step onto it (triggers automatically); switch: press A adjacent
        if goal.target in state.buttons:
            if state.player == goal.target:
                return ACTION_NOOP  # already on the button
            move = next_move_toward(state, goal, preferred_action=preferred_action)
            return ACTION_NOOP if move is None else move
        if manhattan(state.player, goal.target) == 1:
            return ACTION_A
        move = next_move_toward(state, goal, preferred_action=preferred_action)
        return ACTION_NOOP if move is None else move

    if goal.kind == GoalKind.GO_TO_EXIT:
        if state.player == goal.target:
            return _exit_push_action(goal.target)
        move = next_move_toward(state, goal, preferred_action=preferred_action)
        return ACTION_NOOP if move is None else move

    if goal.kind == GoalKind.EXPLORE:
        move = next_move_toward(state, goal, preferred_action=preferred_action)
        return ACTION_NOOP if move is None else move

    return ACTION_NOOP


def _exit_push_action(target: tuple[int, int]) -> int:
    col, row = target
    if row == 0:
        return ACTION_UP
    if row == 7:
        return ACTION_DOWN
    if col == 0:
        return ACTION_LEFT
    if col == 9:
        return ACTION_RIGHT
    return ACTION_NOOP
