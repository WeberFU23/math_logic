import unittest


class TaskRegistryTests(unittest.TestCase):
    def test_builtin_tasks_are_registered(self):
        from nesylink.tasks import get_task, list_tasks

        task_ids = [task.task_id for task in list_tasks()]
        self.assertIn("mathematical_logic/task_1", task_ids)
        self.assertIn("mathematical_logic/task_2", task_ids)
        self.assertIn("mathematical_logic/task_3", task_ids)
        self.assertIn("mathematical_logic/task_4", task_ids)
        self.assertIn("mathematical_logic/task_5", task_ids)
        self.assertNotIn("task_1", task_ids)

        task = get_task("mathematical_logic/task_1")
        self.assertEqual(task.map_id, "mathematical_logic/task_1")
        self.assertEqual(task.reward_id, "mathematical_logic/task_1")
        self.assertEqual(task.gym_id, "NesyLink-MathematicalLogic-Task1-v0")

    def test_unknown_task_id_has_clear_error(self):
        from nesylink.tasks import get_task

        with self.assertRaisesRegex(ValueError, "unknown task_id 'missing'"):
            get_task("missing")


if __name__ == "__main__":
    unittest.main()
