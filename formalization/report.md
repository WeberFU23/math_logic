# 数理逻辑大作业形式化证明报告

本项目采用“公共环境语义 + 路线特有策略语义 + 任务证书”的分层形式化思路。
`Environment.lean` 给出两条路线共同遵守的状态机；Rule-based 和 RL-based 分别证明自己的决策层
满足环境约束；最后用 `SafeFullExec` 和五个任务目标谓词验证完整符号轨迹。

## 1. 环境形式化

### 1.1 状态定义

房间内坐标定义为 `Position := Int × Int`，房间坐标定义为 `RoomCoord := Int × Int`。
核心状态 `SymbolicState` 按游戏语义保存以下信息：

| 状态部分 | Lean 字段 | 含义 |
| --- | --- | --- |
| 玩家 | `player`, `room`, `facing`, `health`, `steps` | 位置、房间、朝向、生命和时钟 |
| 地图 | `walls`, `traps`, `gaps`, `bridges`, `bridgeState`, `npcs` | 不可走格、危险格、桥和 NPC |
| 可交互对象 | `chests`, `monsters`, `buttons`, `switches`, `exitObjects` | 宝箱、怪物、机关和出口 |
| 资源 | `keys`, `gold`, `items`, `hasSword`, `hasShield`, `shieldUp` | 背包、装备和举盾状态 |
| 任务里程碑 | `keysCollected`, `chestsOpened`, `monstersKilled`, `buttonsPressed`, `switchesActivated`, `roomsChanged`, `worldCompleted` | 不会因钥匙消耗等操作丢失的累计进度 |

任务目标使用累计里程碑而不是只观察最终背包。例如钥匙通过锁门后可以被消耗，但
`keysCollected ≥ 1` 仍能证明执行过程中确实取得过钥匙。

### 1.2 动作定义

`Action` 包含七个 Agent 动作和两个扩展环境动作：

```text
wait, up, down, left, right, pressA, pressB, useExit, envTick
```

`up/down/left/right` 通过 `delta` 和 `nextPosition` 更新位置；`pressA` 表示开箱、攻击或触发机关；
`pressB` 表示举盾；`useExit` 表示结构化换房；`envTick` 表示怪物移动、伤害、周期掉血和时钟推进。
`actionOfDirection` 与 `directionOfAction` 连接方向和移动动作。

### 1.3 对象定义

| 对象 | 关键字段或构造 | 形式化内容 |
| --- | --- | --- |
| `Chest` | `pos`, `loot`, `opened`, `room`, `completesTask` | 宝箱位置、奖励、状态和完成标记 |
| `Monster` | `pos`, `hp`, `kind`, `damage`, `loot`, `room` | 怪物生命、类型、伤害和掉落 |
| `Exit` | `pos`, `sourceRoom`, `targetRoom`, `targetSpawn`, `kind` | 出口位置、房间迁移和通过条件 |
| `ExitKind` | `normal`, `lockedKey`, `allMonstersAndKey`, `buttonGate`, `itemGate` | 普通门、钥匙门、清怪门、按钮门和物品门 |
| `Loot` | `none`, `key`, `gold`, `heal`, `item` | 开箱或击杀后的资源变化 |
| `BridgeState` | `northSouth`, `eastWest`, `openAll`, `closed` | Task 4 旋转桥状态 |

`canOpenChestObject`、`canAttackObject` 和 `canUseExitObject` 分别给出对象交互的前置条件。
例如攻击要求怪物存活、位于玩家面前且玩家持剑；出口要求玩家站在门上并满足 `exitCondition`。

### 1.4 目标谓词定义

高层目标由 `GoalKind` 和可选位置组成，覆盖开箱、攻击、按钮、开关、出口、探索和等待。
关卡完成条件直接定义为状态谓词：

| 目标谓词 | 必要条件 |
| --- | --- |
| `Task1Goal` | 世界完成、取得至少一把钥匙、打开至少一个宝箱 |
| `Task2Goal` | 世界完成、击杀怪物、取得钥匙、打开宝箱 |
| `Task3Goal` | 世界完成、至少五次换房、击杀怪物、取得钥匙、打开宝箱 |
| `Task4Goal` | 世界完成、至少两次开关、取得钥匙和剑、击杀怪物、打开至少三个宝箱 |
| `Task5Goal` | 世界完成、打开至少四个宝箱、至少五次换房、按下按钮、取得钥匙 |

`DeadState` 和 `TimedOut` 分别刻画死亡与超时，`FailedState` 是二者的析取。
`CompletedBy goal init` 表示存在一条环境轨迹从初态到达满足 `goal` 的状态；
`TaskCertificate` 进一步保存动作计划、最终状态、`SafeFullExec` 证明和目标证明。

### 1.5 动作转移语义

环境不是用一个可能遗漏前提条件的赋值函数描述，而是用归纳关系 `EnvStep s a t` 和
`FullEnvStep s a t` 描述“状态 `s` 执行动作 `a` 可以转移到状态 `t`”。

轻量语义 `EnvStep` 覆盖：

- `moveSafe`：目标格满足 `isWalkable` 时移动；
- `moveTrap`：地形可通过但目标是陷阱时移动并扣血；
- `moveBlocked`：墙、沟壑、对象等阻挡时保持原位；
- `exitRoom`：站在边界出口并向外推动时换房；
- `openChest`：相邻宝箱在按 A 后被移除并增加钥匙；
- `attackMonster`：相邻、持剑且血量安全时攻击怪物；
- `activateSwitch`：相邻按钮或开关在按 A 后被记录；
- `pressB` 与 `wait`：举盾接口或等待。

完整语义 `FullEnvStep` 在此基础上增加结构化开箱与掉落、怪物 HP、按钮计数、旋转桥、NPC、
盾牌抵伤、怪物移动和伤害、结构化出口、Task 5 周期掉血以及时钟推进。
`exitCondition` 分别检查钥匙数量、清怪状态、按钮记录或背包物品，
`useExitObjectState` 才能更新房间、出生点、钥匙和 `worldCompleted`。

`Exec` 和 `FullExec` 将一步关系递归扩展到动作列表。`SafeFullExec` 还要求轨迹中的每个状态都满足
`¬ FailedState`，因此死亡或超时状态不能被当作通关证书。

### 1.6 关键机制与环境定理

| 机制 | 主要函数 | 已证明性质 |
| --- | --- | --- |
| 合法移动 | `terrainPassable`, `isWalkable`, `SafePosition` | `walkable_is_safe_position`：可走格不越界、不进墙、陷阱或未连接沟壑 |
| 撞墙 | `EnvStep.moveBlocked` | `move_blocked_player_eq`：被阻挡后位置不变 |
| 陷阱和伤害 | `takeDamage`, `task5TimedDrainState` | 伤害只改变生命值，不破坏累计任务里程碑 |
| 开箱和攻击 | `applyLoot`, `openChestObjectState`, `attackMonsterObjectState` | 奖励、击杀和累计计数更新正确 |
| 按钮和桥 | `pressedButtons`, `toggleBridgeState` | 按钮记录、桥切换以及两次切换恢复原状态 |
| 条件门 | `exitCondition`, `canUseExitObject` | 可用按钮门、清怪钥匙门和物品门必然满足相应前置条件 |
| 安全轨迹 | `SafeFullExec` | `safeFullExec_append` 可拼接轨迹，`safeFullExec_final_not_failed` 保证终点非失败 |
| 进度不变量 | `ProgressLe`, `WorldCompletedMonotone` | `fullExec_progressLe` 和 `fullExec_worldCompletedMonotone` 证明累计进度与完成标志不会倒退 |

公共参考场景分别构造 `task1Plan` 至 `task5Plan`。定理 `task1_safe_execution` 至
`task5_safe_execution` 证明五条轨迹逐状态安全，`task1_goal` 至 `task5_goal` 证明其终点满足
对应任务目标。

## 2. Rule-based 策略形式化与证明

### 2.1 形式化思路与策略设计

Rule-based 路线被拆成可单独验证的三段管线：

```text
SymbolicState + AgentMemory
  -> RuleGoal
  -> ActionForGoal / PlannerStep
  -> Shielded
  -> Action
```

`AgentMemory` 记录已访问房间、已开宝箱、已击杀怪物、已触发机关和已用出口。
`RuleGoal` 根据当前状态和记忆产生符号目标，避免把 Python 控制流程整体当作一个不可分析函数。

### 2.2 目标选择和优先级

`GoalAdmissible` 给出每类目标的合法前提，`RuleGoal` 描述 sticky 目标、宝箱、按钮、开关、战斗、
出口、探索和等待等产生规则。`RulePriorityContract` 进一步约束选择器：存在未完成本地进度时
不能提前恢复或等待；出口必须满足资源、清怪和记忆条件。

主要结论包括：

- `rule_goal_admissible`：任何规则目标都满足目标合法性；
- `selector_chest_first`：存在可达未开宝箱时必须优先开箱；
- `selector_cannot_wait_with_progress`：存在具体进度时不能选择等待；
- `priority_selector_goal_admissible`：整个优先链始终输出合法目标。

### 2.3 Planner 和搜索

`PositionReachable state depth target` 表示目标位置恰好经过 `depth` 次安全移动可达；
`PlannerStep` 要求 planner 输出四向移动，并保证下一格 `isWalkable`。

除抽象 planner 契约外，还形式化了可计算逐层搜索：

- `safeActionsFrom` 过滤当前位置的安全四向动作；
- `safeSuccessors` 计算一步后继；
- `breadthFrontier state depth` 结构递归地产生恰好 `depth` 步的可达层；
- `SafeMovePlan` 和 `VerifiedSearchResult` 保存动作计划及其安全证明。

核心完备性结论为：

```lean
target ∈ breadthFrontier state depth ↔
  PositionReachable state depth target
```

`breadth_search_sound_and_complete` 因而同时给出搜索可靠性与完备性，
`safeMovePlan_exec` 证明提取出的计划确实能按公共 `Exec` 语义执行到目标。
这里的完备性只针对固定状态、固定深度的安全移动图，不表示任意地图必然通关。

### 2.4 Executor、动作约束和 Safety Shield

`ActionForGoal` 把目标转换为交互、planner 第一步、出口推动作或等待。
`ActionAllowed` 是 Rule-based 的动作约束：交互直接允许；普通移动必须走向 `isWalkable`；
边界出门必须满足 `exitPushAllowed`。

`Shielded state raw out` 放行安全动作和合法出口，将不安全移动替换为 `wait`。已证明：

- `action_for_goal_allowed`：executor 输出满足动作约束；
- `shielded_output_allowed`：shield 输出满足动作约束；
- `shield_blocks_unsafe_movement`：危险移动只能被过滤为等待；
- `shielded_rule_action_safe_position_or_exit`：最终移动安全或属于合法出门；
- `rule_pipeline_output_allowed`：从目标选择到最终动作的完整管线合法；
- `shielded_total`、`shielded_deterministic`：可控动作的 shield 输出存在且唯一。

### 2.5 五关证明

| 任务 | 规则检查点 | 完成定理 |
| --- | --- | --- |
| Task 1 | 开钥匙箱、通过锁门 | `rule_task1_completed` |
| Task 2 | 击杀怪物、开箱、条件出口 | `rule_task2_completed` |
| Task 3 | 多房间往返、怪物、钥匙箱、最终锁门 | `rule_task3_completed` |
| Task 4 | 两次旋转桥、钥匙、剑、守卫、最终宝箱 | `rule_task4_completed` |
| Task 5 | 四分支探索、怪物、按钮门、钥匙门、四宝箱 | `rule_task5_completed` |

每个检查点都构造具体 `RuleGoal`，证明规则关系在该状态允许预期目标；
`all_rule_task_certificates` 汇总五个 `TaskCertificate`。这些证书证明的是标准符号路线安全并达到目标，
不是把评测程序的每个 episode 预先写入 Lean。

### 2.6 实验结果

Rule-based 使用助教鲁棒性评测的正式结果保存在 `runs/final_evaluation.json`，
每个任务 100 个 episode，共 500 个：

| Task | 原图 | 空间变体 | 颜色变体 | 总成功率 |
| --- | ---: | ---: | ---: | ---: |
| Task 1 | 60/60 | 30/30 | 10/10 | 100% |
| Task 2 | 60/60 | 30/30 | 10/10 | 100% |
| Task 3 | 60/60 | 30/30 | 10/10 | 100% |
| Task 4 | 60/60 | 30/30 | 10/10 | 100% |
| Task 5 | 60/60 | 0/30 | 10/10 | 70% |
| 合计 | 300/300 | 120/150 | 50/50 | 470/500，94% |

失败全部集中在 Task 5 空间变体。Lean 中的安全性和任务证书说明标准符号路线满足规范；
实际鲁棒性结果则说明当前 Rule-based 实现仍需增强 Task 5 变体下的路径和战斗适应性。

## 3. RL-based 策略形式化与证明

### 3.1 形式化思路与模型接口

RL 路线不在 Lean 中展开 PPO 网络权重，而是验证网络外侧可检查的接口：

```text
像素 -> 符号状态 -> 特征编码 -> PPO option
     -> action mask -> goal resolver -> primitive shield -> 环境动作
```

神经网络被抽象为 `MaskablePolicy` 或 `Task5MaskablePolicy`。
`RespectsMask` 和 `Task5RespectsMask` 要求模型只选择最终 mask 中为真的 option。
因此 Lean 结论是条件式的：只要模型遵守 mask，后续解析和执行层就满足已经证明的规范；
并不声称任意权重或任意输入上的 logits 都正确。

### 3.2 符号特征编码

`ofSharedState` 将公共环境状态投影到 RL 编码视图。Task 1-4 的 `encodeHighLevelState` 使用
80 个网格标签、玩家坐标、四个怪物槽、背包、七位 mask、上一 option 和记忆，共 115 维；
Task 5 的 `encodeTask5State` 额外保留方向出口和九位接口，共 122 维。

已证明：

- `allTiles_length` 和 `allTiles_contains`：10×8 的 80 个格子被完整枚举；
- `encodeHighLevelState_wellFormed`：基础特征长度为 115，且每个值满足范围约束；
- `encodeTask5State_wellFormed`：Task 5 特征长度为 122，且每个值合法；
- `safeInfo_selects_exact_interface`：task id 精确选择 7/115 或 9/122 接口；
- `color_mode_base_features_invariant` 和 `color_mode_task5_features_invariant`：满足感知契约时颜色模式不改变编码。

### 3.3 Action Mask、优先级和 Goal Resolver

基础接口有七个高层 option：开箱、攻击、机关、新出口、返回/重访、探索、等待。
Task 5 将出口细分为东南西北四个方向，因此共有九个 option。

`normalizedMask` 和 `task5NormalizedMask` 在环境原始 mask 上执行优先级过滤：

- 宝箱或机关存在时抑制不必要攻击；
- 有本地进度时抑制出口、探索和等待；
- Task 5 阻路怪物优先于本地交互；
- 有钥匙时优先锁门方向，无钥匙时优先条件门方向；
- 新出口存在时抑制已使用出口；
- 没有任何具体进度时启用探索或等待兜底。

`resolveFromMask` 和 `task5ResolveFromMask` 把 option 解析为兼容的符号目标。
关键定理包括：

- `normalizedMask_enabled_exists`、`task5NormalizedMask_enabled_exists`：最终 mask 始终非空；
- `normalizedMask_nonwait_conservative`、`task5NormalizedMask_nonwait_conservative`：除等待兜底外不会创建原始 mask 未允许的 option；
- `normalizedMask_sound`、`task5NormalizedMask_sound`：原始 mask 满足 readiness 时，最终 mask 仍然可靠；
- `mask_respecting_policy_ready_resolution`、`task5_mask_respecting_policy_ready_resolution`：模型选择可解析为兼容且环境 ready 的目标。

### 3.4 Primitive Safety Shield

`PrimitiveDecision` 保存 primitive 动作和 `setupOnly` 标记；非 setup 移动通过 `shield` 检查
`safeTile`。不安全移动被替换为等待，交互动作保持不变。

已证明 `shield_preserves_safe_move`、`shield_idempotent` 和 `shield_move_output_safe`：
安全移动不会被改写，重复过滤结果不变，且 shield 最终保留的移动一定指向安全 tile。

### 3.5 五关证明

| 任务 | RL 检查点 | 完成定理 |
| --- | --- | --- |
| Task 1 | 开箱 option、锁门 option | `rl_task1_completed` |
| Task 2 | 攻击、开箱、条件出口 | `rl_task2_completed` |
| Task 3 | 出口往返、怪物、钥匙箱、最终锁门 | `rl_task3_completed` |
| Task 4 | 开关、钥匙、锁门、剑、守卫、最终宝箱 | `rl_task4_completed` |
| Task 5 | 宝箱、阻路怪物、按钮、南门、返回、东侧锁门 | `rl_task5_completed` |

每个 RL 检查点同时证明三件事：最终 mask 允许预期 option，resolver 得到兼容目标，
对应公共环境对象满足 readiness。`all_rl_tasks_completed` 汇总五个安全任务证书。

### 3.6 实验结果

`rl` 分支的正式结果 `results/rl_robustness_official_500.json` 使用纯 PPO 高层策略，
同样按每个任务 100 个 episode 运行：

| Task | 原图 | 空间变体 | 颜色变体 | 总成功率 |
| --- | ---: | ---: | ---: | ---: |
| Task 1 | 60/60 | 30/30 | 10/10 | 100% |
| Task 2 | 60/60 | 30/30 | 10/10 | 100% |
| Task 3 | 60/60 | 30/30 | 10/10 | 100% |
| Task 4 | 60/60 | 30/30 | 10/10 | 100% |
| Task 5 | 60/60 | 0/30 | 10/10 | 70% |
| 合计 | 300/300 | 120/150 | 50/50 | 470/500，94% |

RL 的全部 30 次失败都来自 Task 5 空间变体，终止原因为 `agent_dead`；原图和五种颜色模式全部通过。
这与形式化边界一致：Lean 已验证 mask、resolver 和 shield 的接口性质，但模型仍可能在合法动作中
做出长期回报较差的选择，尤其是变化后的战斗位置和路线。

## 4. Lean 代码命名、证明结构与验证

Lean 代码采用统一命名规则：

- 类型和关系使用清晰的 PascalCase，如 `SymbolicState`、`FullEnvStep`、`SafeFullExec`、`RuleGoal`；
- 可计算函数使用 camelCase，如 `nextPosition`、`normalizedMask`、`breadthFrontier`；
- 定理使用 snake_case，并用 `rule_`、`rl_` 或 `taskN_` 标明路线和任务；
- 公共环境位于 `MathLogic.Formalization`，两条策略分别位于 `RuleBasedSubmission.Formalization` 和 `RLBasedSubmission.Formalization`。

证明按“定义 -> 通用引理 -> 策略安全定理 -> 关卡检查点 -> 任务证书”组织。
公共状态和转移只定义一次；Rule-based 与 RL-based 分别导入公共环境，不复制环境语义。
所有 Lean 文件均不含 `sorry`、`admit` 或额外 `axiom`。

仓库同时提供 Lean DSL 和 TOML 两种 Lake 配置，使用固定工具链验证：

```powershell
lake -f lakefile.lean build formalization
lake -f lakefile.toml build formalization
rg -n "\b(sorry|admit|axiom)\b" .\formalization -g "*.lean"
```

两个构建命令都应成功，最后一条命令应无匹配。`lean-toolchain` 固定为
`leanprover/lean4:v4.29.0-rc8`，确保助教环境能够复现相同的 elaboration 结果。
