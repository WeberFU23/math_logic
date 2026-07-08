from __future__ import annotations

from abc import ABC, abstractmethod

from rule_based_submission.planner import is_reachable, nearest
from rule_based_submission.symbolic import AgentMemory, Goal, GoalKind, Position, RoomCoord, SymbolicState, globalize, manhattan


class HighLevelPolicy(ABC):
    @abstractmethod
    def choose_goal(self, state: SymbolicState, memory: AgentMemory) -> Goal:
        """Return the next symbolic goal.

        A future RL policy can implement this same method and replace the rule
        selector without touching perception, BFS planning, execution, or shield.
        """


class RuleBasedPolicy(HighLevelPolicy):
    """Generic progress-first symbolic controller.

    The policy deliberately avoids task ids and fixed coordinates. It ranks the
    currently perceived symbolic affordances by the kind of progress they can
    unlock: visible rewards/resources, local mechanisms, necessary combat, then
    exits and fallback exploration.
    """

    def __init__(self, *, debug: bool = False) -> None:
        self._debug = debug

    def _log(self, msg: str) -> None:
        if self._debug:
            print(f"  [strategy] {msg}")

    def choose_goal(self, state: SymbolicState, memory: AgentMemory) -> Goal:
        door_exits = self._door_exits(state)
        mechanisms = self._mechanisms(state)
        unopened_chests = {
            pos for pos in state.chests
            if globalize(state.room, pos) not in memory.opened_chests
        }
        live_monsters = set(state.monsters)

        reachable_chests = self._reachable_goals(state, GoalKind.OPEN_CHEST, unopened_chests)
        reachable_mechanisms = self._reachable_goals(state, GoalKind.ACTIVATE_SWITCH, mechanisms)
        reachable_monsters = self._reachable_goals(state, GoalKind.ATTACK_MONSTER, live_monsters)
        reachable_new_exits = self._reachable_goals(
            state,
            GoalKind.GO_TO_EXIT,
            {pos for pos in door_exits if globalize(state.room, pos) not in memory.used_exits},
        )
        reachable_all_exits = self._reachable_goals(state, GoalKind.GO_TO_EXIT, door_exits)

        # ── 1. sticky goal ───────────────────────────────────────────
        sticky_goal = self._continue_last_goal(
            state, memory, unopened_chests, live_monsters, mechanisms, door_exits,
        )
        if sticky_goal is not None:
            self._log(f"1.STICKY  → {sticky_goal.kind.value}:{sticky_goal.target}")
            return sticky_goal

        # ── 2. adjacent actionable  ──────────────────────────────────
        adjacent = self._adjacent_goal(state, reachable_chests)
        if adjacent is not None:
            self._log(f"2.ADJ_CHEST → {adjacent.target}")
            return adjacent
        if state.has_sword:
            adjacent = self._adjacent_goal(state, reachable_monsters)
            if adjacent is not None and self._safe_to_fight(state):
                self._log(f"2.ADJ_MON → {adjacent.target}")
                return adjacent
        adjacent = self._adjacent_goal(state, reachable_mechanisms)
        if adjacent is not None:
            self._log(f"2.ADJ_MECH → {adjacent.target}")
            return adjacent

        # ── 3. reachable chests ──────────────────────────────────────
        if reachable_chests:
            goal = self._nearest_goal(state, reachable_chests)
            self._log(f"3.CHEST → {goal.target}")
            return goal

        # ── 4. unused exits ──────────────────────────────────────────
        if reachable_new_exits:
            goal = self._best_exit_goal(state, memory, reachable_new_exits)
            self._log(f"4.EXIT_NEW → {goal.target}  candidates={[g.target for g in reachable_new_exits]}")
            return goal

        # ── 5. mechanisms ────────────────────────────────────────────
        mechanism_goal = self._mechanism_goal(state, memory, reachable_mechanisms)
        if mechanism_goal is not None:
            self._log(f"5.MECH → {mechanism_goal.target}")
            return mechanism_goal

        # ── 6. monsters (only when the room has nothing else of value) ─
        if state.has_sword and reachable_monsters and self._room_is_cleared(state, memory):
            goal = self._nearest_goal(state, reachable_monsters)
            self._log(f"6.MONSTER → {goal.target}")
            return goal

        # ── 7. used exits (fallback) ─────────────────────────────────
        if reachable_all_exits:
            goal = self._best_exit_goal(state, memory, reachable_all_exits, allow_used=True)
            self._log(f"7.EXIT_USED → {goal.target}")
            return goal

        # ── 8. explore ───────────────────────────────────────────────
        frontier = self._frontier(state)
        if frontier is not None:
            self._log(f"8.EXPLORE → {frontier}")
            return Goal(GoalKind.EXPLORE, frontier)

        # ── 9. wait (should not normally be reached) ─────────────────
        self._log(f"9.WAIT  chests_in_view={state.chests}  unopened={unopened_chests}  rc={[g.target for g in reachable_chests]}  mechanisms={mechanisms}  rmech={[g.target for g in reachable_mechanisms]}")
        return Goal(GoalKind.WAIT)

    def _continue_last_goal(
        self,
        state: SymbolicState,
        memory: AgentMemory,
        unopened_chests: set[Position],
        live_monsters: set[Position],
        mechanisms: set[Position],
        door_exits: set[Position],
    ) -> Goal | None:
        goal = memory.last_goal
        if goal is None or goal.target is None:
            return None
        target = goal.target
        if goal.kind == GoalKind.OPEN_CHEST and target in unopened_chests:
            return goal if is_reachable(state, goal) or manhattan(state.player, target) == 1 else None
        if goal.kind == GoalKind.ATTACK_MONSTER and target in live_monsters and self._safe_to_fight(state):
            return goal if is_reachable(state, goal) or manhattan(state.player, target) == 1 else None
        if goal.kind == GoalKind.ACTIVATE_SWITCH and target in mechanisms:
            return goal if is_reachable(state, goal) or manhattan(state.player, target) == 1 else None
        if goal.kind == GoalKind.GO_TO_EXIT and target in door_exits:
            if mechanisms and (state.keys > 0 or state.has_sword):
                return None
            if state.player == target:
                return None if globalize(state.room, target) in memory.used_exits else goal
            return goal if is_reachable(state, goal) else None
        return None
    def _mechanisms(self, state: SymbolicState) -> set[Position]:
        # Vision may confuse door-edge glyphs for switches/buttons. Mechanisms are
        # floor objects; boundary door tiles should remain exits, not A targets.
        return {pos for pos in (state.switches | state.buttons) if pos not in self._door_exits(state)}

    def _door_exits(self, state: SymbolicState) -> set[Position]:
        return {
            (col, row)
            for col, row in state.exits
            if (row in {0, 7} and col in {4, 5})
            or (col in {0, 9} and row in {3, 4})
        }

    def _adjacent_goal(self, state: SymbolicState, goals: list[Goal]) -> Goal | None:
        adjacent = [goal for goal in goals if goal.target is not None and manhattan(state.player, goal.target) == 1]
        return self._nearest_goal(state, adjacent) if adjacent else None

    def _reachable_goals(self, state: SymbolicState, kind: GoalKind, positions: set[Position]) -> list[Goal]:
        goals = [Goal(kind, pos) for pos in positions]
        return [goal for goal in goals if is_reachable(state, goal) or state.player == goal.target]

    def _safe_to_fight(self, state: SymbolicState) -> bool:
        return state.health is None or state.health > 1

    def _room_is_cleared(self, state: SymbolicState, memory: AgentMemory) -> bool:
        """Room has no valuable targets left except monsters — only then fight."""
        unopened = {pos for pos in state.chests if globalize(state.room, pos) not in memory.opened_chests}
        if unopened:
            return False
        unused_exits = {pos for pos in self._door_exits(state) if globalize(state.room, pos) not in memory.used_exits}
        if unused_exits:
            return False
        unused_mechanisms = {
            pos for pos in self._mechanisms(state)
            if globalize(state.room, pos) not in memory.activated_switches
        }
        if unused_mechanisms:
            return False
        return True

    def _mechanism_goal(self, state: SymbolicState, memory: AgentMemory, goals: list[Goal]) -> Goal | None:
        if not goals:
            return None
        if memory.switch_cooldown > 0:
            return None
        unused = [goal for goal in goals if goal.target is not None and globalize(state.room, goal.target) not in memory.activated_switches]
        if unused:
            return self._nearest_goal(state, unused)
        return self._nearest_goal(state, goals)

    def _best_exit_goal(
        self,
        state: SymbolicState,
        memory: AgentMemory,
        goals: list[Goal],
        *,
        allow_used: bool = False,
    ) -> Goal:
        candidates = goals if allow_used else [goal for goal in goals if goal.target is not None]
        forward = self._avoid_entry_side(state, memory, candidates)
        candidates = forward or candidates

        def rank(goal: Goal) -> tuple[int, int, int, int, int, Position]:
            target = goal.target or state.player
            neighbor = self._neighbor_room(state.room, target)
            unvisited = 0 if neighbor is not None and neighbor not in memory.room_memory else 1
            used = 1 if globalize(state.room, target) in memory.used_exits else 0
            blocked_approach = 1 if self._exit_approach_blocked(state, target) else 0
            key_bonus = 0 if state.keys > 0 and target[0] == 9 else 1
            entry = 1 if self._is_entry_side(state, goal) and memory.room_steps <= 4 else 0
            return (used, blocked_approach, unvisited, entry, key_bonus + manhattan(state.player, target), target)

        return min(candidates, key=rank)

    def _exit_approach_blocked(self, state: SymbolicState, exit_pos: Position) -> bool:
        col, row = exit_pos
        if col == 0:
            approach = (1, row)
        elif col == 9:
            approach = (8, row)
        elif row == 0:
            approach = (col, 1)
        elif row == 7:
            approach = (col, 6)
        else:
            return False
        return approach in (state.walls | state.traps | state.gaps | state.chests | state.monsters)

    def _neighbor_room(self, room: RoomCoord, exit_pos: Position) -> RoomCoord | None:
        col, row = exit_pos
        if row == 0:
            return (room[0], room[1] - 1)
        if row == 7:
            return (room[0], room[1] + 1)
        if col == 0:
            return (room[0] - 1, room[1])
        if col == 9:
            return (room[0] + 1, room[1])
        return None

    def _avoid_entry_side(self, state: SymbolicState, memory: AgentMemory, goals: list[Goal]) -> list[Goal]:
        if memory.room_steps > 4:
            return goals
        filtered = [goal for goal in goals if not self._is_entry_side(state, goal)]
        return filtered if filtered else goals

    def _is_entry_side(self, state: SymbolicState, goal: Goal) -> bool:
        target = goal.target or state.player
        return (
            (state.player[0] <= 1 and target[0] == 0)
            or (state.player[0] >= 8 and target[0] == 9)
            or (state.player[1] <= 1 and target[1] == 0)
            or (state.player[1] >= 6 and target[1] == 7)
        )

    def _nearest_goal(self, state: SymbolicState, goals: list[Goal]) -> Goal:
        return min(goals, key=lambda goal: (manhattan(state.player, goal.target or state.player), goal.target or (0, 0)))

    def _frontier(self, state: SymbolicState) -> Position | None:
        blockers = state.walls | state.traps | state.gaps | state.chests | state.monsters
        candidates = {
            (col, row)
            for row in range(8)
            for col in range(10)
            if (col, row) not in blockers
        }
        return nearest(candidates, state.player)


class RLHighLevelPolicy(HighLevelPolicy):
    def choose_goal(self, state: SymbolicState, memory: AgentMemory) -> Goal:
        raise NotImplementedError("Plug a trained RL goal selector in here.")








