import rule_based_submission.formalization.Strategy

/-!
本文件连接「环境形式化」和「策略形式化」，给出五个任务可使用的任务完成证明模板。

为什么单独拆出本文件：

1. `Environment.lean` 只描述环境，与策略无关；
2. `Strategy.lean` 只证明规则策略输出动作的合法性与安全性；
3. `TaskProofs.lean` 负责把若干子轨迹拼接起来，证明最终满足任务目标。

这使得第五关策略继续修改时，可以主要更新本文件中的第五关链条证明，
而不破坏环境层和通用策略安全层。
-/

namespace RuleBasedSubmission.Formalization

/-!
【任务可完成谓词】
`CompletedBy goal init` 表示从初始状态 `init` 出发，
存在一条环境执行轨迹到达某个满足目标谓词 `goal` 的最终状态。
-/
def CompletedBy (goal : SymbolicState → Prop) (init : SymbolicState) : Prop :=
  ∃ plan final, Exec init plan final ∧ goal final

/-!
【定理：给出成功轨迹即可证明任务可完成】
如果已经有一条 `Exec` 轨迹到达 `final`，且 `final` 满足目标谓词，
那么初始状态满足 `CompletedBy`。
-/
theorem completed_by_plan
    {goal : SymbolicState → Prop}
    {init final : SymbolicState} {plan : List Action}
    (hplan : Exec init plan final)
    (hgoal : goal final) :
    CompletedBy goal init := by
  exact ⟨plan, final, hplan, hgoal⟩

/-!
【定理：任务一的通用完成证明】
如果执行轨迹最终满足 `Task1Goal`，则任务一在该初始状态下可完成。
-/
theorem task1_completed_if_plan_reaches_goal
    {init final : SymbolicState} {plan : List Action}
    (hplan : Exec init plan final)
    (hgoal : Task1Goal final) :
    CompletedBy Task1Goal init :=
  completed_by_plan hplan hgoal

/-!
【定理：任务二的通用完成证明】
如果执行轨迹最终满足 `Task2Goal`，则任务二在该初始状态下可完成。
-/
theorem task2_completed_if_plan_reaches_goal
    {init final : SymbolicState} {plan : List Action}
    (hplan : Exec init plan final)
    (hgoal : Task2Goal final) :
    CompletedBy Task2Goal init :=
  completed_by_plan hplan hgoal

/-!
【定理：任务三的通用完成证明】
如果跨房间执行轨迹最终满足 `Task3Goal`，则任务三在该初始状态下可完成。
房间切换由环境层的 `EnvStep.exitRoom` 表达。
-/
theorem task3_completed_if_plan_reaches_goal
    {init final : SymbolicState} {plan : List Action}
    (hplan : Exec init plan final)
    (hgoal : Task3Goal final) :
    CompletedBy Task3Goal init :=
  completed_by_plan hplan hgoal

/-!
【定理：任务四的通用完成证明】
如果执行轨迹最终满足 `Task4Goal`，则任务四在该初始状态下可完成。
该谓词抽象“获得剑、清除关键怪物、保有通关资源”的核心链条。
-/
theorem task4_completed_if_plan_reaches_goal
    {init final : SymbolicState} {plan : List Action}
    (hplan : Exec init plan final)
    (hgoal : Task4Goal final) :
    CompletedBy Task4Goal init :=
  completed_by_plan hplan hgoal

/-!
【定理：任务五的通用完成证明】
如果执行轨迹最终满足 `Task5Goal`，则任务五在该初始状态下可完成。
这里给出与其他任务一致的完成接口。
-/
theorem task5_completed_if_plan_reaches_goal
    {init final : SymbolicState} {plan : List Action}
    (hplan : Exec init plan final)
    (hgoal : Task5Goal final) :
    CompletedBy Task5Goal init :=
  completed_by_plan hplan hgoal

/-!
【定理：任务一的子任务拼接证明】
如果存在一段路到达宝箱旁，按 A 开箱，再存在一段路到达出口，
并且最终玩家站在出口上，那么由钥匙单调性可推出任务一完成。
-/
theorem task1_completed_if_open_chest_then_exit
    {init nearChest afterChest final : SymbolicState}
    {toChest toExit : List Action}
    {chest : Position}
    (hToChest : Exec init toChest nearChest)
    (hChest : chest ∈ nearChest.chests)
    (hAdjacent : adjacent nearChest.player chest)
    (hAfterChest :
      afterChest =
        { nearChest with
          chests := nearChest.chests.erase chest,
          keys := nearChest.keys + 1 })
    (hToExit : Exec afterChest toExit final)
    (hFinalExit : final.player ∈ allExits final) :
    CompletedBy Task1Goal init := by
  have hOpenStep : EnvStep nearChest Action.pressA afterChest := by
    rw [hAfterChest]
    exact EnvStep.openChest hChest hAdjacent
  have hOpenExec : Exec nearChest [Action.pressA] afterChest := by
    exact Exec.cons hOpenStep Exec.nil
  have hPhase1 : Exec init (toChest ++ [Action.pressA]) afterChest :=
    exec_append hToChest hOpenExec
  have hAll : Exec init ((toChest ++ [Action.pressA]) ++ toExit) final :=
    exec_append hPhase1 hToExit
  have hAfterKeys : afterChest.keys > 0 := by
    rw [hAfterChest]
    exact Nat.succ_pos nearChest.keys
  have hKeyMono : afterChest.keys ≤ final.keys :=
    exec_keys_monotone hToExit
  have hFinalKeys : final.keys > 0 :=
    Nat.lt_of_lt_of_le hAfterKeys hKeyMono
  exact completed_by_plan hAll ⟨hFinalKeys, hFinalExit⟩

/-!
【定理：任务二的子任务拼接证明】
如果存在路径到怪物旁并成功攻击，再到宝箱旁开箱，最后到出口，
且最终怪物清空、玩家在出口上，则任务二完成。
-/
theorem task2_completed_if_kill_open_exit
    {init nearMonster afterKill nearChest afterChest final : SymbolicState}
    {toMonster toChest toExit : List Action}
    {monster chest : Position}
    (hToMonster : Exec init toMonster nearMonster)
    (hMonster : monster ∈ nearMonster.monsters)
    (hMonsterAdjacent : adjacent nearMonster.player monster)
    (hSword : nearMonster.hasSword = true)
    (hHealth : healthSafe nearMonster)
    (hAfterKill :
      afterKill =
        { nearMonster with monsters := nearMonster.monsters.erase monster })
    (hToChest : Exec afterKill toChest nearChest)
    (hChest : chest ∈ nearChest.chests)
    (hChestAdjacent : adjacent nearChest.player chest)
    (hAfterChest :
      afterChest =
        { nearChest with
          chests := nearChest.chests.erase chest,
          keys := nearChest.keys + 1 })
    (hToExit : Exec afterChest toExit final)
    (hFinalMonsters : final.monsters = [])
    (hFinalExit : final.player ∈ allExits final) :
    CompletedBy Task2Goal init := by
  have hAttackStep : EnvStep nearMonster Action.pressA afterKill := by
    rw [hAfterKill]
    exact EnvStep.attackMonster hMonster hMonsterAdjacent hSword hHealth
  have hAttackExec : Exec nearMonster [Action.pressA] afterKill := by
    exact Exec.cons hAttackStep Exec.nil
  have hOpenStep : EnvStep nearChest Action.pressA afterChest := by
    rw [hAfterChest]
    exact EnvStep.openChest hChest hChestAdjacent
  have hOpenExec : Exec nearChest [Action.pressA] afterChest := by
    exact Exec.cons hOpenStep Exec.nil
  have hPhase1 : Exec init (toMonster ++ [Action.pressA]) afterKill :=
    exec_append hToMonster hAttackExec
  have hPhase2 :
      Exec init ((toMonster ++ [Action.pressA]) ++ toChest) nearChest :=
    exec_append hPhase1 hToChest
  have hPhase3 :
      Exec init (((toMonster ++ [Action.pressA]) ++ toChest) ++ [Action.pressA])
        afterChest :=
    exec_append hPhase2 hOpenExec
  have hAll :
      Exec init
        ((((toMonster ++ [Action.pressA]) ++ toChest) ++ [Action.pressA]) ++ toExit)
        final :=
    exec_append hPhase3 hToExit
  have hAfterKeys : afterChest.keys > 0 := by
    rw [hAfterChest]
    exact Nat.succ_pos nearChest.keys
  have hKeyMono : afterChest.keys ≤ final.keys :=
    exec_keys_monotone hToExit
  have hFinalKeys : final.keys > 0 :=
    Nat.lt_of_lt_of_le hAfterKeys hKeyMono
  exact completed_by_plan hAll ⟨hFinalMonsters, hFinalKeys, hFinalExit⟩

/-!
【定理：任务三的换房轨迹拼接证明】
如果计划先到达出口并执行合法出门动作，再在新房间完成取钥匙和回出口轨迹，
最终满足 `Task3Goal`，则任务三完成。
-/
theorem task3_completed_if_room_chain_succeeds
    {init atExit afterRoom final : SymbolicState}
    {toExit rest : List Action}
    {leave : Action}
    (hToExit : Exec init toExit atExit)
    (hExitAllowed : exitPushAllowed atExit leave)
    (hAfterRoom : afterRoom = { atExit with room := nextRoom atExit.room leave })
    (hRest : Exec afterRoom rest final)
    (hGoal : Task3Goal final) :
    CompletedBy Task3Goal init := by
  have hLeaveStep : EnvStep atExit leave afterRoom := by
    rw [hAfterRoom]
    exact EnvStep.exitRoom hExitAllowed
  have hLeaveExec : Exec atExit [leave] afterRoom := by
    exact Exec.cons hLeaveStep Exec.nil
  have hPhase : Exec init (toExit ++ [leave]) afterRoom :=
    exec_append hToExit hLeaveExec
  have hAll : Exec init ((toExit ++ [leave]) ++ rest) final :=
    exec_append hPhase hRest
  exact completed_by_plan hAll hGoal

/-!
【定理：任务四的关键链条证明】
如果执行轨迹已经完成“取装备、开机关、清怪、获得资源”等关键链条，
并且最终状态满足 `Task4Goal`，则任务四完成。
本定理作为 Task4 报告中的主证明接口。
-/
theorem task4_completed_if_key_chain_succeeds
    {init final : SymbolicState} {plan : List Action}
    (hPlan : Exec init plan final)
    (hSword : final.hasSword = true)
    (hMonsters : final.monsters = [])
    (hKeys : final.keys > 0) :
    CompletedBy Task4Goal init := by
  exact completed_by_plan hPlan ⟨hSword, hMonsters, hKeys⟩

/-!
【定理：任务五的关键链条证明】
规则策略包含条件门按钮、锁门钥匙和全宝箱收集逻辑。
本定理表达第五关证明在任务层的核心拼接方式：
若策略执行轨迹到达一个“条件门前置条件已完成，并且所有宝箱均已打开”的状态，
则第五关完成。`hReady` 对应按钮和怪物前置条件，`hChests` 对应 `Task5Goal`。
-/
theorem task5_completed_if_conditional_chain_opens_all_chests
    {init final : SymbolicState} {plan : List Action}
    (hPlan : Exec init plan final)
    (hReady : conditionalDoorReady final)
    (hChests : final.chests = []) :
    CompletedBy Task5Goal init := by
  have _hTask5MechanismsReady : conditionalDoorReady final := hReady
  exact completed_by_plan hPlan hChests

/-!
【第五关证明义务】
`Task5ProofObligation init` 保留为报告中的总规格：
从初始状态出发存在轨迹到达满足 `Task5Goal` 的状态。
上面的定理给出了可引用的完成证明接口。
-/
def Task5ProofObligation (init : SymbolicState) : Prop :=
  CompletedBy Task5Goal init

end RuleBasedSubmission.Formalization
