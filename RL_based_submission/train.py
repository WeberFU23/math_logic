from __future__ import annotations

import argparse
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from stable_baselines3 import PPO
from stable_baselines3.common.monitor import Monitor
from stable_baselines3.common.vec_env import DummyVecEnv

from RL_based_submission.sb3_env import SymbolicFeatureEnv

DEFAULT_MODEL_DIR = PROJECT_ROOT / "RL_based_submission" / "models"
DEFAULT_LOG_DIR = PROJECT_ROOT / "runs" / "rl_training"
DEFAULT_TASKS = ("mathematical_logic/task_1", "mathematical_logic/task_2", "mathematical_logic/task_3")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train PPO agents on NesyLink mathematical-logic tasks.")
    parser.add_argument("--tasks", nargs="+", default=list(DEFAULT_TASKS), help="Task ids to train.")
    parser.add_argument("--timesteps", type=int, default=100_000, help="Timesteps per task.")
    parser.add_argument("--seed", type=int, default=0, help="Base random seed.")
    parser.add_argument("--model-dir", type=Path, default=DEFAULT_MODEL_DIR, help="Where to save .zip models.")
    parser.add_argument("--log-dir", type=Path, default=DEFAULT_LOG_DIR, help="TensorBoard/log directory.")
    parser.add_argument("--resume", action="store_true", help="Resume from an existing model if present.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    args.model_dir.mkdir(parents=True, exist_ok=True)
    args.log_dir.mkdir(parents=True, exist_ok=True)

    for index, task_id in enumerate(args.tasks):
        train_task(
            task_id=task_id,
            timesteps=args.timesteps,
            seed=args.seed + index,
            model_dir=args.model_dir,
            log_dir=args.log_dir,
            resume=args.resume,
        )


def train_task(*, task_id: str, timesteps: int, seed: int, model_dir: Path, log_dir: Path, resume: bool) -> None:
    slug = task_id.replace("/", "_")
    model_path = model_dir / f"{slug}.zip"

    def make_one():
        return Monitor(SymbolicFeatureEnv(task_id, seed=seed))

    env = DummyVecEnv([make_one])
    try:
        if resume and model_path.exists():
            model = PPO.load(model_path, env=env, seed=seed)
        else:
            model = PPO(
                "MlpPolicy",
                env,
                seed=seed,
                verbose=1,
                tensorboard_log=str(log_dir),
                n_steps=1024,
                batch_size=256,
                gamma=0.995,
                learning_rate=3e-4,
                ent_coef=0.02,
                clip_range=0.2,
                policy_kwargs={"net_arch": [256, 256]},
            )
        model.learn(total_timesteps=timesteps, tb_log_name=slug, reset_num_timesteps=not resume)
        model.save(model_path)
        print(f"saved {task_id} model to {model_path}")
    finally:
        env.close()


if __name__ == "__main__":
    main()
