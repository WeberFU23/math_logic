from __future__ import annotations

from collections import deque
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

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


@dataclass
class SymbolicFrame:
    static: np.ndarray
    confidence: np.ndarray
    player: DynamicEntity | None
    monsters: list[DynamicEntity]
    dynamic_mask: np.ndarray
    raw_static: np.ndarray | None = None

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
    last_static: np.ndarray | None = None
    last_confidence: np.ndarray | None = None

    def __post_init__(self) -> None:
        if not self.templates:
            self.templates = build_template_library()

    def reset(self) -> None:
        self.last_static = None
        self.last_confidence = None

    def extract(self, obs: np.ndarray) -> SymbolicFrame:
        frame = _map_frame(obs)
        player_mask = _mask_colors(frame, PLAYER_COLORS, tolerance=self.dynamic_tolerance)
        monster_mask = _mask_colors(frame, MONSTER_COLORS, tolerance=self.dynamic_tolerance)

        # Outline is shared by all sprites. Keep it only where a unique player or
        # monster color is nearby, otherwise walls and chests would look dynamic.
        player_seed = _mask_colors(
            frame,
            {PLAYER_TUNIC, PLAYER_TUNIC_LIGHT},
            tolerance=min(self.dynamic_tolerance, 4),
        )
        monster_seed = _mask_colors(
            frame,
            {COLOR_MONSTER_CHASER, COLOR_MONSTER_PATROLLER, COLOR_MONSTER_AMBUSHER},
            tolerance=self.dynamic_tolerance,
        )
        player_mask &= _dilate(player_seed, radius=7)
        monster_mask &= _dilate(monster_seed, radius=2)
        monster_mask &= ~player_mask

        player_entities = _entities_from_mask(player_mask, "player", min_pixels=self.min_player_pixels)
        monster_entities = _entities_from_mask(monster_mask, "monster", min_pixels=self.min_monster_pixels)
        player = max(player_entities, key=lambda item: item.pixel_count, default=None)

        static, confidence = self._classify_static(frame, player_mask | monster_mask)
        raw_static = static.copy()

        if self.use_memory:
            static, confidence = self._merge_memory(static, confidence, player_mask | monster_mask)
            self.last_static = static.copy()
            self.last_confidence = confidence.copy()

        return SymbolicFrame(
            static=static,
            confidence=confidence,
            player=player,
            monsters=monster_entities,
            dynamic_mask=player_mask | monster_mask,
            raw_static=raw_static,
        )

    def _classify_static(self, frame: np.ndarray, dynamic_mask: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
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
                    self._templates_for_position(col, row),
                    ignore_mask=mask,
                )
                static[row, col] = label
                if second_score <= 1e-6:
                    confidence[row, col] = 1.0
                else:
                    confidence[row, col] = float(np.clip(1.0 - score / second_score, 0.0, 1.0))

        return static, confidence

    def _templates_for_position(self, col: int, row: int) -> dict[str, np.ndarray]:
        key = (col, row)
        templates = self.positioned_templates.get(key)
        if templates is None:
            templates = build_positioned_template_library(col, row)
            self.positioned_templates[key] = templates
        return templates

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











