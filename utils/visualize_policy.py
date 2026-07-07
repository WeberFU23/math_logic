from __future__ import annotations

import argparse
import sys
from collections import Counter, deque
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image, ImageDraw, ImageFont

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from nesylink.core.constants import ACTION_LABELS
from nesylink.env import make_env
from rule_based_submission.agent import make_policy


DEFAULT_TASK = "mathematical_logic/task_4"
DEFAULT_OUT = PROJECT_ROOT / "runs" / "policy_replay.gif"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Visualize the rule-based submission policy.")
    parser.add_argument("--task", default=DEFAULT_TASK, help="Task id to run.")
    parser.add_argument("--seed", type=int, default=0, help="Environment seed.")
    parser.add_argument("--max-steps", type=int, default=None, help="Optional episode step cap.")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="Output .gif, .mp4, or image directory.")
    parser.add_argument("--fps", type=int, default=12, help="Replay frame rate.")
    parser.add_argument("--stride", type=int, default=4, help="Keep one rendered frame every N env steps.")
    parser.add_argument("--scale", type=int, default=3, help="Integer image scale factor.")
    parser.add_argument("--no-overlay", action="store_true", help="Save raw game frames without text overlay.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.stride < 1:
        raise ValueError("--stride must be >= 1")
    if args.scale < 1:
        raise ValueError("--scale must be >= 1")

    frames, summary = run_episode(args)
    write_frames(frames, args.out, fps=args.fps)
    print(f"wrote {len(frames)} frames to {args.out}")
    print(
        f"task={summary['task']} seed={summary['seed']} "
        f"steps={summary['steps']} success={summary['success']} "
        f"reward={summary['reward']:.3f}"
    )
    if summary["events"]:
        print("events:", ", ".join(f"{name}={count}" for name, count in summary["events"].items()))


def run_episode(args: argparse.Namespace) -> tuple[list[Image.Image], dict[str, Any]]:
    policy = make_policy()
    policy.reset(seed=args.seed, task_id=args.task)
    env = make_env(
        task_id=args.task,
        observation_mode="pixels",
        render_mode="rgb_array",
        max_steps=args.max_steps,
    )

    obs, info = env.reset(seed=args.seed)
    frames: list[Image.Image] = []
    events: Counter[str] = Counter()
    recent_events: deque[str] = deque(maxlen=5)
    total_reward = 0.0
    terminated = False
    truncated = False
    step = 0

    try:
        while not (terminated or truncated):
            action = policy.act(obs, info)
            obs, reward, terminated, truncated, info = env.step(action)
            step += 1
            total_reward += float(reward)

            names = event_names(info)
            events.update(names)
            recent_events.extend(names)

            if step % args.stride == 0 or terminated or truncated:
                frame = frame_from_obs(obs)
                if not args.no_overlay:
                    frame = draw_overlay(
                        frame,
                        step=step,
                        action=action,
                        reward=total_reward,
                        memory=policy.memory,
                        recent_events=tuple(recent_events),
                        info=info,
                    )
                if args.scale != 1:
                    frame = frame.resize(
                        (frame.width * args.scale, frame.height * args.scale),
                        Image.Resampling.NEAREST,
                    )
                frames.append(frame)
    finally:
        env.close()

    summary = {
        "task": args.task,
        "seed": args.seed,
        "steps": step,
        "success": is_success(info, terminated),
        "reward": total_reward,
        "events": dict(sorted(events.items())),
    }
    return frames, summary


def frame_from_obs(obs: Any) -> Image.Image:
    array = np.asarray(obs)
    if array.ndim != 3 or array.shape[-1] != 3:
        raise ValueError(f"expected RGB pixel observation, got shape {array.shape}")
    return Image.fromarray(array.astype(np.uint8), mode="RGB")


def draw_overlay(
    frame: Image.Image,
    *,
    step: int,
    action: int,
    reward: float,
    memory: Any,
    recent_events: tuple[str, ...],
    info: dict[str, Any],
) -> Image.Image:
    canvas = Image.new("RGB", (frame.width, frame.height + 58), (20, 22, 30))
    canvas.paste(frame, (0, 0))
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default()

    goal = getattr(memory, "last_goal", None)
    goal_text = "None" if goal is None else f"{goal.kind.value}:{goal.target}"
    action_text = ACTION_LABELS.get(action, str(action))
    inventory = info.get("inventory", {}) if isinstance(info, dict) else {}
    hp = info.get("agent", {}).get("hp", "?") if isinstance(info, dict) else "?"
    event_text = ", ".join(recent_events[-3:]) if recent_events else "-"

    lines = (
        f"step {step}  action {action_text}  reward {reward:.1f}",
        f"room {memory.room}  goal {goal_text}",
        f"keys {inventory.get('keys', '?')}  sword {inventory.get('has_sword', '?')}  hp {hp}",
        f"events {event_text}",
    )
    y = frame.height + 4
    for line in lines:
        draw.text((4, y), line, fill=(235, 239, 245), font=font)
        y += 13
    return canvas


def write_frames(frames: list[Image.Image], out: Path, *, fps: int) -> None:
    if not frames:
        raise RuntimeError("no frames were captured")
    out = out if out.is_absolute() else PROJECT_ROOT / out
    out.parent.mkdir(parents=True, exist_ok=True)

    suffix = out.suffix.lower()
    if suffix == ".gif":
        duration_ms = max(1, round(1000 / fps))
        frames[0].save(
            out,
            save_all=True,
            append_images=frames[1:],
            duration=duration_ms,
            loop=0,
            optimize=False,
        )
        return

    if suffix == ".mp4":
        import imageio.v2 as imageio

        imageio.mimsave(out, [np.asarray(frame) for frame in frames], fps=fps)
        return

    out.mkdir(parents=True, exist_ok=True)
    digits = len(str(len(frames)))
    for index, frame in enumerate(frames):
        frame.save(out / f"frame_{index:0{digits}d}.png")


def event_names(info: dict[str, Any]) -> list[str]:
    records = info.get("events", {}).get("records", []) if isinstance(info, dict) else []
    return [
        str(record.get("name"))
        for record in records
        if isinstance(record, dict) and record.get("name") is not None
    ]


def is_success(info: dict[str, Any], terminated: bool) -> bool:
    if not isinstance(info, dict):
        return False
    return bool(
        info.get("game", {}).get("world_completed", False)
        or info.get("terminal_reason") == "world_completed"
        or (terminated and info.get("reward", {}).get("terminated_reason") == "world_completed")
    )


if __name__ == "__main__":
    main()
