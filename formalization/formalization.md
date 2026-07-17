# Rule-based 与 RL-based Agent 的 Lean 形式化文件说明

`formalization/` 从视觉抽取后的符号状态开始，对公共环境以及两条 Agent 路线分别进行形式化。
按照课程大作业的证明内容，文档分为三个模块：

- **模块一：公共环境形式化**，说明状态、对象、动作、转移、失败条件、任务目标和安全轨迹；
- **模块二：策略形式化与证明**，分别说明 Rule-based 与 RL-based 的决策接口、安全约束和五关证书；
- **模块三：强化性质证明**，说明轨迹闭包、进度单调性、mask 可靠性、shield 性质和可验证搜索。

## 文件组成与依赖

`formalization/` 包含六个 Lean 文件：

| 文件 | 内容 |
| --- | --- |
| `Environment.lean` | 公共符号环境、对象语义、执行轨迹、五关目标和公共参考场景 |
| `Rule_based_Strategy.lean` | 规则策略的记忆、优先级、规划器、执行器和安全屏蔽契约 |
| `Rule_based_TaskProofs.lean` | 规则路线在 Task 1-5 关键检查点上的目标证明和通关证书 |
| `RL_based_Strategy.lean` | RL 特征编码、option 解析、基础与 Task 5 mask、primitive shield |
| `RL_based_TaskProofs.lean` | RL 路线在 Task 1-5 关键检查点上的 mask 证明和通关证书 |
| `Additional_Proofs.lean` | 两条路线共用的强化不变量、接口定理以及可靠且完备的有界搜索证明 |

依赖关系为：

```text
formalization.Environment
├── formalization.Rule_based_Strategy
│   └── formalization.Rule_based_TaskProofs
└── formalization.RL_based_Strategy
    └── formalization.RL_based_TaskProofs

formalization.Additional_Proofs
├── imports formalization.Rule_based_TaskProofs
└── imports formalization.RL_based_TaskProofs
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
- `Exit`：位置、源房间、目标房间、目标出生点、门条件、进入后显现的按钮和完成标记；
- `ExitKind.normal`：普通门；
- `ExitKind.lockedKey need consume`：钥匙门，可指定是否消耗钥匙；
- `ExitKind.allMonstersAndKey need consume`：清怪且持钥匙的条件门；
- `ExitKind.buttonGate button`：按钮门；
- `ExitKind.itemGate item`：装备门；
- `BridgeState`：南北、东西、全开和关闭四种桥状态。

高层环境目标 `GoalKind` 分为开箱、攻击、按钮、开关、出口、探索和等待。`Goal` 由目标类型和
可选目标位置组成。

### 3. SymbolicState

`SymbolicState` 是全部文件共用的环境状态，主要字段如下：

- 玩家：`player`、`playerCenterPx`、`room`、`facing`；
- 地图对象：`walls`、`chests`、`monsters`、`traps`、`buttons`、`switches`、`gaps`、`npcs`；`buttonLocations` 与 `switchLocations` 在多房间参考状态中记录机关所属房间；
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
轻量位置列表、结构化对象列表、资源、任务里程碑和完成标记。`enterPositionState` 是移动与出口出生
共同使用的位置更新：进入当前房间的未触发按钮 tile 时立即更新 `pressedButtons` 和
`buttonsPressed`，不需要再执行 `pressA`；重复进入同一按钮不会重复计数。

失败与时钟定义：

- `DeadState`：已知血量为零；
- `TimedOut`：步数达到或超过上限；
- `FailedState := DeadState ∨ TimedOut`；
- `task5DrainDue`、`task5TimedDrainState`：Task 5 每 200 tick 的周期扣血；
- `advanceClock`：步数加一。

### 6. 一步语义和轨迹

`EnvStep` 描述轻量语义：安全移动、陷阱移动、阻挡移动、边界换房、开箱、攻击、按 A 开关、B 键和等待。安全移动和陷阱移动都通过 `enterPositionState` 处理站上按钮。

`FullEnvStep` 扩展结构化语义：

- 提升任意 `EnvStep`；
- 结构化开箱、攻击和出口；
- 站上自动触发的按钮、按 A 旋转开关、NPC、盾牌；
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
| Task 5 | 10 个交互/出口动作 | 四个宝箱、西侧怪物、自动踩下按钮、按钮门、消耗钥匙门、五次换房 |

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

具体选择器 `ruleBasedChooseGoal` 直接编码 `strategy.py` 的候选链。`policyReachablePositions` 在
10×8 棋盘上累计扩展 80 层安全后继，`policyCanReachAny` 用于筛除 planner 不可达候选；
`currentRoomChestPositions`、`currentRoomMonsterPositions`、`currentRoomExitObjects` 和机关可见性函数
保证全局参考状态不会把其他房间对象送入当前选择器。`exitVisibleToSelector` 与
`selectorVisibleExitPositions` 刻画开关和出口重叠时的感知遮蔽：未触发时只暴露开关，触发后
出口才成为候选。`firstAdmissibleGoal` 返回 `VerifiedRuleGoal`，即目标值连同
`GoalAdmissible` 证明。

`chooseNewVerifiedRuleGoal` 的分支顺序为宝箱、必要战斗、条件门按钮、条件门怪物、
新条件出口、新锁门、新普通门、开关、三类已用出口、探索和等待；
`continuingGoalChoice` 在其之前实现 sticky goal。`ruleBasedChooseGoal_priorityContract` 是
`RulePriorityContract ruleBasedChooseGoal` 的具体实例，不再要求调用者假设任意 selector 满足契约。
契约的 `implementation` 字段固定实际实现，`stickyFirst` 与 `restartPriority` 分别刻画延续和重新规划。

`ruleBasedChooseGoal_admissible`、`concrete_selector_chest_first`、
`concrete_selector_conditional_button_first` 和 `priority_selector_goal_admissible` 给出合法性及关键优先级结论。

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

`ActionForGoal` 把目标转换为动作：相邻开箱/攻击按 A，按钮走到按钮格，开关在相邻或已处于交互姿态时按 A，
出口可产生边界推出动作或结构化 `useExit` 宏动作；没有计划时等待。

`ActionAllowed` 允许等待、A、B、结构化 `useExit`、合法边界出门，或走向 `isWalkable` tile 的移动。

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
`updateRuleMemory` 进一步确定更新 sticky goal、宝箱、自动按钮、开关、出口、房间步数和冷却。
`RulePolicyStep.planned` 同时要求
`ruleBasedChooseGoal -> ActionForGoal -> Shielded -> FullEnvStep -> updateRuleMemory`；
`RulePolicyStep.reflex` 刻画 Python 在高层选择之前执行的紧急战斗。
`RulePolicyExec` 将上述单步关系归纳扩展到完整动作列表，`rulePolicyExec_to_fullExec` 可投影回公共环境轨迹。

### `Rule_based_TaskProofs.lean`

该文件使用公共 `ReferenceTasks`，不定义任务环境。`emptyRuleMemory` 表示每关起始记忆。

每个检查点构造一个具体 `Goal`，再证明 `RuleGoal`：

| 任务 | 已证明的规则检查点 |
| --- | --- |
| Task 1 | 起始钥匙箱；开箱后的锁门 |
| Task 2 | 条件门所需怪物；钥匙箱；清怪取钥匙后的条件出口 |
| Task 3 | 起始普通出口；怪物房怪物；钥匙房宝箱；返回起点后的最终锁门 |
| Task 4 | 第一次旋桥；钥匙箱；东侧非消耗锁门；剑箱；第二次旋桥；守卫；最终宝箱 |
| Task 5 | 起始宝箱；西侧出口；西侧怪物；西侧宝箱；返回中心自动踩按钮；南侧条件门；南侧宝箱；东侧锁门；东侧宝箱 |

旧的纯环境包装保留为 `ruleTaskNEnvironmentCertificate : TaskCertificate ...`。正式
`ruleTaskNCertificate : RuleTaskCertificate ...` 在公共计划、最终状态、安全执行和目标证明之外，
增加 `initialMemory`、`finalMemory` 与 `generated : RulePolicyExec ...`。Task 1-5 的
`taskN_rule_policy_execution` 逐步给出实际选择器等式、executor、shield、环境转移和记忆更新；
相邻怪物步骤明确使用 `CombatReflex`。`all_rule_tasks_policy_generated` 汇总五条策略生成证明，
`CompletedByRulePolicy` 把安全轨迹、目标成立和同一计划的 `RulePolicyExec` 见证合成一个命题；
`rule_task1_completed` 至 `rule_task5_completed` 以及 `all_rule_task_certificates`
均给出这一强化完成性。纯环境存在性由 `rule_taskN_environment_completed` 单独保留。

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
| Task 5 | 起始宝箱；西出口；阻路怪物；西宝箱；返回中心自动踩按钮；南条件门；南宝箱；北向返回；东锁门；东宝箱 |

Task 5 检查点还验证以下最终分支逻辑：

- `task5BlockingMonsterContext` 同时启用宝箱和攻击，并令 `attackIsProgress = true`，最终只保留攻击；
- `task5SouthExitContext` 把南门标为条件门优先方向；
- `task5ReturnNorthContext` 把北向出口标为已使用，在没有新进度时仍允许必要返回；
- `task5EastLockedExitContext` 在持钥匙时把东门标为锁门优先方向；
- `task5_rl_button_triggered_by_entry` 证明返回中心的出口转移已经记录按钮；下一检查点直接选择南门，不消耗机关动作。

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

## 模块三：强化性质证明

本模块对应 `Additional_Proofs.lean`。该文件同时导入两条路线的任务证明，并在已有环境、策略接口和
通关证书之上补充可复用的整体性质。

### 1. 安全轨迹闭包

| 定理 | 结论 |
| --- | --- |
| `safeFullExec_final_not_failed` | 任意 `SafeFullExec` 的最终状态都不满足 `FailedState` |
| `safeFullExec_append` | 两段首尾相接的安全完整轨迹可以拼接，结果仍是 `SafeFullExec` |

`safeFullExec_append` 使分段证明可以组合成整条路线；中间状态由第一段终点和第二段起点的类型统一。

### 2. 里程碑和世界完成状态单调

`ProgressLe before after` 同时比较六个累计字段：`keysCollected`、`chestsOpened`、
`monstersKilled`、`buttonsPressed`、`switchesActivated` 和 `roomsChanged`。当前钥匙数 `keys`
没有放入该关系，因为钥匙可以被锁门合法消耗。

| 定理组 | 结论 |
| --- | --- |
| `progressLe_refl`, `progressLe_trans` | `ProgressLe` 具有自反性和传递性 |
| `envStep_progressLe`, `fullEnvStep_progressLe` | 轻量一步和完整一步都不会降低累计里程碑 |
| `applyLoot_progressLe`, `openChestObjectState_progressLe`, `attackMonsterObjectState_progressLe` | 拾取、开箱和攻击对象不会降低累计里程碑 |
| `takeDamage_progressLe`, `task5TimedDrainState_progressLe` | 受伤和 Task 5 周期掉血不改变累计里程碑 |
| `fullExec_progressLe`, `safeFullExec_progressLe` | 完整多步轨迹及安全轨迹保持累计进度单调 |

`WorldCompletedMonotone before after` 表示一旦 `before.worldCompleted = true`，则
`after.worldCompleted = true`。`worldCompletedMonotone_refl`、`worldCompletedMonotone_trans`、
`envStep_worldCompletedMonotone`、`fullEnvStep_worldCompletedMonotone`、
`fullExec_worldCompletedMonotone` 和 `safeFullExec_worldCompletedMonotone` 把这一性质从一步提升到整条轨迹。

### 3. Action mask 非空性、保守性和可靠性

`BaseMaskHasEnabled` 与 `Task5MaskHasEnabled` 分别枚举七动作和九动作接口中的所有 option。

| 定理组 | 结论 |
| --- | --- |
| `normalizedMask_has_enabled`, `normalizedMask_enabled_exists` | 任意基础原始 mask 经过优先级归一化后至少保留一个可选 option |
| `task5NormalizedMask_has_enabled`, `task5NormalizedMask_enabled_exists` | 任意 Task 5 上下文的最终九位 mask 至少有一个可选 option |
| `normalizedMask_nonwait_conservative` | 最终基础 mask 中被启用的非等待 option 在原始 mask 中也已启用 |
| `task5NormalizedMask_nonwait_conservative` | Task 5 最终 mask 不会凭空创建非等待 option |

等待是唯一允许由兜底逻辑重新启用的动作，因此保守性定理显式排除 `wait`。

`BaseRawMaskSound state raw` 和 `Task5RawMaskSound state context` 规定：原始 mask 中为真的 option
必须满足公共环境 readiness。由此证明：

- `normalizedMask_sound` 与 `task5NormalizedMask_sound`：优先级过滤后的最终 mask 仍然可靠；
- `mask_respecting_policy_selects_ready` 与 `task5_mask_respecting_policy_selects_ready`：尊重 mask 的策略只能选到 ready option；
- `mask_respecting_policy_ready_resolution` 与 `task5_mask_respecting_policy_ready_resolution`：策略输出同时具有 resolver 结果、目标兼容性和环境 readiness。

这些结论连接了“环境生成原始 mask”“优先级过滤”“模型选 option”“解析成符号目标”四个阶段。

### 4. 两类 safety shield 的强化性质

RL primitive shield 新增三个代数和安全定理：

- `shield_preserves_safe_move`：原始安全移动保持不变；
- `shield_idempotent`：对同一状态重复应用 shield 不会继续改变结果；
- `shield_move_output_safe`：shield 若最终仍输出移动，则目标 tile 满足 `safeTile`。

Rule-based shield 使用 `AgentControllableAction` 限定 agent 可直接产生的等待、A/B 交互和四向移动。
`shielded_total` 证明这些输入总有输出，`shielded_deterministic` 证明输出唯一，
`shielded_exists_unique` 把两者组合为存在且唯一的输出结论。`exitPushAllowed_not_walkable`
说明合法边界出门推动作与普通 `isWalkable` 分支互斥。

### 5. 感知、出口和路线证书接口

| 定理组 | 结论 |
| --- | --- |
| `color_mode_base_features_invariant`, `color_mode_task5_features_invariant` | 在 `ColorModeInvariant` 契约下，不同颜色模式产生完全相同的基础/Task 5 特征 |
| `color_mode_base_policy_output_invariant`, `color_mode_task5_policy_output_invariant` | 相同特征和 mask 进一步推出策略 option 输出相同 |
| `buttonGate_exit_requires_pressed` | 可用按钮门要求指定按钮已被按下 |
| `allMonstersAndKey_exit_requires_resources` | 清怪钥匙门要求钥匙数量满足门槛且当前怪物列表为空 |
| `itemGate_exit_requires_item` | 装备门可用时，背包必须包含对应装备 |
| `fullEnvStep_useExit_has_usable_exit` | 任意 `useExit` 完整转移都能反推出一个满足 `canUseExitObject` 的出口对象 |

`CertificatesShareTrace` 比较两份公共 `TaskCertificate` 的 `plan` 和 `final`。Rule 强化证书先通过 `toTaskCertificate` 投影；五个
`taskN_route_certificates_share_trace` 以及 `all_route_certificates_share_trace` 证明 Rule-based 与
RL-based 的 Task 1-5 证书使用相同公共动作轨迹并到达相同最终状态。

### 6. 可计算搜索的可靠性和完备性

`safeActionsFrom` 使用可判定的 `isWalkable` 过滤四向移动，`safeSuccessors` 计算某位置的一步安全后继。
`breadthFrontier state depth` 对自然数 `depth` 做结构递归，枚举从玩家位置恰好执行 `depth` 步
安全移动后能够到达的位置，因此构造过程必然终止。

核心等价定理为：

```lean
target ∈ breadthFrontier state depth ↔ PositionReachable state depth target
```

对应的 Lean 名称是 `mem_breadthFrontier_iff_positionReachable`。它直接导出：

- `breadthFrontier_complete`：所有恰好 `depth` 步可达的位置都在 frontier 中；
- `breadthFrontier_sound`：frontier 中每个位置都确实恰好 `depth` 步可达；
- `breadth_search_complete`：目标集合中存在可达位置时，搜索必然发现目标；
- `breadth_search_sound`：搜索报告发现目标时，确实存在可达目标；
- `breadth_search_sound_and_complete`：搜索发现与 `PlannerGoalReachable` 等价。

`breadthFindsGoal` 是可直接计算的 Bool 判定器，`breadthFindsGoal_eq_true_iff` 把其返回值连接到
`PlannerGoalReachable`。`SafeMovePlan` 保存逐步安全的动作计划，
`positionReachable_has_safeMovePlan` 从可达证明提取等长计划，`safeMovePlan_exec` 则证明该计划
能按公共 `Exec` 语义执行到目标位置。

`VerifiedSearchResult` 把计划、目标成员关系和安全见证封装在同一结构中。
`verifiedSearchResult_sound` 证明任何结果都可执行且到达目标；
`breadth_found_has_verified_plan` 从搜索命中构造指定深度的结果证书；
`verified_search_result_iff_reachable` 给出“存在可验证搜索结果”与“存在某个深度的可达目标”等价。

这里的完备性严格针对固定符号状态、固定深度和 `PositionReachable` 定义的安全移动图，
不等同于任意地图上的策略通关完备性，也不涉及 PPO 训练收敛。

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

强化性质层进一步证明：

- 安全完整轨迹可拼接，最终状态必然非失败；
- 六个累计任务里程碑和 `worldCompleted` 沿完整执行保持单调；
- 基础与 Task 5 最终 mask 始终非空，非等待位不会脱离原始 mask 被创建；
- 原始 mask 可靠时，最终 mask 以及尊重 mask 的策略选择都满足环境 readiness；
- RL shield 保持安全移动且幂等，Rule-based shield 对可控动作存在唯一输出；
- 颜色模式不变性可提升到特征与策略输出；结构化出口转移满足门的必要前置条件；
- 两条路线的五关证书共享相同计划和最终状态；
- 固定深度安全移动搜索相对 `PositionReachable` 可靠且完备，并能提取可执行计划证书。

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
lake env lean .\formalization\Additional_Proofs.lean
```

检查未完成证明占位：

```powershell
rg -n "\b(sorry|admit|axiom)\b" .\formalization -g "*.lean"
```

检查五关证书和总完成定理：

```powershell
rg -n "RuleTaskCertificate|all_rule_tasks_policy_generated|all_rule_task_certificates|all_rl_tasks_completed" `
  .\formalization\Rule_based_TaskProofs.lean `
  .\formalization\RL_based_TaskProofs.lean
```

有效结果应满足：

1. `lake build formalization` 退出码为 0；
2. 六个逐文件 Lean 命令均无 error；
3. `sorry|admit|axiom` 扫描无匹配；
4. Rule 路线能找到五个 `RuleTaskCertificate` 及策略生成总定理，RL 路线能找到五个 `TaskCertificate` 和总完成定理。
