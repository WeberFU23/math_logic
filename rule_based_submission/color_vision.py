"""Color-variant adaptation and sprite-template matching for pixel observations."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from nesylink.core.constants import (
    COLOR_MONSTER_AMBUSHER,
    COLOR_MONSTER_CHASER,
    COLOR_MONSTER_PATROLLER,
    TILE_SIZE,
)
from nesylink.core.rendering.sprites import (
    MONSTER_DARK,
    MONSTER_EYE,
    MONSTER_SPRITES,
    OUTLINE,
    PLAYER_PALETTE,
    PLAYER_SPRITES,
    draw_floor,
)


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
