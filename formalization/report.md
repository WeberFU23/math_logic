# 数理逻辑大作业形式化证明报告

## 1. 环境形式化

### 1.1 状态定义

房间内位置为 `Position := Int × Int`，房间坐标为 `RoomCoord := Int × Int`。
核心状态 `SymbolicState` 保存：

| 内容 | Lean 字段 |
| --- | --- |
| 玩家 | `player`, `room`, `facing`, `health`, `steps` |
| 地图 | `walls`, `traps`, `gaps`, `bridges`, `bridgeState`, `npcs` |
| 对象 | `chests`, `monsters`, `buttons`, `switches`, `exitObjects` |
| 资源 | `keys`, `gold`, `items`, `hasSword`, `hasShield`, `shieldUp` |
| 累计进度 | `keysCollected`, `chestsOpened`, `monstersKilled`, `buttonsPressed`, `switchesActivated`, `roomsChanged`, `worldCompleted` |

目标使用累计进度。例如钥匙开门后可以被消耗，但 `keysCollected ≥ 1`
仍能证明轨迹中取得过钥匙。

### 1.2 动作定义

```text
wait, up, down, left, right, pressA, pressB, useExit, envTick
```

四个方向动作由 `delta` 和 `nextPosition` 计算；`pressA` 用于开箱、攻击和开关；
`pressB` 用于举盾；`useExit` 是结构化换房；`envTick` 表示环境自动结算。

### 1.3 对象定义

| 对象 | 形式化内容 |
| --- | --- |
| `Chest` | 位置、奖励、是否打开、所属房间、任务完成标记 |
| `Monster` | 位置、HP、类型、伤害、掉落、所属房间 |
| `Exit` | 位置、来源房间、目标房间、出生点和出口类型 |
| `ExitKind` | 普通门、钥匙门、清怪门、按钮门和物品门 |
| `Loot` | 钥匙、金币、回血和物品等奖励 |
| `BridgeState` | Task 4 的南北、东西、全开和关闭状态 |

`canOpenChestObject`、`canAttackObject`、`canUseExitObject` 给出对象交互前提；
`exitCondition` 检查钥匙、怪物、按钮或物品条件。

### 1.4 目标谓词定义

高层 `GoalKind` 包含开箱、攻击、按钮、开关、出口、探索和等待。五关完成条件为：

| 谓词 | 条件 |
| --- | --- |
| `Task1Goal` | 世界完成，取得钥匙，打开宝箱 |
| `Task2Goal` | 世界完成，击杀怪物，取得钥匙，打开宝箱 |
| `Task3Goal` | 世界完成，至少五次换房，击杀怪物，取得钥匙，打开宝箱 |
| `Task4Goal` | 世界完成，两次开关，取得钥匙和剑，击杀怪物，打开三个宝箱 |
| `Task5Goal` | 世界完成，打开四个宝箱，至少五次换房，踩按钮，取得钥匙 |

`FailedState` 表示死亡或超时。`TaskCertificate` 保存计划、终态、
`SafeFullExec` 安全轨迹和终态目标证明。

### 1.5 动作转移语义

`EnvStep before action after` 描述安全移动、陷阱移动、撞墙、边界换房、开箱、
攻击、开关、举盾和等待。`FullEnvStep` 进一步描述结构化掉落、怪物 HP、
旋转桥、NPC、盾牌抵伤、怪物行为、Task 5 周期掉血和结构化出口。

按钮采用“站上触发”语义。`moveSafe`、`moveTrap` 和 `useExitObjectState`
都会调用 `enterPositionState`；首次进入按钮格时立即更新 `pressedButtons` 和
`buttonsPressed`，不需要再执行 `pressA`。

`FullExec` 将一步转移扩展为动作列表。`SafeFullExec` 要求初态、中间状态和终态
均不满足 `FailedState`，因此死亡或超时轨迹不能作为通关证书。

### 1.6 环境性质

| 性质 | 主要定理 |
| --- | --- |
| 合法移动不越界，不进入墙、陷阱、未桥接沟壑或怪物格 | `walkable_is_safe_position` |
| 撞墙后位置不变 | `move_blocked_player_eq` |
| 首次踩按钮计数，再次进入不重复计数 | `enterPositionState_records_fresh_button`, `enterPositionState_does_not_recount_button` |
| 旋转桥切换两次恢复原状态 | `toggleBridge_twice` |
| 条件出口必须满足对应前置条件 | `buttonGate_exit_requires_pressed` 等 |
| 安全轨迹可拼接且终点未失败 | `safeFullExec_append`, `safeFullExec_final_not_failed` |
| 累计进度和完成标志不倒退 | `fullExec_progressLe`, `fullExec_worldCompletedMonotone` |

`task1_safe_execution` 至 `task5_safe_execution` 给出五关公共安全轨迹，
`task1_goal` 至 `task5_goal` 证明其终点满足目标。

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
可执行函数 `ruleBasedChooseGoal` 按 Python 高层策略的顺序处理 sticky 目标、宝箱、
必要清怪、条件门、锁门、普通门、开关、回退出口、探索和等待。

`RulePriorityContract` 的 `implementation` 将 selector 固定为该函数，
`ruleBasedChooseGoal_priorityContract` 给出具体实例。由此证明：

- `ruleBasedChooseGoal_admissible`：具体选择器始终输出合法目标；
- `concrete_selector_chest_first`：无 sticky 时宝箱优先；
- `concrete_selector_conditional_button_first`：高优先级分支为空时按钮优先；
- `priority_selector_goal_admissible`：实际选择器满足目标合法性契约。

### 2.2 Planner、Executor 与 Shield

`PlannerStep` 保证 planner 的第一步是安全四向移动。可计算搜索满足：

```lean
target ∈ breadthFrontier state depth ↔
  PositionReachable state depth target
```

因此 `breadth_search_sound_and_complete` 给出固定状态、固定深度安全移动图上的
可靠性和完备性，不表示任意地图必然通关。

`ActionForGoal` 将目标转换为移动、交互、出口宏动作或等待；
`button_action_for_goal_ne_pressA` 明确证明按钮目标不会输出 A 键。
`Shielded` 放行安全动作并把危险移动替换为 `wait`。主要安全结论为
`action_for_goal_allowed`、`shielded_output_allowed`、
`shielded_rule_action_safe_position_or_exit`、`shielded_total` 和
`shielded_deterministic`。

### 2.3 策略生成的通关证明

`RulePolicyStep` 串联具体选择器、executor、shield、`FullEnvStep` 和
`updateRuleMemory`；紧急战斗由 `CombatReflex` 分支处理。`RulePolicyExec`
归纳串联整条状态、动作和记忆轨迹。

`RuleTaskCertificate` 的 `execution`、`completed` 和 `generated` 使用同一
`plan` 与 `final`。`CompletedByRulePolicy` 同时要求安全环境轨迹、目标成立和
同一计划的 `RulePolicyExec` 见证。

| 任务 | 完成定理 |
| --- | --- |
| Task 1：钥匙箱和锁门 | `rule_task1_completed` |
| Task 2：战斗、宝箱和条件门 | `rule_task2_completed` |
| Task 3：多房间往返和最终锁门 | `rule_task3_completed` |
| Task 4：旋转桥、钥匙、剑、守卫和最终宝箱 | `rule_task4_completed` |
| Task 5：三个分支、自动按钮、钥匙门和四个宝箱 | `rule_task5_completed` |

`taskN_rule_policy_execution` 逐步证明五条计划由具体策略生成；
`all_rule_task_certificates` 汇总五个强化结论。纯环境存在性另以
`rule_taskN_environment_completed` 命名。

`useExit` 将真实执行器连续推动门口的过程抽象为一次结构化换房；像素移动队列、
卡住微调和视觉识别不属于该符号策略状态机。

### 2.4 实验结果

`runs/final_evaluation.json` 共 500 个 episode：

| Task | 原图 | 空间变体 | 颜色变体 | 总成功率 |
| --- | ---: | ---: | ---: | ---: |
| Task 1 | 60/60 | 30/30 | 10/10 | 100% |
| Task 2 | 60/60 | 30/30 | 10/10 | 100% |
| Task 3 | 60/60 | 30/30 | 10/10 | 100% |
| Task 4 | 60/60 | 30/30 | 10/10 | 100% |
| Task 5 | 60/60 | 0/30 | 10/10 | 70% |
| 合计 | 300/300 | 120/150 | 50/50 | 470/500，94% |

失败均来自 Task 5 空间变体，说明实际控制层仍需提高空间变化下的适应性。

## 3. RL-based 路线

### 3.1 形式化思路与策略设计

```text
像素 -> 符号状态 -> 特征编码 -> PPO option
     -> action mask -> goal resolver -> primitive shield -> 环境动作
```

神经网络抽象为 `MaskablePolicy` 或 `Task5MaskablePolicy`。
`RespectsMask` 和 `Task5RespectsMask` 要求模型只选择 mask 允许的 option。
Lean 验证网络外的编码、mask、resolver 和 shield，不证明网络权重对所有输入都最优。

### 3.2 可验证层与定理

| 可验证层 | 主要定义 | 结论 |
| --- | --- | --- |
| 特征编码 | `encodeHighLevelState`, `encodeTask5State` | 长度分别为 115 和 122，且各值满足范围约束 |
| 网格覆盖 | `allTiles` | `allTiles_length`、`allTiles_contains` 证明 10×8 网格完整 |
| 颜色不变性 | `ColorModeInvariant` | 两个 `color_mode_*_features_invariant` 证明满足契约时编码不变 |
| Action mask | `normalizedMask`, `task5NormalizedMask` | mask 非空、除等待兜底外保持保守、满足 readiness 时可靠 |
| Goal resolver | `resolveFromMask`, `task5ResolveFromMask` | 遵守 mask 的模型输出可解析为兼容且 ready 的目标 |
| Primitive shield | `shield`, `safeTile` | 安全移动保持、过滤幂等、最终移动安全 |

五关的 `BaseCheckpoint` 或 `Task5Checkpoint` 证明预期 option 被 mask 允许、
resolver 返回规范目标、环境对象满足 readiness。Task 5 的
`task5_rl_button_triggered_by_entry` 证明返回中心时自动踩下按钮。

`rlTask1Certificate` 至 `rlTask5Certificate` 给出安全参考环境轨迹，
`rl_task1_completed` 至 `rl_task5_completed` 证明目标可安全达到。
这些定理不声称 PPO 必然选择每个检查点列出的 option；实际模型与验证层的关系由
`RespectsMask` 条件定理刻画。

### 3.3 实验结果

`rl` 分支的 `results/rl_robustness_official_500.json` 共 500 个 episode：

| Task | 原图 | 空间变体 | 颜色变体 | 总成功率 |
| --- | ---: | ---: | ---: | ---: |
| Task 1 | 60/60 | 30/30 | 10/10 | 100% |
| Task 2 | 60/60 | 30/30 | 10/10 | 100% |
| Task 3 | 60/60 | 30/30 | 10/10 | 100% |
| Task 4 | 60/60 | 30/30 | 10/10 | 100% |
| Task 5 | 60/60 | 0/30 | 10/10 | 70% |
| 合计 | 300/300 | 120/150 | 50/50 | 470/500，94% |

30 次失败均为 Task 5 空间变体中的 `agent_dead`。这说明局部约束层不能替代
模型对长期战斗和路线的选择。

## 4. Lean 命名、证明结构与验证

类型和关系使用 PascalCase，可计算函数使用 camelCase，定理使用 snake_case；
`rule_`、`rl_` 和 `taskN_` 前缀区分路线与任务。证明按“定义、通用引理、
策略安全定理、关卡检查点、任务证书”组织，Rule-based 与 RL-based 分开陈述。

仓库提交 `lakefile.lean`、`lakefile.toml` 和 `lean-toolchain`，固定工具链为
`leanprover/lean4:v4.29.0-rc8`。所有 Lean 文件不含 `sorry`、`admit` 或额外 `axiom`。

```powershell
lake -f lakefile.lean build formalization
lake -f lakefile.toml build formalization
rg -n "\b(sorry|admit|axiom)\b" .\formalization -g "*.lean"
```

两个构建命令应成功，最后一条命令应无匹配。
