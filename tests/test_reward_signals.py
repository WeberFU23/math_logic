import unittest


class RewardSignalTests(unittest.TestCase):
    def test_base_signals_include_events_completion_and_obs_values(self):
        from nesylink.rewards.base import build_reward_context, extract_reward_signals

        previous_obs = {
            "health": [5],
            "gold": [1],
            "keys": [0],
            "player_tile": [1, 1],
            "monsters_hp": [2, 0],
            "monsters_active_mask": [1, 0],
        }
        obs = {
            "health": [3],
            "gold": [6],
            "keys": [1],
            "player_tile": [2, 1],
            "monsters_hp": [0, 0],
            "monsters_active_mask": [0, 0],
        }
        info = {
            "agent": {"hp": 3, "tile": [2, 1]},
            "inventory": {"gold": 6, "keys": 1},
            "entities": {"monsters_remaining": 0},
            "events": {
                "counts": {
                    "key_collected": 1,
                    "gold_collected": 1,
                    "item_collected": 1,
                    "agent_healed": 1,
                    "agent_damaged": 1,
                    "trap_triggered": 1,
                    "abyss_fall": 1,
                    "monster_damaged": 1,
                    "monster_killed": 1,
                    "shield_block": 1,
                    "door_opened": 1,
                    "chest_opened": 1,
                    "chest_revealed": 1,
                    "button_pressed": 1,
                    "switch_activated": 1,
                    "bridge_rotated": 1,
                    "dynamic_object_state_changed": 1,
                    "talked_npc": 1,
                    "exit_reached": 1,
                    "environment_completed": 1,
                    "action_blocked": 1,
                },
                "flags": {"environment_completed": True},
                "records": [{"name": "key_collected"}],
            },
            "game": {"world_completed": True, "dead": False},
            "debug": {"engine_done": True},
            "terminal_reason": "world_completed",
        }
        context = build_reward_context(
            prev_obs=previous_obs,
            obs=obs,
            prev_info=None,
            info=info,
            action=5,
        )

        signals = extract_reward_signals(context)

        self.assertEqual(signals["hp_loss"], 2)
        self.assertEqual(signals["gold_delta"], 5)
        self.assertEqual(signals["keys_delta"], 1)
        self.assertEqual(signals["player_tile_changed"], 1)
        self.assertEqual(signals["monster_hp_total"], 0)
        self.assertEqual(signals["prev_monster_hp_total"], 2)
        self.assertEqual(signals["active_monsters"], 0)
        self.assertEqual(signals["key_collected"], 1)
        self.assertEqual(signals["gold_collected"], 1)
        self.assertEqual(signals["monster_hit"], 1)
        self.assertEqual(signals["monster_kill"], 1)
        self.assertEqual(signals["trap_triggered"], 1)
        self.assertEqual(signals["switch_activated"], 1)
        self.assertEqual(signals["bridge_rotated"], 1)
        self.assertEqual(signals["world_completed"], 1)
        self.assertEqual(signals["environment_completed"], 1)
        self.assertEqual(signals["engine_terminated"], 1)
        self.assertEqual(signals["terminal_reason"], "world_completed")

    def test_loads_mathematical_logic_reward_and_task2_waits_for_completion(self):
        from nesylink.rewards.loader import load_reward

        reward = load_reward(reward_id="mathematical_logic/task_2")
        reward.reset({}, {})
        _, reward_info = reward(
            {},
            {
                "entities": {"monsters_remaining": 0},
                "events": {
                    "counts": {"monster_killed": 1},
                    "flags": {"monster_killed": True},
                },
                "game": {"world_completed": False, "dead": False},
                "debug": {"engine_done": False},
            },
        )
        self.assertFalse(reward_info["terminated"])

        _, reward_info = reward(
            {},
            {
                "entities": {"monsters_remaining": 0},
                "events": {
                    "counts": {"environment_completed": 1},
                    "flags": {"environment_completed": True},
                },
                "game": {"world_completed": True, "dead": False},
                "debug": {"engine_done": True},
                "terminal_reason": "world_completed",
            },
        )
        self.assertTrue(reward_info["terminated"])
        self.assertEqual(reward_info["terminated_reason"], "world_completed")


if __name__ == "__main__":
    unittest.main()
