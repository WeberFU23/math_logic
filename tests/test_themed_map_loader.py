import unittest
from pathlib import Path


class ThemedMapLoaderTests(unittest.TestCase):
    def test_loads_themed_standalone_room_map(self):
        from nesylink.core.world.loader import load_map

        path = load_map(map_id="mathematical_logic/task_1")
        self.assertEqual(path.name, "room_001.json")
        self.assertEqual(path.parent.name, "task_1")
        self.assertEqual(path.parent.parent.name, "mathematical_logic")

    def test_loads_themed_dungeon_map(self):
        from nesylink.core.world.loader import load_map

        path = load_map(map_id="mathematical_logic/task_5")
        self.assertEqual(path.name, "dungeon.json")
        self.assertEqual(path.parent.name, "task_5")
        self.assertEqual(path.parent.parent.name, "mathematical_logic")


if __name__ == "__main__":
    unittest.main()
