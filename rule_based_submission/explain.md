# 基于规则的 Agent 策略说明

## 整体架构：感知 → 记忆 → 策略 → 规划 → 执行 → 护盾

```
obs(image) + info
    │
    ▼
┌─ vision.py ───────────────────────────────────────────────┐
│  RL_based_submission.VisionExtractor (模板匹配 MSE)         │
│  输出: SymbolicFrame → 转换 → SymbolicState                │
│  分类: wall / chest / trap / button / switch / exit ...    │
└────────────────────────────────────────────────────────────┘
    │
    ▼  SymbolicState
┌─ agent.py: act() ─────────────────────────────────────────┐
│                                                            │
│  _observe_events(info)  ← 处理 block / exit_reached 事件   │
│  _combat_reflex(state)  ← 距离≤2 怪物 → 战斗反射           │
│  strategy.choose_goal() ← 高层目标选择                     │
│  executor.action_for_goal() ← 目标→动作                   │
│  shield()               ← 安全过滤                         │
│  movement queuing       ← 连续帧执行                        │
└────────────────────────────────────────────────────────────┘
    │
    ▼  action (0~6)
```

---

## 1. 符号层 — symbolic.py

### 动作空间

7 个离散动作：

| 编号 | 常量 | 含义 |
|:---:|---|---|
| 0 | `ACTION_NOOP` | 等待 |
| 1 | `ACTION_UP` | 向上移动 1 像素 |
| 2 | `ACTION_DOWN` | 向下移动 1 像素 |
| 3 | `ACTION_LEFT` | 向左移动 1 像素 |
| 4 | `ACTION_RIGHT` | 向右移动 1 像素 |
| 5 | `ACTION_A` | 使用物品 A（剑/交互） |
| 6 | `ACTION_B` | 使用物品 B（盾） |

### 6 种目标类型 `GoalKind`

| 类型 | 含义 | 执行方式 |
|---|---|---|
| `OPEN_CHEST` | 开宝箱 | 走到邻格按 A |
| `ATTACK_MONSTER` | 攻击怪物 | 走到邻格按 A |
| `ACTIVATE_SWITCH` | 激活开关/按钮 | 走到邻格按 A |
| `GO_TO_EXIT` | 穿过出口门 | 走到门 tile，朝门外方向移动 |
| `EXPLORE` | 探索未知区域 | BFS 走到最近的可通行未探索 tile |
| `WAIT` | 等待 | 无事可做时原地不动 |

### `SymbolicState` — 每帧感知快照

```python
player: Position          # 玩家 tile 坐标 (col, row)
room: RoomCoord           # 当前房间坐标
walls / chests / monsters / exits / traps / buttons / switches / bridges / gaps / npcs
keys / health / has_sword / has_shield
```

### `AgentMemory` — 跨步持久记忆

| 字段 | 类型 | 作用 |
|---|---|---|
| `room` | `RoomCoord` | 当前房间坐标，通过 `exit_reached` 事件推断换房 |
| `pending_room_delta` | `RoomCoord \| None` | 待确认的房间偏移量 |
| `last_goal` | `Goal \| None` | 上一帧目标，stick 机制复用；换房时清除 |
| `opened_chests` | `set[GlobalPosition]` | 全局已开宝箱（仅 A+OPEN_CHEST+曼哈顿距离≤1 时标记） |
| `activated_switches` | `set[GlobalPosition]` | 全局已激活开关 |
| `used_exits` | `set[GlobalPosition]` | 已走过的门（含相邻门 tile） |
| `room_memory` | `dict[RoomCoord, RoomSnapshot]` | 访问过房间的快照 |
| `previous_keys` / `spent_keys` | `int` | 钥匙追踪（视觉不可靠，用事件推断） |
| `switch_cooldown` | `int` | 开关冷却帧数，防止反复 toggle |
| `has_sword` / `has_shield` | `bool` | 装备追踪（跨步持久） |

### `update()` 中的关键逻辑

- **宝箱标记**：只有当 `last_action == ACTION_A` 且 `last_goal.kind == OPEN_CHEST` 且玩家与宝箱曼哈顿距离 ≤ 1 时，才标记 `opened_chests`。不再使用差分推断（防止 vision flicker 误标记）。
- **怪物**：不追踪已击杀怪物。怪物死后从画面消失，视觉层自然不再识别。
- **开关标记**：`ACTION_A + ACTIVATE_SWITCH` 时标记 `activated_switches`，设置 40 帧冷却。

---

## 2. 视觉层 — vision.py

采用 `RL_based_submission.vision_extractor.VisionExtractor`：

- **模板匹配 MSE**：用游戏渲染引擎 (`nesylink.core.rendering.sprites`) 预生成每种 tile 在所有可能位置和背景（地板/桥/深渊）上的模板。对每帧的每个 16×16 tile，计算与所有模板的均方误差，取最小值分类。
- **动态遮罩**：通过颜色匹配+膨胀分离玩家和怪物像素，这些像素不参与静态 tile 分类。
- **跨帧记忆**（`use_memory=True`）：被动态实体覆盖超过 35% 的 tile，继承上帧分类结果。
- **转换层**：`SymbolicFrame`（字符串标签矩阵）→ `SymbolicState`（集合+标量）。
- **模块级单例**：`_extractor = VisionExtractor(use_memory=True)`，`reset_vision()` 在每局开始时清空记忆。

### 分类标签映射

| 标签 | 对应 SymbolicState 字段 |
|---|---|
| `"wall"` | `walls` |
| `"chest"` | `chests` |
| `"trap"`, `"abyss"` | `traps` |
| `"button"`, `"button_pressed"` | `buttons` |
| `"switch"`, `"switch_pressed"` | `switches` |
| `"npc"` | `npcs` |
| `"gap"` | `gaps` |
| `"bridge"` | `bridges` |
| `"exit_*"` | `exits` |

---

## 3. 路径规划 — planner.py

### `is_walkable(pos, state, allow_goal=False)`

不可通行：越界、墙、深渊 (`gaps`)、陷阱 (`traps`)、宝箱（挡路）、怪物（占据 tile）。

可通行：桥 (`bridges`) 可跨越深渊；`allow_goal=True` 时出口 tile 视为可通行。

### `bfs_path(state, goals)`

标准 BFS 最短路径搜索，在 10×8 tile 网格上运行。

- 攻击/开箱/激活类目标：goal_tiles 返回目标对象**相邻的 4 个 tile**
- 出口目标：goal_tiles 返回**门 tile 本身**
- 探索目标：goal_tiles 返回**目标 tile**

### `nearest(candidates, origin)`

曼哈顿距离最近，平局时按 `(dist, row, col)` 排序。

---

## 4. 高层策略 — strategy.py

### 9 级优先级链

```
1. 粘性目标 (_continue_last_goal)
   ↓ 条件：目标对象仍然存在且可达
   
2. 相邻可交互对象
   ↓ chest > monster (有剑+安全)
   注：switch 不在相邻优先级里（避免误触）
   
3. 可达宝箱
   ↓ 最可靠的资源来源，且宝箱阻挡移动
   
4. 必须清除的怪物 (_must_clear_monsters_before_exit)
   ↓ 条件：有剑、安全、房间无未开宝箱、无未用开关
   含义：房间清空了其他有价值目标，怪物成为最后障碍
   
5. 未使用出口门
   ↓ 优先未访问房间方向、避开刚进来的门
   
6. 开关/按钮
   ↓ 当前出口耗尽后，用机关改变连通性
   
7. 已使用出口 (fallback)
   ↓ 万不得已时重新走已走过的门
   
8. 探索
   ↓ BFS 找最近的可通行 tile 作为探索目标
   
9. WAIT
   ↓ 真的无事可做（正常情况下不应到达）
```

### 关键决策方法

**`_continue_last_goal` (粘性目标)**：
- `OPEN_CHEST`：目标在 `unopened_chests` 中且可达 → 继续
- `ATTACK_MONSTER`：目标在 `live_monsters` 中且安全 → 继续
- `ACTIVATE_SWITCH`：目标在 `mechanisms` 中 → 先检查是否有未使用的出口，有则放弃 switch 去探出口
- `GO_TO_EXIT`：
  - 有未开宝箱 → **放弃出口**，去开宝箱
  - 有必须清除的怪物 → **放弃出口**，去打怪
  - 已站在门上且用过 → 放弃
  - 可达 → 继续

**`_must_clear_monsters_before_exit`**：
有剑 + 有活怪 + 安全 + 没有宝箱 + 没有未用开关 → 必须先清怪

**`_best_exit_goal` (出口排序)**：6 维评分
1. 是否用过（0=未用，1=用过）
2. 门前是否有障碍物
3. 是否通向未访问房间
4. 是不是刚进来的方向
5. 有钥匙时优先东门（key_bonus）
6. 曼哈顿距离

**`_room_is_cleared`**：房间无未开宝箱 + 无未用开关 → 只剩怪物有价值

**`_mechanism_goal`**：优先未激活的开关；冷却中则等待。

---

## 5. 主控层 — agent.py

`Policy` 类将所有模块串联，核心在 `act(obs, info)` 方法中。

### 5a. 事件处理 `_observe_events`

| 事件 | 处理动作 |
|---|---|
| `action_blocked` | 记录被挡动作+帧数（最多 6 帧），清空移动队列，**清 `pending_room_delta`**（防止假换房） |
| `shield_block / agent_damaged / monster_damaged` | 锁定 240 帧强制战斗模式 `_force_fight_ticks` |
| `exit_reached` | 见 5b |
| `door_opened` | 追踪钥匙消耗（`spent_keys`） |

### 5b. 出口事件 `_observe_exit_events`

收到 `exit_reached` 事件时：
1. 标记出口为已使用
2. 从事件的 `direction` 字段（`"north"/"south"/"west"/"east"`）推断 `pending_room_delta`
3. 清空移动队列

与原始代码的差异：**原始代码在 agent 即将踏出门时预测 `pending_room_delta`**，锁门/条件门会导致"假换房"——门挡住但记忆已换房。现在改为**事件驱动的确认机制**，只有 `exit_reached` 事件才设 `pending_room_delta`。同时 `action_blocked` 时清除 `pending_room_delta` 作为双重保险。

### 5c. 战斗反射 `_combat_reflex`

```
距离 ≤ 2 有怪物
  │
  ├─ 距离 = 1（紧邻）
  │   ├─ 面朝 + 有剑 → A 攻击
  │   ├─ 不面朝      → _step_away 后退一步（拉开距离到 dist=2）
  │   └─ 无路可退    → B 举盾（推走怪物）
  │
  └─ 距离 = 2（隔一格）
      ├─ 有剑 → _step_toward_safe 向怪物靠近一步
      └─ 无路  → B 举盾
```

**典型战斗周期**：距离=2 → 靠近 → 距离=1 → 面朝 → 攻击 → (不面朝) → 后退 → 距离=2 → 再靠近...

### 5d. 面朝判断 `_is_facing`

射线夹角定义：**player 朝向画一条射线，player→monster 连线与该射线的夹角 < 90° 即算面朝**。

等价于：朝向方向向量与 (monster_pos - player_pos) 向量的点积 > 0。

| 朝向 | 面朝条件 |
|---|---|
| UP (0, -1) | `monster.y < player.y` |
| DOWN (0, 1) | `monster.y > player.y` |
| LEFT (-1, 0) | `monster.x < player.x` |
| RIGHT (1, 0) | `monster.x > player.x` |

**朝向追踪 `_facing`**：只有移动动作（UP/DOWN/LEFT/RIGHT）更新朝向，A/B/NOOP 不改变。保证战斗中的朝向持久化，不会因攻击或举盾丢失朝向。

### 5e. 卡住恢复

**`_unstick_action`**：被连续阻挡时换方向绕行。从其余 3 个方向中选择可通行、远离怪物、朝目标前进的方向。

**`_exit_corner_nudge`（新增）**：专门处理出口门卡住的情况。如果 agent 正对着门（水平/垂直方向）但被挡住，沿墙壁方向微调一步对齐门 tile。

- 例：西门 (0,4)，agent 在 (0,3) 朝左，正对门上方被挡 → 微调 DOWN 到 (0,4) 对齐

**unstick_nudge**：nudge 动作的队列设为 **1 帧**（只微调一步），防止大步绕到远处，确保下一帧重新规划。

### 5f. 移动队列

| 场景 | 队列帧数 |
|---|---|
| 正在穿门 (`leaving_through_exit`) | 23 |
| 无怪物 | 15 |
| 怪物距离 ≤ 2 | 1（高频重规划） |
| 其他 | 3 |
| unstick_nudge | 1 |

### 5g. 强制战斗 `_forced_combat_goal`

战斗事件触发后锁定 240 帧。条件：有剑 + 有怪物 + 血量 > 1。优先攻击最近且面朝的怪物。

### 5h. 辅助方法

- **`_step_away`**：从怪物身边后退一格。优先沿主轴后退；必须确保后退后距离 > 1 且不踏入怪物 tile。
- **`_step_toward_safe`**：向怪物走一步。4 方向中选使曼哈顿距离最小且可通行者。
- **`_monster_rank`**：距离 + 面朝惩罚（面朝怪物的优先）。

---

## 6. 安全护盾 — shield.py

最后一道安全检查。移动动作的目标 tile 不可通行 → 强制改为 `ACTION_NOOP`。

例外：已在门 tile 上且下一步出界 → 放行（穿门）。

---

## 7. 动作执行 — executor.py

### `action_for_goal(state, goal)`

| 目标类型 | 逻辑 |
|---|---|
| 交互类（宝箱/怪物/开关） | 曼哈顿=1 → 按 A；否则 BFS 走一步 |
| 出口 | 已在门 tile → `_exit_push_action` 垂直推出；否则 BFS 走到门 tile |
| 探索 | BFS 走到目标 tile |

### `_exit_push_action(target)`

| 门位置 | 动作 |
|---|---|
| row == 0（北门） | UP |
| row == 7（南门） | DOWN |
| col == 0（西门） | LEFT |
| col == 9（东门） | RIGHT |

---

## 8. 模块间数据流

```
obs (128×160×3 RGB)
  │
  ▼
vision.py :: perceive()
  │  提取玩家位置、怪物位置、各类静态 tile 集合
  ▼
SymbolicState
  │
  ├─ agent.py :: _combat_reflex()
  │    紧急战斗 → 直接返回 A/B/移动
  │    无威胁 → 继续
  │
  ├─ strategy.py :: choose_goal()
  │    9 级优先级 → 选出一个 Goal
  │
  ├─ executor.py :: action_for_goal()
  │    Goal → 原始动作
  │
  ├─ agent.py :: _unstick_action() (可选)
  │    被卡住 → 替代动作
  │
  ├─ shield.py :: shield()
  │    安全过滤 → 最终动作
  │
  └─ agent.py :: 队列设置
      移动动作 → 设置 _queued_ticks
      非移动动作 → 不排队
      → 返回 action
```

---

## 文件清单

| 文件 | 职责 |
|---|---|
| `symbolic.py` | 数据类型、动作常量、AgentMemory、工具函数 |
| `vision.py` | 从图像帧抽取符号状态（基于 RL 模块的模板匹配） |
| `planner.py` | BFS 路径搜索、可达性判断 |
| `strategy.py` | 高层目标选择的 9 级优先级链 |
| `executor.py` | 目标 → 动作的转换 |
| `shield.py` | 动作安全过滤 |
| `agent.py` | 主控制器：事件处理、战斗反射、移动队列、面朝追踪 |
| `explain.md` | 本文档 |
