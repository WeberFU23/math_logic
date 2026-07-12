# 规则版 Agent 的 Lean 形式化文件说明

本目录放置规则版 Agent 的 Lean 形式化文件：

- `Environment.lean`
- `Strategy.lean`
- `TaskProofs.lean`

这三个文件按依赖关系拆分：

1. `Environment.lean` 先形式化环境本身；
2. `Strategy.lean` 在环境语义之上形式化规则策略的可验证层；
3. `TaskProofs.lean` 把执行轨迹和五个任务目标连接起来。

这种拆分对应课程评分细则中的两个主要 Lean 模块：

- 模块一：环境形式化；
- 模块二：策略形式化与证明。

环境形式化描述的是游戏规则本身，理论上不依赖具体策略；策略形式化则依赖环境层已经给出的状态、动作、转移和目标谓词。这样做的好处是：当规则策略更新时，通常只需要修改 `Strategy.lean` 或 `TaskProofs.lean`，而不需要重写环境语义。

## 模块一：环境形式化

模块一主要由 `Environment.lean` 完成。它负责把 Python 模拟器中的对象、属性、状态转移函数与交互规则，抽象为 Lean 中的数据类型、函数、关系和谓词。

模块一覆盖评分细则中的要求：

- 状态定义；
- 动作定义；
- 对象定义；
- 目标谓词；
- 移动、撞墙、踩陷阱、开箱、攻击、按钮、开关、出口等动作转移语义；
- 关卡关键机制；
- 基本安全性和不变量证明。

### 1. 基础坐标与常量

`Environment.lean` 首先定义游戏网格和房间坐标：

- `Position`：房间内部 tile 坐标；
- `RoomCoord`：多房间地图中的房间坐标；
- `GlobalPosition`：房间坐标和房间内坐标的组合；
- `boardWidth`：单房间宽度，当前为 `10`；
- `boardHeight`：单房间高度，当前为 `8`；
- `task5DrainInterval`：综合任务中的周期掉血间隔，形式化为 `180`。

其中 `GlobalPosition` 用于刻画跨房间记忆，例如已打开宝箱、已触发机关、已使用出口等。

### 2. 环境对象和动作

环境对象相关定义包括：

- `ObjectKind`：枚举墙、宝箱、怪物、陷阱、按钮、开关、桥、gap、出口和 NPC；
- `Item`：枚举钥匙、剑、盾、金币等物品；
- `Loot`：枚举宝箱或怪物掉落奖励；
- `MonsterKind`：区分追踪、巡逻、伏击等怪物类型；
- `BridgeState`：抽象桥的连通状态；
- `ExitKind`：区分普通出口、锁门出口、按钮门等出口条件；
- `Chest`：结构化宝箱，包含位置和奖励；
- `Monster`：结构化怪物，包含位置、类型、血量、伤害等；
- `Exit`：结构化出口，包含位置、目标房间、目标位置和出口类型。

动作和目标相关定义包括：

- `Direction`：玩家朝向；
- `Action`：等待、上下左右移动、A 键、B 键，以及扩展环境动作 `useExit` 和 `envTick`；
- `GoalKind`：高层目标类型，包括开箱、攻击怪物、激活机关、走向出口、探索和等待；
- `Goal`：高层目标，由目标类型和可选目标位置组成。

辅助函数包括：

- `actionOfDirection`：将方向转换为动作；
- `directionOfAction`：将移动动作转换为方向；
- `movementActions`：四个移动动作的列表；
- `delta`：动作对应的位置变化；
- `nextPosition`：执行动作后的 tile 位置；
- `nextRoom`：出门后房间坐标变化；
- `facingTarget`：玩家面向的 tile；
- `inFront`：目标是否在玩家面前；
- `absDiff`、`manhattan`、`adjacent`：距离和相邻关系。

相关基础定理：

- `actionOfDirection_mem_movementActions`：任意方向对应的动作都属于 `movementActions`。

### 3. 核心环境状态

`SymbolicState` 是环境形式化的核心状态结构，对应 Python 符号层状态。它包含：

- `player`：玩家 tile 坐标；
- `playerCenterPx`：玩家像素中心，用于说明像素对齐信息；
- `room`：当前房间坐标；
- `walls`：墙；
- `chests`：宝箱位置；
- `monsters`：怪物位置；
- `exits`：早期兼容出口字段；
- `normalExits`：普通出口；
- `lockedExits`：锁门出口；
- `conditionalExits`：条件门出口；
- `traps`：陷阱；
- `buttons`：按钮；
- `switches`：开关；
- `bridges`、`bridgeNS`、`bridgeEW`、`bridgeState`：桥和桥状态；
- `gaps`：深渊或不可直接通过的 gap；
- `npcs`：NPC；
- `keys`、`gold`：资源；
- `health`、`maxHealth`：生命值；
- `steps`、`maxSteps`：步数和步数上限；
- `facing`：朝向；
- `items`：背包；
- `hasSword`、`hasShield`、`shieldUp`：装备和盾牌状态；
- `activated`：已触发机关；
- `pressedButtons`：已踩按钮；
- `chestObjects`、`monsterObjects`、`exitObjects`：结构化对象列表。

出口集合由：

- `allExits`

统一给出。它把 `exits`、`normalExits`、`lockedExits`、`conditionalExits` 合并，供策略、shield 和出门语义统一使用。

### 4. 地形、安全和出口谓词

环境谓词包括：

- `inBounds`：位置是否在 `10 × 8` 房间范围内；
- `activeBridges`：当前桥状态下可通行的桥；
- `terrainPassable`：地形层面是否可通过；
- `isWalkable`：策略可以主动走向的安全可通行位置；
- `SafePosition`：用于定理结论的安全位置谓词；
- `isDoorExit`：位置是否是房间边界上的门 tile；
- `exitPushAllowed`：玩家站在出口 tile 上并向房间外移动；
- `healthSafe`：当前血量是否允许主动近战；
- `hasItem`、`hasKey`：背包和钥匙谓词。

这里区分了 `terrainPassable`、`isWalkable` 和 `SafePosition`：

- `terrainPassable` 表示地形可以进入；
- `isWalkable` 进一步排除陷阱；
- `SafePosition` 是安全性证明中使用的后置条件。

### 5. 生命值、奖励和结构化交互函数

生命值和奖励相关函数包括：

- `damageHealth`：踩陷阱时扣血；
- `takeDamage`：受到指定伤害；
- `task5DrainDue`：周期掉血触发条件；
- `task5DrainDue_decidable`：周期掉血条件可判定；
- `task5TimedDrainState`：周期掉血状态更新；
- `healHealth`：回血且不超过 `maxHealth`；
- `AliveState`、`DeadState`、`TimedOut`、`FailedState`：存活、死亡、超时和失败状态；
- `advanceClock`：环境 step 计数推进；
- `lootKeys`、`lootGold`：读取奖励中的钥匙和金币数量；
- `applyLoot`：应用奖励。

结构化交互函数包括：

- `removeChestObjectAt`：删除指定位置宝箱；
- `openChestObjectState`：结构化开箱状态更新；
- `canOpenChestObject`：能否打开结构化宝箱；
- `damageMonsterObjectAt`：伤害指定位置怪物；
- `canAttackObject`：能否攻击结构化怪物；
- `attackMonsterObjectState`：结构化攻击状态更新；
- `canTalkNpc`：能否与 NPC 对话；
- `monsterThreatens`：怪物是否威胁玩家；
- `monsterCanOccupy`：怪物能否占据某个位置；
- `monsterMoveAllowed`：怪物移动是否合法；
- `moveMonsterObjectAt`：移动结构化怪物；
- `monsterDamageState`：怪物造成伤害；
- `shieldBlockState`：盾牌抵挡后的状态；
- `toggleBridgeState`：桥状态切换；
- `exitCondition`：结构化出口条件；
- `canUseExitObject`：结构化出口是否可用；
- `keysAfterExit`：通过锁门后钥匙变化；
- `useExitObjectState`：结构化出口跳转状态更新；
- `TerminalState`：目标或失败导致的终止状态。

### 6. 一步转移语义

轻量一步转移由：

- `EnvStep`

定义。它包含以下构造子：

- `moveSafe`：安全移动；
- `moveTrap`：踩陷阱并扣血；
- `moveBlocked`：目标地形不可通过时保持原地；
- `exitRoom`：站在出口并向外移动，房间坐标改变；
- `openChest`：相邻开箱并获得钥匙；
- `attackMonster`：有剑且血量安全时攻击相邻怪物；
- `activateSwitch`：激活按钮或开关；
- `pressB`：B 键动作；
- `wait`：等待。

完整一步转移由：

- `FullEnvStep`

定义。它包含：

- `basic`：任意 `EnvStep` 都可提升为 `FullEnvStep`；
- `openChestObject`：结构化开箱；
- `attackMonsterObject`：结构化攻击；
- `pressButton`：按钮记录；
- `pressSwitch`：开关切换桥；
- `talkNpc`：NPC 对话；
- `pressShield`：有盾时举盾；
- `pressShieldNoItem`：无盾时 B 键无效；
- `useExitObject`：结构化出口；
- `monsterDamage`：怪物造成伤害；
- `monsterDamageBlocked`：盾牌抵挡怪物伤害；
- `monsterMove`：怪物移动；
- `task5TimedDrain`：周期掉血；
- `advanceClock`：环境时钟推进；
- `envNoImmediateThreat`：无即时威胁时环境 tick 无变化。

多步轨迹由：

- `Exec`
- `FullExec`

定义，用于表示动作列表执行后的可达状态。

### 7. 任务目标谓词

五个任务目标由以下谓词抽象：

- `Task1Goal`：拥有钥匙并到达出口；
- `Task2Goal`：怪物清空、拥有钥匙并到达出口；
- `Task3Goal`：跨房间拿到钥匙并回到出口；
- `Task4Goal`：拥有剑、清除关键怪物并保有通关资源；
- `Task5Goal`：综合任务中所有仍可见宝箱已被处理。

这些目标谓词并不试图复刻奖励函数的每个数值细节，而是保留与任务完成有关的符号条件。

### 8. 环境性质证明

环境层已经证明的性质包括：

- `walkable_terrain_passable`：`isWalkable` 蕴含 `terrainPassable`；
- `walkable_is_safe_position`：`isWalkable` 蕴含 `SafePosition`；
- `move_safe_player_eq`：若 `EnvStep` 使用安全移动，玩家位置等于 `nextPosition`；
- `move_blocked_player_eq`：被阻挡移动保持玩家位置不变；
- `safe_move_preserves_safe_position`：安全移动后的目标满足 `SafePosition`；
- `open_chest_increases_keys`：开箱使钥匙数加一；
- `attack_monster_removes_target`：攻击移除目标怪物；
- `activate_switch_records`：激活机关会记录位置；
- `env_step_keys_monotone`：轻量一步转移不会减少钥匙；
- `exec_keys_monotone`：轻量多步执行不会减少钥匙；
- `exec_append`：`Exec` 轨迹可拼接；
- `env_step_is_full_step`：`EnvStep` 可提升为 `FullEnvStep`；
- `full_exec_append`：`FullExec` 轨迹可拼接；
- `takeDamage_preserves_player`：受伤不移动玩家；
- `task5TimedDrainState_preserves_player`：周期掉血不移动玩家；
- `takeDamage_some_health_eq`：已知血量下扣血结果正确；
- `healHealth_preserves_player`：回血不移动玩家；
- `healHealth_some_le_maxHealth`：回血不超过最大血量；
- `advanceClock_steps_eq`：环境时钟使步数加一；
- `advanceClock_preserves_player`：环境时钟不移动玩家；
- `apply_key_loot_keys`：钥匙奖励增加钥匙；
- `apply_gold_loot_gold`：金币奖励增加金币；
- `apply_item_loot_items`：物品奖励加入背包；
- `applyLoot_preserves_player`：奖励不移动玩家；
- `openChestObjectState_preserves_player`：结构化开箱不移动玩家；
- `attackMonsterObjectState_preserves_player`：结构化攻击不移动玩家；
- `canTalkNpc_listed`：可对话 NPC 必在 NPC 列表；
- `canTalkNpc_in_front`：可对话 NPC 在玩家面前；
- `monsterThreatens_listed`：威胁玩家的怪物在怪物列表中；
- `monsterThreatens_alive`：威胁玩家的怪物生命值大于 0；
- `monsterMoveAllowed_target_inBounds`：怪物合法移动目标在界内；
- `monsterMoveAllowed_target_not_wall`：怪物合法移动目标不是墙；
- `monsterDamageState_preserves_player`：怪物伤害不移动玩家；
- `shieldBlockState_shieldUp_false`：盾牌抵挡后取消举盾状态；
- `shieldBlockState_preserves_player`：盾牌抵挡不移动玩家；
- `pressButton_records_player`：按钮触发记录当前位置；
- `pressButton_preserves_player`：按钮触发不移动玩家；
- `toggleBridge_twice`：桥状态切换两次回到原状态；
- `pressSwitch_preserves_player`：开关不移动玩家；
- `canUseExitObject_listed`：可用出口在出口对象列表中；
- `canUseExitObject_at_player`：可用出口位于玩家当前位置；
- `useExitObject_room_eq`：结构化出口更新房间坐标；
- `useExitObject_player_eq`：结构化出口更新玩家位置；
- `lockedExit_condition_implies_enough_keys`：锁门出口可用蕴含钥匙足够；
- `terminal_of_goal`：目标满足推出终止；
- `terminal_of_failed`：失败推出终止；
- `failed_of_dead`：死亡推出失败；
- `failed_of_timedOut`：超时推出失败。

环境层还定义了 BFS 抽象接口：

- `BoundedReachable`
- `BoundedGoalReachable`
- `BfsFrontierComplete`
- `BfsFindsGoal`

并证明：

- `bfs_completeness_from_frontier_invariant`

该定理表达：如果 frontier 覆盖所有有界可达状态，并且目标在该有界范围内可达，则 frontier 中一定能发现目标。

## 模块二：策略形式化与证明

模块二主要由 `Strategy.lean` 和 `TaskProofs.lean` 完成。

`Strategy.lean` 负责规则策略、planner、executor 和 shield 的可验证层；`TaskProofs.lean` 负责把执行轨迹与任务目标连接起来。

模块二覆盖评分细则中的要求：

- 形式化 planner / 搜索逻辑；
- 形式化 action mask；
- 形式化策略目标选择；
- 证明策略输出合法、安全；
- 证明安全过滤后的动作满足规范；
- 给出成功执行轨迹满足目标的证明接口；
- 给出搜索完备性的抽象证明。

### 1. 策略记忆和目标合法性

`Strategy.lean` 定义：

- `AgentMemory`：策略证明使用的记忆字段；
- `noUnopenedChests`：没有未打开宝箱；
- `noUnusedMechanisms`：没有未使用机关；
- `noVisibleChests`：当前没有可见宝箱；
- `noVisibleSwitches`：当前没有可见开关；
- `noVisibleButtons`：当前没有可见按钮；
- `noUnusedDoorExits`：没有未使用门出口；
- `roomExhaustedBeforeCombat`：清怪前房间已经处理完更高优先级目标；
- `conditionalDoorReady`：条件门的按钮和怪物前置条件已满足；
- `ExitGoalAdmissible`：出口目标合法性；
- `GoalAdmissible`：高层目标合法性。

相关定理：

- `exit_goal_admissible_mem_allExits`：满足 `ExitGoalAdmissible` 的出口一定属于 `allExits`。

### 2. 规则目标选择关系

高层策略选择由：

- `RuleGoal`

形式化。它是一个归纳关系，表示策略在状态 `s` 和记忆 `m` 下可以选择目标 `g`。

`RuleGoal` 的构造子包括：

- `sticky`：继续上一目标；
- `adjacentChest`：相邻宝箱；
- `reachableChest`：可达宝箱；
- `adjacentMonster`：相邻且可安全攻击的怪物；
- `requiredMonster`：房间耗尽后必须清理的怪物；
- `buttonForConditionalDoor`：条件门所需按钮；
- `conditionalMonster`：条件门前置清怪；
- `unusedConditionalExit`：未使用条件门出口；
- `unusedLockedExit`：持有钥匙时的未使用锁门出口；
- `unusedLegacyExit`：兼容早期字段的未使用出口；
- `unusedNormalExit`：未使用普通出口；
- `switchMechanism`：开关；
- `usedLegacyExitFallback`：兼容早期字段的已用出口 fallback；
- `usedNormalExitFallback`：已用普通出口 fallback；
- `usedConditionalExitFallback`：已用条件门 fallback；
- `usedLockedExitFallback`：已用锁门 fallback；
- `explore`：探索；
- `wait`：等待。

核心定理：

- `rule_goal_admissible`

表示：只要 `RuleGoal s m g` 成立，则 `GoalAdmissible s m g` 成立。也就是说，规则策略不会选择语义非法目标。

### 3. planner / search 形式化

planner 相关定义包括：

- `PositionReachable`：从当前玩家位置出发，在有限步内通过安全移动到达某位置；
- `PlannerCanReach`：存在某个有限步数使目标可达；
- `approachTiles`：目标周围可交互邻接格；
- `PlannerStep`：planner 输出第一步动作的安全契约；
- `PlannerFrontierComplete`：frontier 覆盖所有 `n` 步内安全可达位置；
- `PlannerGoalReachable`：目标集合中存在 `n` 步内安全可达目标；
- `PlannerFindsGoal`：frontier 中已经出现目标位置。

planner 相关定理包括：

- `planner_can_reach_player`：当前位置零步可达；
- `planner_step_safe`：`PlannerStep` 输出的第一步是移动动作，且目标位置 `isWalkable`；
- `planner_completeness_from_frontier_invariant`：若 frontier 完备且目标有界可达，则 frontier 能发现目标；
- `planner_finds_singleton_of_reachable`：单目标版本的完备性结论。

这些定义和定理对应课程要求中的 planner/search 形式化和完备性证明。

### 4. action mask、executor 和 shield

动作合法性由：

- `ActionAllowed`

定义。它允许：

- `wait`；
- `pressA`；
- `pressB`；
- 合法出门动作；
- 移动到 `isWalkable` 位置。

目标到动作由：

- `ActionForGoal`

定义。构造子包括：

- `waitGoal`：等待目标输出等待；
- `interactAdjacent`：开箱或攻击目标相邻时按 A；
- `interactPlan`：开箱或攻击目标不相邻时先走向邻接格；
- `buttonAlreadyOn`：已经在按钮上时等待；
- `buttonPlan`：按钮目标走向按钮格；
- `switchAdjacent`：开关相邻时按 A；
- `switchPlan`：开关目标走向邻接格；
- `exitPush`：站在门上时向门外推出房间；
- `exitPlan`：出口目标走向门 tile；
- `explorePlan`：探索目标走向指定 tile；
- `noPlan`：没有可用计划时等待。

安全过滤由：

- `Shielded`

定义。构造子包括：

- `passWait`：等待放行；
- `passA`：A 键放行；
- `passB`：B 键放行；
- `allowExit`：合法出门放行；
- `blockUnsafe`：不安全移动改成等待；
- `allowSafe`：安全移动放行。

相关定理包括：

- `action_for_goal_move_safe_or_exit`：executor 输出的移动动作安全或合法出门；
- `action_for_goal_allowed`：executor 输出满足 `ActionAllowed`；
- `shielded_move_safe_or_exit`：shield 输出的移动动作安全或合法出门；
- `shielded_output_allowed`：shield 输出满足 `ActionAllowed`；
- `shield_blocks_unsafe_movement`：不安全移动会被 shield 改成等待。

### 5. 策略管线安全性

把规则目标、executor 和 shield 串起来后，有以下定理：

- `raw_rule_action_safe_or_exit`：规则目标经过 executor 后，如果原始动作是移动，则安全或合法出门；
- `shielded_rule_action_safe_or_exit`：经过 shield 后，最终移动动作安全或合法出门；
- `shielded_rule_action_safe_position_or_exit`：最终移动不会主动进入危险位置，合法出门除外；
- `rule_pipeline_output_allowed`：完整规则管线输出满足 action mask。

这些定理对应课程要求中的“证明策略输出合法、安全”。

### 6. 任务完成证明

`TaskProofs.lean` 定义：

- `CompletedBy`

表示从初始状态存在一条执行轨迹到达满足目标谓词的最终状态。

通用定理：

- `completed_by_plan`：给出成功轨迹和最终目标证明，即可推出 `CompletedBy`；
- `task1_completed_if_plan_reaches_goal`；
- `task2_completed_if_plan_reaches_goal`；
- `task3_completed_if_plan_reaches_goal`；
- `task4_completed_if_plan_reaches_goal`；
- `task5_completed_if_plan_reaches_goal`。

关键子任务链条定理：

- `task1_completed_if_open_chest_then_exit`：先到宝箱旁、开箱、再到出口，可推出任务一完成；
- `task2_completed_if_kill_open_exit`：先杀怪、再开箱、再到出口，可推出任务二完成；
- `task3_completed_if_room_chain_succeeds`：换房轨迹拼接成功且最终满足目标，可推出任务三完成；
- `task4_completed_if_key_chain_succeeds`：装备、清怪和资源条件满足，可推出任务四完成；
- `task5_completed_if_conditional_chain_opens_all_chests`：条件门前置条件满足且宝箱目标完成，可推出任务五完成。

总规格：

- `Task5ProofObligation`

保留为综合任务的总证明目标形式。

`TaskProofs.lean` 对应课程要求中的“执行轨迹满足目标条件”和“关键子任务正确性证明”。

## 三个文件之间的关系

依赖关系如下：

```text
Environment.lean
      ↓
Strategy.lean
      ↓
TaskProofs.lean
```

`Environment.lean` 提供状态、动作、环境转移和目标谓词。

`Strategy.lean` 使用环境层定义，证明规则策略、planner、executor 和 shield 的安全性。

`TaskProofs.lean` 使用环境层和策略层接口，给出任务完成证明模板和关键子任务链条。

## 形式化边界

Lean 形式化从视觉层抽取后的 `SymbolicState` 开始。

本形式化不证明：

- 像素模板匹配在所有图像上永远正确；
- 连续像素移动的每一帧物理细节；
- Python 队列动作、像素对齐和卡住修正的逐行实现；
- gif 录屏中每一帧都由 Lean 逐帧重放。

本形式化证明的是：

- 环境符号语义合理；
- planner 输出第一步满足安全契约；
- 搜索完备性可由 frontier 不变量推出；
- executor 输出满足 action mask；
- shield 会阻止不安全移动；
- 规则策略经过 executor 和 shield 后，最终动作合法且安全；
- 给出满足环境语义的成功轨迹时，可以推出任务目标成立。

这种边界符合课程要求中“证明可验证层，如 action mask、safety shield、符号 planner、轨迹验证器或任务完成判定”的要求。

## 检查方法

项目根目录包含 `lakefile.lean`。在项目根目录运行：

```powershell
lake build
```

即可检查全部 Lean 文件。

如果 VS Code 中出现 `unknown module prefix`，但命令行 `lake build` 可以通过，通常是 Lean language server 没有按 Lake 项目刷新。处理方式是打开项目根目录 `math_logic`，执行 `Lean 4: Restart Server` 或 `Developer: Reload Window`。
