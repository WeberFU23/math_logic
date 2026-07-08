from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

import numpy as np

from RL_based_submission.vision_extractor import (
    ABYSS,
    BRIDGE,
    BUTTON,
    BUTTON_PRESSED,
    CHEST,
    GAP,
    NPC,
    SWITCH,
    SWITCH_PRESSED,
    TRAP,
    WALL,
    SymbolicFrame,
    VisionExtractor,
)
from rule_based_submission.symbolic import AgentMemory, SymbolicState
from rule_based_submission.symbolic import ACTION_LEFT, ACTION_RIGHT


Position = tuple[int, int]


@dataclass
class AdvancedPerceptor:
    """Convert the template-based visual extractor into the shared symbolic state.

    Only pixels and the explicitly allowed inventory portion of ``info`` affect
    the returned state.  Hidden agent coordinates, room coordinates, entity
    lists, dynamic-object state, and event records are deliberately ignored.
    """

    memory: AgentMemory = field(default_factory=AgentMemory)
    extractor: VisionExtractor = field(default_factory=lambda: VisionExtractor(use_memory=True))
    last_frame: SymbolicFrame | None = None
    last_player: Position | None = None

    def reset(self, *, task_id: str | None = None) -> None:
        self.memory.reset(task_id=task_id)
        self.extractor.reset()
        self.last_frame = None
        self.last_player = None

    def reset_room_vision(self) -> None:
        """Prevent static-memory pixels from one room leaking into the next."""

        self.extractor.reset()
        self.last_frame = None
        self.last_player = None

    def perceive(self, obs: Any, info: dict[str, Any] | None = None) -> SymbolicState:
        frame = self.extractor.extract(np.asarray(obs))
        self.last_frame = frame

        positions: dict[str, set[Position]] = {}
        normal_exits: set[Position] = set()
        locked_exits_set: set[Position] = set()
        conditional_exits: set[Position] = set()
        exit_labels: dict[Position, str] = {}
        for row in range(frame.static.shape[0]):
            for col in range(frame.static.shape[1]):
                label = str(frame.static[row, col])
                positions.setdefault(label, set()).add((col, row))
                if label.startswith("exit_"):
                    exit_labels[(col, row)] = label
                    if "locked_key" in label:
                        locked_exits_set.add((col, row))
                    elif "conditional" in label:
                        conditional_exits.add((col, row))
                    else:
                        normal_exits.add((col, row))

        player = frame.player.anchor_tile if frame.player is not None else self._fallback_player()
        if frame.player is not None:
            self.last_player = player
        player_center_px = frame.player.center_px if frame.player is not None else None
        player_position_px = self._player_position_px(frame)
        monsters = {entity.anchor_tile for entity in frame.monsters}
        keys, gold, has_sword, has_shield, has_heal = _allowed_inventory(info)

        return SymbolicState(
            player=player,
            player_center_px=player_center_px,
            player_position_px=player_position_px,
            room=self.memory.room,
            walls=set(positions.get(WALL, set())),
            chests=set(positions.get(CHEST, set())),
            monsters=monsters,
            normal_exits=normal_exits,
            locked_exits=locked_exits_set,
            conditional_exits=conditional_exits,
            traps=set(positions.get(TRAP, set())) | set(positions.get(ABYSS, set())),
            # Include pressed variants — some mechanisms are reusable
            # (e.g. the rotating bridge switch in task 4 needs multiple
            # activations to cycle through its states).  The tile under
            # the player is excluded to avoid sprite-occlusion artefacts.
            buttons=(set(positions.get(BUTTON, set())) | set(positions.get(BUTTON_PRESSED, set()))) - {player},
            switches=(set(positions.get(SWITCH, set())) | set(positions.get(SWITCH_PRESSED, set()))) - {player},
            bridges=set(positions.get(BRIDGE, set())),
            gaps=set(positions.get(GAP, set())),
            npcs=set(positions.get(NPC, set())),
            exit_labels=exit_labels,
            keys=keys,
            health=None,
            has_sword=has_sword,
            has_shield=has_shield,
        )

    def inventory_features(self, info: dict[str, Any] | None) -> tuple[int, int, bool, bool, bool]:
        return _allowed_inventory(info)

    def _fallback_player(self) -> Position:
        # The last visually observed player position is safer than inventing the
        # room center.  At the first frame, retain the legacy center fallback.
        return self.last_player or (4, 4)

    def _player_position_px(self, frame: SymbolicFrame) -> tuple[float, float] | None:
        if frame.player is None:
            return None
        center_x, center_y = frame.player.center_px
        # The colored sprite bbox is asymmetric for side-facing frames.
        if self.memory.facing_action == ACTION_LEFT:
            left = center_x - 8.5
        elif self.memory.facing_action == ACTION_RIGHT:
            left = center_x - 6.5
        else:
            left = center_x - 7.5
        return (float(round(left)), float(round(center_y - 7.5)))


def _allowed_inventory(info: dict[str, Any] | None) -> tuple[int, int, bool, bool, bool]:
    inventory = info.get("inventory", {}) if isinstance(info, dict) else {}
    if not isinstance(inventory, dict):
        inventory = {}

    keys = _safe_int(inventory.get("keys", 0))
    gold = _safe_int(inventory.get("gold", 0))
    text = f"{inventory.get('equipped', {})} {inventory.get('items', [])} {inventory.get('tools', [])}".lower()
    return (
        max(0, keys),
        max(0, gold),
        "sword" in text,
        "shield" in text,
        "potion" in text or "heal" in text,
    )


def _safe_int(value: Any) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0
