"""Visualize and attribute color-stage perception failures.

This is an offline diagnostic utility. Environment runtime state is used only as
scoring ground truth and is never included in the policy input.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, deque
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any
PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))


import numpy as np
from PIL import Image, ImageDraw, ImageFont

from nesylink.env import make_env
from rule_based_submission.vision import (
    ABYSS,
    BRIDGE,
    BUTTON,
    BUTTON_PRESSED,
    CHEST,
    FLOOR,
    GAP,
    NPC,
    SWITCH,
    SWITCH_PRESSED,
    TRAP,
    WALL,
    SymbolicFrame,
    get_last_symbolic_frame,
    render_debug_overlay,
)
from utils.evaluate_policy import (
    apply_obs_variant,
    build_policy_info,
    call_policy,
    event_names,
    is_success,
    reset_policy,
    resolve_policies,
)


COLOR_VARIANTS = ("grayscale", "dark", "bright", "high_contrast", "inverted")
MAP_WIDTH = 10
MAP_HEIGHT = 8
TILE_SIZE = 16


@dataclass
class FrameMetrics:
    step: int
    expected_mode: str
    inferred_mode: str
    mode_correct: bool
    player_truth: tuple[int, int]
    player_prediction: tuple[int, int] | None
    player_correct: bool
    monster_truth: list[tuple[int, int]]
    monster_prediction: list[tuple[int, int]]
    monster_tp: int
    monster_fp: int
    monster_fn: int
    static_correct: int
    static_total: int
    static_accuracy: float
    static_errors: list[dict[str, Any]]
    attributions: list[str]


@dataclass
class EpisodeSummary:
    task_id: str
    variant: str
    seed: int
    steps: int
    success: bool
    terminal_reason: str | None
    mode_accuracy: float
    player_accuracy: float
    monster_precision: float
    monster_recall: float
    static_accuracy: float
    attribution_counts: dict[str, int]
    event_counts: dict[str, int]
    gif_path: str
    frames_path: str


def _normalize_prediction(label: str) -> str:
    if label.startswith("exit_"):
        return "exit"
    return label


def _truth_static(runtime: Any) -> np.ndarray:
    room = runtime.room
    truth = np.full((MAP_HEIGHT, MAP_WIDTH), FLOOR, dtype=object)

    for (col, row), kind in room.dynamic_tiles.items():
        if kind in {GAP, BRIDGE}:
            truth[row, col] = kind

    for exit_config in room.exits:
        for col, row in exit_config.tiles:
            truth[row, col] = "exit"

    for col, row in room.walls:
        truth[row, col] = WALL

    for chest in room.chests.values():
        if chest.is_visible:
            truth[chest.pos[1], chest.pos[0]] = CHEST

    for npc in room.npcs.values():
        truth[npc.pos[1], npc.pos[0]] = NPC

    for trap in room.traps.values():
        if not trap.is_active or room.dynamic_tiles.get(trap.pos) == BRIDGE:
            continue
        label = ABYSS if trap.trap_type == ABYSS else TRAP
        truth[trap.pos[1], trap.pos[0]] = label

    for button in room.buttons.values():
        label = BUTTON_PRESSED if button.is_pressed else BUTTON
        truth[button.pos[1], button.pos[0]] = label

    for switch in room.switches.values():
        label = SWITCH_PRESSED if switch.is_pressed else SWITCH
        truth[switch.pos[1], switch.pos[0]] = label

    return truth


def _anchor(position_px: tuple[float, float], size_px: int) -> tuple[int, int]:
    center_x = float(position_px[0]) + float(size_px) / 2.0
    center_y = float(position_px[1]) + float(size_px) / 2.0
    return int(center_x // TILE_SIZE), int(center_y // TILE_SIZE)


def _measure(step: int, variant: str, symbolic: SymbolicFrame, runtime: Any) -> FrameMetrics:
    truth_static = _truth_static(runtime)
    predicted_static = np.vectorize(_normalize_prediction)(symbolic.static)
    errors: list[dict[str, Any]] = []
    attributions: list[str] = []

    for row in range(MAP_HEIGHT):
        for col in range(MAP_WIDTH):
            truth = str(truth_static[row, col])
            prediction = str(predicted_static[row, col])
            if truth != prediction:
                errors.append({"pos": [col, row], "truth": truth, "prediction": prediction})
                attributions.append(f"static:{truth}_as_{prediction}")

    player_truth = _anchor(runtime.player.position_px, runtime.player.size_px)
    player_prediction = symbolic.player.anchor_tile if symbolic.player is not None else None
    player_correct = player_prediction == player_truth
    if player_prediction is None:
        attributions.append("player:missed")
    elif not player_correct:
        attributions.append("player:wrong_tile")

    monster_truth = {
        _anchor(monster.position_px, monster.size_px)
        for monster in runtime.room.monsters.values()
    }
    monster_prediction = {monster.anchor_tile for monster in symbolic.monsters}
    true_positive = len(monster_truth & monster_prediction)
    false_positive = len(monster_prediction - monster_truth)
    false_negative = len(monster_truth - monster_prediction)
    if false_positive:
        attributions.extend(["monster:false_positive"] * false_positive)
    if false_negative:
        attributions.extend(["monster:missed"] * false_negative)

    mode_correct = symbolic.color_mode == variant
    if not mode_correct:
        attributions.append("color_mode:mismatch")

    static_correct = MAP_WIDTH * MAP_HEIGHT - len(errors)
    return FrameMetrics(
        step=step,
        expected_mode=variant,
        inferred_mode=symbolic.color_mode,
        mode_correct=mode_correct,
        player_truth=player_truth,
        player_prediction=player_prediction,
        player_correct=player_correct,
        monster_truth=sorted(monster_truth),
        monster_prediction=sorted(monster_prediction),
        monster_tp=true_positive,
        monster_fp=false_positive,
        monster_fn=false_negative,
        static_correct=static_correct,
        static_total=MAP_WIDTH * MAP_HEIGHT,
        static_accuracy=static_correct / (MAP_WIDTH * MAP_HEIGHT),
        static_errors=errors,
        attributions=attributions,
    )


def _draw_box(draw: ImageDraw.ImageDraw, pos: tuple[int, int], color: tuple[int, int, int], width: int = 2) -> None:
    col, row = pos
    left = col * TILE_SIZE * 2
    top = row * TILE_SIZE * 2
    right = (col + 1) * TILE_SIZE * 2 - 1
    bottom = (row + 1) * TILE_SIZE * 2 - 1
    draw.rectangle((left, top, right, bottom), outline=color, width=width)


def _visual_frame(
    obs: np.ndarray,
    symbolic: SymbolicFrame,
    metrics: FrameMetrics,
    *,
    task_id: str,
    action: int,
    total_reward: float,
    recent_events: tuple[str, ...],
) -> Image.Image:
    map_frame = np.asarray(obs)[: MAP_HEIGHT * TILE_SIZE, : MAP_WIDTH * TILE_SIZE, :3]
    truth_image = Image.fromarray(map_frame.astype(np.uint8), mode="RGB").resize(
        (MAP_WIDTH * TILE_SIZE * 2, MAP_HEIGHT * TILE_SIZE * 2),
        Image.Resampling.NEAREST,
    )
    truth_draw = ImageDraw.Draw(truth_image)
    _draw_box(truth_draw, metrics.player_truth, (40, 255, 80), width=3)
    for monster in metrics.monster_truth:
        _draw_box(truth_draw, monster, (255, 150, 30), width=3)
    for error in metrics.static_errors:
        _draw_box(truth_draw, tuple(error["pos"]), (255, 40, 80), width=2)

    overlay_array = render_debug_overlay(obs, symbolic, scale=2)
    overlay_image = Image.fromarray(overlay_array.astype(np.uint8), mode="RGB")
    panel_height = 122
    canvas = Image.new(
        "RGB",
        (truth_image.width + overlay_image.width, max(truth_image.height, overlay_image.height) + panel_height),
        (20, 22, 30),
    )
    canvas.paste(truth_image, (0, 0))
    canvas.paste(overlay_image, (truth_image.width, 0))

    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default()
    draw.text((4, 4), "INPUT + GROUND TRUTH", fill=(255, 255, 255), font=font)
    draw.text((truth_image.width + 4, 4), "VISION PREDICTION", fill=(255, 255, 255), font=font)
    panel_y = max(truth_image.height, overlay_image.height) + 5
    precision_denominator = metrics.monster_tp + metrics.monster_fp
    recall_denominator = metrics.monster_tp + metrics.monster_fn
    monster_precision = metrics.monster_tp / precision_denominator if precision_denominator else 1.0
    monster_recall = metrics.monster_tp / recall_denominator if recall_denominator else 1.0
    errors = ", ".join(metrics.attributions[:4]) if metrics.attributions else "none"
    events = ", ".join(recent_events[-3:]) if recent_events else "-"
    lines = (
        f"{task_id}  variant={metrics.expected_mode}  inferred={metrics.inferred_mode}",
        f"step={metrics.step} action={action} reward={total_reward:.2f}",
        f"player={'OK' if metrics.player_correct else 'FAIL'} truth={metrics.player_truth} pred={metrics.player_prediction}",
        f"monster precision={monster_precision:.3f} recall={monster_recall:.3f}",
        f"static={metrics.static_correct}/{metrics.static_total} ({metrics.static_accuracy:.3f})",
        f"attribution={errors}",
        f"events={events}",
    )
    for index, line in enumerate(lines):
        draw.text((5, panel_y + index * 15), line, fill=(235, 239, 245), font=font)
    return canvas


def _write_gif(frames: list[Image.Image], path: Path, fps: int) -> None:
    if not frames:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    duration = max(1, round(1000 / fps))
    frames[0].save(
        path,
        save_all=True,
        append_images=frames[1:],
        duration=duration,
        loop=0,
        optimize=False,
    )


def _summarize_frames(frames: list[FrameMetrics]) -> tuple[float, float, float, float, float, dict[str, int]]:
    count = max(1, len(frames))
    mode_accuracy = sum(frame.mode_correct for frame in frames) / count
    player_accuracy = sum(frame.player_correct for frame in frames) / count
    monster_tp = sum(frame.monster_tp for frame in frames)
    monster_fp = sum(frame.monster_fp for frame in frames)
    monster_fn = sum(frame.monster_fn for frame in frames)
    monster_precision = monster_tp / (monster_tp + monster_fp) if monster_tp + monster_fp else 1.0
    monster_recall = monster_tp / (monster_tp + monster_fn) if monster_tp + monster_fn else 1.0
    static_correct = sum(frame.static_correct for frame in frames)
    static_total = sum(frame.static_total for frame in frames)
    static_accuracy = static_correct / static_total if static_total else 1.0
    attribution_counts = Counter(item for frame in frames for item in frame.attributions)
    return (
        mode_accuracy,
        player_accuracy,
        monster_precision,
        monster_recall,
        static_accuracy,
        dict(sorted(attribution_counts.items())),
    )


def run_episode(
    *,
    policy: Any,
    task_id: str,
    variant: str,
    seed: int,
    max_steps: int | None,
    stride: int,
    fps: int,
    output_dir: Path,
) -> EpisodeSummary:
    kwargs: dict[str, Any] = {"observation_mode": "pixels"}
    if max_steps is not None:
        kwargs["max_steps"] = max_steps
    env = make_env(task_id=task_id, **kwargs)
    reset_policy(policy)
    raw_obs, raw_info = env.reset(seed=seed)
    obs = apply_obs_variant(raw_obs, variant, info=raw_info, env=env)
    policy_info = build_policy_info(
        info_mode="safe", raw_info=raw_info, last_reward=0.0, task_id=None
    )
    frame_metrics: list[FrameMetrics] = []
    gif_frames: list[Image.Image] = []
    events: Counter[str] = Counter()
    recent_events: deque[str] = deque(maxlen=5)
    total_reward = 0.0
    step = 0
    terminated = False
    truncated = False

    try:
        while not (terminated or truncated):
            action = call_policy(policy, obs, policy_info)
            symbolic = get_last_symbolic_frame()
            if symbolic is None:
                raise RuntimeError(
                    "the selected policy did not use rule_based_submission.vision; "
                    "no symbolic frame is available"
                )
            metrics = _measure(step, variant, symbolic, env.engine.runtime)
            frame_metrics.append(metrics)
            if step % stride == 0:
                gif_frames.append(
                    _visual_frame(
                        obs,
                        symbolic,
                        metrics,
                        task_id=task_id,
                        action=action,
                        total_reward=total_reward,
                        recent_events=tuple(recent_events),
                    )
                )

            raw_obs, reward, terminated, truncated, raw_info = env.step(action)
            step += 1
            total_reward += float(reward)
            names = event_names(raw_info)
            events.update(names)
            recent_events.extend(names)
            obs = apply_obs_variant(raw_obs, variant, info=raw_info, env=env)
            policy_info = build_policy_info(
                info_mode="safe",
                raw_info=raw_info,
                last_reward=float(reward),
                task_id=None,
            )
    finally:
        env.close()

    task_name = task_id.replace("/", "_")
    episode_dir = output_dir / task_name
    stem = f"{variant}__seed_{seed}"
    gif_path = episode_dir / f"{stem}.gif"
    frames_path = episode_dir / f"{stem}.vision.json"
    _write_gif(gif_frames, gif_path, fps)
    frames_path.parent.mkdir(parents=True, exist_ok=True)
    frames_path.write_text(
        json.dumps([asdict(frame) for frame in frame_metrics], indent=2, ensure_ascii=False),
        encoding="utf-8",
    )

    mode_acc, player_acc, monster_precision, monster_recall, static_acc, attribution_counts = _summarize_frames(frame_metrics)
    return EpisodeSummary(
        task_id=task_id,
        variant=variant,
        seed=seed,
        steps=step,
        success=is_success(raw_info, terminated),
        terminal_reason=raw_info.get("terminal_reason"),
        mode_accuracy=mode_acc,
        player_accuracy=player_acc,
        monster_precision=monster_precision,
        monster_recall=monster_recall,
        static_accuracy=static_acc,
        attribution_counts=attribution_counts,
        event_counts=dict(sorted(events.items())),
        gif_path=str(gif_path),
        frames_path=str(frames_path),
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--policy",
        default="rule_based_submission.agent:Policy",
        help="Policy specification accepted by utils/evaluate_policy.py",
    )
    parser.add_argument(
        "--tasks",
        nargs="+",
        default=["mathematical_logic/task_2"],
        help="Tasks to visualize",
    )
    parser.add_argument("--variants", nargs="+", choices=COLOR_VARIANTS, default=list(COLOR_VARIANTS))
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--max-steps", type=int, default=None)
    parser.add_argument("--stride", type=int, default=4, help="Capture one GIF frame every N steps")
    parser.add_argument("--fps", type=int, default=12)
    parser.add_argument("--output-dir", type=Path, default=Path("runs/color_vision_check"))
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.stride < 1 or args.fps < 1:
        raise ValueError("--stride and --fps must be >= 1")
    bindings = resolve_policies(
        default_policy_spec=args.policy,
        task_policy_specs=[],
        task_ids=args.tasks,
        debug=False,
    )
    summaries: list[EpisodeSummary] = []
    for task_id in args.tasks:
        policy = bindings[task_id].policy
        for variant in args.variants:
            summary = run_episode(
                policy=policy,
                task_id=task_id,
                variant=variant,
                seed=args.seed,
                max_steps=args.max_steps,
                stride=args.stride,
                fps=args.fps,
                output_dir=args.output_dir,
            )
            summaries.append(summary)
            print(
                f"{task_id} variant={variant} success={summary.success} steps={summary.steps} "
                f"mode={summary.mode_accuracy:.3f} player={summary.player_accuracy:.3f} "
                f"monster_p={summary.monster_precision:.3f} monster_r={summary.monster_recall:.3f} "
                f"static={summary.static_accuracy:.3f}"
            )
            if summary.attribution_counts:
                print(f"  attribution: {summary.attribution_counts}")
            print(f"  gif: {summary.gif_path}")
            print(f"  frames: {summary.frames_path}")

    summary_path = args.output_dir / "summary.json"
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.write_text(
        json.dumps([asdict(summary) for summary in summaries], indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    print(f"summary: {summary_path}")


if __name__ == "__main__":
    main()
