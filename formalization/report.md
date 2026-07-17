# 数理逻辑大作业形式化证明报告

本报告重点说明形式化思路、两条策略的可验证层、模型与测评接口的关系，以及
Lean 中已经证明的全部定理。按当前报告用途，不列出实验测评结果。

## 1. 环境形式化

### 1.1 状态、动作、对象与目标

房间内位置为 `Position := Int × Int`，房间坐标为 `RoomCoord := Int × Int`。
核心状态 `SymbolicState` 包含玩家位置与朝向、房间、生命和时钟，墙、陷阱、
沟壑与桥，宝箱、怪物、按钮、开关和出口，钥匙、金币、物品与装备，以及
`keysCollected`、`chestsOpened`、`monstersKilled`、`buttonsPressed`、
`switchesActivated`、`roomsChanged`、`worldCompleted` 等累计进度。

动作类型 `Action` 包含：

```text
wait, up, down, left, right, pressA, pressB, useExit, envTick
```

四个方向动作由 `delta` 和 `nextPosition` 计算；`pressA` 用于开箱、攻击和开关；
`pressB` 用于举盾；`useExit` 是结构化换房；`envTick` 表示环境自动结算。

结构化对象包括 `Chest`、`Monster`、`Exit`、`Loot` 和 `BridgeState`。
`ExitKind` 区分普通门、钥匙门、清怪加钥匙门、按钮门和物品门。
`canOpenChestObject`、`canAttackObject`、`canUseExitObject` 给出交互前置条件，
`exitCondition` 检查出口所需资源与机关状态。

五个完成谓词直接描述终态必须达到的里程碑：

| 目标谓词 | 完成条件 |
| --- | --- |
| `Task1Goal` | 世界完成，取得钥匙并打开宝箱 |
| `Task2Goal` | 世界完成，击杀怪物，取得钥匙并打开宝箱 |
| `Task3Goal` | 世界完成，完成多房间往返、击杀怪物、取得钥匙并打开宝箱 |
| `Task4Goal` | 世界完成，两次切换桥，取得钥匙和剑，击杀守卫并打开三个宝箱 |
| `Task5Goal` | 世界完成，打开四个宝箱，完成房间探索，踩下按钮并取得钥匙 |

### 1.2 动作转移语义

`EnvStep before action after` 形式化安全移动、陷阱移动、撞墙、边界换房、
开箱、攻击、开关、举盾和等待。`FullEnvStep` 增加结构化掉落、怪物 HP、
旋转桥、NPC、盾牌抵伤、怪物行为、Task 5 周期掉血和结构化出口。

按钮使用“站上触发”语义。移动和出口到达都调用 `enterPositionState`；首次进入
按钮格时立即更新 `pressedButtons` 与 `buttonsPressed`，不需要额外执行 `pressA`。

`FullExec` 将一步转移扩展为动作列表。`SafeFullExec` 要求初态、所有中间状态和
终态均不满足 `FailedState`，因此死亡或超时轨迹不能成为安全通关证书。
`TaskCertificate` 保存计划、终态、安全执行证明和目标证明。

## 2. Rule-based 路线

### 2.1 形式化思路与策略设计

```text
SymbolicState + AgentMemory
  -> ruleBasedChooseGoal / CombatReflex
  -> ActionForGoal / PlannerStep
  -> Shielded
  -> FullEnvStep
  -> updateRuleMemory
```

`AgentMemory` 保存上一目标、已处理对象、已用出口、房间步数和机关冷却。
`ruleBasedChooseGoal` 是可执行的具体 Lean 选择函数，依次处理 sticky 目标、宝箱、
必要清怪、条件门、锁门、普通门、开关、回退出口、探索和等待。
`RulePriorityContract` 的 `implementation` 字段将 selector 固定为该函数，并由
`ruleBasedChooseGoal_priorityContract` 构造具体实例。

`PlannerStep` 约束 planner 的第一步为安全四向移动；`ActionForGoal` 将目标转换为
移动、交互、出口宏动作或等待；`Shielded` 放行安全动作并将危险移动替换为等待。
`RulePolicyStep` 把具体选择器、executor、shield、环境转移和记忆更新串成一步，
`RulePolicyExec` 再递归形成完整策略轨迹。

`RuleTaskCertificate` 的 `execution`、`completed` 和 `generated` 使用同一计划和终态。
`CompletedByRulePolicy` 因此同时要求安全环境轨迹、目标成立以及同一计划由具体规则
策略生成。纯环境存在性使用 `rule_taskN_environment_completed` 单独命名。

## 3. RL-based 路线

### 3.1 训练方式与信息来源

RL 路线使用 `sb3_contrib.MaskablePPO` 的 `MlpPolicy`，每个任务训练一个高层模型，
共享同一套感知、特征、mask、resolver、BFS、executor 和 shield 结构。训练入口
`train_high_level.py` 默认每关训练 100000 timesteps，使用 4 个向量环境；主要参数为
`n_steps=512`、`batch_size=256`、`n_epochs=10`、`gamma=0.995`、
`gae_lambda=0.95`、`learning_rate=3e-4` 和两层 256 单元 MLP。

策略不读取完整环境内部状态。正式接口使用 `info-mode=safe`，信息来源为像素观测、
显式物品栏、上一步结果和绑定的 `task_id`。`AdvancedPerceptor` 先从像素抽取玩家、
地形、对象、出口和机关等符号状态，再生成 PPO 输入。

### 3.2 模型输入、输出与测评接口

Task 1 至 Task 4 使用 115 维输入，包括 80 个网格标签、玩家坐标、怪物槽、背包、
7 位 action mask、上一 option one-hot 和记忆摘要。模型输出 7 个高层 option：
开箱、攻击、机关、新出口、返回或重访、探索、等待。

Task 5 使用 122 维输入，并把出口拆成北、东、南、西四个方向，共输出 9 个 option。
`MaskablePPO.predict(..., deterministic=True, action_masks=mask)` 保证推理时只从最终 mask
选择。resolver 将 option 转成具体 `Goal`，BFS、executor 和 shield 再产生 primitive
动作。最终提交入口 `Policy.act(obs, info) -> int` 与助教黑盒接口一致。

Lean 将模型抽象为 `MaskablePolicy` 或 `Task5MaskablePolicy`，并以 `RespectsMask` 或
`Task5RespectsMask` 表示模型遵守 mask。证明覆盖编码维度和值域、mask 非空与可靠性、
goal resolver、primitive shield 和任务轨迹验证；不证明神经网络权重对所有输入都最优。

## 4. 所证定理总表

以下表格列出六个 Lean 文件中的全部 332 个公开 `theorem`。为保持可读性，按共同
性质分组；每个定理名只对应源码中的真实声明。最后另列 27 个仅用于展开轨迹的
`private theorem`。公共、Rule-based 与 RL-based 的定理分别统计，不再放在同一
路线表中；混合文件 `Additional_Proofs.lean` 也按证明对象拆分归属。

| 定理归属 | 公开定理数 |
| --- | ---: |
| 公共环境与跨路线性质 | 105 |
| Rule-based | 87 |
| RL-based | 140 |
| 合计 | 332 |

### 4.1 公共环境定理

#### 4.1.1 `Environment.lean`：74 个公开定理

| 定理组 | 全部定理 | 所证性质 |
| --- | --- | --- |
| 感知、动作与证书接口 | `color_mode_invariant_extract_eq`<br>`actionOfDirection_mem_movementActions`<br>`safeFullExec_to_fullExec`<br>`taskCertificate_completedBy` | 颜色模式契约、方向动作合法性、安全轨迹投影和证书完成性 |
| 移动安全 | `walkable_terrain_passable`<br>`walkable_is_safe_position`<br>`move_safe_player_eq`<br>`move_blocked_player_eq`<br>`safe_move_preserves_safe_position` | 可走格满足地形与安全条件，安全移动到达下一格，撞墙保持原位 |
| 基本交互与钥匙 | `open_chest_increases_keys`<br>`attack_monster_removes_target`<br>`activate_switch_records`<br>`env_step_keys_monotone` | 开箱、攻击、开关效果以及轻量环境中的钥匙单调性 |
| 执行组合 | `exec_append`<br>`exec_keys_monotone`<br>`env_step_is_full_step`<br>`full_exec_append` | 轨迹拼接、执行级钥匙单调性以及轻量语义到完整语义的提升 |
| 生命、时钟与掉落 | `takeDamage_preserves_player`<br>`task5TimedDrainState_preserves_player`<br>`takeDamage_some_health_eq`<br>`healHealth_preserves_player`<br>`healHealth_some_le_maxHealth`<br>`advanceClock_steps_eq`<br>`advanceClock_preserves_player`<br>`apply_key_loot_keys`<br>`apply_gold_loot_gold`<br>`apply_item_loot_items`<br>`applyLoot_preserves_player`<br>`openChestObjectState_preserves_player`<br>`attackMonsterObjectState_preserves_player` | 伤害、回血、计时和奖励更新正确，并保持与其无关的玩家位置 |
| NPC、怪物与盾牌 | `canTalkNpc_listed`<br>`canTalkNpc_in_front`<br>`monsterThreatens_listed`<br>`monsterThreatens_alive`<br>`monsterMoveAllowed_target_inBounds`<br>`monsterMoveAllowed_target_not_wall`<br>`monsterDamageState_preserves_player`<br>`shieldBlockState_shieldUp_false`<br>`shieldBlockState_preserves_player` | NPC、怪物威胁和移动前提可追溯，伤害与盾牌结算满足状态约束 |
| 按钮与旋转桥 | `enterPositionState_records_fresh_button`<br>`enterPositionState_counts_fresh_button`<br>`enterPositionState_does_not_recount_button`<br>`enterPositionState_player`<br>`toggleBridge_twice`<br>`pressSwitch_preserves_player` | 首次站上按钮自动记录并计数，重复进入不重计，桥切换两次复原 |
| 出口 | `canUseExitObject_listed`<br>`canUseExitObject_at_player`<br>`useExitObject_room_eq`<br>`useExitObject_player_eq`<br>`lockedExit_condition_implies_enough_keys` | 可用出口必须存在且位于玩家处，换房后的房间和出生点正确，锁门要求足够钥匙 |
| 终止与失败 | `terminal_of_goal`<br>`terminal_of_failed`<br>`failed_of_dead`<br>`failed_of_timedOut` | 目标、死亡和超时与终止状态之间的关系 |
| BFS 抽象完备性 | `bfs_completeness_from_frontier_invariant` | frontier 不变量推出有界 BFS 完备性 |
| Task 1 环境轨迹 | `task1_safe_execution`<br>`task1_goal` | Task 1 参考轨迹逐状态安全且终态满足目标 |
| Task 2 环境轨迹 | `task2_safe_execution`<br>`task2_goal`<br>`task2_exit_blocked_while_monster_alive` | Task 2 安全通关以及怪物存活时条件门不可用 |
| Task 3 环境轨迹 | `task3_safe_execution`<br>`task3_goal`<br>`task3_final_exit_blocked_without_key` | Task 3 安全通关以及无钥匙时最终门不可用 |
| Task 4 环境轨迹 | `task4_safe_execution`<br>`task4_goal`<br>`task4_east_gate_does_not_consume_key`<br>`task4_guardian_requires_sword` | Task 4 安全通关、东门钥匙语义和守卫战前置条件 |
| Task 5 环境轨迹 | `task5_safe_execution`<br>`task5_goal`<br>`task5_button_triggered_on_entry`<br>`task5_south_gate_blocked_before_button`<br>`task5_east_gate_blocked_without_key`<br>`task5_drain_example_due`<br>`task5_drain_example_survives` | Task 5 安全通关、自动按钮、门禁条件和周期掉血示例 |

#### 4.1.2 `Additional_Proofs.lean` 中的公共定理：31 个

| 定理组 | 全部定理 | 所证性质 |
| --- | --- | --- |
| 安全轨迹结构 | `safeFullExec_final_not_failed`<br>`safeFullExec_append` | 安全轨迹终点未失败且可拼接 |
| 累计进度单调性 | `progressLe_refl`<br>`progressLe_trans`<br>`envStep_progressLe`<br>`applyLoot_progressLe`<br>`openChestObjectState_progressLe`<br>`attackMonsterObjectState_progressLe`<br>`takeDamage_progressLe`<br>`task5TimedDrainState_progressLe`<br>`fullEnvStep_progressLe`<br>`fullExec_progressLe`<br>`safeFullExec_progressLe` | 从一步机制到完整安全轨迹，任务累计进度不会倒退 |
| 世界完成标志单调性 | `worldCompletedMonotone_refl`<br>`worldCompletedMonotone_trans`<br>`envStep_worldCompletedMonotone`<br>`openChestObjectState_worldCompletedMonotone`<br>`attackMonsterObjectState_worldCompletedMonotone`<br>`fullEnvStep_worldCompletedMonotone`<br>`fullExec_worldCompletedMonotone`<br>`safeFullExec_worldCompletedMonotone` | `worldCompleted` 一旦为真，在各种一步和多步执行中保持为真 |
| 条件出口安全性 | `buttonGate_exit_requires_pressed`<br>`allMonstersAndKey_exit_requires_resources`<br>`itemGate_exit_requires_item`<br>`fullEnvStep_useExit_has_usable_exit` | 通过各类条件门必然具有按钮、资源、物品或可用出口见证 |
| 两条路线共享轨迹 | `task1_route_certificates_share_trace`<br>`task2_route_certificates_share_trace`<br>`task3_route_certificates_share_trace`<br>`task4_route_certificates_share_trace`<br>`task5_route_certificates_share_trace`<br>`all_route_certificates_share_trace` | Rule 与 RL 证书使用同一公共环境计划和终态 |

### 4.2 Rule-based 所证定理

#### 4.2.1 `Rule_based_Strategy.lean`：26 个公开定理

| 定理组 | 全部定理 | 所证性质 |
| --- | --- | --- |
| 目标合法性与具体优先级 | `exit_goal_admissible_mem_allExits`<br>`rule_goal_admissible`<br>`ruleBasedChooseGoal_admissible`<br>`ruleBasedChooseGoal_priorityContract`<br>`concrete_selector_chest_first`<br>`concrete_selector_conditional_button_first`<br>`priority_selector_goal_admissible` | 出口和规则目标合法，具体选择器满足契约及关键优先级 |
| Planner | `planner_can_reach_player`<br>`planner_step_safe`<br>`planner_completeness_from_frontier_invariant`<br>`planner_finds_singleton_of_reachable` | 自反可达、planner 第一步安全以及 frontier 完备性 |
| 战斗反射与 Executor | `combat_reflex_action_allowed`<br>`button_action_for_goal_ne_pressA`<br>`action_for_goal_move_safe_or_exit`<br>`action_for_goal_allowed` | 战斗反射和目标执行动作合法；按钮目标不输出 A 键 |
| Shield 与完整管线 | `shielded_move_safe_or_exit`<br>`shielded_output_allowed`<br>`shield_blocks_unsafe_movement`<br>`raw_rule_action_safe_or_exit`<br>`shielded_rule_action_safe_or_exit`<br>`shielded_rule_action_safe_position_or_exit`<br>`rule_pipeline_output_allowed` | shield 阻止危险移动，最终动作满足安全位置或合法出门约束 |
| 策略执行与强化证书 | `rulePolicyExec_to_fullExec`<br>`ruleTaskCertificate_completedBy`<br>`ruleTaskCertificate_completedByRulePolicy`<br>`completedByRulePolicy_to_completedBy` | 策略轨迹投影、强化证书的策略完成性及其向环境完成性的投影 |

#### 4.2.2 `Rule_based_TaskProofs.lean`：42 个公开定理

| 定理组 | 全部定理 | 所证性质 |
| --- | --- | --- |
| Task 1 | `task1_rule_chest_checkpoint`<br>`task1_rule_locked_exit_checkpoint`<br>`rule_task1_environment_completed`<br>`task1_rule_policy_execution`<br>`rule_task1_completed` | 宝箱与锁门检查点、环境完成、完整策略生成和强化完成性 |
| Task 2 | `task2_rule_monster_checkpoint`<br>`task2_rule_chest_checkpoint`<br>`task2_rule_conditional_exit_checkpoint`<br>`rule_task2_environment_completed`<br>`task2_rule_policy_execution`<br>`rule_task2_completed` | 战斗、宝箱和条件门检查点及策略通关 |
| Task 3 | `task3_rule_start_exit_checkpoint`<br>`task3_rule_hall_monster_checkpoint`<br>`task3_rule_key_chest_checkpoint`<br>`task3_rule_final_locked_exit_checkpoint`<br>`rule_task3_environment_completed`<br>`task3_rule_policy_execution`<br>`rule_task3_completed` | 多房间、怪物、钥匙箱和最终锁门检查点及策略通关 |
| Task 4 | `task4_rule_first_switch_checkpoint`<br>`task4_rule_key_chest_checkpoint`<br>`task4_rule_east_locked_exit_checkpoint`<br>`task4_rule_sword_chest_checkpoint`<br>`task4_rule_second_switch_checkpoint`<br>`task4_rule_guardian_checkpoint`<br>`task4_rule_final_chest_checkpoint`<br>`rule_task4_environment_completed`<br>`task4_rule_policy_execution`<br>`rule_task4_completed` | 两次旋桥、钥匙、剑、守卫和最终宝箱检查点及策略通关 |
| Task 5 | `task5_rule_start_chest_checkpoint`<br>`task5_rule_west_exit_checkpoint`<br>`task5_rule_west_monster_checkpoint`<br>`task5_rule_west_chest_checkpoint`<br>`task5_rule_button_triggered_by_entry`<br>`task5_rule_conditional_exit_checkpoint`<br>`task5_rule_south_chest_checkpoint`<br>`task5_rule_east_locked_exit_checkpoint`<br>`task5_rule_east_chest_checkpoint`<br>`rule_task5_environment_completed`<br>`task5_rule_policy_execution`<br>`rule_task5_completed` | 三个分支、自动按钮、条件门、锁门和四宝箱检查点及策略通关 |
| 五关汇总 | `all_rule_task_certificates`<br>`all_rule_tasks_policy_generated` | 五关均满足强化证书，五条完整计划均由具体规则策略生成 |

#### 4.2.3 `Additional_Proofs.lean` 中的 Rule-based 定理：19 个

| 定理组 | 全部定理 | 所证性质 |
| --- | --- | --- |
| 关系式 Shield 的全函数性 | `exitPushAllowed_not_walkable`<br>`shielded_total`<br>`shielded_deterministic`<br>`shielded_exists_unique` | 合法出门与普通可走移动区分，`Shielded` 输出存在且唯一 |
| 可计算 BFS 可靠性与完备性 | `mem_safeActionsFrom_iff`<br>`mem_safeSuccessors_iff`<br>`mem_breadthFrontier_iff_positionReachable`<br>`breadthFrontier_complete`<br>`breadthFrontier_sound`<br>`breadth_search_complete`<br>`breadth_search_sound`<br>`breadth_search_sound_and_complete`<br>`breadthFindsGoal_eq_true_iff`<br>`safeMovePlan_positionReachable`<br>`positionReachable_has_safeMovePlan`<br>`safeMovePlan_exec`<br>`verifiedSearchResult_sound`<br>`breadth_found_has_verified_plan`<br>`verified_search_result_iff_reachable` | 可计算 successor/frontier 与关系式可达性等价，可提取并执行安全计划 |

### 4.3 RL-based 所证定理

#### 4.3.1 `RL_based_Strategy.lean`：70 个公开定理

| 定理组 | 全部定理 | 所证性质 |
| --- | --- | --- |
| 网格枚举 | `allTiles_length`<br>`allTiles_contains` | 10×8 网格恰有 80 格且任意合法坐标都被枚举 |
| 基础目标与 resolver | `canonicalGoal_compatible`<br>`activateMechanism_allows_pressed_button`<br>`activateMechanism_allows_rotating_switch`<br>`resolve_some_of_mask_true`<br>`resolve_none_of_mask_false`<br>`mask_respecting_policy_resolves` | option 与目标兼容，mask 位和 resolver 一致，遵守 mask 的模型输出可解析 |
| 基础 mask 优先级 | `normalizedMask_length`<br>`normalizedMask_attack_disabled_of_chest`<br>`normalizedMask_attack_disabled_of_mechanism`<br>`normalizedMask_return_disabled_of_new_exit`<br>`normalizedMask_return_disabled_of_local_progress`<br>`normalizedMask_explore_disabled_of_resolved_progress`<br>`normalizedMask_wait_disabled_of_resolved_progress`<br>`normalizedMask_wait_fallback` | 基础 mask 长度固定，局部进度与新出口具有优先级，等待只作兜底 |
| 基础特征长度 | `gridFeatures_length`<br>`playerFeatures_length`<br>`monsterSlotFeatures_length`<br>`orderedMonsters_perm`<br>`orderedMonsters_length`<br>`monsterFeatures_length`<br>`inventoryFeatures_length`<br>`fixedMaskFeatures_length`<br>`oneHotForLast_length`<br>`memoryFeatures_length` | 每个特征分块长度正确，怪物排序保持元素与数量 |
| 基础特征值域与总编码 | `featuresValid_append`<br>`coordFeature_valid`<br>`clippedFeature_valid`<br>`memoryFeature_valid`<br>`signedMemoryFeature_valid`<br>`gridFeatures_valid`<br>`playerFeatures_valid`<br>`monsterSlotFeatures_valid`<br>`monsterFeatures_valid`<br>`inventoryFeatures_valid`<br>`fixedMaskFeatures_valid`<br>`oneHotForLast_valid`<br>`memoryFeatures_valid`<br>`encodeHighLevelState_wellFormed` | 各分块值域合法，拼接后 115 维基础编码结构正确 |
| Task 5 目标与 resolver | `task5CanonicalGoal_compatible`<br>`task5_resolve_some_of_mask_true`<br>`task5_resolve_none_of_mask_false`<br>`task5_mask_respecting_policy_resolves` | Task 5 方向 option 与目标兼容，遵守 mask 的输出可解析 |
| Task 5 特征编码 | `task5GridFeatures_length`<br>`task5FixedMaskFeatures_length`<br>`task5OneHotForLast_length`<br>`task5MemoryFeatures_length`<br>`task5GridFeatures_valid`<br>`task5FixedMaskFeatures_valid`<br>`task5OneHotForLast_valid`<br>`task5MemoryFeatures_valid`<br>`encodeTask5State_wellFormed` | Task 5 各分块长度和值域合法，总编码为 122 维 |
| Task 5 本地资源优先 | `task5_exit_north_disabled_of_local_resource`<br>`task5_exit_east_disabled_of_local_resource`<br>`task5_exit_south_disabled_of_local_resource`<br>`task5_exit_west_disabled_of_local_resource` | 有本地资源时四个方向出口均被抑制 |
| Task 5 mask 与路线优先级 | `task5NormalizedMask_length`<br>`task5_locked_directions_preferred`<br>`task5_conditional_directions_preferred_without_key`<br>`task5_nonpreferred_exit_disabled`<br>`task5_used_exit_disabled_when_frontier_exists`<br>`task5_all_exits_disabled_of_local_resource`<br>`task5_chest_precedes_mechanism_without_blocking_monster`<br>`task5_optional_attack_disabled_in_resource_room`<br>`task5_blocking_attack_precedes_local_interaction`<br>`task5_recovery_disabled_of_concrete_progress`<br>`task5_wait_fallback` | 九位 mask 长度、锁门与条件门路线、阻路怪物和恢复动作优先级正确 |
| 公共环境投影与 primitive shield | `shared_walkable_projects_to_safe`<br>`shielded_non_setup_move_safe` | 公共可走格投影为 RL 安全格，非 setup 移动经 shield 后安全 |

#### 4.3.2 `RL_based_TaskProofs.lean`：46 个公开定理

| 定理组 | 全部定理 | 所证性质 |
| --- | --- | --- |
| Readiness 与公共环境一致性 | `chestObjectReady_iff`<br>`monsterObjectReady_iff`<br>`exitConditionReady_iff`<br>`exitObjectReady_iff`<br>`chestReady_iff`<br>`monsterReady_iff`<br>`mechanismReady_iff`<br>`exitReady_iff` | RL readiness 判定与公共宝箱、怪物、机关和出口语义等价 |
| 共享输入与目标兼容 | `base_shared_input_wellFormed`<br>`task5_shared_input_wellFormed`<br>`every_base_checkpoint_goal_compatible`<br>`every_task5_checkpoint_goal_compatible` | 公共状态投影后的输入结构正确，检查点目标与 option 兼容 |
| Task 1 | `task1_rl_chest_checkpoint`<br>`task1_rl_locked_exit_checkpoint`<br>`rl_task1_completed` | 开箱与锁门检查点成立，安全参考轨迹达到目标 |
| Task 2 | `task2_rl_monster_checkpoint`<br>`task2_rl_chest_checkpoint`<br>`task2_rl_conditional_exit_checkpoint`<br>`rl_task2_completed` | 怪物、宝箱和条件门检查点成立，安全参考轨迹达到目标 |
| Task 3 | `task3_rl_start_exit_checkpoint`<br>`task3_rl_hall_monster_checkpoint`<br>`task3_rl_key_chest_checkpoint`<br>`task3_rl_return_from_key_room_checkpoint`<br>`task3_rl_return_to_start_checkpoint`<br>`task3_rl_final_locked_exit_checkpoint`<br>`rl_task3_completed` | 多房间往返各检查点成立，安全参考轨迹达到目标 |
| Task 4 | `task4_rl_first_switch_checkpoint`<br>`task4_rl_key_chest_checkpoint`<br>`task4_rl_east_locked_exit_checkpoint`<br>`task4_rl_sword_chest_checkpoint`<br>`task4_rl_second_switch_checkpoint`<br>`task4_rl_guardian_checkpoint`<br>`task4_rl_final_chest_checkpoint`<br>`rl_task4_completed` | 旋转桥、钥匙、剑、守卫和宝箱检查点成立，安全参考轨迹达到目标 |
| Task 5 | `task5_rl_start_chest_checkpoint`<br>`task5_rl_west_exit_checkpoint`<br>`task5_rl_blocking_monster_checkpoint`<br>`task5_rl_west_chest_checkpoint`<br>`task5_rl_button_triggered_by_entry`<br>`task5_rl_conditional_south_exit_checkpoint`<br>`task5_rl_south_chest_checkpoint`<br>`task5_rl_return_north_checkpoint`<br>`task5_rl_locked_east_exit_checkpoint`<br>`task5_rl_east_chest_checkpoint`<br>`rl_task5_completed` | Task 5 路线 option、自动按钮和对象 readiness 检查点成立，安全参考轨迹达到目标 |
| 五关汇总 | `all_rl_tasks_completed` | 五个 RL 安全任务证书共同存在 |

#### 4.3.3 `Additional_Proofs.lean` 中的 RL-based 定理：24 个

| 定理组 | 全部定理 | 所证性质 |
| --- | --- | --- |
| Mask 非空、保守性与可靠性 | `normalizedMask_has_enabled`<br>`normalizedMask_enabled_exists`<br>`task5ConcreteProgress_cases`<br>`task5NormalizedMask_has_enabled`<br>`task5NormalizedMask_enabled_exists`<br>`normalizedMask_nonwait_conservative`<br>`task5ChestBit_true_implies_raw`<br>`task5MechanismBit_true_implies_raw`<br>`task5AttackBit_true_implies_raw`<br>`task5ExitBit_true_implies_raw`<br>`task5NormalizedMask_nonwait_conservative`<br>`normalizedMask_sound`<br>`task5NormalizedMask_sound`<br>`mask_respecting_policy_selects_ready`<br>`task5_mask_respecting_policy_selects_ready`<br>`mask_respecting_policy_ready_resolution`<br>`task5_mask_respecting_policy_ready_resolution` | 最终 mask 始终可选，不凭空开放非等待动作；遵守 mask 的模型输出 ready 且可解析 |
| Primitive shield 强性质 | `shield_preserves_safe_move`<br>`shield_idempotent`<br>`shield_move_output_safe` | RL primitive shield 保持安全移动、重复过滤幂等且最终移动安全 |
| 颜色模式不变性 | `color_mode_base_features_invariant`<br>`color_mode_task5_features_invariant`<br>`color_mode_base_policy_output_invariant`<br>`color_mode_task5_policy_output_invariant` | 满足感知契约时，颜色变化不改变编码或确定性策略输出 |

### 4.4 私有轨迹辅助定理：27 个

| 文件 | 全部私有定理 | 用途 |
| --- | --- | --- |
| `Environment.lean` | `task4_step_switch1`<br>`task4_step_to_center`<br>`task4_step_to_north`<br>`task4_step_open_key`<br>`task4_step_back_for_east`<br>`task4_step_to_east`<br>`task4_step_open_sword`<br>`task4_step_back_to_switch`<br>`task4_step_switch2`<br>`task4_step_to_south`<br>`task4_step_kill_guardian`<br>`task4_step_back_to_final`<br>`task4_step_open_final`<br>`task5_step_open_start`<br>`task5_step_to_west`<br>`task5_step_kill_west_monster`<br>`task5_step_open_west`<br>`task5_step_back_to_button`<br>`task5_step_to_south`<br>`task5_step_open_south`<br>`task5_step_back_to_east_gate`<br>`task5_step_to_east`<br>`task5_step_open_east` | 展开 Task 4 和 Task 5 公共环境轨迹的每一步 |
| `Rule_based_TaskProofs.lean` | `plannedInteractionStep`<br>`plannedSwitchOnStep`<br>`plannedStructuredExitStep`<br>`reflexAttackStep` | 复用计划交互、开关、出口和战斗反射的 `RulePolicyStep` 构造 |

## 5. 模型假设、环境抽象与简化

- 公共环境是 10×8 房间的符号状态机，不证明视觉抽取对任意像素都正确；颜色相关结论以 `ColorModeInvariant` 感知契约为前提。
- `useExit` 将真实环境中连续推动门口的多个 primitive tick 抽象为一次满足 `canUseExitObject` 的结构化换房。
- Rule-based 的 Lean 选择器是 Python 高层优先链的可执行抽象；像素移动队列、卡住微调和视觉缓存不属于 `RulePolicyExec`。
- Rule-based 五关完成定理使用 `CompletedByRulePolicy`，确实绑定具体选择器生成的同一计划；其中紧急攻击按实际控制顺序由 `CombatReflex` 分支处理。
- RL 的 `RespectsMask` 是模型与验证层之间的接口假设。Lean 证明模型选中的 option 在该假设下合法、ready 且可解析，但不证明 PPO 权重必然选出参考通关 option。
- RL 各关证书证明安全参考轨迹与检查点；`rl_taskN_completed` 是环境可达性结论，不应解释为神经网络对所有观测必然通关。
- 两条路线共享同一 `Environment.lean` 和参考任务状态，避免使用两套不一致的环境语义。

## 6. 命名、证明结构与复现

类型和关系使用 PascalCase，可计算函数使用 camelCase，定理使用 snake_case；
`rule_`、`rl_` 和 `taskN_` 前缀区分路线与任务。证明按“定义、通用引理、
策略安全定理、关卡检查点、任务证书、附加性质”组织。

仓库提交 `lakefile.lean`、`lakefile.toml` 和 `lean-toolchain`，工具链固定为
`leanprover/lean4:v4.29.0-rc8`。所有 Lean 文件不含 `sorry`、`admit` 或额外 `axiom`。

```powershell
lake -f lakefile.lean build formalization
lake -f lakefile.toml build formalization
rg -n "\b(sorry|admit|axiom)\b" .\formalization -g "*.lean"
```

两个 Lake 构建命令应成功，最后一条命令应无匹配。
