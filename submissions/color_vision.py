"""Color-variant adaptation and sprite-template matching for pixel observations.

All colour constants, sprite templates, and template-rendering functions are
inlined here so the package has zero dependencies outside stdlib + numpy.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np


# =============================================================================
# Colour constants  (inlined from nesylink.core.constants & .rendering.sprites)
# =============================================================================

TILE_SIZE = 16
Colour = tuple[int, int, int]

OUTLINE = (8, 8, 16)
HIGHLIGHT = (255, 244, 112)
SHADOW = (42, 45, 88)
FLOOR_LIGHT = (72, 122, 248)
FLOOR_DARK = (36, 82, 206)
FLOOR_DARKER = (24, 52, 138)
WALL_LIGHT = (255, 86, 146)
WALL_MID = (219, 18, 82)
WALL_DARK = (88, 0, 36)
WALL_EDGE = (255, 44, 112)
PLAYER_TUNIC = (36, 198, 72)
PLAYER_TUNIC_LIGHT = (126, 248, 82)
PLAYER_FACE = (240, 154, 52)
PLAYER_HAIR = (86, 42, 18)
MONSTER_EYE = (255, 244, 112)
MONSTER_DARK = (126, 44, 0)
CHEST_WOOD = (152, 82, 36)
CHEST_BAND = (255, 216, 80)
CHEST_OPEN_INNER = (42, 18, 16)
LOCK_COLOR = (255, 216, 80)
KEY_COLOR = (255, 216, 80)
COIN_COLOR = (210, 28, 96)
HEART_COLOR = (204, 16, 72)
HEAL_CROSS = (255, 244, 112)
SPIKE_BASE = (36, 82, 206)
SPIKE_BASE_EDGE = (24, 52, 138)
SPIKE_METAL = (238, 238, 236)
SPIKE_SHADE = (112, 112, 126)
SPIKE_HIGHLIGHT = (255, 255, 255)
ABYSS_DARK = (8, 8, 16)
ABYSS_MID = (24, 28, 72)
ABYSS_EDGE = (58, 56, 86)
BUTTON_UP = (40, 190, 74)
BUTTON_DOWN = (28, 112, 52)
SWITCH_BODY = (255, 216, 80)
SWITCH_DOWN = (184, 124, 42)
GAP_DARK = (16, 22, 48)
GAP_MID = (24, 52, 138)
BRIDGE_WOOD = (172, 104, 48)
BRIDGE_EDGE = (96, 48, 26)
EXIT_GLOW = (255, 244, 112)
DOOR_WOOD = (96, 48, 26)
CONDITIONAL_GLYPH = (255, 216, 80)

COLOR_MONSTER_CHASER = (238, 126, 28)
COLOR_MONSTER_AMBUSHER = (255, 180, 48)
COLOR_MONSTER_PATROLLER = (200, 78, 16)
COLOR_NPC = (240, 154, 52)


# =============================================================================
# Sprite templates
# =============================================================================

PLAYER_SPRITES: dict[str, tuple[str, ...]] = {
    "down": (
        "................",
        ".....OOOOOO.....",
        "....OGGGGGGO....",
        "...OGGGGGGGGO...",
        "...OGGOOOGGGO...",
        "...OOFFFFOOO....",
        "...OOFOFOOOO....",
        "....OFFFFOO.....",
        ".....OGGGGO.....",
        "....OGLGGLO.....",
        "...OOGGGGOO.....",
        "...OOGBGGOO.....",
        "...OOGGGGOO.....",
        "....OOO.OOO.....",
        "....OBB.OBB.....",
        "................",
    ),
    "up": (
        "................",
        "......OOOO......",
        ".....OGGGGO.....",
        "....OGGGGGGO....",
        "...OGGGGGGGGO...",
        "...OGGLLLGGGO...",
        "...OGGGHGGGGO...",
        "....OHHHHHO.....",
        ".....OGGGGO.....",
        "....OGLGGLO.....",
        "...OOGGGGOO.....",
        "...OOGBGGOO.....",
        "...OOGGGGOO.....",
        "....OOO.OOO.....",
        "....OBB.OBB.....",
        "................",
    ),
    "right": (
        "................",
        ".....OOOOO......",
        "....OGGGGGO.....",
        "...OGGGGGGGO....",
        "...OGGGGOOOO....",
        "....OOFFFHOO....",
        ".....OFFFOOO....",
        ".....OOFOOO.....",
        "....OOGGGO......",
        "...OOGGLGGO.....",
        "..OOGGGGGGO.....",
        "...OOGBGGOO.....",
        "....OOGGGO......",
        ".....OO.OO......",
        ".....OB.OB......",
        "................",
    ),
}
PLAYER_SPRITES["left"] = tuple(row[::-1] for row in PLAYER_SPRITES["right"])

PLAYER_PALETTE: dict[str, Colour] = {
    "O": OUTLINE,
    "G": PLAYER_TUNIC,
    "L": PLAYER_TUNIC_LIGHT,
    "F": PLAYER_FACE,
    "H": PLAYER_HAIR,
    "B": SHADOW,
}

MONSTER_SPRITES: dict[str, tuple[str, ...]] = {
    "chaser": (
        "................",
        "......O..O......",
        "...O..OOOO..O...",
        "..OMOOMMMMOOMO..",
        "..OMMMMMMMMMMO..",
        ".OMMEOOMMEOOMMO.",
        ".OMMEOOMMEOOMMO.",
        "..OMMMMMMMMMMO..",
        "...OMMOOOOOMMO..",
        "....OMMMMMMO....",
        "...OOO....OOO...",
        "..OO........OO..",
        "................",
        "................",
        "................",
        "................",
    ),
    "patroller": (
        "................",
        "................",
        "..OO......OO....",
        ".OMMO....OMMO...",
        "OMMMMO..OMMMMO..",
        "OMMMMMOOMMMMMO..",
        ".OMMMEOOEMMMO...",
        "..OMMMOOMMMO....",
        "....OMMMMMO.....",
        ".....OHHHO......",
        "......OOO.......",
        "................",
        "................",
        "................",
        "................",
        "................",
    ),
    "ambusher": (
        "................",
        "................",
        ".....OOOOOO.....",
        "...OOMMMMMMOO...",
        "..OMMMMMMMMMMO..",
        "..OMMOOMMOOMMO..",
        ".OMMMEOOOEMMMO..",
        ".OMMMMMMMMMMMO..",
        "..OMMHHHHHMMO...",
        "...OMMMMMMMO....",
        "..OOO....OOO....",
        ".OO........OO...",
        "................",
        "................",
        "................",
        "................",
    ),
}

FONT_3X5: dict[str, tuple[str, ...]] = {
    "0": ("111", "101", "101", "101", "111"),
    "1": ("010", "110", "010", "010", "111"),
    "2": ("111", "001", "111", "100", "111"),
    "3": ("111", "001", "111", "001", "111"),
    "4": ("101", "101", "111", "001", "001"),
    "5": ("111", "100", "111", "001", "111"),
    "6": ("111", "100", "111", "101", "111"),
    "7": ("111", "001", "010", "010", "010"),
    "8": ("111", "101", "111", "101", "111"),
    "9": ("111", "101", "111", "001", "111"),
    "A": ("010", "101", "111", "101", "101"),
    "B": ("110", "101", "110", "101", "110"),
    "C": ("111", "100", "100", "100", "111"),
    "D": ("110", "101", "101", "101", "110"),
    "E": ("111", "100", "110", "100", "111"),
    "F": ("111", "100", "110", "100", "100"),
    "G": ("111", "100", "101", "101", "111"),
    "H": ("101", "101", "111", "101", "101"),
    "I": ("111", "010", "010", "010", "111"),
    "J": ("001", "001", "001", "101", "111"),
    "K": ("101", "101", "110", "101", "101"),
    "L": ("100", "100", "100", "100", "111"),
    "M": ("101", "111", "111", "101", "101"),
    "N": ("101", "111", "111", "111", "101"),
    "O": ("111", "101", "101", "101", "111"),
    "P": ("111", "101", "111", "100", "100"),
    "Q": ("111", "101", "101", "111", "001"),
    "R": ("110", "101", "110", "101", "101"),
    "S": ("111", "100", "111", "001", "111"),
    "T": ("111", "010", "010", "010", "010"),
    "U": ("101", "101", "101", "101", "111"),
    "V": ("101", "101", "101", "101", "010"),
    "W": ("101", "101", "111", "111", "101"),
    "X": ("101", "101", "010", "101", "101"),
    "Y": ("101", "101", "010", "010", "010"),
    "Z": ("111", "001", "010", "100", "111"),
    ":": ("000", "010", "000", "010", "000"),
    ",": ("000", "000", "000", "010", "100"),
    ".": ("000", "000", "000", "000", "010"),
    "-": ("000", "000", "111", "000", "000"),
    "_": ("000", "000", "000", "000", "111"),
    "/": ("001", "001", "010", "100", "100"),
    " ": ("000", "000", "000", "000", "000"),
}


# =============================================================================
# Rendering primitives  (inlined from nesylink.core.rendering.sprites)
# =============================================================================

Rect = tuple[int, int, int, int]


def _tile_rect(col: int, row: int, padding: int = 0) -> Rect:
    left = col * TILE_SIZE + padding
    top = row * TILE_SIZE + padding
    return left, top, TILE_SIZE - padding * 2, TILE_SIZE - padding * 2


def _fill_rect(frame: np.ndarray, rect: Rect, color: Colour) -> None:
    left, top, width, height = rect
    if width <= 0 or height <= 0:
        return
    right = min(frame.shape[1], left + width)
    bottom = min(frame.shape[0], top + height)
    left = max(0, left)
    top = max(0, top)
    if left < right and top < bottom:
        frame[top:bottom, left:right] = color


def _draw_rect_outline(frame: np.ndarray, rect: Rect, color: Colour) -> None:
    left, top, width, height = rect
    _fill_rect(frame, (left, top, width, 1), color)
    _fill_rect(frame, (left, top + height - 1, width, 1), color)
    _fill_rect(frame, (left, top, 1, height), color)
    _fill_rect(frame, (left + width - 1, top, 1, height), color)


def _draw_triangle_up(
    frame: np.ndarray, left: int, top: int, width: int, height: int, color: Colour
) -> None:
    centre = left + width // 2
    for offset in range(height):
        row_width = max(1, int((offset + 1) * width / height))
        row_left = centre - row_width // 2
        _fill_rect(frame, (row_left, top + height - offset - 1, row_width, 1), color)


def _draw_pixel_art(
    frame: np.ndarray,
    sprite: tuple[str, ...],
    left: int,
    top: int,
    palette: dict[str, Colour],
) -> None:
    for y_offset, row in enumerate(sprite):
        for x_offset, key in enumerate(row):
            color = palette.get(key)
            if color is not None:
                _fill_rect(frame, (left + x_offset, top + y_offset, 1, 1), color)


# =============================================================================
# Tile renderers
# =============================================================================

def draw_floor(frame: np.ndarray, col: int, row: int) -> None:
    rect = _tile_rect(col, row)
    _fill_rect(frame, rect, FLOOR_LIGHT)
    left, top, _w, _h = rect
    pebble_shift = (col * 5 + row * 3) % 4
    for px, py in ((1, 1), (8, 1), (4, 6), (12, 8), (2, 12), (9, 13)):
        x = left + px + pebble_shift % 2
        y = top + py
        _fill_rect(frame, (x + 1, y, 4, 1), FLOOR_DARK)
        _fill_rect(frame, (x, y + 1, 6, 3), FLOOR_DARK)
        _fill_rect(frame, (x + 1, y + 4, 4, 1), FLOOR_DARKER)
        _fill_rect(frame, (x + 4, y + 2, 1, 1), FLOOR_LIGHT)


def draw_wall(frame: np.ndarray, col: int, row: int) -> None:
    rect = _tile_rect(col, row)
    _fill_rect(frame, rect, WALL_MID)
    left, top, width, _h = rect
    _draw_rect_outline(frame, rect, OUTLINE)
    _fill_rect(frame, (left + 2, top + 2, width - 4, 3), WALL_LIGHT)
    _fill_rect(frame, (left + 3, top + 5, width - 6, 2), WALL_EDGE)
    _fill_rect(frame, (left + 2, top + 11, width - 4, 2), WALL_DARK)
    _fill_rect(frame, (left + 5, top + 7, 2, 5), WALL_DARK)
    _fill_rect(frame, (left + 11, top + 7, 2, 5), WALL_DARK)
    _fill_rect(frame, (left + 4, top + 3, 8, 1), HIGHLIGHT)


def draw_gap(frame: np.ndarray, col: int, row: int) -> None:
    left, top, _, _ = _tile_rect(col, row)
    _fill_rect(frame, (left, top, TILE_SIZE, TILE_SIZE), GAP_DARK)
    _draw_rect_outline(frame, (left, top, TILE_SIZE, TILE_SIZE), OUTLINE)
    _fill_rect(frame, (left + 3, top + 3, TILE_SIZE - 6, TILE_SIZE - 6), GAP_MID)
    _fill_rect(frame, (left + 5, top + 5, TILE_SIZE - 10, TILE_SIZE - 10), GAP_DARK)


def draw_bridge(frame: np.ndarray, col: int, row: int) -> None:
    left, top, _, _ = _tile_rect(col, row)
    _fill_rect(frame, (left, top, TILE_SIZE, TILE_SIZE), BRIDGE_WOOD)
    _draw_rect_outline(frame, (left, top, TILE_SIZE, TILE_SIZE), OUTLINE)
    _fill_rect(frame, (left + 1, top + 3, TILE_SIZE - 2, 2), BRIDGE_EDGE)
    _fill_rect(frame, (left + 1, top + 8, TILE_SIZE - 2, 2), BRIDGE_EDGE)
    _fill_rect(frame, (left + 1, top + 13, TILE_SIZE - 2, 2), BRIDGE_EDGE)
    _fill_rect(frame, (left + 4, top + 1, 2, TILE_SIZE - 2), HIGHLIGHT)
    _fill_rect(frame, (left + 10, top + 1, 2, TILE_SIZE - 2), BRIDGE_EDGE)


def draw_abyss(frame: np.ndarray, col: int, row: int) -> None:
    left, top, _, _ = _tile_rect(col, row)
    _fill_rect(frame, (left, top, TILE_SIZE, TILE_SIZE), (0, 0, 0))


def draw_trap(frame: np.ndarray, col: int, row: int) -> None:
    left, top, _, _ = _tile_rect(col, row)
    _fill_rect(frame, (left + 1, top + 12, TILE_SIZE - 2, 2), SPIKE_BASE_EDGE)
    _fill_rect(frame, (left + 2, top + 12, TILE_SIZE - 4, 1), SPIKE_BASE)
    for sl in (2, 5, 8, 11):
        _draw_triangle_up(frame, left + sl, top + 7, 3, 6, SPIKE_BASE_EDGE)
        _draw_triangle_up(frame, left + sl + 1, top + 8, 1, 4, SPIKE_METAL)
        _fill_rect(frame, (left + sl + 2, top + 10, 1, 2), SPIKE_SHADE)
        _fill_rect(frame, (left + sl + 1, top + 8, 1, 1), SPIKE_HIGHLIGHT)


def draw_button(frame: np.ndarray, col: int, row: int, *, pressed: bool) -> None:
    left, top, _, _ = _tile_rect(col, row)
    _fill_rect(frame, (left + 3, top + 9, 10, 4), OUTLINE)
    if pressed:
        _fill_rect(frame, (left + 4, top + 7, 8, 4), BUTTON_DOWN)
        _fill_rect(frame, (left + 5, top + 7, 6, 1), (86, 146, 104))
    else:
        _fill_rect(frame, (left + 4, top + 5, 8, 6), BUTTON_UP)
        _fill_rect(frame, (left + 5, top + 5, 6, 1), HIGHLIGHT)
    _draw_rect_outline(
        frame,
        (left + 4, top + (7 if pressed else 5), 8, 4 if pressed else 6),
        OUTLINE,
    )


def draw_switch(frame: np.ndarray, col: int, row: int, *, activated: bool) -> None:
    left, top, _, _ = _tile_rect(col, row)
    _fill_rect(frame, (left + 2, top + 10, 12, 3), OUTLINE)
    _fill_rect(frame, (left + 3, top + 8, 10, 3), SWITCH_DOWN if activated else SWITCH_BODY)
    _fill_rect(frame, (left + 7, top + 3, 2, 6), OUTLINE)
    _fill_rect(frame, (left + 6, top + 2, 4, 3), SWITCH_BODY)
    _fill_rect(frame, (left + 7, top + 2, 2, 1), HIGHLIGHT)
    _draw_rect_outline(frame, (left + 6, top + 2, 4, 3), OUTLINE)


def draw_npc(frame: np.ndarray, col: int, row: int, color: Colour) -> None:
    left, top, _, _ = _tile_rect(col, row)
    _fill_rect(frame, (left + 4, top + 3, 8, 10), color)
    _draw_rect_outline(frame, (left + 4, top + 3, 8, 10), OUTLINE)
    _fill_rect(frame, (left + 6, top + 6, 1, 1), OUTLINE)
    _fill_rect(frame, (left + 9, top + 6, 1, 1), OUTLINE)
    _fill_rect(frame, (left + 5, top + 11, 6, 1), HIGHLIGHT)


def _draw_key(frame: np.ndarray, pos: tuple[int, int]) -> None:
    left, top = pos
    _fill_rect(frame, (left, top + 2, 3, 3), KEY_COLOR)
    _fill_rect(frame, (left + 3, top + 3, 5, 1), KEY_COLOR)
    _fill_rect(frame, (left + 6, top + 4, 1, 2), KEY_COLOR)
    _fill_rect(frame, (left + 8, top + 4, 1, 2), KEY_COLOR)
    _fill_rect(frame, (left + 1, top + 3, 1, 1), OUTLINE)


def _draw_coin(frame: np.ndarray, pos: tuple[int, int]) -> None:
    left, top = pos
    _fill_rect(frame, (left + 2, top, 3, 1), COIN_COLOR)
    _fill_rect(frame, (left + 1, top + 1, 5, 4), COIN_COLOR)
    _fill_rect(frame, (left + 2, top + 5, 3, 1), COIN_COLOR)
    _fill_rect(frame, (left + 3, top + 1, 1, 4), HIGHLIGHT)


def _draw_heal(frame: np.ndarray, pos: tuple[int, int]) -> None:
    left, top = pos
    _fill_rect(frame, (left + 1, top + 1, 2, 2), HEART_COLOR)
    _fill_rect(frame, (left + 4, top + 1, 2, 2), HEART_COLOR)
    _fill_rect(frame, (left, top + 3, 7, 2), HEART_COLOR)
    _fill_rect(frame, (left + 2, top + 5, 3, 1), HEART_COLOR)
    _fill_rect(frame, (left + 3, top + 2, 1, 3), HEAL_CROSS)


def _draw_loot_icon(frame: np.ndarray, pos: tuple[int, int], kind: str) -> None:
    if kind == "key":
        _draw_key(frame, pos)
    elif kind in ("gold", "coin"):
        _draw_coin(frame, pos)
    elif kind in ("heal", "potion", "heart"):
        _draw_heal(frame, pos)


def draw_chest(
    frame: np.ndarray, col: int, row: int, *, opened: bool, loot_kind: str | None = None
) -> None:
    left, top, _, _ = _tile_rect(col, row)
    _fill_rect(frame, (left + 2, top + 5, 12, 8), CHEST_WOOD)
    _draw_rect_outline(frame, (left + 2, top + 5, 12, 8), OUTLINE)
    if opened:
        _fill_rect(frame, (left + 3, top + 3, 10, 4), CHEST_OPEN_INNER)
        _fill_rect(frame, (left + 3, top + 2, 10, 2), CHEST_BAND)
    else:
        _fill_rect(frame, (left + 2, top + 4, 12, 3), CHEST_BAND)
    _fill_rect(frame, (left + 7, top + 7, 2, 3), LOCK_COLOR)
    if loot_kind:
        _draw_loot_icon(frame, (left + 10, top + 2), loot_kind)


def draw_exit(
    frame: np.ndarray,
    tiles: tuple[tuple[int, int], tuple[int, int]],
    exit_type: str,
    color: Colour,
    *,
    opened: bool = False,
) -> None:
    left = min(t[0] for t in tiles) * TILE_SIZE
    top = min(t[1] for t in tiles) * TILE_SIZE
    right = (max(t[0] for t in tiles) + 1) * TILE_SIZE
    bottom = (max(t[1] for t in tiles) + 1) * TILE_SIZE
    width = right - left
    height = bottom - top
    rect = (left + 2, top + 2, width - 4, height - 4)
    if exit_type == "normal":
        _fill_rect(frame, rect, OUTLINE)
        _draw_rect_outline(frame, rect, WALL_LIGHT)
        if width < height:
            _fill_rect(frame, (left + 4, top + 5, max(1, width - 8), height - 10), SHADOW)
            _fill_rect(frame, (left + 4, top + 5, 2, height - 10), HIGHLIGHT)
        else:
            _fill_rect(frame, (left + 5, top + 4, width - 10, max(1, height - 8)), SHADOW)
            _fill_rect(frame, (left + 5, top + 4, width - 10, 2), HIGHLIGHT)
    elif exit_type == "locked_key":
        if opened:
            _fill_rect(frame, rect, color)
            _fill_rect(frame, (left + 4, top + 4, width - 8, height - 8), EXIT_GLOW)
            _draw_rect_outline(frame, rect, OUTLINE)
            ll = left + width // 2 + 2
            lt = top + height // 2 - 2
            _fill_rect(frame, (ll, lt, 5, 4), LOCK_COLOR)
            _fill_rect(frame, (ll + 1, lt - 4, 4, 2), OUTLINE)
            _fill_rect(frame, (ll + 4, lt - 2, 1, 3), OUTLINE)
        else:
            _fill_rect(frame, rect, DOOR_WOOD)
            _draw_rect_outline(frame, rect, OUTLINE)
            _fill_rect(frame, (left + width // 2 - 3, top + height // 2 - 1, 6, 5), LOCK_COLOR)
            _fill_rect(frame, (left + width // 2 - 2, top + height // 2 - 4, 4, 4), OUTLINE)
            _fill_rect(frame, (left + width // 2 - 1, top + height // 2 - 3, 2, 3), color)
    else:
        _fill_rect(frame, rect, OUTLINE)
        _draw_rect_outline(frame, rect, HIGHLIGHT)
        if width < height:
            _fill_rect(frame, (left + width // 2 - 2, top + 5, 4, height - 10), CONDITIONAL_GLYPH)
            for yo in range(7, height - 7, 5):
                _fill_rect(frame, (left + 4, top + yo, width - 8, 2), WALL_DARK)
        else:
            _fill_rect(frame, (left + 5, top + height // 2 - 2, width - 10, 4), CONDITIONAL_GLYPH)
            for xo in range(7, width - 7, 5):
                _fill_rect(frame, (left + xo, top + 4, 2, height - 8), WALL_DARK)


def draw_text(
    frame: np.ndarray, text: str, x: int, y: int, color: Colour, *, scale: int = 1
) -> None:
    cx = x
    for ch in text:
        glyph = FONT_3X5.get(ch, FONT_3X5[" "])
        for ri, row in enumerate(glyph):
            for ci, px in enumerate(row):
                if px == "1":
                    _fill_rect(
                        frame,
                        (cx + ci * scale, y + ri * scale, scale, scale),
                        color,
                    )
        cx += 4 * scale
        if cx >= frame.shape[1] - 2:
            return


COLOR_MODES = ("default", "grayscale", "dark", "bright", "high_contrast", "inverted")
_MONSTER_COLORS = {
    "chaser": COLOR_MONSTER_CHASER,
    "patroller": COLOR_MONSTER_PATROLLER,
    "ambusher": COLOR_MONSTER_AMBUSHER,
}


@dataclass(frozen=True)
class SpriteMatch:
    kind: str
    variant: str
    origin: tuple[int, int]
    bbox: tuple[int, int, int, int]
    center_px: tuple[float, float]
    anchor_tile: tuple[int, int]
    occupied_tiles: frozenset[tuple[int, int]]
    pixel_count: int
    score: float
    foreground_mask: np.ndarray


def transform_color_image(image: np.ndarray, mode: str) -> np.ndarray:
    """Apply exactly the same transforms as ``utils.evaluate_policy``."""
    array = np.asarray(image, dtype=np.uint8)
    if mode == "default":
        return array
    if mode == "grayscale":
        gray = array.mean(axis=2, keepdims=True).astype(np.uint8)
        return np.repeat(gray, 3, axis=2)
    if mode == "dark":
        return (array.astype(np.float32) * 0.55).clip(0, 255).astype(np.uint8)
    if mode == "bright":
        return (array.astype(np.float32) * 1.35).clip(0, 255).astype(np.uint8)
    if mode == "high_contrast":
        return np.where(array > 127, 255, 0).astype(np.uint8)
    if mode == "inverted":
        return 255 - array
    raise ValueError(f"unknown color mode: {mode}")


def infer_color_mode(frame: np.ndarray) -> str:
    """Infer the global evaluator color transform from pixels only."""
    image = np.asarray(frame, dtype=np.uint8)
    if np.isin(image, (0, 255)).all():
        return "high_contrast"
    if np.array_equal(image[..., 0], image[..., 1]) and np.array_equal(image[..., 1], image[..., 2]):
        return "grayscale"
    if int(image.max()) <= 141:
        return "dark"

    floor = _floor_frame(image.shape[1], image.shape[0])
    scores = {}
    observed = image.astype(np.int32)
    for mode in ("default", "bright", "inverted"):
        candidate = transform_color_image(floor, mode).astype(np.int32)
        pixel_error = np.sum((observed - candidate) ** 2, axis=2, dtype=np.int64)
        scores[mode] = float(np.median(pixel_error))
    return min(scores, key=scores.get)


def detect_dynamic_sprites(
    frame: np.ndarray,
    mode: str,
    *,
    previous_player_origin: tuple[int, int] | None = None,
    previous_monster_origins: tuple[tuple[int, int], ...] = (),
    scan_for_monsters: bool = True,
) -> tuple[SpriteMatch, list[SpriteMatch], np.ndarray]:
    """Detect sprites, using cheap local tracking after the first full scan."""
    image = np.asarray(frame, dtype=np.uint8)
    player_candidates = [
        _best_sprite_match(image, "player", facing, sprite, PLAYER_PALETTE, mode, origin_hint=previous_player_origin)
        for facing, sprite in PLAYER_SPRITES.items()
    ]
    player = min(player_candidates, key=lambda match: match.score)
    if previous_player_origin is not None and player.score > 5000.0:
        player = min(
            (_best_sprite_match(image, "player", facing, sprite, PLAYER_PALETTE, mode)
             for facing, sprite in PLAYER_SPRITES.items()),
            key=lambda match: match.score,
        )

    monster_candidates: list[SpriteMatch] = []
    if previous_monster_origins:
        for origin in previous_monster_origins:
            tracked = [
                _best_sprite_match(
                    image, "monster", monster_type, sprite,
                    _monster_palette(monster_type), mode, origin_hint=origin,
                )
                for monster_type, sprite in MONSTER_SPRITES.items()
            ]
            best = min(tracked, key=lambda match: match.score)
            if best.score <= 0.5:
                monster_candidates.append(best)

    if scan_for_monsters or (previous_monster_origins and not monster_candidates):
        monster_candidates.extend(_scan_monsters(image, mode))

    monsters = _non_maximum_suppression(monster_candidates, radius=8)
    dynamic_mask = np.zeros(image.shape[:2], dtype=bool)
    _paint_match_mask(dynamic_mask, player)
    for monster in monsters:
        _paint_match_mask(dynamic_mask, monster)
    return player, monsters, dynamic_mask


def _monster_palette(monster_type: str) -> dict[str, tuple[int, int, int]]:
    return {
        "O": OUTLINE,
        "M": _MONSTER_COLORS[monster_type],
        "H": MONSTER_DARK,
        "E": MONSTER_EYE,
    }


def _scan_monsters(frame: np.ndarray, mode: str) -> list[SpriteMatch]:
    candidates: list[SpriteMatch] = []
    for monster_type, sprite in MONSTER_SPRITES.items():
        score_map, mask = _sprite_score_map(frame, sprite, _monster_palette(monster_type), mode)
        for y, x in np.argwhere(score_map <= 0.5):
            candidates.append(
                _make_match(
                    "monster", monster_type, int(x), int(y), mask,
                    float(score_map[y, x]), frame.shape,
                )
            )
    return candidates


def _best_sprite_match(
    frame: np.ndarray,
    kind: str,
    variant: str,
    sprite: tuple[str, ...],
    palette: dict[str, tuple[int, int, int]],
    mode: str,
    *,
    origin_hint: tuple[int, int] | None = None,
    search_radius: int = 4,
) -> SpriteMatch:
    offset_x = 0
    offset_y = 0
    search_frame = frame
    if origin_hint is not None:
        sprite_height = len(sprite)
        sprite_width = len(sprite[0])
        offset_x = max(0, origin_hint[0] - search_radius)
        offset_y = max(0, origin_hint[1] - search_radius)
        max_x = min(frame.shape[1] - sprite_width, origin_hint[0] + search_radius)
        max_y = min(frame.shape[0] - sprite_height, origin_hint[1] + search_radius)
        search_frame = frame[offset_y : max_y + sprite_height, offset_x : max_x + sprite_width]
    score_map, mask = _sprite_score_map(search_frame, sprite, palette, mode)
    local_y, local_x = np.unravel_index(np.argmin(score_map), score_map.shape)
    x = int(local_x) + offset_x
    y = int(local_y) + offset_y
    return _make_match(kind, variant, x, y, mask, float(score_map[local_y, local_x]), frame.shape)


def _sprite_score_map(
    frame: np.ndarray,
    sprite: tuple[str, ...],
    palette: dict[str, tuple[int, int, int]],
    mode: str,
) -> tuple[np.ndarray, np.ndarray]:
    height = len(sprite)
    width = len(sprite[0])
    mask = np.zeros((height, width), dtype=bool)
    colors = np.zeros((height, width, 3), dtype=np.uint8)
    for y, row in enumerate(sprite):
        for x, key in enumerate(row):
            color = palette.get(key)
            if color is not None:
                mask[y, x] = True
                colors[y, x] = color
    colors = transform_color_image(colors, mode)

    output_height = frame.shape[0] - height + 1
    output_width = frame.shape[1] - width + 1
    scores = np.zeros((output_height, output_width), dtype=np.float64)
    observed = frame.astype(np.int32)
    for y, x in np.argwhere(mask):
        difference = observed[y : y + output_height, x : x + output_width] - colors[y, x].astype(np.int32)
        scores += np.sum(difference * difference, axis=2, dtype=np.int64)
    scores /= max(1, int(mask.sum()))
    return scores, mask


def _make_match(
    kind: str,
    variant: str,
    x: int,
    y: int,
    mask: np.ndarray,
    score: float,
    frame_shape: tuple[int, ...],
) -> SpriteMatch:
    foreground = np.argwhere(mask)
    top = y + int(foreground[:, 0].min())
    bottom = y + int(foreground[:, 0].max()) + 1
    left = x + int(foreground[:, 1].min())
    right = x + int(foreground[:, 1].max()) + 1
    center = (x + mask.shape[1] / 2.0, y + mask.shape[0] / 2.0)
    anchor = (int(center[0] // TILE_SIZE), int(center[1] // TILE_SIZE))
    occupied = frozenset(
        (col, row)
        for row in range(max(0, y // TILE_SIZE), min(8, (y + mask.shape[0] - 1) // TILE_SIZE + 1))
        for col in range(max(0, x // TILE_SIZE), min(10, (x + mask.shape[1] - 1) // TILE_SIZE + 1))
    )
    return SpriteMatch(
        kind=kind,
        variant=variant,
        origin=(x, y),
        bbox=(left, top, right, bottom),
        center_px=center,
        anchor_tile=anchor,
        occupied_tiles=occupied,
        pixel_count=int(mask.sum()),
        score=score,
        foreground_mask=mask,
    )


def _non_maximum_suppression(candidates: list[SpriteMatch], *, radius: int) -> list[SpriteMatch]:
    kept: list[SpriteMatch] = []
    for candidate in sorted(candidates, key=lambda item: item.score):
        if any(
            abs(candidate.origin[0] - other.origin[0]) <= radius
            and abs(candidate.origin[1] - other.origin[1]) <= radius
            for other in kept
        ):
            continue
        kept.append(candidate)
    return kept


def _paint_match_mask(target: np.ndarray, match: SpriteMatch) -> None:
    x, y = match.origin
    height, width = match.foreground_mask.shape
    target[y : y + height, x : x + width] |= match.foreground_mask


def _floor_frame(width: int, height: int) -> np.ndarray:
    frame = np.zeros((height, width, 3), dtype=np.uint8)
    for row in range((height + TILE_SIZE - 1) // TILE_SIZE):
        for col in range((width + TILE_SIZE - 1) // TILE_SIZE):
            draw_floor(frame, col, row)
    return frame
