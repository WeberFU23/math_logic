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

Human play: 需要安装 pygame 依赖：

```bash
pip install -e ".[pygame]"
```
之后可以直接在终端运行
```shell
python -m nesylink.game --rooms nesylink/map_data/mathematical_logic/task_1/room_001.json
python -m nesylink.game --rooms nesylink/map_data/mathematical_logic/task_2/room_001.json
python -m nesylink.game --rooms nesylink/map_data/mathematical_logic/task_3/dungeon.json
python -m nesylink.game --rooms nesylink/map_data/mathematical_logic/task_4/dungeon.json
python -m nesylink.game --rooms nesylink/map_data/mathematical_logic/task_5/dungeon.json
```

| task_id | 地图 | 奖励 | 最大步数 | 任务说明 |
|---|---|---|---:|---|
| `mathematical_logic/task_1` | `nesylink/map_data/mathematical_logic/task_1/room_001.json` | `mathematical_logic/task_1` | 500 | 收集钥匙并从北侧锁门离开 |
| `mathematical_logic/task_2` | `nesylink/map_data/mathematical_logic/task_2/room_001.json` | `mathematical_logic/task_2` | 500 | 击败怪物、拿钥匙、从西侧条件门离开 |
| `mathematical_logic/task_3` | `nesylink/map_data/mathematical_logic/task_3/dungeon.json` | `mathematical_logic/task_3` | 1000 | 穿过怪物房，去西侧房间拿钥匙，返回起点并打开东侧锁门 |
| `mathematical_logic/task_4` | `nesylink/map_data/mathematical_logic/task_4/dungeon.json` | `mathematical_logic/task_4` | 1000 | 旋转桥、拿钥匙和剑、击败守卫并打开最终宝箱 |
| `mathematical_logic/task_5` | `nesylink/map_data/mathematical_logic/task_5/dungeon.json` | `mathematical_logic/task_5` | 1000 | 探索多房间地牢并完成宝箱目标 |

## 作业要求:
TODO: 

## Examples 参考实现

仓库的 `examples/` 目录给出了两个 Python 参考实现，用于演示如何通过当前 `nesylink` 框架接口运行内置任务：

| 文件 | 对应任务 | 说明 |
|---|---|---|
| `examples/task1_reference.py` | `mathematical_logic/task_1` | 使用固定像素级动作序列完成“拿钥匙并通过北侧锁门”的任务。 |
| `examples/task2_reference.py` | `mathematical_logic/task_2` | 使用从 `obs` 抽取的符号状态、邻接谓词和 BFS 子目标规划，完成当前 `mathematical_logic/task_2`。 |

运行方式：

```bash
python docs/Mathematical_logic/examples/task1_reference.py
python docs/Mathematical_logic/examples/task2_reference.py
```

它们是本作业给出的参考实现，重点是展示：

1. 如何从真实环境 `obs` 中抽取离散符号状态。
2. 如何把 tile 级计划展开为像素级动作 replay。
3. 如何通过 `terminated/truncated`、`info["terminal_reason"]` 和 `info["game"]["world_completed"]` 检查真实环境执行结果。

> 注意：当前 `mathematical_logic/task_2` 使用同名主题奖励；击败怪物只是中间目标，episode 只在真实地图完成或死亡时终止。

## 游戏接口介绍

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

`obs` 中最常用的字段：
> 很不幸，本次作业设置希望你们可以直接在 raw pixels 的基础上进行学习，所以一下 obs 字段仅作参考

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

`info` 中最常用的字段：

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
