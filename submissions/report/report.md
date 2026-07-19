# 数理逻辑大作业项目报告

测试时将`submissions`文件夹放在与`docs`文件夹同级的位置即可。
维护的仓库见：https://github.com/WeberFU23/math_logic

## 规则驱动的策略设计

 为保持简明，更详细的规则策略解释请查看 [rules.md](rules.md)

 Agent 采用**分层符号化架构**，将像素观测转换为符号状态，再通过优先级链决策。整体上，同一套规则覆盖五个任务，没有为各关保存固定坐标或完整动作序列。
 核心模块及数据流如下：

```
像素帧 (obs)  ──► vision.py + color_vision.py  ──► SymbolicState
                                                         │
                                           ┌─────────────┘
                                           ▼
                              strategy.py (选择 Goal)
                                           │
                                           ▼
                              planner.py  (根据 Goal 用 BFS 确定路径)
                                           │
                                           ▼
                              executor.py (路径 → 动作)
                                           │
                                           ▼
                              shield.py   (安全检查)
                                           │
                                           ▼
                              agent.py    (具体执行细节)
```

`vision.py` 和 `color_vision.py` 从 RGB 图像中识别玩家、怪物、地形与交互对象，并自动适配灰度、明暗、高对比度和反色变换；`symbolic.py` 将识别结果组织为 `SymbolicState`，同时用 `AgentMemory` 记录已开启宝箱、已触发机关、已使用出口和跨房间状态。该过程只使用图像及接口允许的物品栏、奖励信息，不依赖环境内部地图或对象坐标。

高层策略 `strategy.py` 按固定优先级选择符号目标，主要规则可概括为：

1. 当前目标仍有效且可达时继续执行，避免频繁切换；
2. 优先开启可达宝箱，再处理按钮、开关和条件门；
3. 有剑且生命安全时清理必要怪物，近身威胁由最高优先级的战斗反射立即处理；
4. 满足钥匙、按钮或清怪条件后，优先选择可达且未使用的出口；
5. 无明确任务目标时探索，所有目标均不可用时等待。

`planner.py` 使用四方向 BFS 搜索路径，将墙壁、陷阱、宝箱、怪物、NPC 和无桥深渊视为不可通行区域；`executor.py` 再把目标转换为移动、攻击、交互或出门动作。最终动作经过 `shield.py` 检查，不安全移动会被替换为等待，合法的出口穿越则予以放行。

主循环 `agent.py` 负责整合各层，并补充像素级执行机制：移动动作队列减少重复规划；战斗锁定与警戒反射提高近战稳定性；连续帧位移用于检测卡墙，随后通过对齐微调、出口校准和脱困动作恢复。

## 实验结果

### 测评设置

使用统一规则策略 `submissions.agent:Policy`，在 `safe` 信息模式下运行固定鲁棒性套件。每个任务测试 100 个 episode，其中原始地图 60 个、空间变体 30 个、颜色变体 10 个；seed 使用默认值 0。测评未覆盖 `max_steps` 和 `action_repeat`，均采用各任务配置。该策略为确定性规则策略，不需要训练或模型权重。代码版本为 Git tag [`submission-v1.0`](https://github.com/WeberFU23/math_logic/tree/submission-v1.0)，对应随提交材料提供的完整源代码；完整测评后仅统一了 Python 包导入路径并整理报告与 Lean 工程，未改变策略决策逻辑。

本地调试阶段使用过 `full` 信息模式，用于排查感知、规划和执行问题；这些信息不用于训练，也不作为最终策略的决策输入。正式测评仅进行推理，策略只使用图像帧、历史奖励和接口允许提供的物品栏信息，不读取地图真值、对象坐标、事件或其他隐藏状态。测评使用的命令行如下：

```powershell
python utils\evaluate_policy.py `
  --policy submissions.agent:Policy `
  --info-mode safe `
  --robustness-suite `
  --num-envs 100 `
  --json-out submissions/runs/final_evaluation.json
```

### 结果汇总

完整结果见 [final_evaluation.json](../runs/final_evaluation.json)，运行证明见[测评截图](../runs/测评截图-证明可运行.png)。
表中每个阶段依次给出“成功率 / 平均步数 / 平均奖励”。成功以 episode 完成整个任务并以 `world_completed` 终止为准。

| 任务 | 原始地图（60） | 空间变体（30） | 颜色变体（10） | 综合成功率 |
| --- | ---: | ---: | ---: | ---: |
| Task 1 | 100% / 290.00 / 127.05 | 100% / 204.33 / 127.92 | 100% / 290.00 / 127.05 | 100% |
| Task 2 | 100% / 161.00 / 128.39 | 100% / 193.00 / 142.92 | 100% / 161.00 / 128.39 | 100% |
| Task 3 | 100% / 547.00 / 164.53 | 100% / 646.33 / 163.54 | 100% / 551.40 / 164.49 | 100% |
| Task 4 | 100% / 1080.00 / 251.20 | 100% / 1381.67 / 276.85 | 100% / 1079.60 / 251.20 | 100% |
| Task 5 | 100% / 1095.00 / 171.65 | 0% / 1066.67 / 331.55 | 100% / 1105.00 / 171.67 | 70% |

五个任务合计通关 470/500 个 episode，总成功率为 94%。按阶段汇总，原始地图和颜色变体均为 100%，空间变体为 80%。Task 1–4 在三个阶段全部通关，说明策略能够适应这四关的空间布局变化以及灰度、明暗、对比度和反色等视觉扰动。

阶段性指标与最终成功率一致：Task 1 和 Task 2 的全部 progress 指标在三个阶段均为 100%；Task 3 的 `key_collected`、`monster_killed` 里程碑均为 100%；Task 4 的 `key_collected`、`item_collected`、`door_opened`、`switch_activated` 和 `monster_killed` 里程碑均为 100%。

Task 5 在原始地图和颜色变体中也通关，Task 5 的空间变体是当前策略的主要局限。30 个 episode 均未最终通关，但 `key_collected`、`chest_opened`、`gold_collected`、`button_pressed`、`room_changed` 和 `exit_reached` 均达到 100%，`agent_healed`、`door_opened` 和 `monster_killed` 达到 66.7%；同时 `agent_dead` 为 100%，`environment_completed` 与 `world_completed` 为 0%。这表明策略能够完成前半段探索和机关交互，但在变化后的复杂战斗与后续路线衔接上不够稳健。

### Progress 与 milestone 逐项指标

以下比例直接取自 `final_evaluation.json`：progress 表示该阶段中至少触发过相应事件的 episode 比例，milestone 表示测评器为对应任务配置的关键子目标达成率。“—”表示该任务没有单独配置 milestone。

#### Task 1

| 阶段 | Progress | Milestone |
| --- | --- | --- |
| 原始地图 | `chest_opened` 100%；`door_opened` 100%；`environment_completed` 100%；`exit_reached` 100%；`key_collected` 100%；`room_changed` 100%；`world_completed` 100% | — |
| 空间变体 | `chest_opened` 100%；`door_opened` 100%；`environment_completed` 100%；`exit_reached` 100%；`key_collected` 100%；`room_changed` 100%；`world_completed` 100% | — |
| 颜色变体 | `chest_opened` 100%；`door_opened` 100%；`environment_completed` 100%；`exit_reached` 100%；`key_collected` 100%；`room_changed` 100%；`world_completed` 100% | — |

#### Task 2

| 阶段 | Progress | Milestone |
| --- | --- | --- |
| 原始地图 | `chest_opened` 100%；`environment_completed` 100%；`exit_reached` 100%；`key_collected` 100%；`monster_killed` 100%；`room_changed` 100%；`world_completed` 100% | — |
| 空间变体 | `chest_opened` 100%；`environment_completed` 100%；`exit_reached` 100%；`key_collected` 100%；`monster_killed` 100%；`room_changed` 100%；`world_completed` 100% | — |
| 颜色变体 | `chest_opened` 100%；`environment_completed` 100%；`exit_reached` 100%；`key_collected` 100%；`monster_killed` 100%；`room_changed` 100%；`world_completed` 100% | — |

#### Task 3

| 阶段 | Progress | Milestone |
| --- | --- | --- |
| 原始地图 | `chest_opened` 100%；`door_opened` 100%；`environment_completed` 100%；`exit_reached` 100%；`key_collected` 100%；`monster_killed` 100%；`room_changed` 100%；`world_completed` 100% | `key_collected` 100%；`monster_killed` 100% |
| 空间变体 | `chest_opened` 100%；`door_opened` 100%；`environment_completed` 100%；`exit_reached` 100%；`key_collected` 100%；`monster_killed` 100%；`room_changed` 100%；`world_completed` 100% | `key_collected` 100%；`monster_killed` 100% |
| 颜色变体 | `chest_opened` 100%；`door_opened` 100%；`environment_completed` 100%；`exit_reached` 100%；`key_collected` 100%；`monster_killed` 100%；`room_changed` 100%；`world_completed` 100% | `key_collected` 100%；`monster_killed` 100% |

#### Task 4

| 阶段 | Progress | Milestone |
| --- | --- | --- |
| 原始地图 | `chest_opened` 100%；`door_opened` 100%；`environment_completed` 100%；`exit_reached` 100%；`gold_collected` 100%；`item_collected` 100%；`key_collected` 100%；`monster_killed` 100%；`room_changed` 100%；`world_completed` 100% | `door_opened` 100%；`item_collected` 100%；`key_collected` 100%；`monster_killed` 100%；`switch_activated` 100% |
| 空间变体 | `chest_opened` 100%；`door_opened` 100%；`environment_completed` 100%；`exit_reached` 100%；`gold_collected` 100%；`item_collected` 100%；`key_collected` 100%；`monster_killed` 100%；`room_changed` 100%；`world_completed` 100% | `door_opened` 100%；`item_collected` 100%；`key_collected` 100%；`monster_killed` 100%；`switch_activated` 100% |
| 颜色变体 | `chest_opened` 100%；`door_opened` 100%；`environment_completed` 100%；`exit_reached` 100%；`gold_collected` 100%；`item_collected` 100%；`key_collected` 100%；`monster_killed` 100%；`room_changed` 100%；`world_completed` 100% | `door_opened` 100%；`item_collected` 100%；`key_collected` 100%；`monster_killed` 100%；`switch_activated` 100% |

#### Task 5

| 阶段 | Progress | Milestone |
| --- | --- | --- |
| 原始地图 | `agent_healed` 100%；`button_pressed` 100%；`chest_opened` 100%；`door_opened` 100%；`environment_completed` 100%；`exit_reached` 100%；`gold_collected` 100%；`key_collected` 100%；`monster_killed` 100%；`room_changed` 100%；`world_completed` 100% | `agent_healed` 100%；`button_pressed` 100%；`chest_opened` 100%；`door_opened` 100%；`environment_completed` 100%；`exit_reached` 100%；`gold_collected` 100%；`item_collected` 0%；`key_collected` 100%；`monster_killed` 100%；`room_changed` 100%；`trap_triggered` 0%；`world_completed` 100% |
| 空间变体 | `agent_dead` 100%；`agent_healed` 66.7%；`button_pressed` 100%；`chest_opened` 100%；`door_opened` 66.7%；`exit_reached` 100%；`gold_collected` 100%；`key_collected` 100%；`monster_killed` 66.7%；`room_changed` 100% | `agent_healed` 66.7%；`button_pressed` 100%；`chest_opened` 100%；`door_opened` 66.7%；`environment_completed` 0%；`exit_reached` 100%；`gold_collected` 100%；`item_collected` 0%；`key_collected` 100%；`monster_killed` 66.7%；`room_changed` 100%；`trap_triggered` 0%；`world_completed` 0% |
| 颜色变体 | `agent_healed` 100%；`button_pressed` 100%；`chest_opened` 100%；`door_opened` 100%；`environment_completed` 100%；`exit_reached` 100%；`gold_collected` 100%；`key_collected` 100%；`monster_killed` 100%；`room_changed` 100%；`world_completed` 100% | `agent_healed` 100%；`button_pressed` 100%；`chest_opened` 100%；`door_opened` 100%；`environment_completed` 100%；`exit_reached` 100%；`gold_collected` 100%；`item_collected` 0%；`key_collected` 100%；`monster_killed` 100%；`room_changed` 100%；`trap_triggered` 0%；`world_completed` 100% |

## Lean 形式化与证明

### 形式化思路

形式化采用“感知接口假设 → 符号环境 → 规则选择与安全搜索 → action mask 与 safety shield → 策略执行轨迹 → 任务完成证书”的分层验证思路。首先在视觉模块已正确生成 `SymbolicState` 的前提下定义对象、状态、动作和完整转移语义；随后将具体规则选择器、planner、executor、shield 与环境执行连接起来，证明策略输出合法、安全，并通过可计算 BFS 的可靠性与完备性以及五关执行证书证明目标可达和成功轨迹满足目标谓词。

环境形式化位于 `Environment.lean`，规则策略位于
`Rule_based_Strategy.lean`，五关通关证书位于 `Rule_based_TaskProofs.lean`，强化不变量和
可计算 BFS 证明位于 `Additional_Proofs.lean`。

### 模块一　环境形式化

#### 1.1 形式化范围与抽象层次

Lean 从 `SymbolicState` 开始验证。Python 的 `vision.py` 从允许使用的图像帧中提取玩家、墙、
陷阱、宝箱、怪物、按钮、开关和出口等符号信息。Lean 定义 `PixelFrame`、`ValidPixelFrame`、
`PerceptionSound` 和 `ColorModeInvariant` 作为感知接口，但没有证明视觉算法对所有图像均识别
正确。因此，本项目的严格结论是：**如果符号状态正确反映当前观测，那么环境语义、规则规划和
安全过滤满足下述性质。**

连续像素运动抽象成 tile 级移动；真实环境中连续推门的多个 primitive tick 抽象成带有
`canUseExitObject` 前置条件的 `useExit`。这些简化保留了规划和安全证明需要的关键逻辑。

#### 1.2 状态、动作、对象与目标谓词

| 类别 | Lean 定义 | 建模内容 |
| --- | --- | --- |
| 坐标 | `Position`、`RoomCoord`、`GlobalPosition` | 房间内 10×8 tile、房间坐标和跨房间位置 |
| 玩家 | `player`、`room`、`facing`、`health`、`maxHealth`、`steps`、`maxSteps` | 位置、朝向、生命和超时 |
| 对象 | `Chest`、`Monster`、`Exit`、`Loot`、`BridgeState` | 宝箱、怪物、出口、奖励和旋转桥 |
| 地形 | `walls`、`traps`、`gaps`、`bridges`、`activeBridges` | 墙、陷阱、沟壑和当前桥面 |
| 机关 | `buttons`、`switches`、`pressedButtons`、`activated` | 踩踏按钮和按 A 旋转开关 |
| 资源 | `keys`、`gold`、`items`、`hasSword`、`hasShield` | 钥匙、金币、物品、剑和盾 |
| 进度 | `keysCollected`、`chestsOpened`、`monstersKilled`、`buttonsPressed`、`switchesActivated`、`roomsChanged`、`worldCompleted` | 不因资源消耗而丢失的任务里程碑 |
| 动作 | `wait`、`up/down/left/right`、`pressA`、`pressB`、`useExit`、`envTick` | 等待、移动、交互、盾牌、出口和环境结算 |
| 安全谓词 | `inBounds`、`terrainPassable`、`isWalkable`、`SafePosition`、`FailedState` | 边界、地形、陷阱安全、死亡和超时 |

五关目标使用累计里程碑，避免钥匙被最终门消耗后无法证明“曾经取得钥匙”：

```lean
Task1Goal s := s.worldCompleted = true ∧ s.keysCollected ≥ 1 ∧ s.chestsOpened ≥ 1
Task2Goal s := s.worldCompleted = true ∧ s.monstersKilled ≥ 1 ∧
               s.keysCollected ≥ 1 ∧ s.chestsOpened ≥ 1
Task3Goal s := s.worldCompleted = true ∧ s.roomsChanged ≥ 5 ∧
               s.monstersKilled ≥ 1 ∧ s.keysCollected ≥ 1 ∧ s.chestsOpened ≥ 1
Task4Goal s := s.worldCompleted = true ∧ s.switchesActivated ≥ 2 ∧
               s.keysCollected ≥ 1 ∧ s.hasSword = true ∧
               s.monstersKilled ≥ 1 ∧ s.chestsOpened ≥ 3
Task5Goal s := s.worldCompleted = true ∧ s.chestsOpened ≥ 4 ∧
               s.roomsChanged ≥ 5 ∧ s.buttonsPressed ≥ 1 ∧ s.keysCollected ≥ 1
```

#### 1.3 动作转移语义与关键机制

| 机制 | 形式化语义 |
| --- | --- |
| 安全移动 | `EnvStep.moveSafe` 要求方向动作、下一格在界内且 `isWalkable` |
| 撞墙 | `EnvStep.moveBlocked` 在目标格不可通行时保持玩家位置 |
| 陷阱 | `EnvStep.moveTrap` 将玩家移入陷阱并应用伤害，与安全移动区分 |
| 宝箱 | `canOpenChestObject` 检查对象、房间、未打开和面前位置；`openChestObjectState` 同步奖励与里程碑 |
| 攻击 | `canAttackObject` 要求怪物存活、位于面前且玩家有剑；更新 HP、掉落和击杀数 |
| 按钮 | 首次进入按钮 tile 自动记录并计数，重复进入不重复计数 |
| 开关 | `pressSwitch` 记录开关并切换 `BridgeState` |
| 出口 | `ExitKind` 区分普通、钥匙、清怪加钥匙、按钮和物品门；满足条件后换房 |
| 怪物与盾 | 建模威胁、合法怪物移动、伤害和盾牌格挡 |
| 生命与时钟 | 建模扣血、回血、超时和 Task 5 周期掉血 |

`EnvStep` 给出轻量语义；`FullEnvStep` 增加结构化对象、怪物行为、盾牌、出口和环境 tick。
`FullExec` 是多步完整执行；`SafeFullExec` 还要求初态、全部中间状态和终态均不满足
`FailedState`。`TaskCertificate` 同时保存计划、终态、安全执行证明和目标证明。

### 模块二　策略形式化与证明

#### 2.1 规则策略与实现对应关系

```text
vision.py / symbolic.py
  → strategy.py：选择高层 Goal
  → planner.py：BFS 生成安全路径
  → executor.py：Goal 转成原始动作
  → shield.py：过滤危险移动
  → agent.py：输出 primitive action 并更新记忆
```

Lean 中对应为：

```text
SymbolicState + AgentMemory
  → ruleBasedChooseGoal 或 CombatReflex
  → ActionForGoal / PlannerStep
  → Shielded
  → FullEnvStep
  → updateRuleMemory
  → RulePolicyStep / RulePolicyExec
```

`ruleBasedChooseGoal` 是具体可计算选择器，不是任意抽象策略。其优先级依次处理仍合法的 sticky
目标、宝箱、必要战斗、条件门按钮、条件门怪物、新出口、开关、回退出口、探索和等待。
`ActionAllowed` 是 action mask 规格；`Shielded` 将不安全移动改为等待，放行安全移动和合法出门。

#### 2.2 安全性、可达性、完备性和子任务正确性

**安全性。** `rule_pipeline_output_allowed` 证明 `RuleGoal → ActionForGoal → Shielded` 管线输出
满足 `ActionAllowed`；若输出为移动，`shielded_rule_action_safe_position_or_exit` 进一步证明
落点满足 `SafePosition`，或动作是带出口见证的合法越界。`SafeFullExec` 排除死亡和超时轨迹。

**可达性。** `taskN_safe_execution` 构造五关安全轨迹，`taskN_goal` 证明终态目标；随后
`taskN_rule_policy_execution` 对同一计划逐步证明具体选择器、executor、shield、环境转移和
记忆更新，把环境可达性强化为策略可达性。

**完备性。** 抽象定理说明完备 frontier 不漏掉有界可达目标。可计算层证明 `breadthFrontier`
与关系式 `PositionReachable` 等价，最终得到 `verified_search_result_iff_reachable`。因此在给定
步数 `n` 和 `isWalkable` 安全语义下，存在安全路径当且仅当存在验证搜索结果。

**关键子任务。** 每个 checkpoint 证明规则在相应状态能合法选择正确目标。
`RuleTaskCertificate` 的 `execution`、`completed` 和 `generated` 使用同一计划和终态，所以
`rule_taskN_completed : CompletedByRulePolicy ...` 同时包含安全执行、目标成立和具体策略生成，
不是只证明“环境中存在一条手写路线”。

### 所证定理列表

此处列出评分要求的核心证明，包括 planner、搜索、action mask、输出合法性、安全性、可达性、完备性和任务完成性等，完整定理索引请查看[lean.md](lean.md) 。

| 类别 | 定理 | 结论 |
| --- | --- | --- |
| 可通行位置安全 | `walkable_is_safe_position` | 可通行位置满足界内、非墙和非危险地形条件 |
| 合法移动安全 | `move_safe_player_eq`、`safe_move_preserves_safe_position` | 合法移动到达目标格并保持安全位置 |
| 阻挡移动正确性 | `move_blocked_player_eq` | 撞墙或不可通行移动不改变玩家位置 |
| 交互正确性 | `open_chest_increases_keys`、`attack_monster_removes_target` | 开箱增加钥匙，攻击成功后移除目标怪物 |
| 怪物移动合法性 | `monsterMoveAllowed_target_inBounds`、`monsterMoveAllowed_target_not_wall` | 怪物合法移动不会越界或进入墙体 |
| 出口条件 | `lockedExit_condition_implies_enough_keys` | 锁门可用时必定持有足够钥匙 |
| 目标合法性 | `ruleBasedChooseGoal_admissible` | 具体规则选择器产生的目标满足合法性约束 |
| 规划动作安全性 | `planner_step_safe` | planner 输出的第一步是安全可通行移动 |
| 动作合法性 | `action_for_goal_allowed`、`rule_pipeline_output_allowed` | executor 及完整规则管线的输出满足 action mask |
| 安全过滤正确性 | `shielded_output_allowed`、`shield_blocks_unsafe_movement` | shield 输出合法，并把危险移动替换为等待 |
| 策略移动安全性 | `shielded_rule_action_safe_or_exit`、`shielded_rule_action_safe_position_or_exit` | 策略不会主动进入危险位置，合法出门除外 |
| 可达性 | `safeMovePlan_positionReachable`、`positionReachable_has_safeMovePlan` | 安全动作计划与符号位置可达关系可以相互转换 |
| 搜索完备性 | `breadthFrontier_complete`、`breadth_search_complete` | 给定步数内存在安全可达目标时，逐层搜索能够发现它 |
| 搜索可靠性 | `breadth_search_sound_and_complete`、`verified_search_result_iff_reachable` | 搜索发现目标当且仅当目标可达，并可产生安全动作计划证书 |
| 五关安全轨迹 | `task1_safe_execution` 至 `task5_safe_execution` | 五个参考关卡的给定轨迹均为无失败环境执行 |
| 关键子任务正确性 | `task1_rule_chest_checkpoint`、`task2_rule_monster_checkpoint`、`task3_rule_key_chest_checkpoint`、`task4_rule_guardian_checkpoint`、`task5_rule_button_triggered_by_entry` 等 | 分别验证开箱、清怪、取钥匙、击杀守卫和按钮触发等任务链节点 |
| 任务完成 | `rule_task1_completed` 至 `rule_task5_completed` | 五个参考关卡均存在由规则策略生成的安全成功轨迹 |
| 证书汇总 | `all_rule_task_certificates`、`all_rule_tasks_policy_generated` | 汇总五关完成证书，并确认轨迹由具体规则策略生成 |

上述定理共同形成以下验证链：`ruleBasedChooseGoal` 选择合法目标，planner 产生安全移动，`ActionForGoal` 输出满足 action mask 的动作，`Shielded` 阻止危险移动，`RulePolicyExec` 将策略动作与环境转移连接，最终由五关证书证明成功执行满足目标谓词。


### 抽象与适用范围

Lean 证明从视觉模块已经生成的 `SymbolicState` 开始，不证明像素模板匹配对所有图像都正确；连续像素移动、动作队列、卡墙微调和动画时序被抽象为格级动作。搜索定理证明的是 Lean 中逐层安全搜索相对于 `PositionReachable` 的可靠性与完备性，未逐行验证 Python BFS 实现。五关完成定理针对形式化后的参考关卡和具体轨迹，不代表所有空间变体都必然通关。形式化源码中未使用 `sorry`、`admit` 或 `axiom`。
