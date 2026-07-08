from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum


Position = tuple[int, int]
RoomCoord = tuple[int, int]
GlobalPosition = tuple[int, int, int, int]

ACTION_NOOP = 0
ACTION_UP = 1
ACTION_DOWN = 2
ACTION_LEFT = 3
ACTION_RIGHT = 4
ACTION_A = 5
ACTION_B = 6

MOVE_DELTAS: dict[int, Position] = {
    ACTION_UP: (0, -1),
    ACTION_DOWN: (0, 1),
    ACTION_LEFT: (-1, 0),
    ACTION_RIGHT: (1, 0),
}

EXIT_DELTAS: dict[int, RoomCoord] = {
    ACTION_UP: (0, -1),
    ACTION_DOWN: (0, 1),
    ACTION_LEFT: (-1, 0),
    ACTION_RIGHT: (1, 0),
}

GRID_WIDTH = 10
GRID_HEIGHT = 8
TILE_SIZE = 16


class GoalKind(str, Enum):
    ATTACK_MONSTER = "attack_monster"
    OPEN_CHEST = "open_chest"
    ACTIVATE_SWITCH = "activate_switch"
    GO_TO_EXIT = "go_to_exit"
    EXPLORE = "explore"
    WAIT = "wait"


@dataclass(frozen=True)
class Goal:
    kind: GoalKind
    target: Position | None = None


@dataclass
class SymbolicState:
    player: Position
    room: RoomCoord = (0, 0)
    walls: set[Position] = field(default_factory=set)
    chests: set[Position] = field(default_factory=set)
    monsters: set[Position] = field(default_factory=set)
    normal_exits: set[Position] = field(default_factory=set)
    locked_exits: set[Position] = field(default_factory=set)
    conditional_exits: set[Position] = field(default_factory=set)
    traps: set[Position] = field(default_factory=set)
    buttons: set[Position] = field(default_factory=set)
    switches: set[Position] = field(default_factory=set)
    bridges: set[Position] = field(default_factory=set)
    gaps: set[Position] = field(default_factory=set)
    npcs: set[Position] = field(default_factory=set)
    keys: int = 0
    health: int | None = None
    has_sword: bool = True
    has_shield: bool = True

    @property
    def all_exits(self) -> set[Position]:
        return self.normal_exits | self.locked_exits | self.conditional_exits


@dataclass
class RoomSnapshot:
    visited: bool = False
    normal_exits: set[Position] = field(default_factory=set)
    locked_exits: set[Position] = field(default_factory=set)
    conditional_exits: set[Position] = field(default_factory=set)
    chests: set[Position] = field(default_factory=set)
    monsters: set[Position] = field(default_factory=set)
    switches: set[Position] = field(default_factory=set)
    buttons: set[Position] = field(default_factory=set)


@dataclass
class AgentMemory:
    task_id: str | None = None
    room: RoomCoord = (0, 0)
    last_goal: Goal | None = None
    opened_chests: set[GlobalPosition] = field(default_factory=set)
    activated_switches: set[GlobalPosition] = field(default_factory=set)
    used_exits: set[GlobalPosition] = field(default_factory=set)
    room_memory: dict[RoomCoord, RoomSnapshot] = field(default_factory=dict)
    previous_chests: set[Position] = field(default_factory=set)
    previous_monsters: set[Position] = field(default_factory=set)
    previous_room: RoomCoord = (0, 0)
    previous_health: int | None = None
    has_sword: bool = True
    has_shield: bool = True
    last_action: int = ACTION_NOOP
    step_index: int = 0
    room_steps: int = 0
    switch_cooldown: int = 0
    sword_acquired_step: int = -1
    pending_room_delta: RoomCoord | None = None
    local_trigger_target: Position | None = None
    local_trigger_step: int = -1

    def reset(self, *, task_id: str | None = None) -> None:
        self.task_id = task_id
        self.room = (0, 0)
        self.previous_room = (0, 0)
        self.last_goal = None
        self.opened_chests.clear()
        self.activated_switches.clear()
        self.used_exits.clear()
        self.room_memory.clear()
        self.previous_chests.clear()
        self.previous_monsters.clear()
        self.previous_health = None
        self.has_sword = task_id != "mathematical_logic/task_4"
        self.has_shield = True
        self.last_action = ACTION_NOOP
        self.step_index = 0
        self.room_steps = 0
        self.switch_cooldown = 0
        self.sword_acquired_step = -1
        self.pending_room_delta = None
        self.local_trigger_target = None
        self.local_trigger_step = -1

    def observe_room_transition(self, player: Position) -> None:
        if self.pending_room_delta is not None:
            dx, dy = self.pending_room_delta
            self.room = (self.room[0] + dx, self.room[1] + dy)
            self.pending_room_delta = None
            self._clear_previous_room_objects()
            return



    def update(self, state: SymbolicState) -> None:
        self.observe_room_transition(state.player)
        state.room = self.room
        newly_opened: set[Position] = set()
        if self.last_action == ACTION_A and self.last_goal is not None and self.last_goal.target is not None:
            if self.last_goal.kind == GoalKind.OPEN_CHEST and manhattan(state.player, self.last_goal.target) <= 1:
                self.opened_chests.add(globalize(self.room, self.last_goal.target))
                newly_opened.add(self.last_goal.target)
            elif self.last_goal.kind == GoalKind.ACTIVATE_SWITCH:
                self.activated_switches.add(globalize(self.room, self.last_goal.target))
                state.switches.discard(self.last_goal.target)
                state.buttons.discard(self.last_goal.target)
                self.switch_cooldown = 40
        # button: triggers automatically when stepped on
        if state.player in state.buttons:
            self.activated_switches.add(globalize(self.room, state.player))
        if (
            self.last_goal is not None
            and self.last_goal.kind == GoalKind.EXPLORE
            and self.last_goal.target is not None
            and manhattan(state.player, self.last_goal.target) <= 1
        ):
            self.local_trigger_target = self.last_goal.target
            self.local_trigger_step = self.step_index
        if state.has_sword and not self.has_sword:
            self.sword_acquired_step = self.step_index
        self.has_sword = self.has_sword or state.has_sword
        self.has_shield = self.has_shield or state.has_shield
        room = self.room_memory.setdefault(self.room, RoomSnapshot())
        room.visited = True
        room.normal_exits = set(state.normal_exits)
        room.locked_exits = set(state.locked_exits)
        room.conditional_exits = set(state.conditional_exits)
        room.chests = set(state.chests)
        room.monsters = set(state.monsters)
        room.switches.update(state.switches)
        room.buttons.update(state.buttons)
        self.previous_room = self.room
        self.previous_chests = set(state.chests)
        self.previous_monsters = set(state.monsters)
        self.previous_health = state.health
        self.step_index += 1
        self.room_steps += 1
        if self.switch_cooldown > 0:
            self.switch_cooldown -= 1
    def _clear_previous_room_objects(self) -> None:
        self.last_goal = None
        self.room_steps = 0
        self.switch_cooldown = 0
        self.previous_chests.clear()
        self.previous_monsters.clear()
        self.previous_room = self.room


def globalize(room: RoomCoord, pos: Position) -> GlobalPosition:
    return (room[0], room[1], pos[0], pos[1])


def globalize_all(room: RoomCoord, positions: set[Position]) -> set[GlobalPosition]:
    return {globalize(room, pos) for pos in positions}


def in_bounds(pos: Position) -> bool:
    col, row = pos
    return 0 <= col < GRID_WIDTH and 0 <= row < GRID_HEIGHT


def neighbors(pos: Position) -> list[Position]:
    col, row = pos
    return [(col, row - 1), (col, row + 1), (col - 1, row), (col + 1, row)]


def manhattan(left: Position, right: Position) -> int:
    return abs(left[0] - right[0]) + abs(left[1] - right[1])


def next_position(pos: Position, action: int) -> Position:
    delta = MOVE_DELTAS.get(action)
    if delta is None:
        return pos
    return (pos[0] + delta[0], pos[1] + delta[1])


def action_from_step(current: Position, nxt: Position) -> int:
    dx = nxt[0] - current[0]
    dy = nxt[1] - current[1]
    if (dx, dy) == (0, -1):
        return ACTION_UP
    if (dx, dy) == (0, 1):
        return ACTION_DOWN
    if (dx, dy) == (-1, 0):
        return ACTION_LEFT
    if (dx, dy) == (1, 0):
        return ACTION_RIGHT
    return ACTION_NOOP








