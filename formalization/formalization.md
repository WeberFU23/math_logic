# Rule-based 与 RL-based Agent 的 Lean 形式化文件说明

`formalization/` 从视觉抽取后的符号状态开始，对公共环境以及两条 Agent 路线分别进行形式化。
按照课程大作业的证明内容，文档分为两个模块：

- **模块一：公共环境形式化**，说明状态、对象、动作、转移、失败条件、任务目标和安全轨迹；
- **模块二：策略形式化与证明**，分别说明 Rule-based 与 RL-based 的决策接口、安全约束和五关证书。

## 文件组成与依赖

`formalization/` 包含五个 Lean 文件：

| 文件 | 内容 |
| --- | --- |
| `Environment.lean` | 公共符号环境、对象语义、执行轨迹、五关目标和公共参考场景 |
| `Rule_based_Strategy.lean` | 规则策略的记忆、优先级、规划器、执行器和安全屏蔽契约 |
| `Rule_based_TaskProofs.lean` | 规则路线在 Task 1-5 关键检查点上的目标证明和通关证书 |
| `RL_based_Strategy.lean` | RL 特征编码、option 解析、基础与 Task 5 mask、primitive shield |
| `RL_based_TaskProofs.lean` | RL 路线在 Task 1-5 关键检查点上的 mask 证明和通关证书 |

依赖关系为：

```text
formalization.Environment
├── formalization.Rule_based_Strategy
│   └── formalization.Rule_based_TaskProofs
└── formalization.RL_based_Strategy
    └── formalization.RL_based_TaskProofs
```

主要命名空间：

```lean
MathLogic.Formalization
MathLogic.Formalization.ReferenceTasks
RuleBasedSubmission.Formalization
RLBasedSubmission.Formalization.Strategy
RLBasedSubmission.Formalization
```

两条策略路线都以 `MathLogic.Formalization.SymbolicState`、`FullEnvStep`、
`SafeFullExec`、`Task1Goal` 至 `Task5Goal` 和 `TaskCertificate` 为环境语义。

## 模块一：公共环境形式化

本模块对应 `Environment.lean`。它是两条路线共同依赖的环境语义层。

### 1. 坐标与常量

- `Position := Int × Int`：房间内 tile 坐标。
- `RoomCoord := Int × Int`：房间坐标，支持向西、向北产生的负坐标。
- `GlobalPosition`：`room` 与 `pos` 的组合，用于跨房间记忆。
- `boardWidth = 10`、`boardHeight = 8`：单房间尺寸。
- `task5DrainInterval = 200`：Task 5 周期掉血间隔。
- `Direction`：`north`、`south`、`west`、`east`。

`globalize` 把房间内位置提升为全局位置；`allExits` 汇总旧出口、普通出口、锁门出口和条件出口。

### 2. 动作、物品与对象

`Action` 包含：

```text
wait, up, down, left, right, pressA, pressB, useExit, envTick
```

前七项对应离散控制动作；`useExit` 表示结构化出口跳转；`envTick` 表示环境自动结算。

对象定义包括：

- `Item`：`sword`、`shield`、`boots`、`bridgeTool`；
- `Loot`：空奖励、钥匙、金币、治疗和装备；
- `Chest`：位置、奖励、打开状态、所属房间、是否完成任务；
- `Monster`：位置、血量、种类、伤害、奖励和所属房间；
- `Exit`：位置、源房间、目标房间、目标出生点、门条件和完成标记；
- `ExitKind.normal`：普通门；
- `ExitKind.lockedKey need consume`：钥匙门，可指定是否消耗钥匙；
- `ExitKind.allMonstersAndKey need consume`：清怪且持钥匙的条件门；
- `ExitKind.buttonGate button`：按钮门；
- `ExitKind.itemGate item`：装备门；
- `BridgeState`：南北、东西、全开和关闭四种桥状态。

高层环境目标 `GoalKind` 分为开箱、攻击、按钮、开关、出口、探索和等待。`Goal` 由目标类型和
可选目标位置组成。

### 3. SymbolicState

`SymbolicState` 是五个文件共用的环境状态，主要字段如下：

- 玩家：`player`、`playerCenterPx`、`room`、`facing`；
- 地图对象：`walls`、`chests`、`monsters`、`traps`、`buttons`、`switches`、`gaps`、`npcs`；
- 出口分类：`exits`、`normalExits`、`lockedExits`、`conditionalExits`；
- 桥：`bridges`、`bridgeNS`、`bridgeEW`、`bridgeState`；
- 资源与装备：`keys`、`gold`、`health`、`maxHealth`、`items`、`hasSword`、`hasShield`；
- 环境时钟：`steps`、`maxSteps`；
- 机关记录：`activated`、`pressedButtons`；
- 结构化对象：`chestObjects`、`monsterObjects`、`exitObjects`；
- 任务里程碑：`keysCollected`、`chestsOpened`、`monstersKilled`、`buttonsPressed`、
  `switchesActivated`、`roomsChanged`、`worldCompleted`。

任务目标使用累计里程碑，而不是只检查最终背包。例如消耗钥匙通过最终门后，`keys` 可以为零，
但 `keysCollected ≥ 1` 仍能证明路线确实取得过钥匙。

### 4. 感知接口

- `ColorMode`：默认、灰度、暗色、亮色、高对比和反色六种模式。
- `PixelFrame`：宽、高、通道数和像素列表。
- `ValidPixelFrame`：要求 `160 × 128 × 3`、像素数量正确且每个通道值不超过 255。
- `PerceptionSound`：合法帧经过颜色归一化和符号提取后满足外部真值关系。
- `ColorModeInvariant`：同一帧在任意两种颜色模式下提取到相同符号状态。
- `color_mode_invariant_extract_eq`：直接导出任意两种颜色模式的符号状态相等。

### 5. 地形、交互与失败状态

几何函数包括 `delta`、`nextPosition`、`nextRoom`、`facingTarget`、`inFront`、`manhattan` 和
`adjacent`。

安全谓词按强度分层：

- `inBounds`：位于 `10 × 8` 边界内；
- `activeBridges`：当前桥方向实际开放的 tile；
- `terrainPassable`：不是墙、未桥接 gap、宝箱或怪物；
- `isWalkable`：在 `terrainPassable` 上继续排除陷阱；
- `SafePosition`：环境安全后置条件；
- `exitPushAllowed`：站在门 tile 上并向房间外移动；
- `healthSafe`：血量允许主动攻击。

关键结构化前置条件：

- `canOpenChestObject`：对象存在、房间一致、未打开且位于面前；
- `canAttackObject`：对象存在、房间一致、血量大于零、位于面前且玩家有剑；
- `exitCondition`：按 `ExitKind` 检查钥匙、清怪、按钮或装备；
- `canUseExitObject`：出口存在、源房间一致、玩家站在出口上且条件成立。

状态更新函数 `openChestObjectState`、`attackMonsterObjectState` 和 `useExitObjectState` 会同步更新
轻量位置列表、结构化对象列表、资源、任务里程碑和完成标记。

失败与时钟定义：

- `DeadState`：已知血量为零；
- `TimedOut`：步数达到或超过上限；
- `FailedState := DeadState ∨ TimedOut`；
- `task5DrainDue`、`task5TimedDrainState`：Task 5 每 200 tick 的周期扣血；
- `advanceClock`：步数加一。

### 6. 一步语义和轨迹

`EnvStep` 描述轻量语义：安全移动、陷阱移动、阻挡移动、边界换房、开箱、攻击、机关、B 键和等待。

`FullEnvStep` 扩展结构化语义：

- 提升任意 `EnvStep`；
- 结构化开箱、攻击和出口；
- 按钮、旋转开关、NPC、盾牌；
- 怪物移动、怪物伤害、盾牌抵挡；
- Task 5 周期掉血、时钟推进和无即时威胁 tick。

多步关系：

- `Exec`：由 `EnvStep` 组成；
- `FullExec`：由 `FullEnvStep` 组成；
- `SafeFullExec`：每个中间状态都额外证明 `¬ FailedState`。

`safeFullExec_to_fullExec` 可以遗忘安全见证得到普通完整轨迹。`exec_append` 和
`full_exec_append` 支持轨迹拼接。

### 7. 任务目标与证书

五个公共目标的精确定义如下：

```lean
Task1Goal s :=
  s.worldCompleted = true ∧ s.keysCollected ≥ 1 ∧ s.chestsOpened ≥ 1

Task2Goal s :=
  s.worldCompleted = true ∧ s.monstersKilled ≥ 1 ∧
  s.keysCollected ≥ 1 ∧ s.chestsOpened ≥ 1

Task3Goal s :=
  s.worldCompleted = true ∧ s.roomsChanged ≥ 5 ∧
  s.monstersKilled ≥ 1 ∧ s.keysCollected ≥ 1 ∧ s.chestsOpened ≥ 1

Task4Goal s :=
  s.worldCompleted = true ∧ s.switchesActivated ≥ 2 ∧
  s.keysCollected ≥ 1 ∧ s.hasSword = true ∧
  s.monstersKilled ≥ 1 ∧ s.chestsOpened ≥ 3

Task5Goal s :=
  s.worldCompleted = true ∧ s.chestsOpened ≥ 4 ∧
  s.roomsChanged ≥ 5 ∧ s.buttonsPressed ≥ 1 ∧ s.keysCollected ≥ 1
```

`CompletedBy goal init` 表示存在 `plan` 和 `final`，满足 `FullExec init plan final` 与 `goal final`。

`TaskCertificate goal init` 同时保存：

```text
plan, final, SafeFullExec init plan final, goal final
```

`taskCertificate_completedBy` 把安全证书转换为 `CompletedBy`。

### 8. ReferenceTasks 五关公共场景

`MathLogic.Formalization.ReferenceTasks` 给出五关的有限符号场景。两条路线的任务文件直接引用这些
状态、对象、计划和轨迹定理。

| 任务 | 公共动作计划 | 覆盖机制 |
| --- | --- | --- |
| Task 1 | `[pressA, useExit]` | 开钥匙箱，通过消耗钥匙的锁门 |
| Task 2 | `[pressA, right, pressA, useExit]` | 击败怪物，移动，开钥匙箱，通过清怪加钥匙条件门 |
| Task 3 | `[useExit, pressA, useExit, pressA, useExit, useExit, useExit]` | 怪物房、钥匙房、两次返回、最终消耗钥匙锁门 |
| Task 4 | 13 个交互/出口动作 | 两次旋桥、钥匙箱、非消耗钥匙门、剑箱、守卫、最终宝箱 |
| Task 5 | 11 个交互/出口动作 | 四个宝箱、西侧怪物、按钮门、消耗钥匙门、五次换房 |

每关都有：

- `taskNInit`、若干中间状态、`taskNFinal`；
- `taskNPlan`；
- `taskN_safe_execution : SafeFullExec ...`；
- `taskN_goal : TaskNGoal taskNFinal`。

必要条件定理包括：

- `task2_exit_blocked_while_monster_alive`；
- `task3_final_exit_blocked_without_key`；
- `task4_east_gate_does_not_consume_key`；
- `task4_guardian_requires_sword`；
- `task5_south_gate_blocked_before_button`；
- `task5_east_gate_blocked_without_key`；
- `task5_drain_example_due` 和 `task5_drain_example_survives`。

### 9. 公共安全与搜索定理

环境文件还证明：

- 安全移动落点满足 `SafePosition`；
- 阻挡移动保持玩家位置；
- 开箱、攻击、奖励、伤害和时钟更新不会意外移动玩家；
- 钥匙、金币和装备奖励更新正确；
- 合法出口位于玩家当前位置，锁门可用蕴含钥匙数量足够；
- 两次 `toggleBridgeState` 回到原桥状态；
- `BoundedReachable`、`BfsFrontierComplete` 和
  `bfs_completeness_from_frontier_invariant` 给出有界 BFS 完备性接口。
## 模块二（一）：Rule-based 策略形式化与证明

### `Rule_based_Strategy.lean`

#### 1. AgentMemory 与目标合法性

`AgentMemory` 保存：

- `lastGoal`；
- `openedChests`；
- `activatedButtons`；
- `activatedSwitches`；
- `visitActivatedSwitches`；
- `usedExits`；
- `roomSteps`；
- `switchButtonCooldown`。

按钮使用跨访问记忆，旋转开关同时使用当前访问记忆；开关目标还要求 40 tick 冷却在抽象状态中归零。

`GoalAdmissible s m g` 分情况检查：

- 宝箱必须可见且未记录为打开；
- 怪物必须可见、有剑且 `healthSafe`；
- 按钮必须对应条件门、可见且未记录；
- 开关必须可见、本次访问未触发且冷却为零；
- 出口必须满足 `ExitGoalAdmissible`；
- 探索 tile 必须 `isWalkable`；
- 等待必须没有目标位置。

`ExitGoalAdmissible` 分别处理普通出口、持钥匙的锁门和前置条件已满足的条件门。
`exit_goal_admissible_mem_allExits` 证明合法出口一定属于公共 `allExits`。

#### 2. RuleGoal 与优先链

`RuleGoal s m g` 是规则选择关系，构造子覆盖：

- 延续仍合法的上一目标；
- 相邻或 planner 可达的未开宝箱；
- 相邻怪物和房间耗尽后的必要清怪；
- 条件门按钮、条件门清怪和条件出口；
- 未使用的锁门、普通门和兼容出口；
- 受访问记忆和冷却约束的旋转开关；
- 已使用出口的回退；
- 探索与等待。

`rule_goal_admissible` 对所有构造子分类证明，结论为：

```lean
RuleGoal s m g → GoalAdmissible s m g
```

最终优先级接口由 `RulePriorityContract selector` 描述：

- `admissible`：输出始终合法；
- `chestFirst`：有可达未开宝箱时选择宝箱；
- `conditionalButtonFirst`：没有宝箱且有条件门按钮时选择按钮；
- `combatGuard`：主动战斗只来自房间耗尽或条件门清怪；
- `exitGuard`：出口不能越过可达未开宝箱；
- `recoveryGuard`：有具体进度时不能探索或等待。

对应结论包括 `selector_chest_first`、`selector_cannot_wait_with_progress` 和
`priority_selector_goal_admissible`。

#### 3. 紧急战斗反射

`CombatReflex` 单独描述规划队列之前的即时安全动作：

- 面向相邻怪物且可安全攻击时按 A；
- 有盾时按 B；
- 撤退动作只能走向 `isWalkable` tile。

`combat_reflex_action_allowed` 证明三类反射都满足 `ActionAllowed`。

#### 4. Planner、Executor 与 Shield

`PositionReachable` 和 `PlannerCanReach` 是有限步安全可达规格。`PlannerStep` 保存 planner 第一动作，
并要求该动作属于移动动作且下一 tile 可走。

主要规划定理：

- `planner_can_reach_player`：当前位置零步可达；
- `planner_step_safe`：planner 的第一步安全；
- `planner_completeness_from_frontier_invariant`：frontier 完备且目标有界可达时能找到目标；
- `planner_finds_singleton_of_reachable`：单目标版本。

`ActionForGoal` 把目标转换为动作：相邻开箱/攻击按 A，按钮走到按钮格，开关在相邻时按 A，
出口在门上时向外推出，否则使用 planner；没有计划时等待。

`ActionAllowed` 允许等待、A、B、合法出门，或走向 `isWalkable` tile 的移动。

`Shielded` 对原始动作执行最终过滤：

- 非移动动作直接通过；
- 合法出门通过；
- 安全移动通过；
- 其他移动改成等待。

总安全结论：

- `action_for_goal_move_safe_or_exit`；
- `action_for_goal_allowed`；
- `shielded_move_safe_or_exit`；
- `shielded_output_allowed`；
- `shield_blocks_unsafe_movement`；
- `shielded_rule_action_safe_position_or_exit`；
- `rule_pipeline_output_allowed`。

最后一个定理覆盖 `RuleGoal -> ActionForGoal -> Shielded` 管线，证明最终动作满足 action mask 规格。

### `Rule_based_TaskProofs.lean`

该文件使用公共 `ReferenceTasks`，不定义任务环境。`emptyRuleMemory` 表示每关起始记忆。

每个检查点构造一个具体 `Goal`，再证明 `RuleGoal`：

| 任务 | 已证明的规则检查点 |
| --- | --- |
| Task 1 | 起始钥匙箱；开箱后的锁门 |
| Task 2 | 条件门所需怪物；钥匙箱；清怪取钥匙后的条件出口 |
| Task 3 | 起始普通出口；怪物房怪物；钥匙房宝箱；返回起点后的最终锁门 |
| Task 4 | 第一次旋桥；钥匙箱；东侧非消耗锁门；剑箱；第二次旋桥；守卫；最终宝箱 |
| Task 5 | 起始宝箱；西侧出口；西侧怪物；西侧宝箱；按钮；南侧条件门；南侧宝箱；东侧锁门；东侧宝箱 |

每关定义 `ruleTaskNCertificate : TaskCertificate TaskNGoal taskNInit`，直接引用公共
`taskN_safe_execution` 和 `taskN_goal`。随后由 `taskCertificate_completedBy` 得到
`rule_taskN_completed`。

`all_rule_task_certificates` 同时给出五关的 `CompletedBy` 结论。

## 模块二（二）：RL-based 策略形式化与证明

### `RL_based_Strategy.lean`

#### 1. 共享状态投影

RL 文件中的局部 `SymbolicState` 是编码器读取的定长视图。环境状态类型为：

```lean
abbrev SharedState := MathLogic.Formalization.SymbolicState
```

`ofSharedState` 投影玩家、墙、宝箱、怪物、全部出口、陷阱、按钮加开关、gap、当前活动桥、NPC、
钥匙、金币和装备。`task5ViewOfSharedState` 继续保留普通、锁门和条件出口分类。

投影定理包括：

- `ofSharedState_player`；
- `ofSharedState_inventory`；
- `ofSharedState_objects`；
- `task5ViewOfSharedState_classifies_exits`；
- `shared_walkable_projects_to_safe`：公共环境中的可走 tile 在排除 NPC 后投影为 RL 的 `safeTile`。

#### 2. Task 1-4 的七动作接口

`HighLevelAction` 的顺序和 mask 下标为：

```text
0 openChest
1 attackMonster
2 activateMechanism
3 takeNewExit
4 returnOrRevisit
5 exploreRoom
6 wait
```

`canonicalGoalForOption` 给每个 option 分配规范符号目标；`CompatibleGoal` 允许机关 option 同时表示
按钮和旋转开关。

解析与策略契约：

- `resolveFromMask`：mask 为真时返回规范目标，否则返回 `none`；
- `resolve_some_of_mask_true`、`resolve_none_of_mask_false`：两种解析结果；
- `RespectsMask policy`：策略总是选择 mask 为真的 option；
- `mask_respecting_policy_resolves`：尊重 mask 的策略一定解析为兼容目标。

#### 3. 基础 normalizedMask

`normalizedMask` 对应最终七动作后处理：

1. 宝箱或机关存在时，`prioritizedAttackAllowed` 关闭主动追怪；
2. 新出口或本地进度存在时，`prioritizedReturnAllowed` 关闭回退；
3. 任意确定进度存在时关闭探索和等待；
4. 没有确定进度但可探索时关闭等待；
5. 所有候选都为空时重新打开等待。

已证明：

- 输出长度固定为 7；
- 宝箱或机关分别压制攻击；
- 新出口或本地进度分别压制回退；
- 确定进度压制探索和等待；
- 无进度且不可探索时等待为真。

#### 4. 115 维特征编码

`allTiles` 真实枚举 8 行乘 10 列的 80 个 tile；`allTiles_length` 证明长度为 80，
`allTiles_contains` 证明任意合法自然数坐标都在枚举中。`tileLabelAt_player` 和 `task5TileLabelAt_player` 证明对象标签填充后，玩家所在 tile 会按 Python 编码器语义重置为地板。

Task 1-4 特征分块：

| 分块 | 长度 |
| --- | ---: |
| 网格 tile 标签 | 80 |
| 玩家坐标 | 2 |
| 最多四个怪物坐标 | 8 |
| 钥匙、金币、剑、盾、治疗 | 5 |
| action mask | 7 |
| 上一 option one-hot | 7 |
| 记忆计数器 | 6 |
| 合计 | 115 |

`orderedMonsters` 按“到玩家的曼哈顿距离、x、y”排序后读取前四个槽位，与 Python 的排序键一致；
`orderedMonsters_perm` 和 `orderedMonsters_length` 证明排序不会增删怪物。

`FeatureValue.Valid` 不再是恒真命题。坐标、截断资源和记忆计数器必须满足分母大于零且分子不超过
分母。`FeaturesValid` 检查列表中每一个特征；每个分块都有长度定理和合法性定理。

`encodeHighLevelState_wellFormed` 最终证明：

```lean
values.length = 115 ∧ FeaturesValid values
```

#### 5. Task 5 的九动作与 122 维编码

`Task5Action` 把出口拆成四个方向：

```text
openChest, attackMonster, activateMechanism,
exitNorth, exitEast, exitSouth, exitWest,
exploreRoom, wait
```

Task 5 特征长度为：

```text
80 + 2 + 8 + 5 + 9 + 9 + 9 = 122
```

最后 9 项记忆包括访问房间数、开箱数、击杀数、机关数、出口数、房间步数、房间 x/y 和总步数。
房间 x/y 使用 `Int`；`signedMemoryFeature` 用符号位和截断绝对值表示 `[-1, 1]` 范围内的归一化
坐标，支持西侧和北侧房间的负坐标。

`encodeTask5State_wellFormed` 同时证明长度为 122 和所有分块满足 `FeatureValue.Valid`。

#### 6. task_id 与模型接口

`TaskId` 枚举五关，`SafeInfo` 保存评测器提供的安全任务编号，`interfaceFromSafeInfo` 调用
`interfaceFor`：

| 任务 | option 数 | 输入维度 |
| --- | ---: | ---: |
| Task 1-4 | 7 | 115 |
| Task 5 | 9 | 122 |

`task1_interface` 至 `task5_interface` 逐关证明上述常数，`safeInfo_selects_exact_interface` 证明
运行时选择严格由 `taskId` 决定。

#### 7. Task 5 最终 mask

`Task5MaskContext` 保存原始 mask、已使用方向、锁门方向、条件门方向、是否持钥匙和
`attackIsProgress` 几何判定。

`task5PreferredDirections` 的顺序为：持钥匙且存在新锁门时优先锁门，否则优先条件门。
`task5NormalizedMask` 形式化最终后处理：

1. 优先方向存在时关闭其他方向；
2. 有新出口或本地资源时关闭已使用方向，阻止立即回退；
3. 宝箱或机关未完成时关闭全部出口；
4. 没有阻路怪物时宝箱先于机关，并关闭可选攻击；
5. 怪物确实阻挡可见进度时，攻击先于宝箱和机关；
6. 资源完成且出口存在时关闭无进展攻击；
7. 具体进度存在时关闭探索与等待；
8. mask 为空时打开等待。

主要定理：

- `task5_locked_directions_preferred`；
- `task5_conditional_directions_preferred_without_key`；
- `task5_nonpreferred_exit_disabled`；
- `task5_used_exit_disabled_when_frontier_exists`；
- `task5_all_exits_disabled_of_local_resource`；
- `task5_chest_precedes_mechanism_without_blocking_monster`；
- `task5_optional_attack_disabled_in_resource_room`；
- `task5_blocking_attack_precedes_local_interaction`；
- `task5_recovery_disabled_of_concrete_progress`；
- `task5_wait_fallback`。

#### 8. RL primitive shield

`PrimitiveDecision` 区分仅调整朝向的 setup 动作和普通动作。普通移动经过 `shield`：越界、墙、
陷阱、宝箱、怪物、未桥接 gap 或 NPC 会使动作变成等待。

`shielded_non_setup_move_safe` 证明：非 setup 决策经过 shield 后如果仍是移动，则目标 tile 满足
`safeTile`。
### `RL_based_TaskProofs.lean`

#### 1. 共享环境 readiness 判定

该文件把环境可执行谓词写成可计算布尔判定：

- `chestObjectReady` / `chestReady`；
- `monsterObjectReady` / `monsterReady`；
- `mechanismReady`；
- `exitConditionReady` / `exitObjectReady` / `exitReady`。

这些判定没有另设环境规则。以下定理证明它们与 `Environment.lean` 完全等价：

- `chestObjectReady_iff`、`chestReady_iff`；
- `monsterObjectReady_iff`、`monsterReady_iff`；
- `mechanismReady_iff`；
- `exitConditionReady_iff`；
- `exitObjectReady_iff`、`exitReady_iff`。

Task 5 的方向出口通过 `task5ExitMatchesDirection` 检查出口源房间与目标房间的坐标差，
`task5DirectionalExitReady` 再同时检查公共 `canUseExitObject` 条件。

#### 2. Checkpoint 的含义

`BaseCheckpoint state enabled selected` 同时要求：

1. `baseRawMask enabled` 经过 `normalizedMask` 后仍允许 `selected`；
2. `resolveFromMask` 返回 `selected` 的规范目标；
3. `baseOptionReady state selected = true`，即公共环境中存在可执行对象。

`Task5Checkpoint` 对九动作 `task5NormalizedMask` 给出同样规格。

`every_base_checkpoint_goal_compatible` 和 `every_task5_checkpoint_goal_compatible` 证明所有规范解析
目标都与其 option 兼容。`base_shared_input_wellFormed` 和 `task5_shared_input_wellFormed` 证明任意
共享状态检查点产生的编码分别满足 115/122 维规格。

#### 3. 五关 RL 检查点

| 任务 | 已证明的 RL 检查点 |
| --- | --- |
| Task 1 | 起始宝箱；开箱后的锁门 |
| Task 2 | 起始怪物；移动后的钥匙箱；条件出口 |
| Task 3 | 起始出口；怪物；钥匙箱；从钥匙房返回；返回起点；最终锁门 |
| Task 4 | 第一次开关；钥匙箱；东侧锁门；剑箱；第二次开关；守卫；最终宝箱 |
| Task 5 | 起始宝箱；西出口；阻路怪物；西宝箱；按钮；南条件门；南宝箱；北向返回；东锁门；东宝箱 |

Task 5 检查点还验证以下最终分支逻辑：

- `task5BlockingMonsterContext` 同时启用宝箱和攻击，并令 `attackIsProgress = true`，最终只保留攻击；
- `task5SouthExitContext` 把南门标为条件门优先方向；
- `task5ReturnNorthContext` 把北向出口标为已使用，在没有新进度时仍允许必要返回；
- `task5EastLockedExitContext` 在持钥匙时把东门标为锁门优先方向；
- `task5_rl_button_option_accepts_button_goal` 证明机关 option 可以解析到按钮目标语义。

所有具体检查点由 `native_decide` 对闭合符号状态计算验证；对象 readiness 的语义由上一节的 `_iff`
定理连接回公共环境谓词。

#### 4. 五关 RL 通关证书

每关定义：

```text
rlTask1Certificate
rlTask2Certificate
rlTask3Certificate
rlTask4Certificate
rlTask5Certificate
```

它们的类型都是公共 `TaskCertificate`，保存公共计划、公共最终状态、`SafeFullExec` 和目标证明。

`rl_task1_completed` 至 `rl_task5_completed` 分别给出 `CompletedBy`。`RLTaskSuite` 把五个证书保存到
一个结构中，`all_rl_tasks_completed` 同时给出五关完成结论。

## 证明结论汇总

公共环境层证明以下内容：

- 对象和资源前置条件；
- 一步与多步环境转移；
- 死亡、超时和 Task 5 周期掉血；
- 五关任务目标；
- 五条逐状态无失败轨迹。

rule-based 策略层额外证明：

- 目标选择合法；
- 优先级守卫；
- planner 第一步安全；
- executor 动作合法；
- shield 后的移动安全；
- 五关关键状态可由 `RuleGoal` 产生对应目标。

RL-based 策略层额外证明：

- 共享状态投影保持关键字段；
- 80 个网格 tile 被完整枚举；
- 115/122 维编码长度与数值范围正确；
- task_id 选择正确模型接口；
- 基础和 Task 5 最终 mask 的优先级、安全和兜底性质；
- 尊重 mask 的策略输出可解析为兼容目标；
- primitive shield 后的移动安全；
- 五关关键状态的 option 同时满足 mask、解析和环境 readiness。

## 形式化边界

Lean 证明从共享符号状态开始。像素输入边界由 `PixelFrame`、`ColorNormalizer`、
`SymbolExtractor`、`PerceptionSound` 和 `ColorModeInvariant` 描述；具体视觉实现需要满足这些契约。

RL 网络权重作为不透明函数处理。Lean 验证特征形状、特征值范围、任务接口选择、action mask、
option 到符号目标的解析、primitive shield 和经过认证的五关符号轨迹，不证明任意一组权重都一定
选择认证轨迹。

通关结论使用安全轨迹 `SafeFullExec`。轨迹中每个状态都必须满足 `¬ FailedState`，因此死亡或超时
状态不能作为通关证书。

形式化结论不包含：

- 对具体 Python 函数源码做程序提取或逐行等价证明；
- 对视觉模板识别正确性的无条件证明；
- 对 PPO 训练收敛或某个权重文件必然通关的证明；
- 对评测随机种子的概率成功率证明。

这些边界分别由感知契约、Python 单元测试、模型评测和 rollout 记录补充。

## 检查方法

在项目根目录执行完整构建：

```powershell
lake build formalization
```

逐文件检查：

```powershell
lake env lean .\formalization\Environment.lean
lake env lean .\formalization\Rule_based_Strategy.lean
lake env lean .\formalization\Rule_based_TaskProofs.lean
lake env lean .\formalization\RL_based_Strategy.lean
lake env lean .\formalization\RL_based_TaskProofs.lean
```

检查未完成证明占位：

```powershell
rg -n "\b(sorry|admit|axiom)\b" .\formalization -g "*.lean"
```

检查五关证书和总完成定理：

```powershell
rg -n "TaskCertificate|all_rule_task_certificates|all_rl_tasks_completed" `
  .\formalization\Rule_based_TaskProofs.lean `
  .\formalization\RL_based_TaskProofs.lean
```

有效结果应满足：

1. `lake build formalization` 退出码为 0；
2. 五个逐文件 Lean 命令均无 error；
3. `sorry|admit|axiom` 扫描无匹配；
4. 两条路线都能找到 Task 1-5 的 `TaskCertificate` 和总完成定理。