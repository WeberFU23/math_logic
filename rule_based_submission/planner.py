from __future__ import annotations

from collections import deque

from rule_based_submission.symbolic import (
    Goal,
    GoalKind,
    MOVE_DELTAS,
    Position,
    SymbolicState,
    action_from_step,
    in_bounds,
    manhattan,
    neighbors,
    next_position,
)


def is_walkable(pos: Position, state: SymbolicState, *, allow_goal: bool = False) -> bool:
    if not in_bounds(pos):
        return False
    blockers = set(state.walls) | set(state.traps) | set(state.chests)
    blockers |= set(state.monsters) | set(state.npcs)
    blockers |= set(state.gaps) - set(state.bridges)
    if allow_goal:
        blockers -= state.all_exits
    return pos not in blockers


def goal_tiles(goal: Goal, state: SymbolicState) -> set[Position]:
    if goal.target is None:
        return set()
    if goal.kind in {GoalKind.OPEN_CHEST, GoalKind.ATTACK_MONSTER}:
        return {pos for pos in neighbors(goal.target) if is_walkable(pos, state)}
    if goal.kind == GoalKind.ACTIVATE_SWITCH:
        # button: step onto it; switch: stand adjacent and press A
        if goal.target in state.buttons:
            return {goal.target}
        return {pos for pos in neighbors(goal.target) if is_walkable(pos, state)}
    if goal.kind == GoalKind.GO_TO_EXIT:
        return {goal.target}
    if goal.kind == GoalKind.EXPLORE:
        return {goal.target}
    return set()


def bfs_path(state: SymbolicState, goals: set[Position], preferred_action: int | None = None) -> list[Position] | None:
    if not goals:
        return None
    queue: deque[Position] = deque([state.player])
    parent: dict[Position, Position | None] = {state.player: None}

    while queue:
        current = queue.popleft()
        if current in goals:
            return _reconstruct(parent, current)
        candidates = neighbors(current)
        if current == state.player and preferred_action in MOVE_DELTAS:
            preferred_step = next_position(current, preferred_action)
            candidates.sort(key=lambda pos: 0 if pos == preferred_step else 1)
        for nxt in candidates:
            if nxt in parent:
                continue
            if nxt not in goals and not is_walkable(nxt, state):
                continue
            if nxt in goals and not is_walkable(nxt, state, allow_goal=True):
                continue
            parent[nxt] = current
            queue.append(nxt)
    return None


def is_reachable(state: SymbolicState, goal: Goal) -> bool:
    return bfs_path(state, goal_tiles(goal, state)) is not None


def next_move_toward(state: SymbolicState, goal: Goal, preferred_action: int | None = None) -> int | None:
    path = bfs_path(state, goal_tiles(goal, state), preferred_action=preferred_action)
    if path is None or len(path) < 2:
        return None
    return action_from_step(path[0], path[1])


def nearest(candidates: set[Position], origin: Position) -> Position | None:
    if not candidates:
        return None
    return min(candidates, key=lambda pos: (manhattan(origin, pos), pos[1], pos[0]))


def _reconstruct(parent: dict[Position, Position | None], current: Position) -> list[Position]:
    path: list[Position] = []
    while current is not None:
        path.append(current)
        current = parent[current]
    path.reverse()
    return path
