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

    def choose_goal(self, state: SymbolicState, memory: AgentMemory) -> Goal:
        door_exits = self._door_exits(state)
        mechanisms = self._mechanisms(state)
        unopened_chests = {
            pos for pos in state.chests
            if globalize(state.room, pos) not in memory.opened_chests
        }
        live_monsters = {
            pos for pos in state.monsters
            if globalize(state.room, pos) not in memory.killed_monsters
        }

        reachable_chests = self._reachable_goals(state, GoalKind.OPEN_CHEST, unopened_chests)
        reachable_mechanisms = self._reachable_goals(state, GoalKind.ACTIVATE_SWITCH, mechanisms)
        reachable_monsters = self._reachable_goals(state, GoalKind.ATTACK_MONSTER, live_monsters)
        reachable_new_exits = self._reachable_goals(
            state,
            GoalKind.GO_TO_EXIT,
            {pos for pos in door_exits if globalize(state.room, pos) not in memory.used_exits},
        )
        reachable_all_exits = self._reachable_goals(state, GoalKind.GO_TO_EXIT, door_exits)

        sticky_goal = self._continue_last_goal(
            state,
            memory,
            unopened_chests,
            live_monsters,
            mechanisms,
            door_exits,
        )
        if sticky_goal is not None:
            return sticky_goal

        # If standing next to an actionable object, finish it before starting a
        # long route. This avoids oscillation when moving sprites perturb vision.
        adjacent = self._adjacent_goal(state, reachable_chests)
        if adjacent is not None:
            return adjacent
        if state.has_sword:
            adjacent = self._adjacent_goal(state, reachable_monsters)
            if adjacent is not None and self._safe_to_fight(state):
                return adjacent
        adjacent = self._adjacent_goal(state, reachable_mechanisms)
        if adjacent is not None:
            return adjacent

        # Chests are the most reliable visible source of keys/tools/rewards and
        # are blocking objects, so clear reachable ones before optional exits.
        if reachable_chests:
            return self._nearest_goal(state, reachable_chests)

        # A visible monster often gates conditional exits or nearby resources.
        # Do not wait until after trying every door: clear it once local loot is
        # gone, provided the agent has a weapon and enough health.
        if state.has_sword and reachable_monsters and self._should_fight_now(state, memory, reachable_new_exits):
            return self._nearest_goal(state, reachable_monsters)

        # Once we have acquired a progress resource, returning to remembered
        # mechanism/progress rooms is often better than probing arbitrary exits.
        if state.keys > 0 or state.has_sword:
            room_goal = self._route_to_known_progress_room(state, memory)
            if room_goal is not None:
                return room_goal

        # With a key, prefer frontier exits. Without a key, still explore, but do
        # not bounce immediately through the entry side if alternatives exist.
        if reachable_new_exits:
            return self._best_exit_goal(state, memory, reachable_new_exits)

        # Mechanisms are local topology changers. Use them after the currently
        # reachable frontier is exhausted, then revisit exits under the new layout.
        mechanism_goal = self._mechanism_goal(state, memory, reachable_mechanisms, reachable_new_exits)
        if mechanism_goal is not None:
            return mechanism_goal

        # Route back to rooms remembered to contain visible progress. This is a
        # generic room graph heuristic based on observed exit transitions.
        room_goal = self._route_to_known_progress_room(state, memory)
        if room_goal is not None:
            return room_goal

        # If all new exits are exhausted, revisit reachable exits. This handles
        # hub rooms whose mechanisms or inventory changes make an old side useful.
        if reachable_all_exits:
            return self._best_exit_goal(state, memory, reachable_all_exits, allow_used=True)

        if state.has_sword and reachable_monsters and self._safe_to_fight(state):
            return self._nearest_goal(state, reachable_monsters)

        frontier = self._frontier(state)
        if frontier is not None:
            return Goal(GoalKind.EXPLORE, frontier)

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

    def _should_fight_now(self, state: SymbolicState, memory: AgentMemory, frontier_exits: list[Goal]) -> bool:
        if not self._safe_to_fight(state):
            return False
        if not frontier_exits:
            return True
        # If we have a key/tool or the room has only exits left, combat is likely
        # the condition that unlocks final/progress exits.
        if state.keys > 0 or state.has_sword:
            return True
        no_new_exits = all(globalize(state.room, goal.target or state.player) in memory.used_exits for goal in frontier_exits)
        return no_new_exits

    def _mechanism_goal(self, state: SymbolicState, memory: AgentMemory, goals: list[Goal], new_exits: list[Goal]) -> Goal | None:
        if not goals:
            return None
        # If a switch was just used, give the environment time to expose the new
        # bridge/door state and try a frontier exit before toggling again.
        if memory.switch_cooldown > 0 and new_exits:
            return None
        unused = [goal for goal in goals if goal.target is not None and globalize(state.room, goal.target) not in memory.activated_switches]
        if unused:
            return self._nearest_goal(state, unused)
        if not new_exits:
            return self._nearest_goal(state, goals)
        return None

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

        def rank(goal: Goal) -> tuple[int, int, int, int, Position]:
            target = goal.target or state.player
            neighbor = self._neighbor_room(state.room, target)
            unvisited = 0 if neighbor is not None and neighbor not in memory.room_memory else 1
            used = 1 if globalize(state.room, target) in memory.used_exits else 0
            key_bonus = 0 if state.keys > 0 and target[0] == 9 else 1
            entry = 1 if self._is_entry_side(state, goal) and memory.room_steps <= 4 else 0
            return (used, unvisited, entry, key_bonus + manhattan(state.player, target), target)

        return min(candidates, key=rank)

    def _route_to_known_progress_room(self, state: SymbolicState, memory: AgentMemory) -> Goal | None:
        target_rooms = self._known_progress_rooms(state, memory)
        if not target_rooms:
            return None
        reachable_exits = self._reachable_goals(state, GoalKind.GO_TO_EXIT, self._door_exits(state))
        if not reachable_exits:
            return None

        current = state.room
        target_room = min(target_rooms, key=lambda room: (self._room_distance(current, room), room))

        def rank(goal: Goal) -> tuple[int, int, int, Position]:
            target = goal.target or state.player
            neighbor = self._neighbor_room(current, target)
            if neighbor is None:
                return (99, manhattan(state.player, target), 99, target)
            before = self._room_distance(current, target_room)
            after = self._room_distance(neighbor, target_room)
            improves = 0 if after < before else 1
            used = 1 if globalize(state.room, target) in memory.used_exits else 0
            return (improves, after, used, target)

        return min(reachable_exits, key=rank)

    def _known_progress_rooms(self, state: SymbolicState, memory: AgentMemory) -> set[RoomCoord]:
        rooms: set[RoomCoord] = set()
        for room, snapshot in memory.room_memory.items():
            if room == state.room:
                continue
            unopened = {pos for pos in snapshot.chests if globalize(room, pos) not in memory.opened_chests}
            unkilled = {pos for pos in snapshot.monsters if globalize(room, pos) not in memory.killed_monsters}
            mechanisms = {
                pos for pos in (snapshot.switches | snapshot.buttons)
                if globalize(room, pos) not in memory.activated_switches
                and globalize(room, pos) not in memory.opened_chests
            }
            if unopened or mechanisms or (state.has_sword and unkilled):
                rooms.add(room)
        return rooms

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

    def _room_distance(self, left: RoomCoord, right: RoomCoord) -> int:
        return abs(left[0] - right[0]) + abs(left[1] - right[1])

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








