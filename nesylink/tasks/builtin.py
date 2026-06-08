from __future__ import annotations

from .registry import register_task
from .specs import TaskSpec


EASY_GRID_MONSTER_PERIODS = {"chaser": 1, "ambusher": 1, "patroller": 2}


BUILTIN_TASKS = (
    TaskSpec(
        task_id="mathematical_logic/task_1",
        gym_id="NesyLink-MathematicalLogic-Task1-v0",
        map_id="mathematical_logic/task_1",
        reward_id="mathematical_logic/task_1",
        max_steps=500,
        mission="Collect the key and reach the exit.",
    ),
    TaskSpec(
        task_id="mathematical_logic/task_2",
        gym_id="NesyLink-MathematicalLogic-Task2-v0",
        map_id="mathematical_logic/task_2",
        reward_id="mathematical_logic/task_2",
        max_steps=500,
        mission="Defeat the monster, collect the key, and reach the exit.",
    ),
    TaskSpec(
        task_id="mathematical_logic/task_3",
        gym_id="NesyLink-MathematicalLogic-Task3-v0",
        map_id="mathematical_logic/task_3",
        reward_id="mathematical_logic/task_3",
        max_steps=1000,
        mission="Travel west through the chaser room, collect the key, return, and unlock the right door.",
    ),
    TaskSpec(
        task_id="mathematical_logic/task_4",
        gym_id="NesyLink-MathematicalLogic-Task4-v0",
        map_id="mathematical_logic/task_4",
        reward_id="mathematical_logic/task_4",
        max_steps=1000,
        control_mode="grid",
        observation_mode="grid",
        monster_move_periods=EASY_GRID_MONSTER_PERIODS,
        max_monsters=1,
        mission=(
            "Rotate the bridge to collect the key, unlock the sword room, "
            "defeat the monster, and open the revealed center chest."
        ),
    ),
    TaskSpec(
        task_id="mathematical_logic/task_5",
        gym_id="NesyLink-MathematicalLogic-Task5-v0",
        map_id="mathematical_logic/task_5",
        reward_id="mathematical_logic/task_5",
        max_steps=1000,
        mission="Explore the multi-room dungeon, collect resources, and complete all chest objectives.",
    ),
)


def register_builtin_tasks() -> None:
    for task in BUILTIN_TASKS:
        try:
            register_task(task)
        except ValueError as exc:
            if "duplicate" not in str(exc):
                raise
