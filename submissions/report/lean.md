# 完整所证定理索引

## 模块一　环境形式化

### 1.1 `Environment.lean` 的 74 个公开定理

#### 1.1.2 接口、移动、交互和轨迹

| 定理 | 具体证明内容 | 类别 |
| --- | --- | --- |
| `color_mode_invariant_extract_eq` | 感知契约成立时，同一帧在任意两种颜色模式下提取的符号状态相等 | 感知接口 |
| `actionOfDirection_mem_movementActions` | 任意方向映射得到的动作属于四方向移动集合 | 动作合法性 |
| `safeFullExec_to_fullExec` | 安全完整轨迹可投影成同计划、同终态的普通完整轨迹 | 轨迹投影 |
| `taskCertificate_completedBy` | `TaskCertificate` 蕴含存在一条完整轨迹到达目标 | 证书正确性 |
| `walkable_terrain_passable` | `isWalkable` 蕴含地形可通行 | 安全性 |
| `walkable_is_safe_position` | 可走格在界内、地形可通行且不是陷阱，因此满足 `SafePosition` | 安全性 |
| `move_safe_player_eq` | 安全移动后玩家精确到达 `nextPosition` | 移动正确性 |
| `move_blocked_player_eq` | 撞墙或障碍后玩家位置保持不变 | 撞墙正确性 |
| `safe_move_preserves_safe_position` | 安全移动一步的落点满足 `SafePosition` | 安全不变量 |
| `open_chest_increases_keys` | 轻量开钥匙箱后钥匙按奖励数增加 | 开箱正确性 |
| `attack_monster_removes_target` | 成功轻量攻击后目标怪物位置被移除 | 攻击正确性 |
| `activate_switch_records` | 激活开关后其位置写入 `activated` | 机关正确性 |
| `env_step_keys_monotone` | 任意轻量环境一步都不减少钥匙 | 资源不变量 |
| `exec_append` | 两段 `Exec` 可拼接成动作列表连接后的轨迹 | 轨迹组合 |
| `exec_keys_monotone` | 轻量多步执行中钥匙单调不减 | 资源不变量 |
| `env_step_is_full_step` | 任意轻量一步可提升为完整环境一步 | 语义兼容 |
| `full_exec_append` | 两段 `FullExec` 可拼接成完整轨迹 | 轨迹组合 |

#### 1.1.2 状态更新、对象、机关和出口

| 定理 | 具体证明内容 | 类别 |
| --- | --- | --- |
| `takeDamage_preserves_player` | 扣血不改变玩家位置 | 帧条件 |
| `task5TimedDrainState_preserves_player` | Task 5 周期掉血不改变玩家位置 | 帧条件 |
| `takeDamage_some_health_eq` | 已知生命为 `hp` 时，扣血结果精确等于 `hp - damage` | 生命正确性 |
| `healHealth_preserves_player` | 回血不改变玩家位置 | 帧条件 |
| `healHealth_some_le_maxHealth` | 回血结果不超过 `maxHealth` | 安全不变量 |
| `advanceClock_steps_eq` | 时钟推进后 `steps` 精确增加一 | 时钟正确性 |
| `advanceClock_preserves_player` | 时钟推进不改变玩家位置 | 帧条件 |
| `apply_key_loot_keys` | 钥匙掉落使钥匙精确增加指定数量 | 奖励正确性 |
| `apply_gold_loot_gold` | 金币掉落使金币精确增加指定数量 | 奖励正确性 |
| `apply_item_loot_items` | 物品掉落后该物品出现在背包中 | 奖励正确性 |
| `applyLoot_preserves_player` | 任意掉落结算不改变玩家位置 | 帧条件 |
| `openChestObjectState_preserves_player` | 结构化开箱更新对象、奖励和进度，但不瞬移玩家 | 帧条件 |
| `attackMonsterObjectState_preserves_player` | 结构化攻击更新怪物和奖励，但不瞬移玩家 | 帧条件 |
| `canTalkNpc_listed` | 能交谈蕴含 NPC 确实在当前 NPC 表中 | 前置条件 |
| `canTalkNpc_in_front` | 能交谈蕴含 NPC 位于玩家正前方 | 前置条件 |
| `monsterThreatens_listed` | 构成威胁的怪物确实存在于怪物对象表 | 威胁正确性 |
| `monsterThreatens_alive` | 构成威胁的怪物生命值大于零 | 威胁正确性 |
| `monsterMoveAllowed_target_inBounds` | 合法怪物移动目标一定在边界内 | 安全性 |
| `monsterMoveAllowed_target_not_wall` | 合法怪物移动目标一定不是墙 | 安全性 |
| `monsterDamageState_preserves_player` | 怪物伤害结算不改变玩家位置 | 帧条件 |
| `shieldBlockState_shieldUp_false` | 一次格挡结算后 `shieldUp` 复位为 `false` | 盾牌正确性 |
| `shieldBlockState_preserves_player` | 格挡结算不改变玩家位置 | 帧条件 |
| `enterPositionState_records_fresh_button` | 首次进入新按钮格后，该按钮被记录为已按下 | 按钮正确性 |
| `enterPositionState_counts_fresh_button` | 首次进入新按钮格后按钮计数精确增加一 | 计数正确性 |
| `enterPositionState_does_not_recount_button` | 再次进入已记录按钮格不重复计数 | 进度不变量 |
| `enterPositionState_player` | 进入位置状态后的玩家位置精确等于目标位置 | 移动正确性 |
| `toggleBridge_twice` | 任意桥状态连续切换两次回到原状态 | 机关不变量 |
| `pressSwitch_preserves_player` | 旋转开关操作不改变玩家位置 | 帧条件 |
| `canUseExitObject_listed` | 可使用出口蕴含该出口存在于对象表 | 前置条件 |
| `canUseExitObject_at_player` | 可使用出口蕴含玩家正站在出口位置 | 前置条件 |
| `useExitObject_room_eq` | 使用出口后的房间精确等于目标房间 | 换房正确性 |
| `useExitObject_player_eq` | 使用出口后的玩家位置精确等于目标出生点 | 换房正确性 |
| `lockedExit_condition_implies_enough_keys` | 钥匙门条件成立蕴含钥匙数量足够 | 门禁安全性 |

#### 1.1.3 终止、完备性和五关参考环境

| 定理 | 具体证明内容 | 类别 |
| --- | --- | --- |
| `terminal_of_goal` | 目标谓词成立时状态终止 | 完成判定 |
| `terminal_of_failed` | 失败状态一定终止 | 失败判定 |
| `failed_of_dead` | 死亡蕴含 `FailedState` | 失败判定 |
| `failed_of_timedOut` | 超时蕴含 `FailedState` | 失败判定 |
| `bfs_completeness_from_frontier_invariant` | frontier 覆盖所有 `n` 步可达状态且目标有界可达时，frontier 中必有目标 | 有界完备性 |
| `task1_safe_execution` | 构造 Task 1 开箱、出门的完整安全轨迹 | 安全可达性 |
| `task1_goal` | Task 1 终态满足完成、取钥匙和开箱目标 | 目标正确性 |
| `task2_safe_execution` | 构造 Task 2 杀怪、开箱、出门的完整安全轨迹 | 安全可达性 |
| `task2_goal` | Task 2 终态满足完成、击杀、钥匙和宝箱目标 | 目标正确性 |
| `task2_exit_blocked_while_monster_alive` | 怪物存活时清怪加钥匙门不可用 | 关键机制 |
| `task3_safe_execution` | 构造 Task 3 跨房间、杀怪、取钥匙和返回最终门的安全轨迹 | 安全可达性 |
| `task3_goal` | Task 3 终态满足换房、击杀、钥匙、宝箱和完成目标 | 目标正确性 |
| `task3_final_exit_blocked_without_key` | 无钥匙时 Task 3 最终锁门不可用 | 关键机制 |
| `task4_safe_execution` | 构造两次旋桥、取钥匙、取剑、杀守卫和开终箱的安全轨迹 | 安全可达性 |
| `task4_goal` | Task 4 终态满足完整任务链目标 | 目标正确性 |
| `task4_east_gate_does_not_consume_key` | 东侧钥匙门按关卡设定不消耗钥匙 | 关键机制 |
| `task4_guardian_requires_sword` | 对守卫的合法攻击前置条件要求持剑 | 关键机制 |
| `task5_safe_execution` | 构造四宝箱、怪物、按钮、条件门和钥匙门的安全轨迹 | 安全可达性 |
| `task5_goal` | Task 5 终态满足四宝箱、五次换房、按钮、钥匙和完成目标 | 目标正确性 |
| `task5_button_triggered_on_entry` | 返回中心进入按钮格时按钮自动触发且计数为一 | 关键机制 |
| `task5_south_gate_blocked_before_button` | 按钮未按下前南门不可用 | 关键机制 |
| `task5_east_gate_blocked_without_key` | 无钥匙时东门不可用 | 关键机制 |
| `task5_drain_example_due` | 给定示例满足周期掉血触发条件 | 时钟机制 |
| `task5_drain_example_survives` | 示例状态周期掉血后玩家仍存活 | 生命安全 |

### 1.2 公共强化不变量逐条说明

以下是 `Additional_Proofs.lean` 中直接服务规则路线的 25 个公共定理。

| 定理 | 具体证明内容 | 类别 |
| --- | --- | --- |
| `safeFullExec_final_not_failed` | 安全完整轨迹的最终状态不死亡且不超时 | 轨迹安全性 |
| `safeFullExec_append` | 两段首尾相接的安全轨迹可拼接并保持安全 | 安全组合 |
| `progressLe_refl` | 累计进度偏序具有自反性 | 进度不变量 |
| `progressLe_trans` | 累计进度偏序具有传递性 | 进度不变量 |
| `envStep_progressLe` | 任意轻量一步不降低累计进度 | 进度单调性 |
| `applyLoot_progressLe` | 掉落结算不降低累计进度 | 进度单调性 |
| `openChestObjectState_progressLe` | 结构化开箱不降低累计里程碑 | 进度单调性 |
| `attackMonsterObjectState_progressLe` | 结构化攻击不降低累计里程碑 | 进度单调性 |
| `takeDamage_progressLe` | 扣血不回退任务进度 | 进度单调性 |
| `task5TimedDrainState_progressLe` | 周期掉血不回退任务进度 | 进度单调性 |
| `fullEnvStep_progressLe` | 每种完整环境一步都保持进度单调 | 进度单调性 |
| `fullExec_progressLe` | 任意完整多步轨迹保持进度单调 | 轨迹不变量 |
| `safeFullExec_progressLe` | 任意安全完整轨迹保持进度单调 | 轨迹不变量 |
| `worldCompletedMonotone_refl` | 完成标志保持关系具有自反性 | 完成不变量 |
| `worldCompletedMonotone_trans` | 完成标志保持关系具有传递性 | 完成不变量 |
| `envStep_worldCompletedMonotone` | 轻量一步不清除已完成标志 | 完成不变量 |
| `openChestObjectState_worldCompletedMonotone` | 开箱不清除已完成标志 | 完成不变量 |
| `attackMonsterObjectState_worldCompletedMonotone` | 攻击不清除已完成标志 | 完成不变量 |
| `fullEnvStep_worldCompletedMonotone` | 任意完整一步保持已完成标志 | 完成不变量 |
| `fullExec_worldCompletedMonotone` | 任意完整轨迹保持已完成标志 | 完成不变量 |
| `safeFullExec_worldCompletedMonotone` | 任意安全轨迹保持已完成标志 | 完成不变量 |
| `buttonGate_exit_requires_pressed` | 使用按钮门蕴含所需按钮已按下 | 门禁安全性 |
| `allMonstersAndKey_exit_requires_resources` | 使用清怪加钥匙门蕴含怪物已清空且钥匙足够 | 门禁安全性 |
| `itemGate_exit_requires_item` | 使用物品门蕴含持有所需物品 | 门禁安全性 |
| `fullEnvStep_useExit_has_usable_exit` | 任意结构化出门转移都带有满足 `canUseExitObject` 的出口见证 | 出口正确性 |

## 模块二　策略形式化与证明

### 2.1 `Rule_based_Strategy.lean` 的 26 个公开定理

| 定理 | 具体证明内容 | 类别 |
| --- | --- | --- |
| `exit_goal_admissible_mem_allExits` | 合法出口目标的位置一定属于当前状态 `allExits` | 目标合法性 |
| `planner_can_reach_player` | 玩家当前位置在零步内满足 `PlannerCanReach` | 可达性基础 |
| `rule_goal_admissible` | 对所有规则分支分类证明：`RuleGoal` 选择的目标必满足 `GoalAdmissible` | 策略正确性 |
| `ruleBasedChooseGoal_admissible` | 具体函数 `ruleBasedChooseGoal` 返回的目标一定合法 | 实现正确性 |
| `ruleBasedChooseGoal_priorityContract` | 具体选择器满足 sticky-first 和重新规划优先级契约 | 优先级正确性 |
| `concrete_selector_chest_first` | 无延续目标且存在宝箱候选时，具体选择器返回该宝箱 | 关键优先级 |
| `concrete_selector_conditional_button_first` | 无宝箱且条件门需要按钮时，具体选择器优先返回按钮 | 关键优先级 |
| `priority_selector_goal_admissible` | 从优先级契约推出选择器最终目标始终合法 | 策略正确性 |
| `planner_step_safe` | Planner 输出一定是方向移动且下一格 `isWalkable` | Planner 安全性 |
| `planner_completeness_from_frontier_invariant` | frontier 完整且目标有界可达时，frontier 必找到某目标 | 抽象完备性 |
| `planner_finds_singleton_of_reachable` | 单一目标有界可达时，完备 frontier 必找到它 | 抽象完备性 |
| `combat_reflex_action_allowed` | 紧急攻击、持盾格挡和安全撤退均满足 `ActionAllowed` | 反射安全性 |
| `button_action_for_goal_ne_pressA` | 按钮由踩踏触发，按钮目标的 executor 不会输出 `pressA` | 执行器正确性 |
| `action_for_goal_move_safe_or_exit` | executor 输出移动时，该移动安全或满足 `exitPushAllowed` | 执行器安全性 |
| `action_for_goal_allowed` | executor 对任意目标产生的动作均满足 action mask | 动作合法性 |
| `shielded_move_safe_or_exit` | shield 最终仍输出移动时，该移动安全或是合法出门 | Shield 安全性 |
| `shielded_output_allowed` | shield 的任意输出均满足 `ActionAllowed` | Shield 合法性 |
| `shield_blocks_unsafe_movement` | 原始动作是非出口危险移动时，shield 输出只能是 `wait` | Shield 安全性 |
| `raw_rule_action_safe_or_exit` | 规则目标经 executor 得到的原始移动安全或合法出门 | 管线安全性 |
| `shielded_rule_action_safe_or_exit` | 规则目标、executor 和 shield 串联后的最终移动安全或合法出门 | 管线安全性 |
| `shielded_rule_action_safe_position_or_exit` | 将结论强化为最终移动落点满足 `SafePosition`，合法出门除外 | 管线安全性 |
| `rule_pipeline_output_allowed` | 完整规则管线的最终输出满足 action mask | 总体合法性 |
| `rulePolicyExec_to_fullExec` | 规则策略多步执行可投影为同计划、同终态的公共环境轨迹 | 策略—环境一致性 |
| `ruleTaskCertificate_completedBy` | 规则任务证书可投影为普通环境完成性 `CompletedBy` | 证书投影 |
| `ruleTaskCertificate_completedByRulePolicy` | 规则任务证书推出安全、达标且由策略生成的 `CompletedByRulePolicy` | 策略完成性 |
| `completedByRulePolicy_to_completedBy` | 具体策略完成性蕴含普通环境可达性 | 逻辑蕴含 |

### 2.2 `Rule_based_TaskProofs.lean` 的 42 个公开定理

#### Task 1–Task 3

| 定理 | 具体证明内容 | 类别 |
| --- | --- | --- |
| `task1_rule_chest_checkpoint` | 初态钥匙宝箱存在、未记录且相邻，规则可合法选择开箱 | 子任务正确性 |
| `task1_rule_locked_exit_checkpoint` | 取得钥匙后锁门条件成立且未使用，规则可选择最终出口 | 子任务正确性 |
| `rule_task1_environment_completed` | 从 Task 1 公共安全证书推出环境中存在目标轨迹 | 环境可达性 |
| `task1_rule_policy_execution` | Task 1 计划由具体选择器、executor、shield 和记忆更新生成 | 策略生成性 |
| `rule_task1_completed` | Task 1 的安全执行、目标成立和策略生成同时成立 | 策略完成性 |
| `task2_rule_monster_checkpoint` | 条件门要求清怪，怪物可见、持剑且生命安全，规则选择攻击 | 子任务正确性 |
| `task2_rule_chest_checkpoint` | 击杀并移动后宝箱相邻且未开，规则可选择宝箱 | 子任务正确性 |
| `task2_rule_conditional_exit_checkpoint` | 清怪并取钥匙后门禁资源满足，规则可选择条件出口 | 子任务正确性 |
| `rule_task2_environment_completed` | 从 Task 2 安全证书推出环境可完成性 | 环境可达性 |
| `task2_rule_policy_execution` | 杀怪、移动、开箱和出门计划由规则策略生成 | 策略生成性 |
| `rule_task2_completed` | Task 2 满足 `CompletedByRulePolicy` | 策略完成性 |
| `task3_rule_start_exit_checkpoint` | 初态普通出口未使用，规则可选择进入怪物房 | 子任务正确性 |
| `task3_rule_hall_monster_checkpoint` | 进入大厅后怪物相邻、持剑且生命安全，规则可攻击 | 子任务正确性 |
| `task3_rule_key_chest_checkpoint` | 到达钥匙房后宝箱相邻且未开，规则可开箱 | 子任务正确性 |
| `task3_rule_final_locked_exit_checkpoint` | 返回起点且持钥匙时，规则可选择最终锁门 | 子任务正确性 |
| `rule_task3_environment_completed` | 从 Task 3 安全证书推出多房间任务环境可完成 | 环境可达性 |
| `task3_rule_policy_execution` | 跨房、攻击、开箱、返回和最终出门计划由规则策略生成 | 策略生成性 |
| `rule_task3_completed` | Task 3 满足 `CompletedByRulePolicy` | 策略完成性 |

#### Task 4

| 定理 | 具体证明内容 | 类别 |
| --- | --- | --- |
| `task4_rule_first_switch_checkpoint` | 初态第一个旋桥开关可见、未触发且冷却允许，规则可选择开关 | 子任务正确性 |
| `task4_rule_key_chest_checkpoint` | 桥切换并进入北房后钥匙宝箱相邻且未开 | 子任务正确性 |
| `task4_rule_east_locked_exit_checkpoint` | 取钥匙返回中央后东侧非消耗钥匙门满足条件 | 子任务正确性 |
| `task4_rule_sword_chest_checkpoint` | 到达东房后剑宝箱相邻且未开，规则可取剑 | 子任务正确性 |
| `task4_rule_second_switch_checkpoint` | 取剑返回中央后第二个开关满足访问记忆和冷却条件 | 子任务正确性 |
| `task4_rule_guardian_checkpoint` | 进入南房时守卫相邻，玩家有剑且生命安全，规则可攻击 | 子任务正确性 |
| `task4_rule_final_chest_checkpoint` | 击杀守卫并返回后胜利宝箱相邻且未开 | 子任务正确性 |
| `rule_task4_environment_completed` | 从 Task 4 安全证书推出完整任务链在环境中可完成 | 环境可达性 |
| `task4_rule_policy_execution` | 13 步旋桥、钥匙、剑、守卫和终箱计划由规则策略逐步生成 | 策略生成性 |
| `rule_task4_completed` | Task 4 满足 `CompletedByRulePolicy` | 策略完成性 |

#### Task 5 与五关汇总

| 定理 | 具体证明内容 | 类别 |
| --- | --- | --- |
| `task5_rule_start_chest_checkpoint` | 初态起始宝箱相邻且未开，规则可选择开箱 | 子任务正确性 |
| `task5_rule_west_exit_checkpoint` | 起始宝箱处理后西侧普通出口未使用，规则可向西推进 | 子任务正确性 |
| `task5_rule_west_monster_checkpoint` | 进入西房后怪物相邻、持剑且生命安全，规则可攻击 | 子任务正确性 |
| `task5_rule_west_chest_checkpoint` | 击杀西房怪物后西房宝箱相邻且未开 | 子任务正确性 |
| `task5_rule_button_triggered_by_entry` | 返回中央进入按钮格后按钮已记录且累计按钮数为一 | 按钮正确性 |
| `task5_rule_conditional_exit_checkpoint` | 按钮触发后南侧条件门 ready 且未使用 | 子任务正确性 |
| `task5_rule_south_chest_checkpoint` | 进入南房后南侧宝箱相邻且未开 | 子任务正确性 |
| `task5_rule_east_locked_exit_checkpoint` | 返回中央且持钥匙时东侧锁门条件成立 | 子任务正确性 |
| `task5_rule_east_chest_checkpoint` | 进入东房后最终宝箱相邻且未开 | 子任务正确性 |
| `rule_task5_environment_completed` | 从 Task 5 安全证书推出综合任务环境可完成 | 环境可达性 |
| `task5_rule_policy_execution` | 四宝箱、怪物、按钮、条件门和钥匙门计划由具体规则策略生成 | 策略生成性 |
| `rule_task5_completed` | Task 5 满足 `CompletedByRulePolicy` | 策略完成性 |
| `all_rule_task_certificates` | 将五关 `RuleTaskCertificate` 汇总为一个合取结论 | 五关汇总 |
| `all_rule_tasks_policy_generated` | 汇总五条 `RulePolicyExec`，证明所有参考计划由规则策略生成 | 五关汇总 |

### 2.3 `Additional_Proofs.lean` 的 19 个 Rule-based 公开定理

| 定理 | 具体证明内容 | 类别 |
| --- | --- | --- |
| `exitPushAllowed_not_walkable` | 合法推出房间的目标越界，不能同时算普通可走移动 | 语义互斥 |
| `shielded_total` | 任意状态和原始动作至少存在一个 shield 输出 | Shield 全函数性 |
| `shielded_deterministic` | 同一状态和原始动作的两个 shield 输出必相等 | Shield 确定性 |
| `shielded_exists_unique` | shield 输出存在且唯一 | Shield 函数性 |
| `mem_safeActionsFrom_iff` | 动作在可计算安全动作表中，当且仅当它是方向移动且下一格可走 | successor 正确性 |
| `mem_safeSuccessors_iff` | 位置在一步安全后继表中，当且仅当存在安全移动动作到达它 | successor 等价性 |
| `mem_breadthFrontier_iff_positionReachable` | 位置在第 `n` 层 frontier 中，当且仅当 `PositionReachable s n p` | frontier 等价性 |
| `breadthFrontier_complete` | 每个 `n` 步安全可达位置都在可计算 frontier 中 | BFS 完备性 |
| `breadthFrontier_sound` | frontier 中每个位置都确实在 `n` 步内安全可达 | BFS 可靠性 |
| `breadth_search_complete` | 目标安全可达时，可计算 BFS 会包含目标 | 搜索完备性 |
| `breadth_search_sound` | BFS 报告找到目标时，该目标确实安全可达 | 搜索可靠性 |
| `breadth_search_sound_and_complete` | BFS 找到目标与目标安全可达双向等价 | 可靠且完备 |
| `breadthFindsGoal_eq_true_iff` | 布尔搜索判定为真，当且仅当存在安全可达目标 | 布尔实现正确性 |
| `safeMovePlan_positionReachable` | 任意安全移动计划产生 `PositionReachable` 见证 | 计划可靠性 |
| `positionReachable_has_safeMovePlan` | 任意 `PositionReachable` 见证都能提取安全移动计划 | 计划完备性 |
| `safeMovePlan_exec` | 提取的安全移动计划可在轻量环境中执行到目标 | 可执行性 |
| `verifiedSearchResult_sound` | 验证搜索结果中的计划安全、可执行并到达声明目标 | 搜索证书可靠性 |
| `breadth_found_has_verified_plan` | BFS 找到目标时可构造带安全计划的验证搜索结果 | 证书构造 |
| `verified_search_result_iff_reachable` | 存在验证搜索结果，当且仅当目标在界限内安全可达 | 最终可靠完备性 |

### 2.4 私有轨迹辅助定理

私有定理不是额外假设；它们逐步构造公开安全轨迹和策略轨迹。

| 私有定理 | 具体作用 |
| --- | --- |
| `task4_step_switch1` | Task 4 第一次旋桥的一步转移 |
| `task4_step_to_center` | 西房进入中央房的出口转移 |
| `task4_step_to_north` | 中央房进入北房的出口转移 |
| `task4_step_open_key` | 打开钥匙宝箱的转移 |
| `task4_step_back_for_east` | 北房返回中央准备去东房 |
| `task4_step_to_east` | 通过东侧非消耗钥匙门 |
| `task4_step_open_sword` | 打开剑宝箱 |
| `task4_step_back_to_switch` | 东房返回中央开关处 |
| `task4_step_switch2` | 第二次旋桥 |
| `task4_step_to_south` | 进入南房 |
| `task4_step_kill_guardian` | 持剑击杀守卫 |
| `task4_step_back_to_final` | 返回最终宝箱房 |
| `task4_step_open_final` | 打开胜利宝箱并完成世界 |
| `task5_step_open_start` | Task 5 打开起始宝箱 |
| `task5_step_to_west` | 进入西房 |
| `task5_step_kill_west_monster` | 击杀西房怪物 |
| `task5_step_open_west` | 打开西房宝箱 |
| `task5_step_back_to_button` | 返回中央并自动踩下按钮 |
| `task5_step_to_south` | 通过按钮门进入南房 |
| `task5_step_open_south` | 打开南房宝箱 |
| `task5_step_back_to_east_gate` | 返回中央东门 |
| `task5_step_to_east` | 使用钥匙进入东房 |
| `task5_step_open_east` | 打开东房最终宝箱 |
| `plannedInteractionStep` | 复用目标选择、executor、shield、环境一步和记忆更新的交互步骤 |
| `plannedSwitchOnStep` | 复用站在开关上按 A 的完整策略步骤 |
| `plannedStructuredExitStep` | 复用结构化出口的完整策略步骤 |
| `reflexAttackStep` | 复用紧急战斗反射攻击步骤 |
