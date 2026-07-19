import Rule_based_Strategy

open MathLogic.Formalization
open MathLogic.Formalization.ReferenceTasks

/-!
本文件给出 rule-based 路线在五个任务上的策略证书。

公共关卡状态、完整环境转移和无失败轨迹全部来自 `Environment.lean`。
本文件在同一组状态上完成规则路线特有的四层证明：

1. 保留关系式 `RuleGoal` 检查点，说明局部规则为何合法；
2. 为五关每一步证明具体 `ruleBasedChooseGoal` 的计算结果；
3. 通过 `RulePolicyStep` 串联 executor、shield、`FullEnvStep` 和
   `updateRuleMemory`，再以 `RulePolicyExec` 贯穿整条轨迹；
4. 用 `RuleTaskCertificate` 同时封装安全执行、任务目标和策略生成性。

前半部分的 `ruleTaskNEnvironmentCertificate` 仅作为公共环境基线；正式的
`ruleTaskNCertificate` 还证明同一计划确由规则 Agent 逐步产生。
-/

namespace RuleBasedSubmission.Formalization

def emptyRuleMemory : AgentMemory := {}

/-! ## Task 1 -/

def task1RuleChestGoal : Goal :=
  { kind := GoalKind.openChest, target := some task1Chest.pos }

def task1RuleExitGoal : Goal :=
  { kind := GoalKind.goToExit, target := some task1Exit.pos }

theorem task1_rule_chest_checkpoint :
    RuleGoal task1Init emptyRuleMemory task1RuleChestGoal := by
  apply RuleGoal.adjacentChest
  · simp [task1Init]
  · simp [emptyRuleMemory]
  · simp [adjacent, manhattan, absDiff, task1Init, task1Chest]

theorem task1_rule_locked_exit_checkpoint :
    RuleGoal task1AfterChest emptyRuleMemory task1RuleExitGoal := by
  apply RuleGoal.unusedLockedExit
  · simp [task1AfterChest, openChestObjectState, task1Init, task1Exit,
      task1Chest, applyLoot]
  · simp [task1AfterChest, openChestObjectState, task1Init,
      task1Chest, applyLoot]
  · simp [emptyRuleMemory]

def ruleTask1EnvironmentCertificate : TaskCertificate Task1Goal task1Init :=
  { plan := task1Plan
    final := task1Final
    execution := task1_safe_execution
    completed := task1_goal }

theorem rule_task1_environment_completed : CompletedBy Task1Goal task1Init :=
  taskCertificate_completedBy ruleTask1EnvironmentCertificate

/-! ## Task 2 -/

def task2RuleMonsterGoal : Goal :=
  { kind := GoalKind.attackMonster, target := some task2Monster.pos }

def task2RuleChestGoal : Goal :=
  { kind := GoalKind.openChest, target := some task2Chest.pos }

def task2RuleExitGoal : Goal :=
  { kind := GoalKind.goToExit, target := some task2Exit.pos }

theorem task2_rule_monster_checkpoint :
    RuleGoal task2Init emptyRuleMemory task2RuleMonsterGoal := by
  apply RuleGoal.conditionalMonster
  · simp [task2Init]
  · simp [noVisibleButtons, task2Init]
  · simp [task2Init]
  · simp [task2Init]
  · simp [healthSafe, task2Init]

theorem task2_rule_chest_checkpoint :
    RuleGoal task2AfterMove emptyRuleMemory task2RuleChestGoal := by
  apply RuleGoal.adjacentChest
  · simp [task2AfterMove, task2AfterMonster, attackMonsterObjectState,
      task2Init, task2Monster, task2Chest, applyLoot,
      damageMonsterObjectAt, nextPosition, delta]
  · simp [emptyRuleMemory]
  · simp [adjacent, manhattan, absDiff, task2AfterMove,
      task2AfterMonster, attackMonsterObjectState, task2Init,
      task2Monster, task2Chest, applyLoot, damageMonsterObjectAt,
      nextPosition, delta]

theorem task2_rule_conditional_exit_checkpoint :
    RuleGoal task2AfterChest emptyRuleMemory task2RuleExitGoal := by
  apply RuleGoal.unusedConditionalExit
  · simp [task2AfterChest, openChestObjectState, task2AfterMove,
      task2AfterMonster, attackMonsterObjectState, task2Init,
      task2Monster, task2Chest, task2Exit, applyLoot,
      damageMonsterObjectAt, nextPosition, delta]
  · simp [conditionalDoorReady, visibleButtonsSatisfied,
      task2AfterChest, openChestObjectState, task2AfterMove,
      task2AfterMonster, attackMonsterObjectState, task2Init,
      task2Monster, task2Chest, applyLoot, damageMonsterObjectAt,
      nextPosition, delta]
  · simp [emptyRuleMemory]

def ruleTask2EnvironmentCertificate : TaskCertificate Task2Goal task2Init :=
  { plan := task2Plan
    final := task2Final
    execution := task2_safe_execution
    completed := task2_goal }

theorem rule_task2_environment_completed : CompletedBy Task2Goal task2Init :=
  taskCertificate_completedBy ruleTask2EnvironmentCertificate

/-! ## Task 3 -/

def task3RuleStartExitGoal : Goal :=
  { kind := GoalKind.goToExit, target := some task3StartToHall.pos }

def task3RuleMonsterGoal : Goal :=
  { kind := GoalKind.attackMonster, target := some task3Monster.pos }

def task3RuleChestGoal : Goal :=
  { kind := GoalKind.openChest, target := some task3Chest.pos }

def task3RuleFinalExitGoal : Goal :=
  { kind := GoalKind.goToExit, target := some task3FinalExit.pos }

theorem task3_rule_start_exit_checkpoint :
    RuleGoal task3Init emptyRuleMemory task3RuleStartExitGoal := by
  apply RuleGoal.unusedNormalExit
  · simp [task3Init]
  · simp [emptyRuleMemory]

theorem task3_rule_hall_monster_checkpoint :
    RuleGoal task3InHall emptyRuleMemory task3RuleMonsterGoal := by
  apply RuleGoal.adjacentMonster
  · simp [task3InHall, useExitObjectState, task3Init,
      task3StartToHall, task3Monster, keysAfterExit]
  · simp [adjacent, manhattan, absDiff, task3InHall,
      useExitObjectState, task3Init, task3StartToHall,
      task3Monster, keysAfterExit]
  · simp [task3InHall, useExitObjectState, task3Init,
      task3StartToHall, keysAfterExit]
  · simp [healthSafe, task3InHall, useExitObjectState,
      task3Init, task3StartToHall, keysAfterExit]

theorem task3_rule_key_chest_checkpoint :
    RuleGoal task3InKeyRoom emptyRuleMemory task3RuleChestGoal := by
  apply RuleGoal.adjacentChest
  · simp [task3InKeyRoom, useExitObjectState, task3AfterMonster,
      attackMonsterObjectState, task3InHall, task3Init,
      task3StartToHall, task3HallToKey, task3Monster,
      task3Chest, applyLoot, damageMonsterObjectAt, keysAfterExit]
  · simp [emptyRuleMemory]
  · simp [adjacent, manhattan, absDiff, task3InKeyRoom,
      useExitObjectState, task3AfterMonster,
      attackMonsterObjectState, task3InHall, task3Init,
      task3StartToHall, task3HallToKey, task3Monster,
      task3Chest, applyLoot, damageMonsterObjectAt, keysAfterExit]

theorem task3_rule_final_locked_exit_checkpoint :
    RuleGoal task3BackAtStart emptyRuleMemory task3RuleFinalExitGoal := by
  apply RuleGoal.unusedLockedExit
  · simp [task3BackAtStart, useExitObjectState, task3BackInHall,
      task3AfterChest, openChestObjectState, task3InKeyRoom,
      task3AfterMonster, attackMonsterObjectState, task3InHall,
      task3Init, task3StartToHall, task3HallToKey,
      task3KeyToHall, task3HallToStart, task3FinalExit,
      task3Monster, task3Chest, applyLoot, damageMonsterObjectAt,
      keysAfterExit]
  · simp [task3BackAtStart, useExitObjectState, task3BackInHall,
      task3AfterChest, openChestObjectState, task3InKeyRoom,
      task3AfterMonster, attackMonsterObjectState, task3InHall,
      task3Init, task3StartToHall, task3HallToKey,
      task3KeyToHall, task3HallToStart, task3Monster,
      task3Chest, applyLoot, damageMonsterObjectAt, keysAfterExit]
  · simp [emptyRuleMemory]

def ruleTask3EnvironmentCertificate : TaskCertificate Task3Goal task3Init :=
  { plan := task3Plan
    final := task3Final
    execution := task3_safe_execution
    completed := task3_goal }

theorem rule_task3_environment_completed : CompletedBy Task3Goal task3Init :=
  taskCertificate_completedBy ruleTask3EnvironmentCertificate
/-! ## Task 4 -/

def task4RuleSwitchGoal (position : Position) : Goal :=
  { kind := GoalKind.activateSwitch, target := some position }

def task4RuleKeyChestGoal : Goal :=
  { kind := GoalKind.openChest, target := some task4KeyChest.pos }

def task4RuleEastExitGoal : Goal :=
  { kind := GoalKind.goToExit, target := some task4CenterToEast.pos }

def task4RuleSwordChestGoal : Goal :=
  { kind := GoalKind.openChest, target := some task4SwordChest.pos }

def task4RuleGuardianGoal : Goal :=
  { kind := GoalKind.attackMonster, target := some task4Guardian.pos }

def task4RuleFinalChestGoal : Goal :=
  { kind := GoalKind.openChest, target := some task4FinalChest.pos }

theorem task4_rule_first_switch_checkpoint :
    RuleGoal task4Init emptyRuleMemory (task4RuleSwitchGoal (9, 4)) := by
  apply RuleGoal.switchMechanism
  · simp [task4Init]
  · simp [emptyRuleMemory]
  · simp [emptyRuleMemory]

theorem task4_rule_key_chest_checkpoint :
    RuleGoal task4InNorth emptyRuleMemory task4RuleKeyChestGoal := by
  apply RuleGoal.adjacentChest
  · simp [task4InNorth, useExitObjectState, task4InCenter,
      task4AfterFirstSwitch, task4Init, task4WestToCenter,
      task4CenterToNorth, task4KeyChest, keysAfterExit]
  · simp [emptyRuleMemory]
  · simp [adjacent, manhattan, absDiff, task4InNorth,
      useExitObjectState, task4InCenter, task4AfterFirstSwitch,
      task4Init, task4WestToCenter, task4CenterToNorth,
      task4KeyChest, keysAfterExit]

theorem task4_rule_east_locked_exit_checkpoint :
    RuleGoal task4BackForEast emptyRuleMemory task4RuleEastExitGoal := by
  apply RuleGoal.unusedLockedExit
  · simp [task4BackForEast, useExitObjectState, task4AfterKey,
      openChestObjectState, task4InNorth, task4InCenter,
      task4AfterFirstSwitch, task4Init, task4WestToCenter,
      task4CenterToNorth, task4NorthToCenter, task4CenterToEast,
      task4KeyChest, applyLoot, keysAfterExit]
  · simp [task4BackForEast, useExitObjectState, task4AfterKey,
      openChestObjectState, task4InNorth, task4InCenter,
      task4AfterFirstSwitch, task4Init, task4WestToCenter,
      task4CenterToNorth, task4NorthToCenter, task4KeyChest,
      applyLoot, keysAfterExit]
  · simp [emptyRuleMemory]

theorem task4_rule_sword_chest_checkpoint :
    RuleGoal task4InEast emptyRuleMemory task4RuleSwordChestGoal := by
  apply RuleGoal.adjacentChest
  · simp [task4InEast, useExitObjectState, task4BackForEast,
      task4AfterKey, openChestObjectState, task4InNorth,
      task4InCenter, task4AfterFirstSwitch, task4Init,
      task4WestToCenter, task4CenterToNorth, task4NorthToCenter,
      task4CenterToEast, task4KeyChest, task4SwordChest,
      applyLoot, keysAfterExit]
  · simp [emptyRuleMemory]
  · simp [adjacent, manhattan, absDiff, task4InEast,
      useExitObjectState, task4BackForEast, task4AfterKey,
      openChestObjectState, task4InNorth, task4InCenter,
      task4AfterFirstSwitch, task4Init, task4WestToCenter,
      task4CenterToNorth, task4NorthToCenter, task4CenterToEast,
      task4KeyChest, task4SwordChest, applyLoot, keysAfterExit]

theorem task4_rule_second_switch_checkpoint :
    RuleGoal task4AtCenterSwitch emptyRuleMemory
      (task4RuleSwitchGoal (4, 4)) := by
  apply RuleGoal.switchMechanism
  · simp [task4AtCenterSwitch, useExitObjectState, task4AfterSword,
      openChestObjectState, task4InEast, task4BackForEast,
      task4AfterKey, task4InNorth, task4InCenter,
      task4AfterFirstSwitch, task4Init, task4WestToCenter,
      task4CenterToNorth, task4NorthToCenter, task4CenterToEast,
      task4EastToCenter, task4KeyChest, task4SwordChest,
      applyLoot, keysAfterExit]
  · simp [emptyRuleMemory]
  · simp [emptyRuleMemory]

theorem task4_rule_guardian_checkpoint :
    RuleGoal task4InSouth emptyRuleMemory task4RuleGuardianGoal := by
  apply RuleGoal.adjacentMonster
  · simp [task4InSouth, useExitObjectState, task4AfterSecondSwitch,
      task4AtCenterSwitch, task4AfterSword, openChestObjectState,
      task4InEast, task4BackForEast, task4AfterKey, task4InNorth,
      task4InCenter, task4AfterFirstSwitch, task4Init,
      task4WestToCenter, task4CenterToNorth, task4NorthToCenter,
      task4CenterToEast, task4EastToCenter, task4CenterToSouth,
      task4Guardian, task4KeyChest, task4SwordChest,
      applyLoot, keysAfterExit]
  · simp [adjacent, manhattan, absDiff, task4InSouth,
      useExitObjectState, task4AfterSecondSwitch, task4AtCenterSwitch,
      task4AfterSword, openChestObjectState, task4InEast,
      task4BackForEast, task4AfterKey, task4InNorth, task4InCenter,
      task4AfterFirstSwitch, task4Init, task4WestToCenter,
      task4CenterToNorth, task4NorthToCenter, task4CenterToEast,
      task4EastToCenter, task4CenterToSouth, task4Guardian,
      task4KeyChest, task4SwordChest, applyLoot, keysAfterExit]
  · simp [task4InSouth, useExitObjectState, task4AfterSecondSwitch,
      task4AtCenterSwitch, task4AfterSword, openChestObjectState,
      task4InEast, task4BackForEast, task4AfterKey, task4InNorth,
      task4InCenter, task4AfterFirstSwitch, task4Init,
      task4WestToCenter, task4CenterToNorth, task4NorthToCenter,
      task4CenterToEast, task4EastToCenter, task4CenterToSouth,
      task4KeyChest, task4SwordChest, applyLoot, keysAfterExit]
  · simp [healthSafe, task4InSouth, useExitObjectState,
      task4AfterSecondSwitch, task4AtCenterSwitch, task4AfterSword,
      openChestObjectState, task4InEast, task4BackForEast,
      task4AfterKey, task4InNorth, task4InCenter,
      task4AfterFirstSwitch, task4Init, task4WestToCenter,
      task4CenterToNorth, task4NorthToCenter, task4CenterToEast,
      task4EastToCenter, task4CenterToSouth, task4KeyChest,
      task4SwordChest, applyLoot, keysAfterExit]

theorem task4_rule_final_chest_checkpoint :
    RuleGoal task4AtFinalChest emptyRuleMemory task4RuleFinalChestGoal := by
  apply RuleGoal.adjacentChest
  · simp [task4AtFinalChest, useExitObjectState,
      task4AfterGuardian, attackMonsterObjectState, task4InSouth,
      task4AfterSecondSwitch, task4AtCenterSwitch, task4AfterSword,
      openChestObjectState, task4InEast, task4BackForEast,
      task4AfterKey, task4InNorth, task4InCenter,
      task4AfterFirstSwitch, task4Init, task4WestToCenter,
      task4CenterToNorth, task4NorthToCenter, task4CenterToEast,
      task4EastToCenter, task4CenterToSouth, task4SouthToCenter,
      task4KeyChest, task4SwordChest, task4FinalChest,
      task4Guardian, applyLoot, damageMonsterObjectAt,
      keysAfterExit]
  · simp [emptyRuleMemory]
  · simp [adjacent, manhattan, absDiff, task4AtFinalChest,
      useExitObjectState, task4AfterGuardian,
      attackMonsterObjectState, task4InSouth, task4AfterSecondSwitch,
      task4AtCenterSwitch, task4AfterSword, openChestObjectState,
      task4InEast, task4BackForEast, task4AfterKey, task4InNorth,
      task4InCenter, task4AfterFirstSwitch, task4Init,
      task4WestToCenter, task4CenterToNorth, task4NorthToCenter,
      task4CenterToEast, task4EastToCenter, task4CenterToSouth,
      task4SouthToCenter, task4KeyChest, task4SwordChest,
      task4FinalChest, task4Guardian, applyLoot,
      damageMonsterObjectAt, keysAfterExit]

def ruleTask4EnvironmentCertificate : TaskCertificate Task4Goal task4Init :=
  { plan := task4Plan
    final := task4Final
    execution := task4_safe_execution
    completed := task4_goal }

theorem rule_task4_environment_completed : CompletedBy Task4Goal task4Init :=
  taskCertificate_completedBy ruleTask4EnvironmentCertificate
/-! ## Task 5 -/

def task5RuleChestGoal (position : Position) : Goal :=
  { kind := GoalKind.openChest, target := some position }

def task5RuleMonsterGoal : Goal :=
  { kind := GoalKind.attackMonster, target := some task5WestMonster.pos }

def task5RuleExitGoal (position : Position) : Goal :=
  { kind := GoalKind.goToExit, target := some position }

theorem task5_rule_start_chest_checkpoint :
    RuleGoal task5Init emptyRuleMemory
      (task5RuleChestGoal task5StartChest.pos) := by
  apply RuleGoal.adjacentChest
  · simp [task5Init]
  · simp [emptyRuleMemory]
  · simp [adjacent, manhattan, absDiff, task5Init, task5StartChest]

theorem task5_rule_west_exit_checkpoint :
    RuleGoal task5AfterStartChest emptyRuleMemory
      (task5RuleExitGoal task5CenterToWest.pos) := by
  apply RuleGoal.unusedNormalExit
  · simp [task5AfterStartChest, openChestObjectState, task5Init,
      task5StartChest, task5CenterToWest, applyLoot]
  · simp [emptyRuleMemory]

theorem task5_rule_west_monster_checkpoint :
    RuleGoal task5InWest emptyRuleMemory task5RuleMonsterGoal := by
  apply RuleGoal.adjacentMonster
  · simp [task5InWest, useExitObjectState, task5AfterStartChest,
      openChestObjectState, task5Init, task5StartChest,
      task5CenterToWest, task5WestMonster, applyLoot, keysAfterExit]
  · simp [adjacent, manhattan, absDiff, task5InWest,
      useExitObjectState, task5AfterStartChest, openChestObjectState,
      task5Init, task5StartChest, task5CenterToWest,
      task5WestMonster, applyLoot, keysAfterExit]
  · simp [task5InWest, useExitObjectState, task5AfterStartChest,
      openChestObjectState, task5Init, task5StartChest,
      task5CenterToWest, applyLoot, keysAfterExit]
  · simp [healthSafe, task5InWest, useExitObjectState,
      task5AfterStartChest, openChestObjectState, task5Init,
      task5StartChest, task5CenterToWest, applyLoot, keysAfterExit]

theorem task5_rule_west_chest_checkpoint :
    RuleGoal task5AfterWestMonster emptyRuleMemory
      (task5RuleChestGoal task5WestChest.pos) := by
  apply RuleGoal.adjacentChest
  · simp [task5AfterWestMonster, attackMonsterObjectState,
      task5InWest, useExitObjectState, task5AfterStartChest,
      openChestObjectState, task5Init, task5StartChest,
      task5WestChest, task5CenterToWest, task5WestMonster,
      applyLoot, damageMonsterObjectAt, keysAfterExit]
  · simp [emptyRuleMemory]
  · simp [adjacent, manhattan, absDiff, task5AfterWestMonster,
      attackMonsterObjectState, task5InWest, useExitObjectState,
      task5AfterStartChest, openChestObjectState, task5Init,
      task5StartChest, task5WestChest, task5CenterToWest,
      task5WestMonster, applyLoot, damageMonsterObjectAt,
      keysAfterExit]

theorem task5_rule_button_triggered_by_entry :
    (4, 4) ∈ task5BackAtButton.pressedButtons ∧
      task5BackAtButton.buttonsPressed = 1 :=
  task5_button_triggered_on_entry
theorem task5_rule_conditional_exit_checkpoint :
    RuleGoal task5AfterButton emptyRuleMemory
      (task5RuleExitGoal task5CenterToSouth.pos) := by
  apply RuleGoal.unusedConditionalExit
  · simp [task5AfterButton, task5BackAtButton, useExitObjectState,
      task5AfterWestChest, openChestObjectState,
      task5AfterWestMonster, attackMonsterObjectState, task5InWest,
      task5AfterStartChest, task5Init, task5StartChest,
      task5WestChest, task5CenterToWest, task5WestToCenter,
      task5CenterToSouth, task5WestMonster, applyLoot,
      damageMonsterObjectAt, keysAfterExit]
  · simp [conditionalDoorReady, visibleButtonsSatisfied,
      task5AfterButton, task5BackAtButton, useExitObjectState,
      task5AfterWestChest, openChestObjectState,
      task5AfterWestMonster, attackMonsterObjectState, task5InWest,
      task5AfterStartChest, task5Init, task5StartChest,
      task5WestChest, task5CenterToWest, task5WestToCenter,
      task5WestMonster, applyLoot, damageMonsterObjectAt,
      keysAfterExit]
  · simp [emptyRuleMemory]

theorem task5_rule_south_chest_checkpoint :
    RuleGoal task5InSouth emptyRuleMemory
      (task5RuleChestGoal task5SouthChest.pos) := by
  apply RuleGoal.adjacentChest
  · simp [task5InSouth, useExitObjectState, task5AfterButton,
      task5BackAtButton, task5AfterWestChest, openChestObjectState,
      task5AfterWestMonster, attackMonsterObjectState, task5InWest,
      task5AfterStartChest, task5Init, task5StartChest,
      task5WestChest, task5SouthChest, task5CenterToWest,
      task5WestToCenter, task5CenterToSouth, task5WestMonster,
      applyLoot, damageMonsterObjectAt, keysAfterExit]
  · simp [emptyRuleMemory]
  · simp [adjacent, manhattan, absDiff, task5InSouth,
      useExitObjectState, task5AfterButton, task5BackAtButton,
      task5AfterWestChest, openChestObjectState,
      task5AfterWestMonster, attackMonsterObjectState, task5InWest,
      task5AfterStartChest, task5Init, task5StartChest,
      task5WestChest, task5SouthChest, task5CenterToWest,
      task5WestToCenter, task5CenterToSouth, task5WestMonster,
      applyLoot, damageMonsterObjectAt, keysAfterExit]

theorem task5_rule_east_locked_exit_checkpoint :
    RuleGoal task5BackAtEastGate emptyRuleMemory
      (task5RuleExitGoal task5CenterToEast.pos) := by
  apply RuleGoal.unusedLockedExit
  · simp [task5BackAtEastGate, useExitObjectState,
      task5AfterSouthChest, openChestObjectState, task5InSouth,
      task5AfterButton, task5BackAtButton, task5AfterWestChest,
      task5AfterWestMonster, attackMonsterObjectState, task5InWest,
      task5AfterStartChest, task5Init, task5StartChest,
      task5WestChest, task5SouthChest, task5CenterToWest,
      task5WestToCenter, task5CenterToSouth, task5SouthToCenter,
      task5CenterToEast, task5WestMonster, applyLoot,
      damageMonsterObjectAt, keysAfterExit]
  · simp [task5BackAtEastGate, useExitObjectState,
      task5AfterSouthChest, openChestObjectState, task5InSouth,
      task5AfterButton, task5BackAtButton, task5AfterWestChest,
      task5AfterWestMonster, attackMonsterObjectState, task5InWest,
      task5AfterStartChest, task5Init, task5StartChest,
      task5WestChest, task5SouthChest, task5CenterToWest,
      task5WestToCenter, task5CenterToSouth, task5SouthToCenter,
      task5WestMonster, applyLoot, damageMonsterObjectAt,
      keysAfterExit]
  · simp [emptyRuleMemory]

theorem task5_rule_east_chest_checkpoint :
    RuleGoal task5InEast emptyRuleMemory
      (task5RuleChestGoal task5EastChest.pos) := by
  apply RuleGoal.adjacentChest
  · simp [task5InEast, useExitObjectState, task5BackAtEastGate,
      task5AfterSouthChest, openChestObjectState, task5InSouth,
      task5AfterButton, task5BackAtButton, task5AfterWestChest,
      task5AfterWestMonster, attackMonsterObjectState, task5InWest,
      task5AfterStartChest, task5Init, task5StartChest,
      task5WestChest, task5SouthChest, task5EastChest,
      task5CenterToWest, task5WestToCenter, task5CenterToSouth,
      task5SouthToCenter, task5CenterToEast, task5WestMonster,
      applyLoot, damageMonsterObjectAt, keysAfterExit]
  · simp [emptyRuleMemory]
  · simp [adjacent, manhattan, absDiff, task5InEast,
      useExitObjectState, task5BackAtEastGate, task5AfterSouthChest,
      openChestObjectState, task5InSouth, task5AfterButton,
      task5BackAtButton, task5AfterWestChest, task5AfterWestMonster,
      attackMonsterObjectState, task5InWest, task5AfterStartChest,
      task5Init, task5StartChest, task5WestChest, task5SouthChest,
      task5EastChest, task5CenterToWest, task5WestToCenter,
      task5CenterToSouth, task5SouthToCenter, task5CenterToEast,
      task5WestMonster, applyLoot, damageMonsterObjectAt,
      keysAfterExit]

def ruleTask5EnvironmentCertificate : TaskCertificate Task5Goal task5Init :=
  { plan := task5Plan
    final := task5Final
    execution := task5_safe_execution
    completed := task5_goal }

theorem rule_task5_environment_completed : CompletedBy Task5Goal task5Init :=
  taskCertificate_completedBy ruleTask5EnvironmentCertificate

/-! ## 具体策略生成轨迹 -/

def ruleExitGoal (exit : Exit) : Goal :=
  { kind := GoalKind.goToExit, target := some exit.pos }

private theorem plannedInteractionStep
    {before after : SymbolicState} {memory : AgentMemory}
    {kind : GoalKind} {position : Position}
    (hselect : ruleBasedChooseGoal before memory =
      { kind := kind, target := some position })
    (hkind : interactionKind kind)
    (hadjacent : adjacent before.player position)
    (henvironment : FullEnvStep before Action.pressA after) :
    RulePolicyStep before memory Action.pressA after
      (updateRuleMemory before memory
        (some { kind := kind, target := some position }) after) :=
  RulePolicyStep.planned hselect
    (ActionForGoal.interactAdjacent hkind hadjacent)
    Shielded.passA henvironment rfl

private theorem plannedSwitchOnStep
    {before after : SymbolicState} {memory : AgentMemory}
    {position : Position}
    (hselect : ruleBasedChooseGoal before memory =
      { kind := GoalKind.activateSwitch, target := some position })
    (hvisible : switchVisibleAt before position)
    (hplayer : before.player = position)
    (henvironment : FullEnvStep before Action.pressA after) :
    RulePolicyStep before memory Action.pressA after
      (updateRuleMemory before memory
        (some { kind := GoalKind.activateSwitch, target := some position })
        after) :=
  RulePolicyStep.planned hselect
    (ActionForGoal.switchOn hvisible hplayer)
    Shielded.passA henvironment rfl

private theorem plannedStructuredExitStep
    {before : SymbolicState} {memory : AgentMemory} {exit : Exit}
    (hselect : ruleBasedChooseGoal before memory = ruleExitGoal exit)
    (husable : canUseExitObject before exit) :
    RulePolicyStep before memory Action.useExit
      (useExitObjectState before exit)
      (updateRuleMemory before memory (some (ruleExitGoal exit))
        (useExitObjectState before exit)) :=
  RulePolicyStep.planned hselect
    (ActionForGoal.structuredExit husable)
    Shielded.passUseExit
    (FullEnvStep.useExitObject husable) rfl

private theorem reflexAttackStep
    {before after : SymbolicState} {memory : AgentMemory}
    (hreflex : CombatReflex before Action.pressA)
    (henvironment : FullEnvStep before Action.pressA after) :
    RulePolicyStep before memory Action.pressA after
      (updateRuleMemory before memory none after) :=
  RulePolicyStep.reflex hreflex Shielded.passA henvironment rfl

/-! ### Task 1 -/

def task1RuleMemory0 : AgentMemory := {}
def task1RuleMemory1 : AgentMemory :=
  updateRuleMemory task1Init task1RuleMemory0
    (some task1RuleChestGoal) task1AfterChest
def task1RuleMemory2 : AgentMemory :=
  updateRuleMemory task1AfterChest task1RuleMemory1
    (some task1RuleExitGoal) task1Final

theorem task1_rule_policy_execution :
    RulePolicyExec task1Init task1RuleMemory0 task1Plan
      task1Final task1RuleMemory2 := by
  change RulePolicyExec task1Init task1RuleMemory0
    [Action.pressA, Action.useExit] task1Final task1RuleMemory2
  refine RulePolicyExec.cons (next := task1AfterChest) (nextMemory := task1RuleMemory1) ?_ ?_
  · exact plannedInteractionStep
      (kind := GoalKind.openChest) (position := task1Chest.pos)
      (by native_decide)
      (by simp [interactionKind])
      (by native_decide)
      (FullEnvStep.openChestObject (by native_decide))
  · refine RulePolicyExec.cons (next := task1Final) (nextMemory := task1RuleMemory2) ?_ ?_
    · simpa [task1RuleExitGoal, ruleExitGoal] using
        (plannedStructuredExitStep
          (before := task1AfterChest) (memory := task1RuleMemory1)
          (exit := task1Exit) (by native_decide) (by native_decide))
    · exact RulePolicyExec.nil

/-! ### Task 2 -/

def task2RuleMemory0 : AgentMemory := {}
def task2RuleMemory1 : AgentMemory :=
  updateRuleMemory task2Init task2RuleMemory0 none task2AfterMonster
def task2RuleMemory2 : AgentMemory :=
  updateRuleMemory task2AfterMonster task2RuleMemory1
    (some task2RuleChestGoal) task2AfterMove
def task2RuleMemory3 : AgentMemory :=
  updateRuleMemory task2AfterMove task2RuleMemory2
    (some task2RuleChestGoal) task2AfterChest
def task2RuleMemory4 : AgentMemory :=
  updateRuleMemory task2AfterChest task2RuleMemory3
    (some task2RuleExitGoal) task2Final

theorem task2_rule_policy_execution :
    RulePolicyExec task2Init task2RuleMemory0 task2Plan
      task2Final task2RuleMemory4 := by
  change RulePolicyExec task2Init task2RuleMemory0
    [Action.pressA, Action.right, Action.pressA, Action.useExit]
    task2Final task2RuleMemory4
  refine RulePolicyExec.cons (next := task2AfterMonster) (nextMemory := task2RuleMemory1) ?_ ?_
  · exact reflexAttackStep
      (CombatReflex.attack
        (monster := task2Monster.pos)
        (by native_decide) (by native_decide)
        (by native_decide) (by native_decide))
      (FullEnvStep.attackMonsterObject (by
        simp [canAttackObject, task2Init, task2Monster, task2Room,
          inFront, facingTarget, nextPosition, actionOfDirection, delta,
          hasItem]))
  · refine RulePolicyExec.cons (next := task2AfterMove) (nextMemory := task2RuleMemory2) ?_ ?_
    · apply RulePolicyStep.planned
        (goal := task2RuleChestGoal) (raw := Action.right)
      · native_decide
      · apply ActionForGoal.interactPlan
        · simp [interactionKind]
        · exact PlannerStep.step
            (first := nextPosition task2AfterMonster.player Action.right)
            (by native_decide) rfl
            (by native_decide) (by native_decide)
      · exact Shielded.allowSafe (by native_decide) (by native_decide)
      · exact FullEnvStep.basic (by
          simpa [task2AfterMove, enterPositionState] using
            (EnvStep.moveSafe
              (s := task2AfterMonster) (a := Action.right)
              (by native_decide) (by native_decide)))
      · rfl
    · refine RulePolicyExec.cons (next := task2AfterChest) (nextMemory := task2RuleMemory3) ?_ ?_
      · exact plannedInteractionStep
          (kind := GoalKind.openChest) (position := task2Chest.pos)
          (by native_decide)
          (by simp [interactionKind])
          (by native_decide)
          (FullEnvStep.openChestObject (by native_decide))
      · refine RulePolicyExec.cons (next := task2Final) (nextMemory := task2RuleMemory4) ?_ ?_
        · simpa [task2RuleExitGoal, ruleExitGoal] using
            (plannedStructuredExitStep
              (before := task2AfterChest) (memory := task2RuleMemory3)
              (exit := task2Exit) (by native_decide) (by native_decide))
        · exact RulePolicyExec.nil
/-! ### Task 3 -/

def task3RuleMemory0 : AgentMemory := {}
def task3RuleMemory1 : AgentMemory :=
  updateRuleMemory task3Init task3RuleMemory0
    (some (ruleExitGoal task3StartToHall)) task3InHall
def task3RuleMemory2 : AgentMemory :=
  updateRuleMemory task3InHall task3RuleMemory1 none task3AfterMonster
def task3RuleMemory3 : AgentMemory :=
  updateRuleMemory task3AfterMonster task3RuleMemory2
    (some (ruleExitGoal task3HallToKey)) task3InKeyRoom
def task3RuleMemory4 : AgentMemory :=
  updateRuleMemory task3InKeyRoom task3RuleMemory3
    (some task3RuleChestGoal) task3AfterChest
def task3RuleMemory5 : AgentMemory :=
  updateRuleMemory task3AfterChest task3RuleMemory4
    (some (ruleExitGoal task3KeyToHall)) task3BackInHall
def task3RuleMemory6 : AgentMemory :=
  updateRuleMemory task3BackInHall task3RuleMemory5
    (some (ruleExitGoal task3HallToStart)) task3BackAtStart
def task3RuleMemory7 : AgentMemory :=
  updateRuleMemory task3BackAtStart task3RuleMemory6
    (some (ruleExitGoal task3FinalExit)) task3Final

theorem task3_rule_policy_execution :
    RulePolicyExec task3Init task3RuleMemory0 task3Plan
      task3Final task3RuleMemory7 := by
  change RulePolicyExec task3Init task3RuleMemory0
    [Action.useExit, Action.pressA, Action.useExit, Action.pressA,
      Action.useExit, Action.useExit, Action.useExit]
    task3Final task3RuleMemory7
  refine RulePolicyExec.cons
    (next := task3InHall) (nextMemory := task3RuleMemory1) ?_ ?_
  · exact plannedStructuredExitStep
      (before := task3Init) (memory := task3RuleMemory0)
      (exit := task3StartToHall) (by native_decide) (by native_decide)
  · refine RulePolicyExec.cons
      (next := task3AfterMonster) (nextMemory := task3RuleMemory2) ?_ ?_
    · exact reflexAttackStep
        (CombatReflex.attack
          (monster := task3Monster.pos)
          (by native_decide) (by native_decide)
          (by native_decide) (by native_decide))
        (FullEnvStep.attackMonsterObject (by
          simp [canAttackObject, task3InHall, useExitObjectState,
            task3Init, task3StartToHall, task3Monster,
            task3StartRoom, task3HallRoom, keysAfterExit,
            inFront, facingTarget, nextPosition,
            actionOfDirection, delta, hasItem]))
    · refine RulePolicyExec.cons
        (next := task3InKeyRoom) (nextMemory := task3RuleMemory3) ?_ ?_
      · exact plannedStructuredExitStep
          (before := task3AfterMonster) (memory := task3RuleMemory2)
          (exit := task3HallToKey) (by native_decide) (by native_decide)
      · refine RulePolicyExec.cons
          (next := task3AfterChest) (nextMemory := task3RuleMemory4) ?_ ?_
        · exact plannedInteractionStep
            (kind := GoalKind.openChest) (position := task3Chest.pos)
            (by native_decide)
            (by simp [interactionKind])
            (by native_decide)
            (FullEnvStep.openChestObject (by native_decide))
        · refine RulePolicyExec.cons
            (next := task3BackInHall) (nextMemory := task3RuleMemory5) ?_ ?_
          · exact plannedStructuredExitStep
              (before := task3AfterChest) (memory := task3RuleMemory4)
              (exit := task3KeyToHall) (by native_decide) (by native_decide)
          · refine RulePolicyExec.cons
              (next := task3BackAtStart) (nextMemory := task3RuleMemory6) ?_ ?_
            · exact plannedStructuredExitStep
                (before := task3BackInHall) (memory := task3RuleMemory5)
                (exit := task3HallToStart) (by native_decide) (by native_decide)
            · refine RulePolicyExec.cons
                (next := task3Final) (nextMemory := task3RuleMemory7) ?_ ?_
              · exact plannedStructuredExitStep
                  (before := task3BackAtStart) (memory := task3RuleMemory6)
                  (exit := task3FinalExit) (by native_decide) (by native_decide)
              · exact RulePolicyExec.nil
/-! ### Task 4 -/

def task4RuleMemory0 : AgentMemory := {}
def task4RuleMemory1 : AgentMemory :=
  updateRuleMemory task4Init task4RuleMemory0
    (some (task4RuleSwitchGoal (9, 4))) task4AfterFirstSwitch
def task4RuleMemory2 : AgentMemory :=
  updateRuleMemory task4AfterFirstSwitch task4RuleMemory1
    (some (ruleExitGoal task4WestToCenter)) task4InCenter
def task4RuleMemory3 : AgentMemory :=
  updateRuleMemory task4InCenter task4RuleMemory2
    (some (ruleExitGoal task4CenterToNorth)) task4InNorth
def task4RuleMemory4 : AgentMemory :=
  updateRuleMemory task4InNorth task4RuleMemory3
    (some task4RuleKeyChestGoal) task4AfterKey
def task4RuleMemory5 : AgentMemory :=
  updateRuleMemory task4AfterKey task4RuleMemory4
    (some (ruleExitGoal task4NorthToCenter)) task4BackForEast
def task4RuleMemory6 : AgentMemory :=
  updateRuleMemory task4BackForEast task4RuleMemory5
    (some (ruleExitGoal task4CenterToEast)) task4InEast
def task4RuleMemory7 : AgentMemory :=
  updateRuleMemory task4InEast task4RuleMemory6
    (some task4RuleSwordChestGoal) task4AfterSword
def task4RuleMemory8 : AgentMemory :=
  updateRuleMemory task4AfterSword task4RuleMemory7
    (some (ruleExitGoal task4EastToCenter)) task4AtCenterSwitch
def task4RuleMemory9 : AgentMemory :=
  updateRuleMemory task4AtCenterSwitch task4RuleMemory8
    (some (task4RuleSwitchGoal (4, 4))) task4AfterSecondSwitch
def task4RuleMemory10 : AgentMemory :=
  updateRuleMemory task4AfterSecondSwitch task4RuleMemory9
    (some (ruleExitGoal task4CenterToSouth)) task4InSouth
def task4RuleMemory11 : AgentMemory :=
  updateRuleMemory task4InSouth task4RuleMemory10 none task4AfterGuardian
def task4RuleMemory12 : AgentMemory :=
  updateRuleMemory task4AfterGuardian task4RuleMemory11
    (some (ruleExitGoal task4SouthToCenter)) task4AtFinalChest
def task4RuleMemory13 : AgentMemory :=
  updateRuleMemory task4AtFinalChest task4RuleMemory12
    (some task4RuleFinalChestGoal) task4Final

theorem task4_rule_policy_execution :
    RulePolicyExec task4Init task4RuleMemory0 task4Plan
      task4Final task4RuleMemory13 := by
  change RulePolicyExec task4Init task4RuleMemory0
    [Action.pressA, Action.useExit, Action.useExit, Action.pressA,
      Action.useExit, Action.useExit, Action.pressA, Action.useExit,
      Action.pressA, Action.useExit, Action.pressA, Action.useExit,
      Action.pressA] task4Final task4RuleMemory13
  refine RulePolicyExec.cons
    (next := task4AfterFirstSwitch) (nextMemory := task4RuleMemory1) ?_ ?_
  · exact plannedSwitchOnStep
      (position := (9, 4)) (by native_decide) (by native_decide)
      (by native_decide) (FullEnvStep.pressSwitch (by native_decide))
  · refine RulePolicyExec.cons
      (next := task4InCenter) (nextMemory := task4RuleMemory2) ?_ ?_
    · exact plannedStructuredExitStep
        (before := task4AfterFirstSwitch) (memory := task4RuleMemory1)
        (exit := task4WestToCenter) (by native_decide) (by native_decide)
    · refine RulePolicyExec.cons
        (next := task4InNorth) (nextMemory := task4RuleMemory3) ?_ ?_
      · exact plannedStructuredExitStep
          (before := task4InCenter) (memory := task4RuleMemory2)
          (exit := task4CenterToNorth) (by native_decide) (by native_decide)
      · refine RulePolicyExec.cons
          (next := task4AfterKey) (nextMemory := task4RuleMemory4) ?_ ?_
        · exact plannedInteractionStep
            (kind := GoalKind.openChest) (position := task4KeyChest.pos)
            (by native_decide)
            (by simp [interactionKind])
            (by native_decide)
            (FullEnvStep.openChestObject (by native_decide))
        · refine RulePolicyExec.cons
            (next := task4BackForEast) (nextMemory := task4RuleMemory5) ?_ ?_
          · exact plannedStructuredExitStep
              (before := task4AfterKey) (memory := task4RuleMemory4)
              (exit := task4NorthToCenter) (by native_decide) (by native_decide)
          · refine RulePolicyExec.cons
              (next := task4InEast) (nextMemory := task4RuleMemory6) ?_ ?_
            · exact plannedStructuredExitStep
                (before := task4BackForEast) (memory := task4RuleMemory5)
                (exit := task4CenterToEast) (by native_decide) (by native_decide)
            · refine RulePolicyExec.cons
                (next := task4AfterSword) (nextMemory := task4RuleMemory7) ?_ ?_
              · exact plannedInteractionStep
                  (kind := GoalKind.openChest) (position := task4SwordChest.pos)
                  (by native_decide)
                  (by simp [interactionKind])
                  (by native_decide)
                  (FullEnvStep.openChestObject (by native_decide))
              · refine RulePolicyExec.cons
                  (next := task4AtCenterSwitch) (nextMemory := task4RuleMemory8) ?_ ?_
                · exact plannedStructuredExitStep
                    (before := task4AfterSword) (memory := task4RuleMemory7)
                    (exit := task4EastToCenter) (by native_decide) (by native_decide)
                · refine RulePolicyExec.cons
                    (next := task4AfterSecondSwitch)
                    (nextMemory := task4RuleMemory9) ?_ ?_
                  · exact plannedSwitchOnStep
                      (position := (4, 4)) (by native_decide)
                      (by native_decide) (by native_decide)
                      (FullEnvStep.pressSwitch (by native_decide))
                  · refine RulePolicyExec.cons
                      (next := task4InSouth) (nextMemory := task4RuleMemory10) ?_ ?_
                    · exact plannedStructuredExitStep
                        (before := task4AfterSecondSwitch)
                        (memory := task4RuleMemory9)
                        (exit := task4CenterToSouth)
                        (by native_decide) (by native_decide)
                    · refine RulePolicyExec.cons
                        (next := task4AfterGuardian)
                        (nextMemory := task4RuleMemory11) ?_ ?_
                      · exact reflexAttackStep
                          (CombatReflex.attack
                            (monster := task4Guardian.pos)
                            (by native_decide) (by native_decide)
                            (by native_decide) (by native_decide))
                          (FullEnvStep.attackMonsterObject (by
                            simp [canAttackObject, task4InSouth,
                              useExitObjectState, task4AfterSecondSwitch,
                              task4AtCenterSwitch, task4AfterSword,
                              openChestObjectState, task4InEast,
                              task4BackForEast, task4AfterKey,
                              task4InNorth, task4InCenter,
                              task4AfterFirstSwitch, task4Init,
                              task4WestToCenter, task4CenterToNorth,
                              task4NorthToCenter, task4CenterToEast,
                              task4EastToCenter, task4CenterToSouth,
                              task4KeyChest, task4SwordChest,
                              task4Guardian, task4WestRoom,
                              task4CenterRoom, task4NorthRoom,
                              task4EastRoom, task4SouthRoom,
                              applyLoot, keysAfterExit, inFront,
                              facingTarget, nextPosition,
                              actionOfDirection, delta, hasItem]))
                      · refine RulePolicyExec.cons
                          (next := task4AtFinalChest)
                          (nextMemory := task4RuleMemory12) ?_ ?_
                        · exact plannedStructuredExitStep
                            (before := task4AfterGuardian)
                            (memory := task4RuleMemory11)
                            (exit := task4SouthToCenter)
                            (by native_decide) (by native_decide)
                        · refine RulePolicyExec.cons
                            (next := task4Final)
                            (nextMemory := task4RuleMemory13) ?_ ?_
                          · exact plannedInteractionStep
                              (kind := GoalKind.openChest)
                              (position := task4FinalChest.pos)
                              (by native_decide)
                              (by simp [interactionKind])
                              (by native_decide)
                              (FullEnvStep.openChestObject (by native_decide))
                          · exact RulePolicyExec.nil
/-! ### Task 5 -/

def task5RuleMemory0 : AgentMemory := {}
def task5RuleMemory1 : AgentMemory :=
  updateRuleMemory task5Init task5RuleMemory0
    (some (task5RuleChestGoal task5StartChest.pos)) task5AfterStartChest
def task5RuleMemory2 : AgentMemory :=
  updateRuleMemory task5AfterStartChest task5RuleMemory1
    (some (ruleExitGoal task5CenterToWest)) task5InWest
def task5RuleMemory3 : AgentMemory :=
  updateRuleMemory task5InWest task5RuleMemory2 none task5AfterWestMonster
def task5RuleMemory4 : AgentMemory :=
  updateRuleMemory task5AfterWestMonster task5RuleMemory3
    (some (task5RuleChestGoal task5WestChest.pos)) task5AfterWestChest
def task5RuleMemory5 : AgentMemory :=
  updateRuleMemory task5AfterWestChest task5RuleMemory4
    (some (ruleExitGoal task5WestToCenter)) task5BackAtButton
def task5RuleMemory6 : AgentMemory :=
  updateRuleMemory task5BackAtButton task5RuleMemory5
    (some (ruleExitGoal task5CenterToSouth)) task5InSouth
def task5RuleMemory7 : AgentMemory :=
  updateRuleMemory task5InSouth task5RuleMemory6
    (some (task5RuleChestGoal task5SouthChest.pos)) task5AfterSouthChest
def task5RuleMemory8 : AgentMemory :=
  updateRuleMemory task5AfterSouthChest task5RuleMemory7
    (some (ruleExitGoal task5SouthToCenter)) task5BackAtEastGate
def task5RuleMemory9 : AgentMemory :=
  updateRuleMemory task5BackAtEastGate task5RuleMemory8
    (some (ruleExitGoal task5CenterToEast)) task5InEast
def task5RuleMemory10 : AgentMemory :=
  updateRuleMemory task5InEast task5RuleMemory9
    (some (task5RuleChestGoal task5EastChest.pos)) task5Final

theorem task5_rule_policy_execution :
    RulePolicyExec task5Init task5RuleMemory0 task5Plan
      task5Final task5RuleMemory10 := by
  change RulePolicyExec task5Init task5RuleMemory0
    [Action.pressA, Action.useExit, Action.pressA, Action.pressA,
      Action.useExit, Action.useExit, Action.pressA, Action.useExit,
      Action.useExit, Action.pressA] task5Final task5RuleMemory10
  refine RulePolicyExec.cons
    (next := task5AfterStartChest) (nextMemory := task5RuleMemory1) ?_ ?_
  · exact plannedInteractionStep
      (kind := GoalKind.openChest) (position := task5StartChest.pos)
      (by native_decide)
      (by simp [interactionKind])
      (by native_decide)
      (FullEnvStep.openChestObject (by native_decide))
  · refine RulePolicyExec.cons
      (next := task5InWest) (nextMemory := task5RuleMemory2) ?_ ?_
    · exact plannedStructuredExitStep
        (before := task5AfterStartChest) (memory := task5RuleMemory1)
        (exit := task5CenterToWest) (by native_decide) (by native_decide)
    · refine RulePolicyExec.cons
        (next := task5AfterWestMonster) (nextMemory := task5RuleMemory3) ?_ ?_
      · exact reflexAttackStep
          (CombatReflex.attack
            (monster := task5WestMonster.pos)
            (by native_decide) (by native_decide)
            (by native_decide) (by native_decide))
          (FullEnvStep.attackMonsterObject (by
            simp [canAttackObject, task5InWest, useExitObjectState,
              task5AfterStartChest, openChestObjectState, task5Init,
              task5StartChest, task5CenterToWest, task5WestMonster,
              task5CenterRoom, task5WestRoom, applyLoot,
              removeChestObjectAt, keysAfterExit, inFront,
              facingTarget, nextPosition, actionOfDirection, delta,
              hasItem]))
      · refine RulePolicyExec.cons
          (next := task5AfterWestChest) (nextMemory := task5RuleMemory4) ?_ ?_
        · exact plannedInteractionStep
            (kind := GoalKind.openChest) (position := task5WestChest.pos)
            (by native_decide)
            (by simp [interactionKind])
            (by native_decide)
            (FullEnvStep.openChestObject (by native_decide))
        · refine RulePolicyExec.cons
            (next := task5BackAtButton) (nextMemory := task5RuleMemory5) ?_ ?_
          · exact plannedStructuredExitStep
              (before := task5AfterWestChest) (memory := task5RuleMemory4)
              (exit := task5WestToCenter) (by native_decide) (by native_decide)
          · refine RulePolicyExec.cons
              (next := task5InSouth) (nextMemory := task5RuleMemory6) ?_ ?_
            · exact plannedStructuredExitStep
                (before := task5BackAtButton) (memory := task5RuleMemory5)
                (exit := task5CenterToSouth) (by native_decide) (by native_decide)
            · refine RulePolicyExec.cons
                (next := task5AfterSouthChest) (nextMemory := task5RuleMemory7) ?_ ?_
              · exact plannedInteractionStep
                  (kind := GoalKind.openChest) (position := task5SouthChest.pos)
                  (by native_decide)
                  (by simp [interactionKind])
                  (by native_decide)
                  (FullEnvStep.openChestObject (by native_decide))
              · refine RulePolicyExec.cons
                  (next := task5BackAtEastGate) (nextMemory := task5RuleMemory8) ?_ ?_
                · exact plannedStructuredExitStep
                    (before := task5AfterSouthChest)
                    (memory := task5RuleMemory7)
                    (exit := task5SouthToCenter)
                    (by native_decide) (by native_decide)
                · refine RulePolicyExec.cons
                    (next := task5InEast) (nextMemory := task5RuleMemory9) ?_ ?_
                  · exact plannedStructuredExitStep
                      (before := task5BackAtEastGate)
                      (memory := task5RuleMemory8)
                      (exit := task5CenterToEast)
                      (by native_decide) (by native_decide)
                  · refine RulePolicyExec.cons
                      (next := task5Final) (nextMemory := task5RuleMemory10) ?_ ?_
                    · exact plannedInteractionStep
                        (kind := GoalKind.openChest)
                        (position := task5EastChest.pos)
                        (by native_decide)
                        (by simp [interactionKind])
                        (by native_decide)
                        (FullEnvStep.openChestObject (by native_decide))
                    · exact RulePolicyExec.nil
/-! ## 强化后的五关证书 -/

def ruleTask1Certificate : RuleTaskCertificate Task1Goal task1Init :=
  { plan := task1Plan
    final := task1Final
    execution := task1_safe_execution
    completed := task1_goal
    initialMemory := task1RuleMemory0
    finalMemory := task1RuleMemory2
    generated := task1_rule_policy_execution }

def ruleTask2Certificate : RuleTaskCertificate Task2Goal task2Init :=
  { plan := task2Plan
    final := task2Final
    execution := task2_safe_execution
    completed := task2_goal
    initialMemory := task2RuleMemory0
    finalMemory := task2RuleMemory4
    generated := task2_rule_policy_execution }

def ruleTask3Certificate : RuleTaskCertificate Task3Goal task3Init :=
  { plan := task3Plan
    final := task3Final
    execution := task3_safe_execution
    completed := task3_goal
    initialMemory := task3RuleMemory0
    finalMemory := task3RuleMemory7
    generated := task3_rule_policy_execution }

def ruleTask4Certificate : RuleTaskCertificate Task4Goal task4Init :=
  { plan := task4Plan
    final := task4Final
    execution := task4_safe_execution
    completed := task4_goal
    initialMemory := task4RuleMemory0
    finalMemory := task4RuleMemory13
    generated := task4_rule_policy_execution }

def ruleTask5Certificate : RuleTaskCertificate Task5Goal task5Init :=
  { plan := task5Plan
    final := task5Final
    execution := task5_safe_execution
    completed := task5_goal
    initialMemory := task5RuleMemory0
    finalMemory := task5RuleMemory10
    generated := task5_rule_policy_execution }

theorem rule_task1_completed : CompletedByRulePolicy Task1Goal task1Init :=
  ruleTaskCertificate_completedByRulePolicy ruleTask1Certificate

theorem rule_task2_completed : CompletedByRulePolicy Task2Goal task2Init :=
  ruleTaskCertificate_completedByRulePolicy ruleTask2Certificate

theorem rule_task3_completed : CompletedByRulePolicy Task3Goal task3Init :=
  ruleTaskCertificate_completedByRulePolicy ruleTask3Certificate

theorem rule_task4_completed : CompletedByRulePolicy Task4Goal task4Init :=
  ruleTaskCertificate_completedByRulePolicy ruleTask4Certificate

theorem rule_task5_completed : CompletedByRulePolicy Task5Goal task5Init :=
  ruleTaskCertificate_completedByRulePolicy ruleTask5Certificate

theorem all_rule_task_certificates :
    CompletedByRulePolicy Task1Goal task1Init ∧
    CompletedByRulePolicy Task2Goal task2Init ∧
    CompletedByRulePolicy Task3Goal task3Init ∧
    CompletedByRulePolicy Task4Goal task4Init ∧
    CompletedByRulePolicy Task5Goal task5Init :=
  ⟨rule_task1_completed, rule_task2_completed, rule_task3_completed,
    rule_task4_completed, rule_task5_completed⟩

/-!
【五关证书均由具体规则策略生成】
该定理把五个 `generated` 字段集中暴露，便于报告和自动检查直接引用。
-/
theorem all_rule_tasks_policy_generated :
    RulePolicyExec task1Init ruleTask1Certificate.initialMemory
        ruleTask1Certificate.plan task1Final ruleTask1Certificate.finalMemory ∧
    RulePolicyExec task2Init ruleTask2Certificate.initialMemory
        ruleTask2Certificate.plan task2Final ruleTask2Certificate.finalMemory ∧
    RulePolicyExec task3Init ruleTask3Certificate.initialMemory
        ruleTask3Certificate.plan task3Final ruleTask3Certificate.finalMemory ∧
    RulePolicyExec task4Init ruleTask4Certificate.initialMemory
        ruleTask4Certificate.plan task4Final ruleTask4Certificate.finalMemory ∧
    RulePolicyExec task5Init ruleTask5Certificate.initialMemory
        ruleTask5Certificate.plan task5Final ruleTask5Certificate.finalMemory :=
  ⟨ruleTask1Certificate.generated, ruleTask2Certificate.generated,
    ruleTask3Certificate.generated, ruleTask4Certificate.generated,
    ruleTask5Certificate.generated⟩
end RuleBasedSubmission.Formalization
