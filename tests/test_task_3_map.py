import unittest


class Task3MapTests(unittest.TestCase):
    def test_task_3_is_three_room_key_return_task(self):
        from nesylink.env import make_env

        env = make_env(task_id="mathematical_logic/task_3")
        try:
            room_manager = env.unwrapped.engine.room_manager
            self.assertEqual(len(room_manager.room_templates), 3)

            start = room_manager.template_by_room_id("start_room")
            middle = room_manager.template_by_room_id("monster_hall")
            key_room = room_manager.template_by_room_id("key_room")

            locked_exit = next(exit_cfg for exit_cfg in start.exits if exit_cfg.exit_id == "locked_right_exit")
            self.assertEqual(locked_exit.direction, "east")
            self.assertEqual(locked_exit.exit_type, "locked_key")
            self.assertEqual(locked_exit.requires["key_count"], 1)
            self.assertTrue(locked_exit.requires["consume_key"])
            self.assertTrue(locked_exit.complete_task)

            self.assertTrue(
                any(
                    entry.kind == "monster"
                    and entry.payload.get("monster_type") == "chaser"
                    for entry in middle.objects
                )
            )
            self.assertTrue(
                any(
                    entry.kind == "chest"
                    and entry.payload.get("loot", {}).get("kind") == "key"
                    for entry in key_room.objects
                )
            )
        finally:
            env.close()


if __name__ == "__main__":
    unittest.main()
