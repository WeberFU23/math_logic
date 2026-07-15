from __future__ import annotations

import argparse
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from sb3_contrib import MaskablePPO
from stable_baselines3.common.callbacks import CheckpointCallback
from stable_baselines3.common.monitor import Monitor
from stable_baselines3.common.vec_env import DummyVecEnv, SubprocVecEnv

from RL_based_submission.high_level_env import HighLevelOptionEnv


DEFAULT_MODEL_DIR = PROJECT_ROOT / "RL_based_submission" / "high_level_models"
DEFAULT_LOG_DIR = PROJECT_ROOT / "runs" / "high_level_training"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train maskable PPO high-level goal selectors.")
    parser.add_argument(
        "--tasks",
        nargs="+",
        default=["mathematical_logic/task_1"],
        help="Train one independent high-level policy per task.",
    )
    parser.add_argument("--timesteps", type=int, default=100_000, help="PPO timesteps per task.")
    parser.add_argument("--seed", type=int, default=0, help="Base random seed.")
    parser.add_argument("--num-envs", type=int, default=4, help="Number of rollout environments.")
    parser.add_argument(
        "--n-steps",
        type=int,
        default=512,
        help="Rollout steps per environment before each PPO update.",
    )
    parser.add_argument(
        "--vec-env",
        choices=("auto", "dummy", "subproc"),
        default="auto",
        help="Vectorization backend; auto uses subprocesses when num-envs > 1.",
    )
    parser.add_argument("--device", default="cpu", help="PyTorch device: cpu, cuda, or auto.")
    parser.add_argument(
        "--checkpoint-freq",
        type=int,
        default=10_000,
        help="Save a recovery checkpoint every N aggregate timesteps; 0 disables it.",
    )
    parser.add_argument("--model-dir", type=Path, default=DEFAULT_MODEL_DIR)
    parser.add_argument("--log-dir", type=Path, default=DEFAULT_LOG_DIR)
    parser.add_argument("--resume", action="store_true")
    parser.add_argument(
        "--task5-drain-interval",
        type=int,
        default=None,
        help="Training-only Task-5 curriculum interval; evaluation remains 200.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.timesteps < 1:
        raise ValueError("--timesteps must be positive")
    if args.num_envs < 1:
        raise ValueError("--num-envs must be positive")
    if args.n_steps < 1:
        raise ValueError("--n-steps must be positive")
    args.model_dir.mkdir(parents=True, exist_ok=True)
    args.log_dir.mkdir(parents=True, exist_ok=True)

    for task_index, task_id in enumerate(args.tasks):
        train_task(
            task_id=task_id,
            timesteps=args.timesteps,
            seed=args.seed + 1000 * task_index,
            num_envs=args.num_envs,
            n_steps=args.n_steps,
            vec_env=args.vec_env,
            device=args.device,
            checkpoint_freq=args.checkpoint_freq,
            model_dir=args.model_dir,
            log_dir=args.log_dir,
            resume=args.resume,
            task5_drain_interval=args.task5_drain_interval,
        )


def train_task(
    *,
    task_id: str,
    timesteps: int,
    seed: int,
    num_envs: int,
    n_steps: int,
    vec_env: str,
    device: str,
    checkpoint_freq: int,
    model_dir: Path,
    log_dir: Path,
    resume: bool,
    task5_drain_interval: int | None,
) -> None:
    slug = task_id.replace("/", "_")
    model_path = model_dir / f"{slug}.zip"

    factories = []
    for env_index in range(num_envs):
        env_seed = seed + env_index

        def make_one(task=task_id, one_seed=env_seed):
            return Monitor(HighLevelOptionEnv(
                task,
                seed=one_seed,
                training_drain_interval=task5_drain_interval,
            ))

        factories.append(make_one)

    use_subprocesses = vec_env == "subproc" or (vec_env == "auto" and num_envs > 1)
    env = (
        SubprocVecEnv(factories, start_method="fork")
        if use_subprocesses
        else DummyVecEnv(factories)
    )
    try:
        if resume and model_path.exists():
            model = MaskablePPO.load(model_path, env=env, device=device)
            reset_num_timesteps = False
        else:
            model = MaskablePPO(
                "MlpPolicy",
                env,
                seed=seed,
                verbose=1,
                device=device,
                tensorboard_log=str(log_dir),
                n_steps=n_steps,
                batch_size=256,
                n_epochs=10,
                gamma=0.995,
                gae_lambda=0.95,
                learning_rate=3e-4,
                ent_coef=0.02,
                clip_range=0.2,
                policy_kwargs={"net_arch": [256, 256]},
            )
            reset_num_timesteps = True

        callback = None
        if checkpoint_freq > 0:
            checkpoint_dir = model_dir / "checkpoints" / slug
            checkpoint_dir.mkdir(parents=True, exist_ok=True)
            callback = CheckpointCallback(
                save_freq=max(checkpoint_freq // num_envs, 1),
                save_path=str(checkpoint_dir),
                name_prefix="high_level",
            )

        model.learn(
            total_timesteps=timesteps,
            tb_log_name=f"high_level_{slug}",
            reset_num_timesteps=reset_num_timesteps,
            progress_bar=False,
            callback=callback,
        )
        model.save(model_path)
        print(f"saved {task_id} high-level model to {model_path}")
    finally:
        env.close()


if __name__ == "__main__":
    main()
