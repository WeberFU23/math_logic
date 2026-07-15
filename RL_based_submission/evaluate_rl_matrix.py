"""Run an exact original/spatial/color matrix with the pure RL policy."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from utils.evaluate_policy import (
    DEFAULT_TASKS,
    SPATIAL_MAP_VARIANTS,
    load_policy,
    print_summary,
    run_episode,
    summarize,
)


COLOR_VARIANTS = (
    "grayscale",
    "dark",
    "bright",
    "high_contrast",
    "inverted",
)
POLICY_SPEC = "RL_based_submission/high_level_agent.py"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Evaluate the pure RL policy with exact stage counts.")
    parser.add_argument("--original", type=int, default=3)
    parser.add_argument("--spatial", type=int, default=2)
    parser.add_argument("--color", type=int, default=1)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--spatial-offset", type=int, default=0)
    parser.add_argument("--color-offset", type=int, default=0)
    parser.add_argument(
        "--json-out",
        type=Path,
        default=Path("results/rl_only_3_original_2_spatial_1_color.json"),
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    counts = (args.original, args.spatial, args.color)
    if any(count < 0 for count in counts) or sum(counts) < 1:
        raise ValueError("stage counts must be non-negative and total at least one episode")

    policy = load_policy(POLICY_SPEC)
    results = []
    selected_spatial_variants = [
        SPATIAL_MAP_VARIANTS[(args.spatial_offset + index) % len(SPATIAL_MAP_VARIANTS)]
        for index in range(args.spatial)
    ]
    selected_color_variants = [
        COLOR_VARIANTS[(args.color_offset + index) % len(COLOR_VARIANTS)]
        for index in range(args.color)
    ]
    for task_id in DEFAULT_TASKS:
        stage_entries = [
            ("original", "default", "default", args.seed + index)
            for index in range(args.original)
        ]
        stage_entries.extend(
            (
                "spatial",
                "default",
                selected_spatial_variants[index],
                args.seed + index,
            )
            for index in range(args.spatial)
        )
        stage_entries.extend(
            (
                "color",
                selected_color_variants[index],
                "default",
                args.seed + index,
            )
            for index in range(args.color)
        )

        for eval_stage, obs_variant, map_variant, seed in stage_entries:
            result = run_episode(
                policy=policy,
                task_id=task_id,
                eval_stage=eval_stage,
                seed=seed,
                max_steps=None,
                render_mode=None,
                obs_variant=obs_variant,
                action_repeat=None,
                map_variant=map_variant,
                info_mode="safe",
                policy_task_id=task_id,
            )
            results.append(result)
            print(
                f"{task_id} stage={eval_stage} obs_variant={obs_variant} "
                f"map_variant={map_variant} seed={seed} success={result.success} "
                f"steps={result.steps} reward={result.total_reward:.3f}",
                flush=True,
            )

    summary = summarize(results)
    print_summary(summary)
    payload = {
        "configuration": {
            "policy": POLICY_SPEC,
            "info_mode": "safe",
            "tasks": list(DEFAULT_TASKS),
            "original_per_task": args.original,
            "spatial_per_task": args.spatial,
            "color_per_task": args.color,
            "spatial_variants": selected_spatial_variants,
            "color_variants": selected_color_variants,
            "base_seed": args.seed,
        },
        "summary": summary,
        "episodes": [asdict(result) for result in results],
    }
    args.json_out.parent.mkdir(parents=True, exist_ok=True)
    args.json_out.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False, sort_keys=True),
        encoding="utf-8",
    )
    print(f"\nWrote JSON results to {args.json_out}", flush=True)


if __name__ == "__main__":
    main()
