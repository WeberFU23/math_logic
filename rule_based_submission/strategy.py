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

    The priority chain ranks the currently perceived symbolic affordances:
    chests > buttons (for conditional doors) > exits (normal > conditional > locked)
    > switches > explore > wait.
    """

    def __init__(self, *, debug: bool = False) -> None:
        self._debug = debug

    def _log(self, msg: str) -> None:
        if self._debug:
            print(f"  [strategy] {msg}")

    # ------------------------------------------------------------------
    # main priority chain
    # ------------------------------------------------------------------

    def choose_goal(self, state: SymbolicState, memory: AgentMemory) -> Goal:
        door_exits = self._door_exits(state)
        door_normal = self._door_normal(state)
        door_locked = self._door_locked(state)
        door_conditional = self._door_conditional(state)
        mechanisms = self._mechanisms(state)          # switches only
        has_cond_door = bool(door_conditional)
        have_key = state.keys > 0

        unopened_chests = {
            pos for pos in state.chests
            if globalize(state.room, pos) not in memory.opened_chests
        }
        live_monsters = set(state.monsters)

        reachable_chests = self._reachable_goals(state, GoalKind.OPEN_CHEST, unopened_chests)
        reachable_mechanisms = self._reachable_goals(state, GoalKind.ACTIVATE_SWITCH, mechanisms)
        reachable_monsters = self._reachable_goals(state, GoalKind.ATTACK_MONSTER, live_monsters)

        # buttons only matter when a conditional door exists in this room
        unpressed = {
            pos for pos in state.buttons
            if globalize(state.room, pos) not in memory.activated_switches
        } if has_cond_door else set[Position]()
        reachable_buttons = self._reachable_goals(state, GoalKind.ACTIVATE_SWITCH, unpressed)

        cond_prereqs_met = has_cond_door and not unpressed and not live_monsters

        def _new(doors: set[Position]) -> set[Position]:
            return {p for p in doors if globalize(state.room, p) not in memory.used_exits}

        reachable_normal_new  = self._reachable_goals(state, GoalKind.GO_TO_EXIT, _new(door_normal))
        reachable_locked_new  = self._reachable_goals(state, GoalKind.GO_TO_EXIT, _new(door_locked))
        reachable_cond_new    = self._reachable_goals(state, GoalKind.GO_TO_EXIT, _new(door_conditional))
        reachable_normal_all  = self._reachable_goals(state, GoalKind.GO_TO_EXIT, door_normal)
        reachable_locked_all  = self._reachable_goals(state, GoalKind.GO_TO_EXIT, door_locked)
        reachable_cond_all    = self._reachable_goals(state, GoalKind.GO_TO_EXIT, door_conditional)

        # -- 1. sticky goal -------------------------------------------------
        sticky = self._continue_last_goal(
            state, memory, unopened_chests, live_monsters, mechanisms,
            door_exits, door_locked, door_conditional, state.buttons,
        )
        if sticky is not None:
            self._log(f"1.STICKY  -> {sticky.kind.value}:{sticky.target}")
            return sticky

        # -- 2. adjacent actionable -----------------------------------------
        adj = self._adjacent_goal(state, reachable_chests)
        if adj is not None:
            self._log(f"2.ADJ_CHEST -> {adj.target}")
            return adj
        if state.has_sword:
            adj = self._adjacent_goal(state, reachable_monsters)
            if adj is not None and self._safe_to_fight(state):
                self._log(f"2.ADJ_MON -> {adj.target}")
                return adj

        # -- 3. reachable chests --------------------------------------------
        if reachable_chests:
            g = self._nearest_goal(state, reachable_chests)
            self._log(f"3.CHEST -> {g.target}")
            return g

        # -- 4. monsters (must clear before exit) ---------------------------
        if reachable_monsters and self._must_clear_monsters_before_exit(
            state, memory, unopened_chests, door_exits, mechanisms,
        ):
            g = self._nearest_goal(state, reachable_monsters)
            self._log(f"4.MONSTER -> {g.target}")
            return g

        # -- 5. unused NORMAL exits -----------------------------------------
        if reachable_normal_new:
            g = self._best_exit_goal(state, memory, reachable_normal_new)
            self._log(f"5.EXIT_NEW_N -> {g.target}")
            return g

        # -- 6. CONDITIONAL door — press buttons first, then go through ------
        if has_cond_door:
            if reachable_buttons and not cond_prereqs_met:
                g = self._nearest_goal(state, reachable_buttons)
                self._log(f"6.BUTTON_FOR_COND -> {g.target}")
                return g
            # buttons done but monsters remain — redirect to monsters
            if not cond_prereqs_met and live_monsters and state.has_sword and self._safe_to_fight(state):
                if reachable_monsters:
                    g = self._nearest_goal(state, reachable_monsters)
                    self._log(f"6.MON_FOR_COND -> {g.target}")
                    return g
            if cond_prereqs_met and reachable_cond_new:
                g = self._best_exit_goal(state, memory, reachable_cond_new)
                self._log(f"6.EXIT_NEW_C -> {g.target}")
                return g

        # -- 7. unused LOCKED exits (only when carrying a key) ---------------
        if have_key and reachable_locked_new:
            g = self._best_exit_goal(state, memory, reachable_locked_new)
            self._log(f"7.EXIT_NEW_L -> {g.target}")
            return g

        # -- 8. switches (not buttons) --------------------------------------
        mg = self._mechanism_goal(state, memory, reachable_mechanisms)
        if mg is not None:
            self._log(f"8.SWITCH -> {mg.target}")
            return mg

        # -- 9. used NORMAL exits (fallback) --------------------------------
        if reachable_normal_all:
            g = self._best_exit_goal(state, memory, reachable_normal_all, allow_used=True)
            self._log(f"9.EXIT_USED_N -> {g.target}")
            return g

        # -- 10. CONDITIONAL door (used) — press buttons first, then go -----
        if has_cond_door:
            if reachable_buttons and not cond_prereqs_met:
                g = self._nearest_goal(state, reachable_buttons)
                self._log(f"10.BUTTON_FOR_COND -> {g.target}")
                return g
            # buttons done but monsters remain — redirect to monsters
            if not cond_prereqs_met and live_monsters and state.has_sword and self._safe_to_fight(state):
                if reachable_monsters:
                    g = self._nearest_goal(state, reachable_monsters)
                    self._log(f"10.MON_FOR_COND -> {g.target}")
                    return g
            if cond_prereqs_met and reachable_cond_all:
                g = self._best_exit_goal(state, memory, reachable_cond_all, allow_used=True)
                self._log(f"10.EXIT_USED_C -> {g.target}")
                return g

        # -- 11. used LOCKED exits ------------------------------------------
        if have_key and reachable_locked_all:
            g = self._best_exit_goal(state, memory, reachable_locked_all, allow_used=True)
            self._log(f"11.EXIT_USED_L -> {g.target}")
            return g

        # -- 12. explore ----------------------------------------------------
        frontier = self._frontier(state)
        if frontier is not None:
            self._log(f"12.EXPLORE -> {frontier}")
            return Goal(GoalKind.EXPLORE, frontier)

        # -- 13. wait -------------------------------------------------------
        self._log(f"13.WAIT  chests={state.chests}  buttons={state.buttons}  mons={state.monsters}")
        return Goal(GoalKind.WAIT)

    # ------------------------------------------------------------------
    # sticky goal
    # ------------------------------------------------------------------

    def _continue_last_goal(
        self,
        state: SymbolicState,
        memory: AgentMemory,
        unopened_chests: set[Position],
        live_monsters: set[Position],
        mechanisms: set[Position],
        door_exits: set[Position],
        door_locked: set[Position],
        door_conditional: set[Position],
        all_buttons: set[Position],
    ) -> Goal | None:
        goal = memory.last_goal
        if goal is None or goal.target is None:
            return None
        target = goal.target

        if goal.kind == GoalKind.OPEN_CHEST and target in unopened_chests:
            return goal if is_reachable(state, goal) or manhattan(state.player, target) == 1 else None

        if goal.kind == GoalKind.ATTACK_MONSTER and target in live_monsters and self._safe_to_fight(state):
            return goal if is_reachable(state, goal) or manhattan(state.player, target) == 1 else None

        if goal.kind == GoalKind.ACTIVATE_SWITCH:
            # button target
            if target in all_buttons:
                if state.player == target:
                    return None  # already on it, triggered
                return goal if is_reachable(state, goal) else None
            # switch target
            if target in mechanisms:
                if self._has_unused_exits(state, memory, door_exits):
                    return None
                return goal if is_reachable(state, goal) or manhattan(state.player, target) == 1 else None

        if goal.kind == GoalKind.GO_TO_EXIT and target in door_exits:
            # chests always take priority
            if unopened_chests:
                return None
            # locked exit without key — ignore
            if target in door_locked and state.keys <= 0:
                return None
            # conditional exit with remaining buttons or monsters — ignore
            if target in door_conditional and (state.buttons or live_monsters):
                return None
            # monsters still need clearing
            if self._must_clear_monsters_before_exit(state, memory, unopened_chests, door_exits, mechanisms):
                return None
            if state.player == target:
                return None if globalize(state.room, target) in memory.used_exits else goal
            return goal if is_reachable(state, goal) else None

        return None

    # ------------------------------------------------------------------
    # exit helpers
    # ------------------------------------------------------------------

    def _door_exits(self, state: SymbolicState) -> set[Position]:
        """All boundary-door tiles regardless of type."""
        return {
            (col, row)
            for col, row in state.all_exits
            if (row in {0, 7} and col in {4, 5})
            or (col in {0, 9} and row in {3, 4})
        }

    def _door_normal(self, state: SymbolicState) -> set[Position]:
        return self._door_exits(state) & state.normal_exits

    def _door_locked(self, state: SymbolicState) -> set[Position]:
        return self._door_exits(state) & state.locked_exits

    def _door_conditional(self, state: SymbolicState) -> set[Position]:
        return self._door_exits(state) & state.conditional_exits

    # ------------------------------------------------------------------
    # mechanisms  (switches only — buttons handled in priority 5)
    # ------------------------------------------------------------------

    def _mechanisms(self, state: SymbolicState) -> set[Position]:
        """Switches only — buttons are handled separately for conditional doors."""
        return {pos for pos in state.switches if pos not in self._door_exits(state)}

    def _has_unused_mechanisms(
        self, state: SymbolicState, memory: AgentMemory, mechanisms: set[Position]
    ) -> bool:
        return any(
            globalize(state.room, pos) not in memory.activated_switches
            for pos in mechanisms
        )

    def _mechanism_goal(self, state: SymbolicState, memory: AgentMemory, goals: list[Goal]) -> Goal | None:
        if not goals:
            return None
        if memory.switch_cooldown > 0:
            return None
        unused = [g for g in goals if g.target is not None
                  and globalize(state.room, g.target) not in memory.activated_switches]
        if unused:
            return self._nearest_goal(state, unused)
        return self._nearest_goal(state, goals)

    # ------------------------------------------------------------------
    # monsters
    # ------------------------------------------------------------------

    def _safe_to_fight(self, state: SymbolicState) -> bool:
        return state.health is None or state.health > 1

    def _must_clear_monsters_before_exit(
        self,
        state: SymbolicState,
        memory: AgentMemory,
        unopened_chests: set[Position],
        door_exits: set[Position],
        mechanisms: set[Position],
    ) -> bool:
        """Only fight monsters when the room is otherwise exhausted."""
        _sword = state.has_sword
        _mons = bool(state.monsters)
        _safe = self._safe_to_fight(state)
        _chests = bool(state.chests)
        _switches = bool(state.switches)
        _buttons = bool(state.buttons)
        _exits = self._has_unused_exits(state, memory, door_exits)
        result = (
            _sword and _mons and _safe
            and not _chests
            and not _switches
            and not _buttons
            and not _exits
        )
        if self._debug:
            self._log(
                f"_must_clear: sword={_sword} mons={_mons} safe={_safe} "
                f"chests={_chests} switches={_switches} buttons={_buttons} "
                f"unused_exits={_exits} => {result}"
            )
        return result

    # ------------------------------------------------------------------
    # exit ranking
    # ------------------------------------------------------------------

    def _has_unused_exits(
        self, state: SymbolicState, memory: AgentMemory, door_exits: set[Position]
    ) -> bool:
        return any(
            globalize(state.room, pos) not in memory.used_exits
            for pos in door_exits
        )

    def _best_exit_goal(
        self,
        state: SymbolicState,
        memory: AgentMemory,
        goals: list[Goal],
        *,
        allow_used: bool = False,
    ) -> Goal:
        candidates = goals if allow_used else [g for g in goals if g.target is not None]
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
            return (used, blocked_approach, unvisited, entry,
                    key_bonus + manhattan(state.player, target), target)

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

    def _route_to_known_progress_room(self, state: SymbolicState, memory: AgentMemory) -> Goal | None:
        target_rooms = self._known_progress_rooms(state, memory)
        if not target_rooms:
            return None
        reachable_exits = self._reachable_goals(state, GoalKind.GO_TO_EXIT, self._door_exits(state))
        if not reachable_exits:
            return None

        current = state.room
        target_room = min(target_rooms, key=lambda room: (self._room_distance(current, room), room))

        def rank(goal: Goal) -> tuple[int, int, int, int, Position]:
            target = goal.target or state.player
            neighbor = self._neighbor_room(current, target)
            if neighbor is None:
                return (99, 99, manhattan(state.player, target), 99, target)
            before = self._room_distance(current, target_room)
            after = self._room_distance(neighbor, target_room)
            improves = 0 if after < before else 1
            used = 1 if globalize(state.room, target) in memory.used_exits else 0
            # A doorway is rendered as two adjacent tiles.  Both lead to the
            # same neighbour, so choose the half nearest the current player
            # instead of falling back to lexicographic coordinates (which made
            # the agent climb back to row 3 before leaving from row 4).
            return (improves, after, used, manhattan(state.player, target), target)

        return min(reachable_exits, key=rank)

    def _known_progress_rooms(self, state: SymbolicState, memory: AgentMemory) -> set[RoomCoord]:
        rooms: set[RoomCoord] = set()
        for room, snapshot in memory.room_memory.items():
            if room == state.room:
                continue
            unopened = {pos for pos in snapshot.chests if globalize(room, pos) not in memory.opened_chests}
            unkilled = {
                pos for pos in snapshot.monsters
                if globalize(room, pos) not in memory.killed_monsters
            }
            mechanisms = {
                pos for pos in (snapshot.switches | snapshot.buttons)
                if globalize(room, pos) not in memory.activated_switches
                and globalize(room, pos) not in memory.opened_chests
            }
            # A key is useful in a previously observed locked-door room.  Keep
            # that semantic fact in memory so returning from a remote key room
            # is directed toward progress instead of an arbitrary used exit.
            unlockable = state.keys > 0 and bool(snapshot.locked_exits)
            # An already-used mechanism may be reusable (for example, a
            # rotating bridge).  Remember it as possible progress, but do not
            # make every observed one-shot button a permanent attractor.
            reusable_mechanism = any(
                globalize(room, pos) in memory.activated_switches
                for pos in (snapshot.switches | snapshot.buttons)
            )
            if unopened or mechanisms or unlockable or (state.has_sword and unkilled) or reusable_mechanism:
                rooms.add(room)
        return rooms

    def _room_distance(self, left: RoomCoord, right: RoomCoord) -> int:
        return abs(left[0] - right[0]) + abs(left[1] - right[1])

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
        filtered = [g for g in goals if not self._is_entry_side(state, g)]
        return filtered if filtered else goals

    def _is_entry_side(self, state: SymbolicState, goal: Goal) -> bool:
        target = goal.target or state.player
        return (
            (state.player[0] <= 1 and target[0] == 0)
            or (state.player[0] >= 8 and target[0] == 9)
            or (state.player[1] <= 1 and target[1] == 0)
            or (state.player[1] >= 6 and target[1] == 7)
        )

    # ------------------------------------------------------------------
    # generic helpers
    # ------------------------------------------------------------------

    def _adjacent_goal(self, state: SymbolicState, goals: list[Goal]) -> Goal | None:
        adj = [g for g in goals if g.target is not None and manhattan(state.player, g.target) == 1]
        return self._nearest_goal(state, adj) if adj else None

    def _reachable_goals(self, state: SymbolicState, kind: GoalKind, positions: set[Position]) -> list[Goal]:
        goals = [Goal(kind, pos) for pos in positions]
        return [g for g in goals if is_reachable(state, g) or state.player == g.target]

    def _nearest_goal(self, state: SymbolicState, goals: list[Goal]) -> Goal:
        return min(goals, key=lambda g: (manhattan(state.player, g.target or state.player),
                                          g.target or (0, 0)))

    def _frontier(self, state: SymbolicState) -> Position | None:
        blockers = state.walls | state.traps | state.gaps | state.chests | state.monsters
        candidates = {
            (col, row)
            for row in range(8)
            for col in range(10)
            if (col, row) not in blockers and (col, row) != state.player
        }
        return nearest(candidates, state.player)


class RLHighLevelPolicy(HighLevelPolicy):
    def choose_goal(self, state: SymbolicState, memory: AgentMemory) -> Goal:
        raise NotImplementedError("Plug a trained RL goal selector in here.")
