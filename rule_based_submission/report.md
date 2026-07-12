# 数理逻辑课程项目实验报告：规则版 Agent 与 Lean 形式化证明

## 1. 项目目标

本项目面向 NesyLink 数理逻辑任务，目标是完成一个基于规则和符号规划的 Agent，并在 Lean 中形式化环境语义、策略可验证层和关键性质证明。

本报告对应规则版提交部分，主要覆盖：

- 环境形式化：将游戏中的状态、动作、对象、转移规则和任务目标抽象为 Lean 数据类型、函数和谓词；
- 策略形式化：将规则策略、planner/search、action mask、executor 和 safety shield 抽象为 Lean 关系；
- 性质证明：证明环境基本安全性、不变量、planner 完备性接口、策略动作合法性与安全性，以及成功轨迹满足任务目标；
- 实验结果：规则版 Agent 已在五个任务中给出通关运行记录。

## 2. 方法概述

规则版 Agent 的整体流程是：

1. `vision.py` 从像素帧中提取符号状态；
2. `symbolic.py` 维护跨步记忆，例如已开宝箱、已触发机关、已使用出口和房间记忆；
3. `strategy.py` 按规则优先级选择高层目标；
4. `planner.py` 用 BFS 搜索到目标附近或目标 tile 的安全路径；
5. `executor.py` 将目标转成一个原始动作；
6. `shield.py` 对原始动作做最终安全过滤；
7. `agent.py` 处理连续移动、像素对齐、战斗反应和房间切换记忆。

最终提交策略的决策依据是图像帧、历史反馈和接口中可见的持有物品信息。形式化证明不直接证明像素识别本身完全正确，而是从已经抽取出的符号状态 `SymbolicState` 开始，验证符号层策略和安全约束。

## 3. 规则策略设计

规则策略采用统一的 progress-first 目标选择逻辑。它不为每一关硬编码完整动作序列，而是根据当前符号状态选择下一步最有价值的目标。

核心优先级包括：

- 已有目标仍然有效时继续执行，减少抖动；
- 相邻宝箱优先开，宝箱可达时优先规划到宝箱；
- 怪物相邻且有剑、血量安全时攻击；
- 房间中宝箱、按钮、开关和未用出口都处理后，再把清怪作为离开前的 fallback；
- 条件门按“踩按钮、必要时清怪、走条件门”的顺序处理；
- 锁门出口要求持有钥匙；
- 普通出口、已用出口和探索目标作为后续推进手段；
- 没有可用目标时等待。

执行器层的动作语义为：

- 开箱和攻击需要相邻后按 A；
- 按钮通过走到按钮 tile 触发；
- 开关相邻后按 A；
- 出口目标需要走到门 tile，并朝门外方向移动；
- 探索目标通过 BFS 走向安全可通行 tile。

最后，safety shield 会过滤所有移动动作：不安全移动会被改成等待；合法出门动作和安全移动动作才会放行。

## 4. Lean 文件结构

Lean 文件位于 `rule_based_submission/formalization/`：

- `Environment.lean`：环境形式化；
- `Strategy.lean`：策略可验证层形式化与证明；
- `TaskProofs.lean`：任务完成证明模板；
- `formalization.md`：三个形式化文件的说明。

项目根目录包含 `lakefile.lean`，可以用以下命令检查：

```powershell
lake build
```

当前 Lean 文件不包含未说明的 `sorry`、`admit` 或 `axiom`。

## 5. 模块一：环境形式化

`Environment.lean` 定义了环境的符号层语义。

主要定义包括：

- 坐标与房间：`Position`、`RoomCoord`、`GlobalPosition`；
- 对象与资源：`ObjectKind`、`Item`、`Loot`、`MonsterKind`、`Chest`、`Monster`、`Exit`；
- 出口机制：`ExitKind`、`normalExits`、`lockedExits`、`conditionalExits`、`allExits`；
- 动作与目标：`Action`、`GoalKind`、`Goal`；
- 状态：`SymbolicState`；
- 地形谓词：`inBounds`、`terrainPassable`、`isWalkable`、`SafePosition`；
- 转移关系：`EnvStep`、`FullEnvStep`；
- 多步执行：`Exec`、`FullExec`；
- 任务目标：`Task1Goal` 到 `Task5Goal`。

`EnvStep` 覆盖策略层直接使用的轻量语义：安全移动、陷阱、阻挡、出门、开箱、攻击、机关、举盾和等待。

`FullEnvStep` 补充更完整的环境机制：结构化宝箱奖励、结构化怪物、NPC、盾牌抵挡、结构化出口、怪物 tick、环境 tick 和周期掉血。

环境层已证明的代表性性质包括：

- `walkable_is_safe_position`：可通行位置是安全位置；
- `move_safe_player_eq`：安全移动后玩家到达目标位置；
- `move_blocked_player_eq`：被阻挡移动不改变玩家位置；
- `safe_move_preserves_safe_position`：安全移动保持安全位置；
- `open_chest_increases_keys`：开箱增加钥匙；
- `attack_monster_removes_target`：攻击移除目标怪物；
- `env_step_keys_monotone` 和 `exec_keys_monotone`：钥匙数在轻量语义下单调不减；
- `healHealth_some_le_maxHealth`：回血不超过最大生命值；
- `monsterMoveAllowed_target_inBounds` 和 `monsterMoveAllowed_target_not_wall`：怪物合法移动目标在界内且不是墙；
- `lockedExit_condition_implies_enough_keys`：锁门出口可用蕴含钥匙足够；
- `bfs_completeness_from_frontier_invariant`：如果 BFS frontier 覆盖有界可达状态，则有界可达目标会被发现。

本模块对应实验手册中“状态 / 动作 / 对象 / 目标谓词齐全”“转移语义合理”“关键机制刻画”“基本安全性或不变量证明”的要求。

## 6. 模块二：策略形式化与证明

`Strategy.lean` 形式化的是规则版 Agent 的可验证符号层，而不是 Python 中每一行实现细节。

主要定义包括：

- `AgentMemory`：策略证明中使用的记忆抽象；
- `GoalAdmissible`：高层目标合法性；
- `ExitGoalAdmissible`：普通门、锁门、条件门的合法性；
- `RuleGoal`：规则策略可以选择的目标；
- `PositionReachable` 和 `PlannerCanReach`：有限步安全可达；
- `PlannerStep`：planner 输出第一步的安全契约；
- `PlannerFrontierComplete`、`PlannerGoalReachable`、`PlannerFindsGoal`：搜索完备性接口；
- `ActionAllowed`：action mask 规格；
- `ActionForGoal`：executor 从目标生成动作；
- `Shielded`：safety shield 过滤关系。

已证明的代表性策略性质包括：

- `rule_goal_admissible`：规则策略选择的目标一定合法；
- `planner_step_safe`：planner 输出的第一步是安全移动；
- `planner_completeness_from_frontier_invariant`：若有界可达目标被完备 frontier 覆盖，则搜索会发现目标；
- `planner_finds_singleton_of_reachable`：单目标版本的 planner 完备性；
- `action_for_goal_allowed`：executor 输出动作满足 action mask；
- `action_for_goal_move_safe_or_exit`：executor 输出的移动动作安全或合法出门；
- `shielded_output_allowed`：shield 输出满足 action mask；
- `shield_blocks_unsafe_movement`：不安全移动会被 shield 改为等待；
- `shielded_rule_action_safe_or_exit`：策略、executor、shield 串联后，最终移动安全或合法出门；
- `shielded_rule_action_safe_position_or_exit`：最终移动不会主动进入危险位置，合法出门除外；
- `rule_pipeline_output_allowed`：完整规则管线输出满足 action mask。

本模块对应实验手册中“planner/search/action mask 逻辑”“输出合法、安全”“成功执行满足目标”“可进一步证明完备性”的要求。

## 7. 模块二补充：任务完成证明

`TaskProofs.lean` 将环境轨迹与任务目标连接起来。

核心定义是：

```lean
def CompletedBy (goal : SymbolicState → Prop) (init : SymbolicState) : Prop :=
  ∃ plan final, Exec init plan final ∧ goal final
```

含义是：从初始状态出发，存在一条环境执行轨迹到达满足目标谓词的最终状态。

任务层定理包括：

- `completed_by_plan`：给出成功轨迹即可证明任务可完成；
- `task1_completed_if_plan_reaches_goal` 到 `task5_completed_if_plan_reaches_goal`：五个任务的统一完成接口；
- `task1_completed_if_open_chest_then_exit`：开箱后到出口即可完成任务一；
- `task2_completed_if_kill_open_exit`：杀怪、开箱、到出口即可完成任务二；
- `task3_completed_if_room_chain_succeeds`：跨房间链条成功即可完成任务三；
- `task4_completed_if_key_chain_succeeds`：关键链条成功即可完成任务四；
- `task5_completed_if_conditional_chain_opens_all_chests`：综合任务中条件门前置条件完成且宝箱目标完成即可证明任务完成。

这些定理表达的是轨迹验证器和任务完成判定层的正确性：只要执行轨迹满足形式化环境语义并到达目标状态，就能推出任务完成。因此它们属于策略形式化与证明模块中“成功执行时满足目标”的部分。

## 8. 实验结果

规则版 Agent 已完成五个任务。仓库 `runs/` 目录提供每个任务的通关录屏，作为代码运行结果附件：

| 任务 | 运行结果 |
| ---- | -------- |
| Task 1 | [runs/task1.gif](../runs/task1.gif) |
| Task 2 | [runs/task2.gif](../runs/task2.gif) |
| Task 3 | [runs/task3.gif](../runs/task3.gif) |
| Task 4 | [runs/task4.gif](../runs/task4.gif) |
| Task 5 | [runs/task5.gif](../runs/task5.gif) |

这些 gif 记录展示了规则版 Agent 在五个关卡中的完整通关过程。若需要重新运行批量评测，可使用：

```powershell
python utils\evaluate_policy.py --policy rule_based_submission.agent:Policy --num-envs 1 --seed 0
```

## 9. 抽象与简化说明

Lean 形式化做了以下抽象：

- Lean 从 `SymbolicState` 开始，不证明像素模板匹配和视觉识别对所有输入都正确；
- 连续像素移动被抽象成 tile 级动作和位置变化；
- Python 中的连续队列动作、像素对齐和卡住修正不逐帧建模，而由 planner/executor/shield 的符号层契约覆盖；
- 任务完成证明验证符号轨迹和目标谓词，不在 Lean 中重放 gif 的每一帧；
- 对神经网络或强化学习策略没有做证明，因为本报告对应规则版 Agent。

这些抽象保留了环境规则、策略决策和安全过滤中的核心逻辑，也与实验手册中“可证明 action mask、safety shield、符号 planner、轨迹验证器或任务完成判定”的要求一致。

## 10. 结论

本项目完成了规则版 Agent 的环境建模、策略实现和 Lean 形式化证明。

环境层覆盖了状态、动作、对象、目标谓词和主要交互机制；策略层覆盖了目标合法性、planner/search、action mask、executor 和 safety shield；任务层给出了五个任务的统一完成证明接口和关键子任务拼接证明。

实验结果方面，`runs/` 目录中的五个通关 gif 证明规则版 Agent 已能完成五个关卡。Lean 验证方面，`lake build` 可检查全部形式化文件，并且当前形式化文件不依赖未说明的 `sorry`、`admit` 或 `axiom`。
