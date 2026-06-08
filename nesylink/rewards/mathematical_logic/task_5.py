from __future__ import annotations

from .common import MathematicalLogicReward


class MathematicalLogicTask5Reward(MathematicalLogicReward):
    reward_name = "mathematical_logic/task_5"
    reward_weights = {
        **MathematicalLogicReward.reward_weights,
        "room_changed": 2.0,
        "button_pressed": 1.0,
        "talked_npc": 0.5,
        "chest_opened": 2.0,
        "gold_delta": 1.0,
        "key_collected": 5.0,
        "keys_delta": 5.0,
        "agent_healed": 2.0,
        "monster_hit": 1.0,
        "monster_kill": 5.0,
        "trap_triggered": -2.0,
        "hp_loss": -2.0,
        "door_opened": 5.0,
        "exit_reached": 5.0,
    }


def make_reward(**kwargs):
    return MathematicalLogicTask5Reward(**kwargs)
