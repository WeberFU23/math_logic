from nesylink.env import make_env

ACTION = {
    "WAIT": 0,
    "UP": 1,
    "DOWN": 2,
    "LEFT": 3,
    "RIGHT": 4,
    "BUTTON_A": 5,
    "BUTTON_B": 6,
}


def repeat(name: str, n: int) -> list[int]:
    return [ACTION[name]] * n


def task_1_reference_plan() -> list[int]:
    plan: list[int] = []

    # Start: tile (4, 6).
    # Move around the wall barrier to stand next to the chest at (0, 3).
    plan += repeat("RIGHT", 48)  # tile (7, 6)
    plan += repeat("UP", 48)     # tile (7, 3)
    plan += repeat("LEFT", 96)   # tile (1, 3), adjacent to chest

    # Open chest and collect key.
    plan.append(ACTION["BUTTON_A"])

    # Move to the north exit tile through the open corridor.
    plan += repeat("RIGHT", 32)  # tile (3, 3)
    plan += repeat("UP", 48)     # tile (3, 0)
    plan += repeat("RIGHT", 16)  # tile (4, 0), north exit
    plan += repeat("UP", 20)     # use north exit; extra steps handle edge flush

    return plan


def run_task_1() -> None:
    env = make_env(task_id="mathematical_logic/task_1")
    obs, info = env.reset(seed=0)

    for step_index, action in enumerate(task_1_reference_plan(), start=1):
        obs, reward, terminated, truncated, info = env.step(action)

        if terminated or truncated:
            print("finished at step:", step_index)
            print("terminal_reason:", info["terminal_reason"])
            print("world_completed:", info["game"]["world_completed"])
            print("events:", info["events"]["records"])
            break

    env.close()


if __name__ == "__main__":
    run_task_1()
