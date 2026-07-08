from __future__ import annotations

from rule_based_submission.planner import is_walkable
from rule_based_submission.symbolic import (
    ACTION_A,
    ACTION_B,
    ACTION_DOWN,
    ACTION_LEFT,
    ACTION_NOOP,
    ACTION_RIGHT,
    ACTION_UP,
    MOVE_DELTAS,
    Position,
    SymbolicState,
    manhattan,
    next_position,
)


def shield(action: int, state: SymbolicState) -> int:
    if action in {ACTION_NOOP, ACTION_A, ACTION_B}:
        return action
    if action not in MOVE_DELTAS:
        return ACTION_NOOP
    candidate = next_position(state.player, action)
    if state.player in state.all_exits and not (0 <= candidate[0] < 10 and 0 <= candidate[1] < 8):
        return action
    if not is_walkable(candidate, state, allow_goal=True):
        return ACTION_NOOP
    return action


# ---------------------------------------------------------------------------
# shared combat reflex — used by both rule-based and RL-based agents
# ---------------------------------------------------------------------------


def combat_reflex(
    state: SymbolicState,
    facing_action: int,
    has_sword: bool,
    has_shield: bool,
) -> int | None:
    """Return an urgent combat action when a monster threatens the player.

    Returns ``None`` when there is no immediate threat, letting the
    caller proceed with normal planning.
    """
    if not state.monsters:
        return None

    player = state.player
    near_threats = [
        m for m in state.monsters
        if manhattan(player, m) <= 2
        and not _wall_between(state, player, m)
    ]
    if not near_threats:
        return None

    target = min(near_threats, key=lambda m: _monster_rank(player, m, facing_action))
    m_dist = manhattan(player, target)

    # -- cardinal adjacent (manhattan == 1) ---------------------------------
    if m_dist == 1:
        if has_sword and _is_facing(player, target, facing_action):
            return ACTION_A
        retreat = _step_away(state, target)
        if retreat is not None:
            return retreat
        if has_shield:
            return ACTION_B
        return None

    # -- diagonal adjacent (manhattan == 2, euclidean < 1.5) ----------------
    if has_sword:
        approach = _step_toward_safe(state, target)
        if approach is not None:
            return approach
    if has_shield:
        return ACTION_B
    return None


def _is_facing(player: Position, target: Position, facing_action: int) -> bool:
    """True when the facing direction points toward the target."""
    dx = target[0] - player[0]
    dy = target[1] - player[1]
    if facing_action == ACTION_UP:
        return dy < 0
    if facing_action == ACTION_DOWN:
        return dy > 0
    if facing_action == ACTION_LEFT:
        return dx < 0
    if facing_action == ACTION_RIGHT:
        return dx > 0
    return False


def _step_away(state: SymbolicState, monster: Position) -> int | None:
    """Move one tile directly away from *monster*, if walkable."""
    px, py = state.player
    dx = monster[0] - px
    dy = monster[1] - py
    if abs(dx) >= abs(dy):
        candidates = [
            ACTION_LEFT if dx > 0 else ACTION_RIGHT,
            ACTION_UP if dy > 0 else ACTION_DOWN,
        ]
    else:
        candidates = [
            ACTION_UP if dy > 0 else ACTION_DOWN,
            ACTION_LEFT if dx > 0 else ACTION_RIGHT,
        ]
    candidates.extend(
        a for a in (ACTION_UP, ACTION_DOWN, ACTION_LEFT, ACTION_RIGHT)
        if a not in candidates
    )
    for action in candidates:
        pos = next_position(state.player, action)
        if not is_walkable(pos, state, allow_goal=True):
            continue
        if pos in state.monsters:
            continue
        if manhattan(pos, monster) > 1:
            return action
    return None


def _step_toward_safe(state: SymbolicState, monster: Position) -> int | None:
    """Move one step toward *monster* without walking into any monster."""
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


def _wall_between(
    state: SymbolicState, player: Position, monster: Position
) -> bool:
    """True when a wall blocks the direct path between player and monster."""
    px, py = player
    mx, my = monster
    dist = manhattan(player, monster)
    if dist <= 1:
        return False
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


def _monster_rank(
    player: Position, monster: Position, facing_action: int
) -> tuple[int, int, Position]:
    """Sort key: prefer the nearest monster that we are already facing."""
    facing_penalty = 0 if _is_facing(player, monster, facing_action) else 1
    return (manhattan(player, monster), facing_penalty, monster)
