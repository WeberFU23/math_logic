# 2026 春 数理逻辑大作业

本目录说明如何把 `nesylink` 中的五个内置任务作为数理逻辑课程大作业使用。作业目标不是训练强化学习模型，而是要求同学把游戏环境抽象成形式系统，给出可检查的状态、动作、转移关系和目标公式，并实现一个能够完成任务的求解器。

推荐技术路线：

1. 用 Python 读取 `nesylink` 的 `obs` 和 `info`，先完成可执行求解器。
2. 在 Lean4 中形式化描述任务的抽象模型，例如状态空间、动作语义、可达关系和目标性质。
3. 让搜索算法输出动作序列，并用真实 `nesylink` 环境 replay 验证。

## 环境准备

从项目根目录安装本仓库：

```bash
pip install -e .
```

Human player：

```shell
python -m nesylink.game --rooms nesylink/map_data/dungeons/task_1/room_001.json
python -m nesylink.game --rooms nesylink/map_data/dungeons/task_2/room_001.json
python -m nesylink.game --rooms nesylink/map_data/dungeons/task_3/dungeon.json
```

| task_id | 地图 | 奖励 | 最大步数 | 任务说明 |
|---|---|---|---:|---|
| `task_1` | `nesylink/map_data/dungeons/task_1/room_001.json` | `collect_key` | 500 | 收集钥匙并从北侧锁门离开 |
| `task_2` | `nesylink/map_data/dungeons/task_2/room_001.json` | `kill_monster` | 500 | 击败怪物、拿钥匙、从西侧条件门离开 |
| `task_3` | `nesylink/map_data/dungeons/task_3/dungeon.json` | `collect_key` | 500 | 穿过怪物房，去西侧房间拿钥匙，返回起点并打开东侧锁门 |

## Examples 参考实现

仓库的 `examples/` 目录给出了两个 Python 参考实现，用于演示如何通过当前 `nesylink` 框架接口运行内置任务：

| 文件 | 对应任务 | 说明 |
|---|---|---|
| `examples/task1_reference.py` | `task_1` | 使用固定像素级动作序列完成“拿钥匙并通过北侧锁门”的任务。 |
| `examples/task2_reference.py` | `task_2` | 使用从 `obs` 抽取的符号状态、邻接谓词和 BFS 子目标规划，完成当前 `task_2` 的怪物击败目标。 |

运行方式：

```bash
python docs/Mathematical-logic/examples/task1_reference.py
python docs/Mathematical-logic/examples/task2_reference.py
```

它们是本作业给出的参考实现，重点是展示：

1. 如何从真实环境 `obs` 中抽取离散符号状态。
2. 如何把 tile 级计划展开为像素级动作 replay。
3. 如何通过 `terminated/truncated`、`info["terminal_reason"]` 和 `info["game"]["world_completed"]` 检查真实环境执行结果。

> 注意：当前 `task_2` 在 `nesylink/tasks/builtin.py` 中使用 `kill_monster` 奖励；该奖励在所有怪物被击败时以 `terminal_reason == "all_monsters_defeated"` 终止。若报告中进一步讨论“拿钥匙并走到西侧条件门”的完整地图目标，应说明这是比当前 reward 终止条件更强的任务性质。

## 游戏接口

动作空间是离散动作，编号如下：

| 编号 | 名称 | 含义 |
|---:|---|---|
| 0 | `WAIT` | 等待 |
| 1 | `UP` | 向上移动 1 像素 |
| 2 | `DOWN` | 向下移动 1 像素 |
| 3 | `LEFT` | 向左移动 1 像素 |
| 4 | `RIGHT` | 向右移动 1 像素 |
| 5 | `BUTTON_A` | 交互；若没有可交互对象，则使用剑攻击 |
| 6 | `BUTTON_B` | 使用盾 |

地图大小为 `10 x 8` 个 tile，每个 tile 是 `16 x 16` 像素。因此从一个 tile 的左上角移动到相邻 tile 的左上角，通常需要连续执行 16 次同方向动作。

`obs` 中本作业最常用的字段：

| 字段 | 含义 |
|---|---|
| `obs["grid"]` | 当前房间的 8 x 10 离散网格 |
| `obs["player_tile"]` | 玩家当前 tile 坐标 `[x, y]` |
| `obs["player_position_px"]` | 玩家像素坐标 |
| `obs["health"]` | 当前生命值 |
| `obs["keys"]` | 当前钥匙数量 |
| `obs["monsters_tile"]` | 怪物 tile 坐标 |
| `obs["monsters_hp"]` | 怪物生命值 |
| `obs["monsters_active_mask"]` | 怪物槽位是否有效 |

`obs["grid"]` 的 tile 编码：

| 编码 | 含义 |
|---:|---|
| 0 | 空地 |
| 1 | 墙 |
| 2 | 玩家 |
| 3 | 怪物 |
| 4 | 宝箱 |
| 5 | 出口 |
| 6 | 陷阱 |
| 7 | 按钮 |
| 8 | NPC |

`info` 中本作业最常用的字段：

| 字段 | 含义 |
|---|---|
| `info["env"]["room_id"]` | 当前房间 id |
| `info["agent"]["tile"]` | 玩家当前 tile |
| `info["agent"]["facing"]` | 玩家朝向 |
| `info["inventory"]["keys"]` | 当前钥匙数量 |
| `info["entities"]["monsters_remaining"]` | 当前房间剩余怪物数量 |
| `info["entities"]["chests_remaining"]` | 当前房间未开启宝箱数量 |
| `info["events"]["records"]` | 当前 step 产生的事件 |
| `info["game"]["world_completed"]` | 是否完成整个任务 |
| `info["terminal_reason"]` | 终止原因，例如 `world_completed` 或 `agent_dead` |

## 交互规则
>（TODO 目前是 Codex 胡乱生成的版本）

作业中可以使用以下抽象规则：

1. 玩家状态至少包含当前位置、当前房间、钥匙数量、生命值、朝向。
2. 墙不可进入。
3. 宝箱在玩家与其相邻时可以通过 `BUTTON_A` 打开。
4. 钥匙宝箱打开后，钥匙数量增加。
5. 锁门需要满足钥匙数量要求；若配置了 `consume_key: true`，通过门时消耗钥匙。
6. 陷阱会造成伤害，并把玩家传送回指定出生点。
7. 怪物会追踪玩家；玩家可用剑攻击，怪物生命值降为 0 后消失。
8. 条件门可能要求所有怪物已被击败，或要求玩家持有钥匙。
9. `complete_task: true` 的出口被成功使用后，环境产生 `environment_completed` 事件并终止。

实际引擎是像素级移动；形式化建模时允许先做 tile 级抽象，但必须说明抽象和真实环境 replay 之间的对应关系。

## 三个任务

### Task 1：钥匙与锁门

地图文件：`nesylink/map_data/dungeons/task_1/room_001.json`

初始位置：

```text
room_001, tile (4, 6)
```

关键对象：

| 对象 | 位置 | 规则 |
|---|---|---|
| 宝箱 `chest_key` | `(0, 3)` | 相邻时按 `BUTTON_A`，获得 1 把钥匙 |
| 北侧锁门 `north_exit` | `(4,0)` 或 `(5,0)` | 需要 1 把钥匙，进入后完成任务 |

本任务适合用作参考任务。学生应能给出如下形式化目标：

```text
exists plan,
  run(init, plan) = some final
  and final.terminated = true
  and final.terminal_reason = world_completed
```

也可以用时序逻辑表达：

```text
F(key_collected) and F(door_opened) and F(environment_completed)
```

### Task 2：怪物、陷阱、钥匙与条件门

地图文件：`nesylink/map_data/dungeons/task_2/room_001.json`

初始位置：

```text
room_001, tile (7, 3)
```

关键对象：

| 对象 | 位置 | 规则 |
|---|---|---|
| 陷阱 | 顶部 `(1..8,0)` 与底部 `(1..8,7)` | 触发后掉血并回到出生点 |
| 宝箱 `chest_key` | `(1, 3)` | 相邻时按 `BUTTON_A`，获得钥匙 |
| 追踪怪物 `monster_chaser_left` | `(2, 2)` | 生命值 2，剑攻击两次可击败 |
| 西侧条件门 `west_exit` | `(0,3)` 或 `(0,4)` | 要求所有怪物被击败且钥匙数量至少为 1 |

本任务要求学生不仅描述钥匙和门，还要把“危险状态”或“怪物未击败”纳入形式化模型。可接受的目标包括：

```text
F(monster_killed) and F(key_collected) and F(environment_completed)
```

并附加安全条件：

```text
G(agent_hp > 0)
```

如果使用搜索算法，状态至少应包含：

```text
(room_id, player_tile, keys, hp, monster_hp_or_alive, chest_opened)
```

### Task 3：多房间往返任务

地图文件：`nesylink/map_data/dungeons/task_3/dungeon.json`

房间结构：

| 房间 | 坐标 | 作用 |
|---|---|---|
| `start_room` | `(0,0)` | 起点；东侧锁门是最终目标 |
| `monster_hall` | `(-1,0)` | 中间房间，包含追踪怪物 |
| `key_room` | `(-2,0)` | 西侧钥匙房，包含钥匙宝箱 |

初始位置：

```text
start_room, tile (4, 4)
```

关键对象：

| 对象 | 房间 | 位置 | 规则 |
|---|---|---|---|
| 西侧普通出口 | `start_room` | `(0,3)` 或 `(0,4)` | 通往 `monster_hall` |
| 追踪怪物 `hall_chaser` | `monster_hall` | `(5,3)` | 可绕过，也可击败 |
| 钥匙宝箱 `return_key_chest` | `key_room` | `(5,4)` | 相邻时按 `BUTTON_A` 获得钥匙 |
| 东侧锁门 `locked_right_exit` | `start_room` | `(9,3)` 或 `(9,4)` | 需要 1 把钥匙，通过后完成任务 |

本任务强调多房间状态和回溯。形式化状态中必须包含 `room_id`，否则无法区分不同房间中的相同 tile 坐标。

推荐目标公式：

```text
F(room_id = key_room and key_collected)
and F(room_id = start_room and door_opened)
and F(environment_completed)
```

可选安全条件：

```text
G(agent_hp > 0)
```

## 形式化建模要求

学生需要给出以下内容。

### 1. 状态空间

可以先用抽象状态：

```text
State :=
  room_id        : RoomId
  player_tile    : GridPos
  facing         : Direction
  keys           : Nat
  hp             : Nat
  opened_chests  : Set ChestId
  killed_monsters: Set MonsterId
  completed      : Bool
```

对于 task_1，状态可以简化为：

```text
State := (player_tile, keys, chest_opened, completed)
```

对于 task_2/task_3，必须加入怪物、房间和生命值。

### 2. 动作集合

```text
Action := WAIT | UP | DOWN | LEFT | RIGHT | BUTTON_A | BUTTON_B
```

若做 tile 级抽象，可把连续 16 次像素移动抽象成一次 tile 移动，但报告中必须写清楚：

```text
tileMove(dir) corresponds to 16 repeated pixel actions dir
```

### 3. 转移关系

应定义：

```text
step : State -> Action -> Option State
```

或关系式：

```text
Transition(s, a, s')
```

至少覆盖：

1. 移动到空地。
2. 撞墙或越界。
3. 与宝箱相邻时打开宝箱。
4. 获得钥匙。
5. 使用锁门或条件门。
6. 触发完成条件。
7. 怪物和陷阱对生命值的影响。

### 4. 目标性质

最基本的 goal predicate：

```text
Goal(s) := s.completed = true
```

更完整的性质：

```text
ValidPlan(plan) :=
  exists final,
    run(init, plan) = some final
    and Goal(final)
```

若使用 Lean4，可进一步证明 soundness：

```text
theorem solver_sound :
  solver problem = some plan ->
  exists final,
    run problem.init plan = some final /\ problem.isGoal final = true
```

### 5. 搜索算法

允许使用以下任一种：

1. BFS：适合 task_1 和 tile 级抽象。
2. DFS with visited：实现简单，但不保证最短。
3. A*：适合 task_2/task_3，可用曼哈顿距离作为启发函数。
4. 手写策略：只可作为 baseline，仍需解释为什么策略满足目标。

Lean4 中建议先写 `bfsFuel`，避免终止性证明成为主要困难：

```lean
def bfsFuel (fuel : Nat) (problem : SearchProblem) : Option (List Action) :=
  -- 每次递归消耗 fuel
```

## Python 参考：Task 1

下面代码只作为 task_1 的参考求解器。它直接使用 `obs` 和 `info`，并在真实环境中 replay 一个可行动作序列。

```python
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
    env = make_env(task_id="task_1")
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
```

期望输出中应包含：

```text
terminal_reason: world_completed
world_completed: True
```

这个参考实现的重点是说明：可以先用 Python 观察环境，并验证动作序列。正式作业中，学生应进一步把任务规则抽象出来，而不是只提交硬编码动作。

## Lean4 对接建议

建议把 Lean4 和 Python 环境通过 JSON 协议连接：

```text
Lean4 solver
  -> 输出动作序列 List Action
Python runner
  -> 在 nesylink 中 replay
  -> 返回 obs/info/terminal_reason
```

最小 JSON 状态可以设计为：

```json
{
  "room_id": "room_001",
  "player_tile": [4, 6],
  "facing": "down",
  "keys": 0,
  "hp": 5,
  "monsters_remaining": 0,
  "chests_remaining": 1,
  "world_completed": false
}
```

Lean4 中可先定义：

```lean
inductive Action where
  | wait
  | up
  | down
  | left
  | right
  | buttonA
  | buttonB
deriving Repr, DecidableEq

structure State where
  roomId : String
  x : Nat
  y : Nat
  keys : Nat
  hp : Nat
  completed : Bool
deriving Repr, DecidableEq
```

然后实现：

```lean
def step? : World -> State -> Action -> Option State
def runPlan : World -> State -> List Action -> Option State
def isGoal : State -> Bool := fun s => s.completed
```

如果暂时不做完整 Lean/Python 双向通信，也可以让 Lean 只输出 plan，再由 Python runner 验证：

```text
Lean 输出: [RIGHT, RIGHT, ..., BUTTON_A, ...]
Python 验证: replay 后 terminal_reason == "world_completed"
```

## 提交要求

每组提交内容建议包括：

1. 一份报告，说明状态、动作、转移关系、目标公式和搜索算法。
2. 至少一个任务的 Lean4 形式化模型。
3. 至少完成 task_1 的可执行求解器。
4. 对 task_2 或 task_3 的扩展说明或实现。
5. Python replay 结果，证明输出策略能在真实环境中完成任务。

评分重点：

| 项目 | 要求 |
|---|---|
| 形式化建模 | 状态、动作、转移、目标定义清晰 |
| 逻辑表达 | 能用谓词逻辑、时序逻辑或 Lean4 表达任务性质 |
| 求解能力 | 至少能完成 task_1，鼓励完成 task_2/task_3 |
| 验证能力 | 能在真实 `nesylink` 环境中 replay 并给出结果 |
| 解释质量 | 能说明抽象模型与真实环境之间的差异 |

## 常见问题

### 为什么动作序列很长？

环境是像素级移动。每次方向动作只移动 1 像素，而一个 tile 是 16 像素，所以 tile 级路径需要展开成多次像素动作。

### 形式化时是否必须模拟怪物的每一像素移动？

不必须。可以先使用保守抽象，例如把怪物相邻区域定义为危险区域，或把怪物生命值作为离散状态。但报告中要说明这个抽象是否 sound，以及 Python replay 是否验证通过。

### 是否必须用 Lean4 调用 Python？

不必须。最低要求是 Lean4 中有形式化模型或关键性质定义，Python 中能 replay plan。更高阶实现可以加入 Lean4/Python JSON bridge，实现搜索器和环境的直接交互。

### 是否可以用强化学习？

本作业重点是数理逻辑和形式化方法。强化学习结果可以作为额外展示，但不能替代形式化描述、目标公式和可解释的求解过程。
