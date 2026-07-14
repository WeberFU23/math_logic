"""Pixel perception, symbolic adaptation, and an optional live debugger.

The rule-based policy imports :func:`perceive` and :func:`reset_vision`. Run
``python -m rule_based_submission.vision`` to inspect extraction interactively.
"""

from __future__ import annotations

from collections import deque
from collections.abc import Callable
from dataclasses import dataclass, field, replace
from pathlib import Path
from typing import Any, Iterable

import numpy as np

from nesylink.core.constants import (
    COLOR_MONSTER_AMBUSHER,
    COLOR_MONSTER_CHASER,
    COLOR_MONSTER_PATROLLER,
    COLOR_NPC,
    TILE_SIZE,
)
from nesylink.core.rendering.sprites import (
    BUTTON_DOWN,
    BUTTON_UP,
    CHEST_BAND,
    CHEST_WOOD,
    FLOOR_LIGHT,
    HEART_COLOR,
    KEY_COLOR,
    MONSTER_DARK,
    MONSTER_EYE,
    OUTLINE,
    PLAYER_FACE,
    PLAYER_HAIR,
    PLAYER_TUNIC,
    PLAYER_TUNIC_LIGHT,
    draw_abyss,
    draw_bridge,
    draw_button,
    draw_chest,
    draw_exit,
    draw_floor,
    draw_gap,
    draw_npc,
    draw_switch,
    draw_trap,
    draw_text,
    draw_wall,
)


from rule_based_submission.color_vision import (
    SpriteMatch,
    detect_dynamic_sprites,
    infer_color_mode,
    transform_color_image,
)
from rule_based_submission.symbolic import AgentMemory, Position, SymbolicState


GridPos = tuple[int, int]
BBox = tuple[int, int, int, int]

MAP_WIDTH_TILES = 10
MAP_HEIGHT_TILES = 8
MAP_PIXEL_WIDTH = MAP_WIDTH_TILES * TILE_SIZE
MAP_PIXEL_HEIGHT = MAP_HEIGHT_TILES * TILE_SIZE

UNKNOWN = "unknown"
FLOOR = "floor"
WALL = "wall"
CHEST = "chest"
TRAP = "trap"
ABYSS = "abyss"
BUTTON = "button"
BUTTON_PRESSED = "button_pressed"
SWITCH = "switch"
SWITCH_PRESSED = "switch_pressed"
NPC = "npc"
GAP = "gap"
BRIDGE = "bridge"

PLAYER_COLORS = {
    OUTLINE,
    PLAYER_TUNIC,
    PLAYER_TUNIC_LIGHT,
    PLAYER_FACE,
    PLAYER_HAIR,
}

MONSTER_COLORS = {
    OUTLINE,
    MONSTER_EYE,
    MONSTER_DARK,
    COLOR_MONSTER_CHASER,
    COLOR_MONSTER_PATROLLER,
    COLOR_MONSTER_AMBUSHER,
}


@dataclass(frozen=True)
class DynamicEntity:
    kind: str
    bbox: BBox
    center_px: tuple[float, float]
    anchor_tile: GridPos
    occupied_tiles: frozenset[GridPos]
    pixel_count: int


def _dynamic_entity_from_match(match: SpriteMatch) -> DynamicEntity:
    return DynamicEntity(
        kind=match.kind,
        bbox=match.bbox,
        center_px=match.center_px,
        anchor_tile=match.anchor_tile,
        occupied_tiles=match.occupied_tiles,
        pixel_count=match.pixel_count,
    )


def _stabilize_boundary_anchor(
    match: SpriteMatch,
    previous_origin: tuple[int, int] | None,
    previous_anchor: tuple[int, int] | None,
) -> SpriteMatch:
    """Resolve rendered centers exactly on grid lines using temporal direction."""
    if previous_origin is None:
        return match

    anchor = list(match.anchor_tile)
    centers = match.center_px
    previous_centers = (
        previous_origin[0] + match.foreground_mask.shape[1] / 2.0,
        previous_origin[1] + match.foreground_mask.shape[0] / 2.0,
    )
    limits = (MAP_WIDTH_TILES, MAP_HEIGHT_TILES)
    changed = False
    for axis in (0, 1):
        center = centers[axis]
        if abs(center % TILE_SIZE) > 1e-6:
            continue
        boundary_tile = int(center // TILE_SIZE)
        if previous_centers[axis] < center:
            resolved = boundary_tile - 1
        elif previous_centers[axis] > center:
            resolved = boundary_tile
        elif previous_anchor is not None:
            resolved = previous_anchor[axis]
        else:
            continue
        resolved = max(0, min(limits[axis] - 1, resolved))
        changed = changed or resolved != anchor[axis]
        anchor[axis] = resolved
    return replace(match, anchor_tile=tuple(anchor)) if changed else match


@dataclass
class SymbolicFrame:
    static: np.ndarray
    confidence: np.ndarray
    player: DynamicEntity | None
    monsters: list[DynamicEntity]
    dynamic_mask: np.ndarray
    raw_static: np.ndarray | None = None
    color_mode: str = "default"

    def blocked_tiles(self) -> set[GridPos]:
        blocked = {tuple(pos) for pos in np.argwhere(self.static == WALL)[:, ::-1]}
        blocked.update(tuple(pos) for pos in np.argwhere(self.static == CHEST)[:, ::-1])
        blocked.update(tuple(pos) for pos in np.argwhere(self.static == GAP)[:, ::-1])
        blocked.update(tuple(pos) for pos in np.argwhere(self.static == ABYSS)[:, ::-1])
        return blocked


@dataclass
class VisionExtractor:
    use_memory: bool = True
    dynamic_tolerance: int = 10
    min_player_pixels: int = 18
    min_monster_pixels: int = 18
    occlusion_threshold: float = 0.35
    templates: dict[str, np.ndarray] = field(default_factory=dict)
    positioned_templates: dict[tuple[int, int], dict[str, np.ndarray]] = field(default_factory=dict)
    transformed_templates: dict[tuple[int, int, str], dict[str, np.ndarray]] = field(default_factory=dict)
    last_static: np.ndarray | None = None
    last_confidence: np.ndarray | None = None
    last_symbolic_frame: SymbolicFrame | None = None
    color_mode: str = "default"
    color_mode_locked: bool = False
    previous_player_origin: tuple[int, int] | None = None
    previous_player_anchor: tuple[int, int] | None = None
    previous_monster_origins: tuple[tuple[int, int], ...] = ()
    dynamic_initialized: bool = False
    monster_rescan_ticks: int = 0

    def __post_init__(self) -> None:
        if not self.templates:
            self.templates = build_template_library()

    def reset(self, *, preserve_color_mode: bool = False) -> None:
        self.last_static = None
        self.last_confidence = None
        self.last_symbolic_frame = None
        if not preserve_color_mode:
            self.color_mode = "default"
            self.color_mode_locked = False
        self.previous_player_origin = None
        self.previous_player_anchor = None
        self.previous_monster_origins = ()
        self.dynamic_initialized = False
        self.monster_rescan_ticks = 0

    def extract(self, obs: np.ndarray) -> SymbolicFrame:
        frame = _map_frame(obs)
        if not self.color_mode_locked:
            self.color_mode = infer_color_mode(frame)
            self.color_mode_locked = True
        had_tracked_monsters = bool(self.previous_monster_origins)
        player_match, monster_matches, dynamic_mask = detect_dynamic_sprites(
            frame,
            self.color_mode,
            previous_player_origin=self.previous_player_origin,
            previous_monster_origins=self.previous_monster_origins,
            scan_for_monsters=not self.dynamic_initialized or self.monster_rescan_ticks > 0,
        )
        if monster_matches:
            self.monster_rescan_ticks = 0
        elif had_tracked_monsters:
            self.monster_rescan_ticks = 8
        elif self.monster_rescan_ticks > 0:
            self.monster_rescan_ticks -= 1
        player_match = _stabilize_boundary_anchor(
            player_match,
            self.previous_player_origin,
            self.previous_player_anchor,
        )
        self.previous_player_origin = player_match.origin
        self.previous_monster_origins = tuple(match.origin for match in monster_matches)
        self.previous_player_anchor = player_match.anchor_tile
        self.dynamic_initialized = True
        player = _dynamic_entity_from_match(player_match)
        monster_entities = [_dynamic_entity_from_match(match) for match in monster_matches]

        static, confidence = self._classify_static(frame, dynamic_mask, self.color_mode)
        raw_static = static.copy()

        if self.use_memory:
            static, confidence = self._merge_memory(static, confidence, dynamic_mask)
            self.last_static = static.copy()
            self.last_confidence = confidence.copy()

        symbolic = SymbolicFrame(
            static=static,
            confidence=confidence,
            player=player,
            monsters=monster_entities,
            dynamic_mask=dynamic_mask,
            raw_static=raw_static,
            color_mode=self.color_mode,
        )
        self.last_symbolic_frame = symbolic
        return symbolic

    def _classify_static(
        self, frame: np.ndarray, dynamic_mask: np.ndarray, color_mode: str
    ) -> tuple[np.ndarray, np.ndarray]:
        static = np.full((MAP_HEIGHT_TILES, MAP_WIDTH_TILES), UNKNOWN, dtype=object)
        confidence = np.zeros((MAP_HEIGHT_TILES, MAP_WIDTH_TILES), dtype=np.float32)

        for row in range(MAP_HEIGHT_TILES):
            for col in range(MAP_WIDTH_TILES):
                y0 = row * TILE_SIZE
                x0 = col * TILE_SIZE
                tile = frame[y0 : y0 + TILE_SIZE, x0 : x0 + TILE_SIZE]
                mask = dynamic_mask[y0 : y0 + TILE_SIZE, x0 : x0 + TILE_SIZE]
                label, score, second_score = classify_tile(
                    tile,
                    self._templates_for_position(col, row, color_mode),
                    ignore_mask=mask,
                )
                static[row, col] = label
                if second_score <= 1e-6:
                    confidence[row, col] = 1.0
                else:
                    confidence[row, col] = float(np.clip(1.0 - score / second_score, 0.0, 1.0))

        return static, confidence

    def _templates_for_position(self, col: int, row: int, color_mode: str) -> dict[str, np.ndarray]:
        key = (col, row)
        templates = self.positioned_templates.get(key)
        if templates is None:
            templates = build_positioned_template_library(col, row)
            self.positioned_templates[key] = templates
        transformed_key = (col, row, color_mode)
        transformed = self.transformed_templates.get(transformed_key)
        if transformed is None:
            transformed = {
                label: transform_color_image(template, color_mode)
                for label, template in templates.items()
            }
            self.transformed_templates[transformed_key] = transformed
        return transformed

    def _merge_memory(
        self,
        static: np.ndarray,
        confidence: np.ndarray,
        dynamic_mask: np.ndarray,
    ) -> tuple[np.ndarray, np.ndarray]:
        if self.last_static is None:
            return static, confidence

        merged = static.copy()
        merged_confidence = confidence.copy()
        for row in range(MAP_HEIGHT_TILES):
            for col in range(MAP_WIDTH_TILES):
                y0 = row * TILE_SIZE
                x0 = col * TILE_SIZE
                covered = dynamic_mask[y0 : y0 + TILE_SIZE, x0 : x0 + TILE_SIZE].mean()
                if covered >= self.occlusion_threshold or static[row, col] == UNKNOWN:
                    merged[row, col] = self.last_static[row, col]
                    if self.last_confidence is not None:
                        merged_confidence[row, col] = self.last_confidence[row, col]

        return merged, merged_confidence


def extract_symbolic_frame(obs: np.ndarray, extractor: VisionExtractor | None = None) -> SymbolicFrame:
    vision = extractor if extractor is not None else VisionExtractor(use_memory=False)
    return vision.extract(obs)




def render_debug_overlay(
    obs: np.ndarray,
    symbolic: SymbolicFrame | None = None,
    *,
    extractor: VisionExtractor | None = None,
    scale: int = 4,
) -> np.ndarray:
    if scale < 1:
        raise ValueError("scale must be >= 1")

    vision = extractor if extractor is not None else VisionExtractor(use_memory=False)
    frame = _map_frame(obs)
    state = symbolic if symbolic is not None else vision.extract(frame)
    canvas = np.repeat(np.repeat(frame.copy(), scale, axis=0), scale, axis=1)

    for row in range(MAP_HEIGHT_TILES):
        for col in range(MAP_WIDTH_TILES):
            label = str(state.static[row, col])
            color = _label_color(label)
            x0 = col * TILE_SIZE * scale
            y0 = row * TILE_SIZE * scale
            x1 = (col + 1) * TILE_SIZE * scale - 1
            y1 = (row + 1) * TILE_SIZE * scale - 1
            _draw_box(canvas, x0, y0, x1, y1, color)
            text = _short_label(label)
            if text:
                _draw_label(canvas, text, x0 + 2, y0 + 2, color)

    if state.player is not None:
        _draw_entity_overlay(canvas, state.player, (40, 255, 80), scale)
    for monster in state.monsters:
        _draw_entity_overlay(canvas, monster, (255, 80, 40), scale)

    return canvas


def save_debug_overlay(
    path: str | Path,
    obs: np.ndarray,
    symbolic: SymbolicFrame | None = None,
    *,
    extractor: VisionExtractor | None = None,
    scale: int = 4,
) -> Path:
    output_path = Path(path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    image = render_debug_overlay(obs, symbolic, extractor=extractor, scale=scale)
    try:
        from PIL import Image

        Image.fromarray(image).save(output_path)
    except ImportError:
        _save_ppm(output_path, image)
    return output_path

def build_template_library() -> dict[str, np.ndarray]:
    templates: dict[str, np.ndarray] = {}

    def tile_template(draw) -> np.ndarray:
        frame = _floor_frame(TILE_SIZE, TILE_SIZE)
        draw(frame)
        return frame

    templates[FLOOR] = tile_template(lambda frame: None)
    templates[WALL] = tile_template(lambda frame: draw_wall(frame, 0, 0))
    templates[GAP] = tile_template(lambda frame: draw_gap(frame, 0, 0))
    templates[BRIDGE] = tile_template(lambda frame: draw_bridge(frame, 0, 0))
    templates[TRAP] = tile_template(lambda frame: draw_trap(frame, 0, 0))
    templates[ABYSS] = tile_template(lambda frame: draw_abyss(frame, 0, 0))
    templates[BUTTON] = tile_template(lambda frame: draw_button(frame, 0, 0, pressed=False))
    templates[BUTTON_PRESSED] = tile_template(lambda frame: draw_button(frame, 0, 0, pressed=True))
    templates[SWITCH] = tile_template(lambda frame: draw_switch(frame, 0, 0, activated=False))
    templates[SWITCH_PRESSED] = tile_template(lambda frame: draw_switch(frame, 0, 0, activated=True))
    templates[NPC] = tile_template(lambda frame: draw_npc(frame, 0, 0, COLOR_NPC))
    templates["chest_key"] = tile_template(lambda frame: draw_chest(frame, 0, 0, opened=False, loot_kind="key"))
    templates["chest_gold"] = tile_template(lambda frame: draw_chest(frame, 0, 0, opened=False, loot_kind="gold"))
    templates["chest_heal"] = tile_template(lambda frame: draw_chest(frame, 0, 0, opened=False, loot_kind="heal"))
    templates["chest_open"] = tile_template(lambda frame: draw_chest(frame, 0, 0, opened=True, loot_kind=""))

    for exit_type in ("normal", "locked_key", "conditional"):
        for opened in (False, True):
            for direction, tiles in _exit_tiles_by_direction().items():
                frame = _floor_frame(MAP_PIXEL_WIDTH, MAP_PIXEL_HEIGHT)
                draw_exit(frame, tiles, exit_type, _exit_color(exit_type), opened=opened)
                suffix = "open" if opened else "closed"
                for index, (col, row) in enumerate(tiles):
                    y0 = row * TILE_SIZE
                    x0 = col * TILE_SIZE
                    label = f"exit_{direction}_{exit_type}_{suffix}_{index}"
                    templates[label] = frame[y0 : y0 + TILE_SIZE, x0 : x0 + TILE_SIZE].copy()

    return templates


def build_positioned_template_library(col: int, row: int) -> dict[str, np.ndarray]:
    """Build position-specific templates for tile (col, row).

    Objects that don't fill their tile (chest, trap, button, switch, NPC)
    are rendered on all three background types (floor, bridge, gap) so that
    MSE matching works regardless of the underlying terrain.
    """
    templates: dict[str, np.ndarray] = {}

    def _tile_from_frame(frame: np.ndarray) -> np.ndarray:
        y0 = row * TILE_SIZE
        x0 = col * TILE_SIZE
        return frame[y0:y0 + TILE_SIZE, x0:x0 + TILE_SIZE].copy()

    def _make_all_backgrounds(draw_fn, label: str) -> None:
        """Render `draw_fn` on floor, bridge, and gap backgrounds."""
        for bg_name, bg_builder in _BACKGROUND_BUILDERS.items():
            frame = bg_builder(MAP_PIXEL_WIDTH, MAP_PIXEL_HEIGHT)
            draw_fn(frame)
            suffix = f"_on_{bg_name}" if bg_name != "floor" else ""
            templates[label + suffix] = _tile_from_frame(frame)

    # ── Objects that fill the tile (background doesn't matter) ──
    templates[FLOOR] = _tile_from_frame(_floor_frame(MAP_PIXEL_WIDTH, MAP_PIXEL_HEIGHT))
    templates[WALL] = _tile_from_frame(_make_single_frame(lambda f: draw_wall(f, col, row)))
    templates[GAP] = _tile_from_frame(_make_single_frame(lambda f: draw_gap(f, col, row)))
    templates[BRIDGE] = _tile_from_frame(_make_single_frame(lambda f: draw_bridge(f, col, row)))
    templates[ABYSS] = _tile_from_frame(_make_single_frame(lambda f: draw_abyss(f, col, row)))

    # ── Objects that DON'T fill the tile (multi-background) ──
    _make_all_backgrounds(lambda f: draw_trap(f, col, row), TRAP)
    _make_all_backgrounds(lambda f: draw_button(f, col, row, pressed=False), BUTTON)
    _make_all_backgrounds(lambda f: draw_button(f, col, row, pressed=True), BUTTON_PRESSED)
    _make_all_backgrounds(lambda f: draw_switch(f, col, row, activated=False), SWITCH)
    _make_all_backgrounds(lambda f: draw_switch(f, col, row, activated=True), SWITCH_PRESSED)
    _make_all_backgrounds(lambda f: draw_npc(f, col, row, COLOR_NPC), NPC)
    _make_all_backgrounds(lambda f: draw_chest(f, col, row, opened=False, loot_kind="key"), "chest_key")
    _make_all_backgrounds(lambda f: draw_chest(f, col, row, opened=False, loot_kind="gold"), "chest_gold")
    _make_all_backgrounds(lambda f: draw_chest(f, col, row, opened=False, loot_kind="heal"), "chest_heal")
    _make_all_backgrounds(lambda f: draw_chest(f, col, row, opened=True, loot_kind=""), "chest_open")

    # ── Exits — also multi-background (edge tiles may show background) ──
    for direction, tiles in _exit_tiles_by_direction().items():
        if (col, row) not in tiles:
            continue
        for exit_type in ("normal", "locked_key", "conditional"):
            for opened in (False, True):
                suffix = "open" if opened else "closed"
                index = tiles.index((col, row))
                label = f"exit_{direction}_{exit_type}_{suffix}_{index}"
                for bg_name, bg_builder in _BACKGROUND_BUILDERS.items():
                    frame = bg_builder(MAP_PIXEL_WIDTH, MAP_PIXEL_HEIGHT)
                    draw_exit(frame, tiles, exit_type, _exit_color(exit_type), opened=opened)
                    bg_suffix = f"_on_{bg_name}" if bg_name != "floor" else ""
                    templates[label + bg_suffix] = _tile_from_frame(frame)

    return templates


def _make_single_frame(draw_fn) -> np.ndarray:
    """Render on floor background (for objects that fill the tile)."""
    frame = _floor_frame(MAP_PIXEL_WIDTH, MAP_PIXEL_HEIGHT)
    draw_fn(frame)
    return frame

def classify_tile(
    tile: np.ndarray,
    templates: dict[str, np.ndarray],
    *,
    ignore_mask: np.ndarray | None = None,
) -> tuple[str, float, float]:
    scores: list[tuple[float, str]] = []
    usable = None
    if ignore_mask is not None:
        usable = ~ignore_mask
        if usable.mean() < 0.25:
            usable = None

    for label, template in templates.items():
        score = _template_mse(tile, template, usable)
        scores.append((score, _normalize_label(label)))

    scores.sort(key=lambda item: item[0])
    best_score, best_label = scores[0]
    second_score = next((score for score, label in scores[1:] if label != best_label), best_score)
    return best_label, best_score, second_score


def _normalize_label(label: str) -> str:
    # Strip multi-background suffix: "chest_key_on_bridge" → "chest_key"
    for bg_suffix in ("_on_bridge", "_on_gap"):
        if label.endswith(bg_suffix):
            label = label[: -len(bg_suffix)]
            break

    if label.startswith("chest_"):
        return CHEST
    if label.startswith("exit_"):
        return label
    # Map background-sensitive labels back to their base types
    for bg_label in (BUTTON, BUTTON_PRESSED, SWITCH, SWITCH_PRESSED, TRAP, NPC):
        if label == bg_label:
            return label
    return label


def _template_mse(tile: np.ndarray, template: np.ndarray, usable: np.ndarray | None) -> float:
    diff = tile.astype(np.int32) - template.astype(np.int32)
    sq = np.sum(diff * diff, axis=2, dtype=np.int64)
    if usable is not None:
        selected = sq[usable]
        if selected.size:
            return float(selected.mean())
    return float(sq.mean())


def _floor_frame(width: int, height: int) -> np.ndarray:
    frame = np.zeros((height, width, 3), dtype=np.uint8)
    for row in range((height + TILE_SIZE - 1) // TILE_SIZE):
        for col in range((width + TILE_SIZE - 1) // TILE_SIZE):
            draw_floor(frame, col, row)
    return frame


def _bridge_frame(width: int, height: int) -> np.ndarray:
    """Full frame with bridge (brown) background on every tile."""
    frame = np.zeros((height, width, 3), dtype=np.uint8)
    for row in range((height + TILE_SIZE - 1) // TILE_SIZE):
        for col in range((width + TILE_SIZE - 1) // TILE_SIZE):
            draw_bridge(frame, col, row)
    return frame


def _gap_frame(width: int, height: int) -> np.ndarray:
    """Full frame with gap (dark) background on every tile."""
    frame = np.zeros((height, width, 3), dtype=np.uint8)
    for row in range((height + TILE_SIZE - 1) // TILE_SIZE):
        for col in range((width + TILE_SIZE - 1) // TILE_SIZE):
            draw_gap(frame, col, row)
    return frame


_BACKGROUND_BUILDERS: dict[str, Callable[[int, int], np.ndarray]] = {
    "floor": _floor_frame,
    "bridge": _bridge_frame,
    "gap": _gap_frame,
}

# Objects that DON'T fill their tile — background is visible around them.
# These need multi-background templates.
_BG_SENSITIVE_OBJECTS = {CHEST, TRAP, BUTTON, BUTTON_PRESSED, SWITCH, SWITCH_PRESSED, NPC}


def _exit_tiles_by_direction() -> dict[str, tuple[GridPos, GridPos]]:
    return {
        "north": ((4, 0), (5, 0)),
        "south": ((4, 7), (5, 7)),
        "west": ((0, 3), (0, 4)),
        "east": ((9, 3), (9, 4)),
    }


def _exit_color(exit_type: str) -> tuple[int, int, int]:
    if exit_type == "locked_key":
        return (96, 48, 26)
    if exit_type == "conditional":
        return (255, 216, 80)
    return (255, 244, 112)



def _label_color(label: str) -> tuple[int, int, int]:
    if label == WALL:
        return (255, 80, 160)
    if label == CHEST:
        return (255, 216, 80)
    if label in {TRAP, ABYSS, GAP}:
        return (255, 80, 80)
    if label in {BUTTON, BUTTON_PRESSED, SWITCH, SWITCH_PRESSED}:
        return (80, 255, 120)
    if label == NPC:
        return (255, 180, 80)
    if label == BRIDGE:
        return (220, 150, 70)
    if label.startswith("exit_"):
        return (255, 255, 80)
    if label == UNKNOWN:
        return (255, 255, 255)
    return (120, 220, 255)


def _short_label(label: str) -> str:
    if label == FLOOR:
        return ""
    if label == WALL:
        return "W"
    if label == CHEST:
        return "C"
    if label == TRAP:
        return "TR"
    if label == ABYSS:
        return "AB"
    if label == BUTTON:
        return "BT"
    if label == BUTTON_PRESSED:
        return "BP"
    if label == SWITCH:
        return "SW"
    if label == SWITCH_PRESSED:
        return "SP"
    if label == NPC:
        return "N"
    if label == GAP:
        return "G"
    if label == BRIDGE:
        return "BR"
    if label.startswith("exit_"):
        parts = label.split("_")
        direction = parts[1][0].upper() if len(parts) > 1 else "E"
        kind = "K" if "locked_key" in label else "C" if "conditional" in label else "O"
        return f"E{direction}{kind}"
    if label == UNKNOWN:
        return "?"
    return label[:3].upper()


def _draw_label(canvas: np.ndarray, text: str, x: int, y: int, color: tuple[int, int, int]) -> None:
    shadow = (0, 0, 0)
    draw_text(canvas, text.upper(), x + 1, y + 1, shadow, scale=2)
    draw_text(canvas, text.upper(), x, y, color, scale=2)


def _draw_box(canvas: np.ndarray, x0: int, y0: int, x1: int, y1: int, color: tuple[int, int, int]) -> None:
    canvas[y0 : y0 + 2, x0 : x1 + 1] = color
    canvas[y1 - 1 : y1 + 1, x0 : x1 + 1] = color
    canvas[y0 : y1 + 1, x0 : x0 + 2] = color
    canvas[y0 : y1 + 1, x1 - 1 : x1 + 1] = color


def _draw_entity_overlay(
    canvas: np.ndarray,
    entity: DynamicEntity,
    color: tuple[int, int, int],
    scale: int,
) -> None:
    left, top, right, bottom = entity.bbox
    x0 = left * scale
    y0 = top * scale
    x1 = right * scale - 1
    y1 = bottom * scale - 1
    _draw_box(canvas, x0, y0, x1, y1, color)
    cx = int(round(entity.center_px[0] * scale))
    cy = int(round(entity.center_px[1] * scale))
    canvas[max(0, cy - 3) : min(canvas.shape[0], cy + 4), max(0, cx - 1) : min(canvas.shape[1], cx + 2)] = color
    canvas[max(0, cy - 1) : min(canvas.shape[0], cy + 2), max(0, cx - 3) : min(canvas.shape[1], cx + 4)] = color
    tile_text = f"{entity.kind[0].upper()}{entity.anchor_tile[0]},{entity.anchor_tile[1]}"
    _draw_label(canvas, tile_text, x0, max(0, y0 - 14), color)


def _save_ppm(path: Path, image: np.ndarray) -> None:
    ppm_path = path if path.suffix.lower() == ".ppm" else path.with_suffix(".ppm")
    header = f"P6\n{image.shape[1]} {image.shape[0]}\n255\n".encode("ascii")
    with ppm_path.open("wb") as handle:
        handle.write(header)
        handle.write(np.ascontiguousarray(image).tobytes())

def _map_frame(obs: np.ndarray) -> np.ndarray:
    frame = np.asarray(obs)
    if frame.ndim != 3 or frame.shape[2] != 3:
        raise ValueError(f"expected RGB observation, got shape {frame.shape}")
    if frame.shape[0] < MAP_PIXEL_HEIGHT or frame.shape[1] < MAP_PIXEL_WIDTH:
        raise ValueError(f"observation too small for map area: {frame.shape}")
    return frame[:MAP_PIXEL_HEIGHT, :MAP_PIXEL_WIDTH, :3].astype(np.uint8, copy=False)


def _mask_colors(frame: np.ndarray, colors: Iterable[tuple[int, int, int]], *, tolerance: int) -> np.ndarray:
    result = np.zeros(frame.shape[:2], dtype=bool)
    pixels = frame.astype(np.int16)
    for color in colors:
        target = np.array(color, dtype=np.int16)
        result |= np.all(np.abs(pixels - target) <= tolerance, axis=2)
    return result


def _dilate(mask: np.ndarray, *, radius: int) -> np.ndarray:
    if radius <= 0:
        return mask.copy()
    padded = np.pad(mask, radius, mode="constant", constant_values=False)
    result = np.zeros_like(mask)
    size = 2 * radius + 1
    for dy in range(size):
        for dx in range(size):
            result |= padded[dy : dy + mask.shape[0], dx : dx + mask.shape[1]]
    return result


def _entities_from_mask(mask: np.ndarray, kind: str, *, min_pixels: int) -> list[DynamicEntity]:
    visited = np.zeros(mask.shape, dtype=bool)
    entities: list[DynamicEntity] = []

    height, width = mask.shape
    for start_y, start_x in np.argwhere(mask):
        if visited[start_y, start_x]:
            continue
        pixels = _component(mask, visited, int(start_x), int(start_y), width, height)
        if len(pixels) < min_pixels:
            continue
        xs = np.array([item[0] for item in pixels], dtype=np.int32)
        ys = np.array([item[1] for item in pixels], dtype=np.int32)
        left = int(xs.min())
        top = int(ys.min())
        right = int(xs.max()) + 1
        bottom = int(ys.max()) + 1
        center_x = float((left + right - 1) / 2.0)
        center_y = float((top + bottom - 1) / 2.0)
        occupied = frozenset(
            (x, y)
            for y in range(top // TILE_SIZE, (bottom - 1) // TILE_SIZE + 1)
            for x in range(left // TILE_SIZE, (right - 1) // TILE_SIZE + 1)
            if 0 <= x < MAP_WIDTH_TILES and 0 <= y < MAP_HEIGHT_TILES
        )
        entities.append(
            DynamicEntity(
                kind=kind,
                bbox=(left, top, right, bottom),
                center_px=(center_x, center_y),
                anchor_tile=(int(center_x // TILE_SIZE), int(center_y // TILE_SIZE)),
                occupied_tiles=occupied,
                pixel_count=len(pixels),
            )
        )

    return entities


def _component(
    mask: np.ndarray,
    visited: np.ndarray,
    start_x: int,
    start_y: int,
    width: int,
    height: int,
) -> list[tuple[int, int]]:
    queue: deque[tuple[int, int]] = deque([(start_x, start_y)])
    visited[start_y, start_x] = True
    pixels: list[tuple[int, int]] = []

    while queue:
        x, y = queue.popleft()
        pixels.append((x, y))
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if nx < 0 or nx >= width or ny < 0 or ny >= height:
                continue
            if visited[ny, nx] or not mask[ny, nx]:
                continue
            visited[ny, nx] = True
            queue.append((nx, ny))

    return pixels


# Rule-policy adapter
# -------------------

_extractor = VisionExtractor(use_memory=True)
_last_policy_symbolic_frame: SymbolicFrame | None = None


def get_last_symbolic_frame() -> SymbolicFrame | None:
    return _last_policy_symbolic_frame


def reset_vision(*, preserve_color_mode: bool = False) -> None:
    _extractor.reset(preserve_color_mode=preserve_color_mode)


def perceive(
    obs: Any, memory: AgentMemory, info: dict[str, Any] | None = None
) -> SymbolicState:
    frame = _observation_frame(obs)
    global _last_policy_symbolic_frame
    symbolic = _extractor.extract(frame)
    _last_policy_symbolic_frame = symbolic
    static = symbolic.static  # (8, 10) grid of string labels

    walls: set[Position] = set()
    chests: set[Position] = set()
    normal_exits: set[Position] = set()
    locked_exits: set[Position] = set()
    conditional_exits: set[Position] = set()
    traps: set[Position] = set()
    buttons: set[Position] = set()
    switches: set[Position] = set()
    gaps: set[Position] = set()
    bridges: set[Position] = set()
    npcs: set[Position] = set()

    for row in range(MAP_HEIGHT_TILES):
        for col in range(MAP_WIDTH_TILES):
            label = static[row, col]
            pos = (col, row)
            if label == WALL:
                walls.add(pos)
            elif label == CHEST:
                chests.add(pos)
            elif label in (TRAP, ABYSS):
                traps.add(pos)
            elif label in (BUTTON, BUTTON_PRESSED):
                buttons.add(pos)
            elif label in (SWITCH, SWITCH_PRESSED):
                switches.add(pos)
            elif label == NPC:
                npcs.add(pos)
            elif label == GAP:
                gaps.add(pos)
            elif label == BRIDGE:
                bridges.add(pos)
            elif "locked_key" in label:
                if "_open_" in label:
                    normal_exits.add(pos)
                else:
                    locked_exits.add(pos)
            elif "conditional" in label:
                conditional_exits.add(pos)
            elif label.startswith("exit_"):
                normal_exits.add(pos)

    # Player --- anchor tile from vision pixel centre.
    if symbolic.player is not None:
        player: Position = symbolic.player.anchor_tile
        player_center_px = symbolic.player.center_px
    else:
        player = (4, 4)
        player_center_px = None
    # Monsters --- one anchor tile per dynamic entity
    monsters: set[Position] = set()
    for monster in symbolic.monsters:
        monsters.add(monster.anchor_tile)

    # Clean up overlaps
    normal_exits = normal_exits - walls - chests - traps
    locked_exits = locked_exits - walls - chests - traps
    conditional_exits = conditional_exits - walls - chests - traps

    keys, gold, has_sword, has_shield, health = _inventory(info, memory)

    return SymbolicState(
        player=player,
        player_center_px=player_center_px,
        room=memory.room,
        walls=walls,
        chests=chests,
        monsters=monsters,
        normal_exits=normal_exits,
        locked_exits=locked_exits,
        conditional_exits=conditional_exits,
        traps=traps,
        buttons=buttons,
        switches=switches,
        bridges=bridges,
        gaps=gaps - bridges,
        npcs=npcs,
        keys=keys,
        gold=gold,
        last_reward=_last_reward(info),
        health=health,
        has_sword=has_sword,
        has_shield=has_shield,
    )


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def _observation_frame(obs: Any) -> np.ndarray:
    frame = np.asarray(obs)
    if frame.ndim == 4:
        frame = frame[0]
    if frame.ndim != 3 or frame.shape[2] < 3:
        raise ValueError(f"expected RGB observation, got shape {frame.shape}")
    return frame[: MAP_HEIGHT_TILES * 16, : MAP_WIDTH_TILES * 16, :3].astype(
        np.uint8, copy=False
    )


def _inventory(
    info: dict[str, Any] | None, memory: AgentMemory
) -> tuple[int, int, bool, bool, int | None]:
    keys = 0
    gold = 0
    has_sword = memory.has_sword
    has_shield = memory.has_shield
    health: int | None = None
    if isinstance(info, dict):
        inventory = info.get("inventory", {})
        if isinstance(inventory, dict):
            try:
                keys = max(0, int(inventory.get("keys", 0)))
            except (TypeError, ValueError):
                pass
            try:
                gold = max(0, int(inventory.get("gold", 0)))
            except (TypeError, ValueError):
                pass
            equipped = inventory.get("equipped", {})
            items = inventory.get("items", [])
            text = f"{equipped} {items}".lower()
            has_sword = has_sword or "sword" in text
            has_shield = has_shield or "shield" in text

    return keys, gold, has_sword, has_shield, health


def _last_reward(info: dict[str, Any] | None) -> float:
    if not isinstance(info, dict):
        return 0.0
    try:
        return float(info.get("last_reward", 0.0))
    except (TypeError, ValueError):
        return 0.0


# Optional live debugger
# ----------------------

SCALE = 3  # overlay pixel scale for readability


def _print_detections(symbolic: SymbolicFrame, step: int) -> None:
    """Print a compact summary of what was detected this frame."""
    parts = [f"Step {step:4d}"]

    if symbolic.player is not None:
        p = symbolic.player
        parts.append(f"Player @ tile {p.anchor_tile} px={p.center_px}")
    else:
        parts.append("Player: NOT FOUND")

    parts.append(f"Monsters: {len(symbolic.monsters)}")
    for m in symbolic.monsters:
        parts.append(f"  @ tile {m.anchor_tile} ({m.pixel_count} px)")

    # Count static labels
    static = symbolic.static
    counts = {}
    for row in range(8):
        for col in range(10):
            label = static[row, col]
            counts[label] = counts.get(label, 0) + 1

    parts.append("Static: " + " ".join(
        f"{k}={v}" for k, v in sorted(counts.items()) if v > 0 and k != FLOOR
    ))

    blocked = symbolic.blocked_tiles()
    parts.append(f"Blocked tiles: {len(blocked)}")

    print(" | ".join(parts))


def debug_main() -> None:
    """Run the optional pygame visual debugger."""
    import argparse

    import nesylink
    import pygame
    from nesylink.core.constants import TARGET_FPS, WINDOW_HEIGHT, WINDOW_WIDTH
    from nesylink.core.input import HumanInputState
    from nesylink.tasks import list_tasks
    parser = argparse.ArgumentParser(description="Test vision extraction live")
    task_ids = [t.task_id for t in list_tasks()]
    parser.add_argument("--task", type=str, default="mathematical_logic/task_1",
                        choices=task_ids, help=f"Task ID. Available: {task_ids}")
    parser.add_argument("--seed", type=int, default=None, help="Random seed")
    parser.add_argument("--memory", action="store_true", default=True,
                        help="Use memory to fill occluded tiles")
    parser.add_argument("--no-memory", dest="memory", action="store_false",
                        help="Disable memory")
    parser.add_argument("--print-every", type=int, default=1,
                        help="Print detection summary every N steps")
    args = parser.parse_args()

    # Build environment
    env = nesylink.make_env(
        task_id=args.task,
        api="gym",
        render_mode="rgb_array",
        auto_reset_on_step=True,
        observation_mode="pixels",
    )

    obs, info = env.reset(seed=args.seed)
    print(f"\n[Task: {args.task}]")
    print(f"[Controls: Arrows=move, Z=A(sword), X=B(shield), V=toggle overlay, C=print detections, Esc=quit]")
    print(f"[Overlay legend: W=Wall C=Chest TR=Trap G=Gap BR=Bridge BT=Button SW=Switch N=NPC E*=Exit]\n")

    pygame.init()
    pygame.display.set_caption(f"Vision Test - {args.task}")
    # Double-wide window: game on left, overlay on right
    screen = pygame.display.set_mode((WINDOW_WIDTH * 2 + 20, WINDOW_HEIGHT + 40))
    clock = pygame.time.Clock()
    input_state = HumanInputState()

    vision = VisionExtractor(use_memory=args.memory)
    show_overlay = True
    game_over = False
    victory = False
    running = True
    step_count = 0
    last_symbolic: SymbolicFrame | None = None

    def reset_episode():
        nonlocal obs, info, game_over, victory, step_count
        obs, info = env.reset(seed=args.seed)
        vision.reset()
        step_count = 0
        game_over = False
        victory = False
        print("[Episode reset]\n")

    while running:
        clock.tick(TARGET_FPS)

        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            elif event.type == pygame.KEYDOWN:
                if event.key == pygame.K_ESCAPE:
                    running = False
                elif event.key == pygame.K_v:
                    show_overlay = not show_overlay
                    print(f"[Overlay {'ON' if show_overlay else 'OFF'}]")
                elif event.key == pygame.K_c:
                    if last_symbolic is not None:
                        _print_detections(last_symbolic, step_count)
                elif game_over or victory:
                    reset_episode()
                else:
                    input_state.handle_keydown(event.key)
            elif event.type == pygame.KEYUP:
                input_state.handle_keyup(event.key)

        if running and not game_over and not victory:
            action = input_state.resolve_action()
            obs, reward, terminated, truncated, info = env.step(action)
            step_count += 1

            # Run vision extraction
            try:
                symbolic = vision.extract(obs)
                last_symbolic = symbolic
                if step_count % args.print_every == 0:
                    _print_detections(symbolic, step_count)
            except Exception as exc:
                print(f"[Vision error at step {step_count}: {exc}]")
                last_symbolic = None

            if terminated:
                reason = info.get("terminal_reason")
                if reason == "agent_dead":
                    game_over = True
                    print("[GAME OVER - agent died]")
                elif reason == "world_completed":
                    victory = True
                    print("[VICTORY - world completed!]")

        # Render
        screen.fill((30, 30, 30))

        # Left: game screen
        frame = env.render()
        game_surface = pygame.surfarray.make_surface(np.transpose(frame, (1, 0, 2)))
        game_scaled = pygame.transform.scale(game_surface, (WINDOW_WIDTH, WINDOW_HEIGHT))
        screen.blit(game_scaled, (10, 10))
        _draw_label_on_screen(screen, "GAME", 10, WINDOW_HEIGHT + 15, (200, 200, 200))

        # Right: vision debug overlay
        if show_overlay and last_symbolic is not None:
            try:
                overlay = render_debug_overlay(obs, last_symbolic, extractor=vision, scale=SCALE)
                overlay_h = overlay.shape[0]
                overlay_w = overlay.shape[1]
                overlay_surface = pygame.surfarray.make_surface(
                    np.transpose(overlay, (1, 0, 2))
                )
                # Scale to fit
                target_w = WINDOW_WIDTH
                target_h = int(overlay_h * (WINDOW_WIDTH / overlay_w))
                overlay_scaled = pygame.transform.scale(overlay_surface, (target_w, target_h))
                screen.blit(overlay_scaled, (WINDOW_WIDTH + 20, 10))
                _draw_label_on_screen(screen, "VISION (grid labels + entity boxes)",
                                      WINDOW_WIDTH + 20, WINDOW_HEIGHT + 15, (200, 200, 200))
            except Exception as exc:
                _draw_label_on_screen(screen, f"Overlay error: {exc}",
                                      WINDOW_WIDTH + 20, 30, (255, 100, 100))
        else:
            _draw_label_on_screen(screen, "Overlay OFF (press V)",
                                  WINDOW_WIDTH + 20, WINDOW_HEIGHT // 2, (150, 150, 150))

        # Status bar
        if game_over:
            _draw_label_on_screen(screen, "GAME OVER - Press any key",
                                  10, 10, (255, 80, 80))
        elif victory:
            _draw_label_on_screen(screen, "VICTORY - Press any key",
                                  10, 10, (80, 255, 80))

        pygame.display.flip()

    env.close()
    pygame.quit()


def _draw_label_on_screen(screen, text: str, x: int, y: int, color: tuple[int, int, int]) -> None:
    import pygame
    font = pygame.font.SysFont(None, 18)
    surf = font.render(text, True, color)
    screen.blit(surf, (x, y))


if __name__ == "__main__":
    debug_main()
