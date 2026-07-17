import formalization.RL_based_Strategy

open MathLogic.Formalization
open MathLogic.Formalization.ReferenceTasks

/-!
本文件给出 RL-based 路线在五个任务上的策略证书。

五关的对象、状态、环境转移、失败条件和目标谓词全部来自共享的
`Environment.lean`。本文件只验证 RL 路线特有的接口：

1. 共享状态投影后满足 115/122 维特征契约；
2. 最终 action mask 在关键检查点允许预期 option；
3. 被选 option 能解析为兼容高层目标，并且该目标在共享环境中确实可执行；
4. 五条公共轨迹分别形成 `TaskCertificate`，从而得到安全通关存在性。

PPO 权重保持为不透明对象。因此这里证明的是模型外围的符号接口和一条经认证路线，
不声称任意训练权重都会自动选择这条路线。
-/

namespace RLBasedSubmission.Formalization

open Strategy

/-! ## 共享环境上的 option 可执行性 -/

def chestObjectReady (state : SharedState)
    (chest : MathLogic.Formalization.Chest) : Bool :=
  decide (chest ∈ state.chestObjects) &&
  decide (chest.room = state.room) &&
  !chest.opened &&
  decide (MathLogic.Formalization.facingTarget state = chest.pos)

def chestReady (state : SharedState) : Bool :=
  state.chestObjects.any (chestObjectReady state)

def monsterObjectReady (state : SharedState)
    (monster : MathLogic.Formalization.Monster) : Bool :=
  decide (monster ∈ state.monsterObjects) &&
  decide (monster.room = state.room) &&
  decide (monster.hp > 0) &&
  decide (MathLogic.Formalization.facingTarget state = monster.pos) &&
  (state.hasSword || decide (MathLogic.Formalization.Item.sword ∈ state.items))

def monsterReady (state : SharedState) : Bool :=
  state.monsterObjects.any (monsterObjectReady state)

def mechanismReady (state : SharedState) : Bool :=
  decide (state.player ∈ state.buttons) || decide (state.player ∈ state.switches)

def exitConditionReady (state : SharedState)
    (exit : MathLogic.Formalization.Exit) : Bool :=
  match exit.kind with
  | MathLogic.Formalization.ExitKind.normal => true
  | MathLogic.Formalization.ExitKind.lockedKey need _ => decide (need ≤ state.keys)
  | MathLogic.Formalization.ExitKind.allMonstersAndKey need _ =>
      decide (need ≤ state.keys) && decide (state.monsters = [])
  | MathLogic.Formalization.ExitKind.buttonGate button =>
      decide (button ∈ state.pressedButtons)
  | MathLogic.Formalization.ExitKind.itemGate item =>
      decide (item ∈ state.items)

def exitObjectReady (state : SharedState)
    (exit : MathLogic.Formalization.Exit) : Bool :=
  decide (exit ∈ state.exitObjects) &&
  decide (exit.sourceRoom = state.room) &&
  decide (exit.pos = state.player) &&
  exitConditionReady state exit

def exitReady (state : SharedState) : Bool :=
  state.exitObjects.any (exitObjectReady state)

theorem chestObjectReady_iff
    (state : SharedState) (chest : MathLogic.Formalization.Chest) :
    chestObjectReady state chest = true ↔
      MathLogic.Formalization.canOpenChestObject state chest := by
  simp [chestObjectReady, MathLogic.Formalization.canOpenChestObject,
    MathLogic.Formalization.inFront, and_assoc]

theorem monsterObjectReady_iff
    (state : SharedState) (monster : MathLogic.Formalization.Monster) :
    monsterObjectReady state monster = true ↔
      MathLogic.Formalization.canAttackObject state monster := by
  simp [monsterObjectReady, MathLogic.Formalization.canAttackObject,
    MathLogic.Formalization.inFront, MathLogic.Formalization.hasItem, and_assoc]

theorem exitConditionReady_iff
    (state : SharedState) (exit : MathLogic.Formalization.Exit) :
    exitConditionReady state exit = true ↔
      MathLogic.Formalization.exitCondition state exit := by
  cases hkind : exit.kind <;> simp [exitConditionReady,
    MathLogic.Formalization.exitCondition, hkind]

theorem exitObjectReady_iff
    (state : SharedState) (exit : MathLogic.Formalization.Exit) :
    exitObjectReady state exit = true ↔
      MathLogic.Formalization.canUseExitObject state exit := by
  simp [exitObjectReady, MathLogic.Formalization.canUseExitObject,
    exitConditionReady_iff, and_assoc]
theorem chestReady_iff (state : SharedState) :
    chestReady state = true ↔
      ∃ chest, chest ∈ state.chestObjects ∧
        MathLogic.Formalization.canOpenChestObject state chest := by
  simp [chestReady, chestObjectReady_iff]

theorem monsterReady_iff (state : SharedState) :
    monsterReady state = true ↔
      ∃ monster, monster ∈ state.monsterObjects ∧
        MathLogic.Formalization.canAttackObject state monster := by
  simp [monsterReady, monsterObjectReady_iff]

theorem mechanismReady_iff (state : SharedState) :
    mechanismReady state = true ↔
      state.player ∈ state.buttons ∨ state.player ∈ state.switches := by
  simp [mechanismReady]

theorem exitReady_iff (state : SharedState) :
    exitReady state = true ↔
      ∃ exit, exit ∈ state.exitObjects ∧
        MathLogic.Formalization.canUseExitObject state exit := by
  simp [exitReady, exitObjectReady_iff]

def baseOptionReady (state : SharedState) : HighLevelAction → Bool
  | HighLevelAction.openChest => chestReady state
  | HighLevelAction.attackMonster => monsterReady state
  | HighLevelAction.activateMechanism => mechanismReady state
  | HighLevelAction.takeNewExit => exitReady state
  | HighLevelAction.returnOrRevisit => exitReady state
  | HighLevelAction.exploreRoom => true
  | HighLevelAction.wait => true

def task5ExitMatchesDirection
    (option : Task5Action) (exit : MathLogic.Formalization.Exit) : Bool :=
  match option with
  | Task5Action.exitNorth => decide (exit.targetRoom.2 < exit.sourceRoom.2)
  | Task5Action.exitEast => decide (exit.sourceRoom.1 < exit.targetRoom.1)
  | Task5Action.exitSouth => decide (exit.sourceRoom.2 < exit.targetRoom.2)
  | Task5Action.exitWest => decide (exit.targetRoom.1 < exit.sourceRoom.1)
  | _ => false

def task5DirectionalExitReady (state : SharedState) (option : Task5Action) : Bool :=
  state.exitObjects.any fun exit =>
    exitObjectReady state exit &&
      task5ExitMatchesDirection option exit

def task5OptionReady (state : SharedState) : Task5Action → Bool
  | Task5Action.openChest => chestReady state
  | Task5Action.attackMonster => monsterReady state
  | Task5Action.activateMechanism => mechanismReady state
  | Task5Action.exitNorth => task5DirectionalExitReady state Task5Action.exitNorth
  | Task5Action.exitEast => task5DirectionalExitReady state Task5Action.exitEast
  | Task5Action.exitSouth => task5DirectionalExitReady state Task5Action.exitSouth
  | Task5Action.exitWest => task5DirectionalExitReady state Task5Action.exitWest
  | Task5Action.exploreRoom => true
  | Task5Action.wait => true

/-! ## 固定长度 mask 与特征输入 -/

def baseRawMask (enabled : List HighLevelAction) : List Bool :=
  [ decide (HighLevelAction.openChest ∈ enabled)
  , decide (HighLevelAction.attackMonster ∈ enabled)
  , decide (HighLevelAction.activateMechanism ∈ enabled)
  , decide (HighLevelAction.takeNewExit ∈ enabled)
  , decide (HighLevelAction.returnOrRevisit ∈ enabled)
  , decide (HighLevelAction.exploreRoom ∈ enabled)
  , decide (HighLevelAction.wait ∈ enabled)
  ]

def task5RawMask (enabled : List Task5Action) : List Bool :=
  [ decide (Task5Action.openChest ∈ enabled)
  , decide (Task5Action.attackMonster ∈ enabled)
  , decide (Task5Action.activateMechanism ∈ enabled)
  , decide (Task5Action.exitNorth ∈ enabled)
  , decide (Task5Action.exitEast ∈ enabled)
  , decide (Task5Action.exitSouth ∈ enabled)
  , decide (Task5Action.exitWest ∈ enabled)
  , decide (Task5Action.exploreRoom ∈ enabled)
  , decide (Task5Action.wait ∈ enabled)
  ]

def emptyMemorySummary : MemorySummary :=
  { visitedRooms := 0
    openedChests := 0
    killedMonsters := 0
    activatedSwitches := 0
    usedExits := 0
    roomSteps := 0 }

def emptyTask5MemorySummary : Task5MemorySummary :=
  { visitedRooms := 0
    openedChests := 0
    killedMonsters := 0
    activatedSwitches := 0
    usedExits := 0
    roomSteps := 0
    roomX := 0
    roomY := 0
    elapsedSteps := 0 }

def baseInputFromShared
    (state : SharedState) (enabled : List HighLevelAction) : HighLevelInput :=
  { state := ofSharedState state
    actionMask := normalizedMask (baseRawMask enabled)
    lastOption := none
    memory := emptyMemorySummary }

def task5InputFromShared
    (state : SharedState) (context : Task5MaskContext) : Task5HighLevelInput :=
  { state := task5ViewOfSharedState state
    actionMask := task5NormalizedMask context
    lastOption := none
    memory := emptyTask5MemorySummary }

theorem base_shared_input_wellFormed
    (state : SharedState) (enabled : List HighLevelAction) :
    WellFormedFeatures (encodeHighLevelState (baseInputFromShared state enabled)) :=
  encodeHighLevelState_wellFormed _

theorem task5_shared_input_wellFormed
    (state : SharedState) (context : Task5MaskContext) :
    Task5WellFormedFeatures (encodeTask5State (task5InputFromShared state context)) :=
  encodeTask5State_wellFormed _

/-!
检查点同时要求：最终 mask 中 option 为真、resolver 返回其规范目标，并且共享环境中
存在当前可执行的对应对象。目标兼容性由下面两个对所有 option 成立的定理统一给出。
-/
def BaseCheckpoint
    (state : SharedState) (enabled : List HighLevelAction)
    (selected : HighLevelAction) : Prop :=
  let mask := normalizedMask (baseRawMask enabled)
  actionAtMask mask selected = true ∧
  resolveFromMask mask selected = some (canonicalGoalForOption selected) ∧
  baseOptionReady state selected = true

def Task5Checkpoint
    (state : SharedState) (context : Task5MaskContext)
    (selected : Task5Action) : Prop :=
  let mask := task5NormalizedMask context
  task5ActionAtMask mask selected = true ∧
  task5ResolveFromMask mask selected = some (task5CanonicalGoalForOption selected) ∧
  task5OptionReady state selected = true

instance baseCheckpointDecidable
    (state : SharedState) (enabled : List HighLevelAction)
    (selected : HighLevelAction) :
    Decidable (BaseCheckpoint state enabled selected) := by
  unfold BaseCheckpoint
  infer_instance

instance task5CheckpointDecidable
    (state : SharedState) (context : Task5MaskContext)
    (selected : Task5Action) :
    Decidable (Task5Checkpoint state context selected) := by
  unfold Task5Checkpoint
  infer_instance

theorem every_base_checkpoint_goal_compatible (selected : HighLevelAction) :
    CompatibleGoal selected (canonicalGoalForOption selected) :=
  canonicalGoal_compatible selected

theorem every_task5_checkpoint_goal_compatible (selected : Task5Action) :
    Task5CompatibleGoal selected (task5CanonicalGoalForOption selected) :=
  task5CanonicalGoal_compatible selected

/-! ## Task 1：钥匙箱与锁门 -/

theorem task1_rl_chest_checkpoint :
    BaseCheckpoint task1Init [HighLevelAction.openChest]
      HighLevelAction.openChest := by
  native_decide

theorem task1_rl_locked_exit_checkpoint :
    BaseCheckpoint task1AfterChest [HighLevelAction.takeNewExit]
      HighLevelAction.takeNewExit := by
  native_decide

def rlTask1Certificate : TaskCertificate Task1Goal task1Init :=
  { plan := task1Plan
    final := task1Final
    execution := task1_safe_execution
    completed := task1_goal }

theorem rl_task1_completed : CompletedBy Task1Goal task1Init :=
  taskCertificate_completedBy rlTask1Certificate

/-! ## Task 2：必须先消灭怪物，再取钥匙并通过条件门 -/

theorem task2_rl_monster_checkpoint :
    BaseCheckpoint task2Init [HighLevelAction.attackMonster]
      HighLevelAction.attackMonster := by
  native_decide

theorem task2_rl_chest_checkpoint :
    BaseCheckpoint task2AfterMove [HighLevelAction.openChest]
      HighLevelAction.openChest := by
  native_decide

theorem task2_rl_conditional_exit_checkpoint :
    BaseCheckpoint task2AfterChest [HighLevelAction.takeNewExit]
      HighLevelAction.takeNewExit := by
  native_decide

def rlTask2Certificate : TaskCertificate Task2Goal task2Init :=
  { plan := task2Plan
    final := task2Final
    execution := task2_safe_execution
    completed := task2_goal }

theorem rl_task2_completed : CompletedBy Task2Goal task2Init :=
  taskCertificate_completedBy rlTask2Certificate

/-! ## Task 3：跨房间取钥匙并回到最终锁门 -/

theorem task3_rl_start_exit_checkpoint :
    BaseCheckpoint task3Init [HighLevelAction.takeNewExit]
      HighLevelAction.takeNewExit := by
  native_decide

theorem task3_rl_hall_monster_checkpoint :
    BaseCheckpoint task3InHall [HighLevelAction.attackMonster]
      HighLevelAction.attackMonster := by
  native_decide

theorem task3_rl_key_chest_checkpoint :
    BaseCheckpoint task3InKeyRoom [HighLevelAction.openChest]
      HighLevelAction.openChest := by
  native_decide

theorem task3_rl_return_from_key_room_checkpoint :
    BaseCheckpoint task3AfterChest [HighLevelAction.returnOrRevisit]
      HighLevelAction.returnOrRevisit := by
  native_decide

theorem task3_rl_return_to_start_checkpoint :
    BaseCheckpoint task3BackInHall [HighLevelAction.returnOrRevisit]
      HighLevelAction.returnOrRevisit := by
  native_decide

theorem task3_rl_final_locked_exit_checkpoint :
    BaseCheckpoint task3BackAtStart [HighLevelAction.takeNewExit]
      HighLevelAction.takeNewExit := by
  native_decide

def rlTask3Certificate : TaskCertificate Task3Goal task3Init :=
  { plan := task3Plan
    final := task3Final
    execution := task3_safe_execution
    completed := task3_goal }

theorem rl_task3_completed : CompletedBy Task3Goal task3Init :=
  taskCertificate_completedBy rlTask3Certificate

/-! ## Task 4：两次旋桥、钥匙、剑、守卫与最终宝箱 -/

theorem task4_rl_first_switch_checkpoint :
    BaseCheckpoint task4Init [HighLevelAction.activateMechanism]
      HighLevelAction.activateMechanism := by
  native_decide

theorem task4_rl_key_chest_checkpoint :
    BaseCheckpoint task4InNorth [HighLevelAction.openChest]
      HighLevelAction.openChest := by
  native_decide

theorem task4_rl_east_locked_exit_checkpoint :
    BaseCheckpoint task4BackForEast [HighLevelAction.takeNewExit]
      HighLevelAction.takeNewExit := by
  native_decide

theorem task4_rl_sword_chest_checkpoint :
    BaseCheckpoint task4InEast [HighLevelAction.openChest]
      HighLevelAction.openChest := by
  native_decide

theorem task4_rl_second_switch_checkpoint :
    BaseCheckpoint task4AtCenterSwitch [HighLevelAction.activateMechanism]
      HighLevelAction.activateMechanism := by
  native_decide

theorem task4_rl_guardian_checkpoint :
    BaseCheckpoint task4InSouth [HighLevelAction.attackMonster]
      HighLevelAction.attackMonster := by
  native_decide

theorem task4_rl_final_chest_checkpoint :
    BaseCheckpoint task4AtFinalChest [HighLevelAction.openChest]
      HighLevelAction.openChest := by
  native_decide

def rlTask4Certificate : TaskCertificate Task4Goal task4Init :=
  { plan := task4Plan
    final := task4Final
    execution := task4_safe_execution
    completed := task4_goal }

theorem rl_task4_completed : CompletedBy Task4Goal task4Init :=
  taskCertificate_completedBy rlTask4Certificate

/-! ## Task 5：九动作方向 mask、按钮门、钥匙门和四个宝箱 -/

def task5StartChestContext : Task5MaskContext :=
  { rawMask := task5RawMask [Task5Action.openChest] }

def task5WestExitContext : Task5MaskContext :=
  { rawMask := task5RawMask [Task5Action.exitWest] }

def task5BlockingMonsterContext : Task5MaskContext :=
  { rawMask := task5RawMask [Task5Action.openChest, Task5Action.attackMonster]
    attackIsProgress := true }

def task5WestChestContext : Task5MaskContext :=
  { rawMask := task5RawMask [Task5Action.openChest] }


def task5SouthExitContext : Task5MaskContext :=
  { rawMask := task5RawMask [Task5Action.exitSouth]
    conditionalDirections := [Task5Action.exitSouth] }

def task5SouthChestContext : Task5MaskContext :=
  { rawMask := task5RawMask [Task5Action.openChest] }

def task5ReturnNorthContext : Task5MaskContext :=
  { rawMask := task5RawMask [Task5Action.exitNorth]
    usedDirections := [Task5Action.exitNorth] }

def task5EastLockedExitContext : Task5MaskContext :=
  { rawMask := task5RawMask [Task5Action.exitEast]
    lockedDirections := [Task5Action.exitEast]
    hasKey := true }

def task5EastChestContext : Task5MaskContext :=
  { rawMask := task5RawMask [Task5Action.openChest] }

theorem task5_rl_start_chest_checkpoint :
    Task5Checkpoint task5Init task5StartChestContext Task5Action.openChest := by
  native_decide

theorem task5_rl_west_exit_checkpoint :
    Task5Checkpoint task5AfterStartChest task5WestExitContext Task5Action.exitWest := by
  native_decide

theorem task5_rl_blocking_monster_checkpoint :
    Task5Checkpoint task5InWest task5BlockingMonsterContext
      Task5Action.attackMonster := by
  native_decide

theorem task5_rl_west_chest_checkpoint :
    Task5Checkpoint task5AfterWestMonster task5WestChestContext
      Task5Action.openChest := by
  native_decide

theorem task5_rl_button_triggered_by_entry :
    (4, 4) ∈ task5BackAtButton.pressedButtons ∧
      task5BackAtButton.buttonsPressed = 1 :=
  task5_button_triggered_on_entry
theorem task5_rl_conditional_south_exit_checkpoint :
    Task5Checkpoint task5AfterButton task5SouthExitContext
      Task5Action.exitSouth := by
  native_decide

theorem task5_rl_south_chest_checkpoint :
    Task5Checkpoint task5InSouth task5SouthChestContext
      Task5Action.openChest := by
  native_decide

theorem task5_rl_return_north_checkpoint :
    Task5Checkpoint task5AfterSouthChest task5ReturnNorthContext
      Task5Action.exitNorth := by
  native_decide

theorem task5_rl_locked_east_exit_checkpoint :
    Task5Checkpoint task5BackAtEastGate task5EastLockedExitContext
      Task5Action.exitEast := by
  native_decide

theorem task5_rl_east_chest_checkpoint :
    Task5Checkpoint task5InEast task5EastChestContext
      Task5Action.openChest := by
  native_decide

def rlTask5Certificate : TaskCertificate Task5Goal task5Init :=
  { plan := task5Plan
    final := task5Final
    execution := task5_safe_execution
    completed := task5_goal }

theorem rl_task5_completed : CompletedBy Task5Goal task5Init :=
  taskCertificate_completedBy rlTask5Certificate

/-! ## 五关总证书 -/

structure RLTaskSuite where
  task1 : TaskCertificate Task1Goal task1Init
  task2 : TaskCertificate Task2Goal task2Init
  task3 : TaskCertificate Task3Goal task3Init
  task4 : TaskCertificate Task4Goal task4Init
  task5 : TaskCertificate Task5Goal task5Init

def rlTaskSuite : RLTaskSuite :=
  { task1 := rlTask1Certificate
    task2 := rlTask2Certificate
    task3 := rlTask3Certificate
    task4 := rlTask4Certificate
    task5 := rlTask5Certificate }

theorem all_rl_tasks_completed :
    CompletedBy Task1Goal task1Init ∧
    CompletedBy Task2Goal task2Init ∧
    CompletedBy Task3Goal task3Init ∧
    CompletedBy Task4Goal task4Init ∧
    CompletedBy Task5Goal task5Init := by
  exact ⟨rl_task1_completed, rl_task2_completed, rl_task3_completed,
    rl_task4_completed, rl_task5_completed⟩

end RLBasedSubmission.Formalization
