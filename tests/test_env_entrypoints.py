import unittest


class EnvEntrypointTests(unittest.TestCase):
    def test_make_env_accepts_task_id(self):
        from nesylink.env import make_env

        env = make_env(task_id="mathematical_logic/task_1")
        try:
            obs, info = env.reset(seed=0)
            self.assertIn("grid", obs)
            self.assertEqual(info["env"]["map_id"], "mathematical_logic/task_1")
            self.assertEqual(env.spec.id, "NesyLink-MathematicalLogic-Task1-v0")
            self.assertEqual(env.unwrapped.mission, "Collect the key and reach the exit.")
        finally:
            env.close()

    def test_all_mathematical_logic_tasks_reset(self):
        from nesylink.env import make_env

        for index in range(1, 6):
            task_id = f"mathematical_logic/task_{index}"
            with self.subTest(task_id=task_id):
                env = make_env(task_id=task_id)
                try:
                    obs, info = env.reset(seed=0)
                    self.assertIn("grid", obs)
                    self.assertEqual(info["env"]["map_id"], task_id)
                    self.assertEqual(info["reward"]["reward_name"], task_id)
                finally:
                    env.close()

    def test_explicit_arguments_override_task_defaults(self):
        from nesylink.env import make_env

        env = make_env(task_id="mathematical_logic/task_1", max_steps=1)
        try:
            env.reset(seed=0)
            _, _, terminated, truncated, _ = env.step(0)
            self.assertFalse(terminated)
            self.assertTrue(truncated)
        finally:
            env.close()

    def test_gymnasium_make_can_create_registered_task(self):
        import gymnasium as gym
        import nesylink

        nesylink.register_gym_envs()
        env = gym.make("NesyLink-MathematicalLogic-Task1-v0")
        try:
            obs, info = env.reset(seed=0)
            self.assertIn("grid", obs)
            self.assertEqual(info["env"]["map_id"], "mathematical_logic/task_1")
        finally:
            env.close()


if __name__ == "__main__":
    unittest.main()
