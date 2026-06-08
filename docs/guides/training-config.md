# Training Configuration Guide

This guide describes the practical knobs to set when training RL agents on
NesyLink.

## Environment Selection

Use Gymnasium IDs for stable built-in tasks:

```python
import gymnasium as gym
import nesylink

env = gym.make("NesyLink-MathematicalLogic-Task1-v0")
```

Use `make_env(...)` for experiments:

```python
from nesylink.env import make_env

env = make_env(
    map_id="dungeon",
    reward_id="exploration",
    reward_kwargs={"step": -0.01, "room_changed": 1.0},
    max_steps=500,
    action_repeat=1,
)
```

## Core Training Knobs

- `task_id`: selects a Python `TaskSpec` with map, reward, and defaults.
- `map_id` / `map_path`: selects the world layout.
- `reward_id` / `reward_module`: selects the reward function.
- `reward_kwargs`: overrides reward weights.
- `max_steps`: truncates episodes after a fixed horizon.
- `action_repeat`: repeats each chosen action for multiple engine ticks.
- `render_mode="rgb_array"`: enables image observations through `env.render()`.

Explicit `make_env(...)` arguments override task defaults.

## Random Rollout Smoke Test

Run this before training a real agent:

```python
from nesylink.env import make_env

env = make_env(task_id="mathematical_logic/task_1")
obs, info = env.reset(seed=0)
total_reward = 0.0

for _ in range(100):
    action = env.action_space.sample()
    obs, reward, terminated, truncated, info = env.step(action)
    total_reward += reward
    if terminated or truncated:
        break

print(total_reward, info["terminal_reason"])
env.close()
```

## PPO-style Configuration

For a standard on-policy algorithm, start with:

```python
env = make_env(
    task_id="mathematical_logic/task_1",
    max_steps=500,
    reward_kwargs={
        "step": -0.01,
        "keys_delta": 5.0,
        "door_opened": 3.0,
        "exit_reached": 20.0,
        "death": -10.0,
    },
)
```

Recommended first pass:

- use structured observations before image-only learning
- keep `action_repeat=1`
- keep `max_steps` between 300 and 800 for small maps
- log `info["events"]["counts"]` and `info["reward"]["reward_signals"]`
- evaluate on fixed seeds after every training checkpoint

## Image-based Training

Use `render_mode="rgb_array"` and call `env.render()` when your training stack
expects pixels:

```python
env = make_env(task_id="mathematical_logic/task_5", render_mode="rgb_array")
obs, info = env.reset(seed=0)
image = env.render()
```

The render frame includes the dungeon area plus HUD. The structured observation
does not include the HUD as walkable map space.

## Dreamer-style Usage

The Dreamer-facing adapter lives in `nesylink.wrappers.dreamer_env`. It flattens
structured observation fields into a vector and can include resized rendered
images.

Use it when the training stack expects an `embodied.Env`-style interface. Keep
Gymnasium as the default interface for new experiments unless the world-model
training code specifically requires the Dreamer adapter.

## Debugging Reward Learning

When learning stalls, inspect:

- `info["events"]["counts"]`
- `info["reward"]["reward_signals"]`
- `info["reward"]["reward_weights"]`
- `info["terminal_reason"]`
- `info["episode"]["step_count"]`

If an event appears but reward remains zero, check the reward weight. If the
reward signal never appears, check the map object, exit condition, or action
sequence that should generate the event.
