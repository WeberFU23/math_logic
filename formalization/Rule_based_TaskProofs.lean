import formalization.Rule_based_Strategy

open MathLogic.Formalization
open MathLogic.Formalization.ReferenceTasks

/-!
本文件给出 rule-based 路线在五个任务上的策略证书。

公共关卡状态、完整环境转移和无失败轨迹全部来自 `Environment.lean`；
本文件只做规则路线特有的两件事：

1. 把公共安全轨迹封装成 `TaskCertificate`；
2. 在每个关键检查点构造 `RuleGoal`，证明规则优先链能够产生合法目标。

因此这里不再定义第二套任务环境，也不再使用“假设计划已经成功”的空泛条件模板。
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

def ruleTask1Certificate : TaskCertificate Task1Goal task1Init :=
  { plan := task1Plan
    final := task1Final
    execution := task1_safe_execution
    completed := task1_goal }

theorem rule_task1_completed : CompletedBy Task1Goal task1Init :=
  taskCertificate_completedBy ruleTask1Certificate

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

def ruleTask2Certificate : TaskCertificate Task2Goal task2Init :=
  { plan := task2Plan
    final := task2Final
    execution := task2_safe_execution
    completed := task2_goal }

theorem rule_task2_completed : CompletedBy Task2Goal task2Init :=
  taskCertificate_completedBy ruleTask2Certificate

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

def ruleTask3Certificate : TaskCertificate Task3Goal task3Init :=
  { plan := task3Plan
    final := task3Final
    execution := task3_safe_execution
    completed := task3_goal }

theorem rule_task3_completed : CompletedBy Task3Goal task3Init :=
  taskCertificate_completedBy ruleTask3Certificate
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

def ruleTask4Certificate : TaskCertificate Task4Goal task4Init :=
  { plan := task4Plan
    final := task4Final
    execution := task4_safe_execution
    completed := task4_goal }

theorem rule_task4_completed : CompletedBy Task4Goal task4Init :=
  taskCertificate_completedBy ruleTask4Certificate
/-! ## Task 5 -/

def task5RuleChestGoal (position : Position) : Goal :=
  { kind := GoalKind.openChest, target := some position }

def task5RuleMonsterGoal : Goal :=
  { kind := GoalKind.attackMonster, target := some task5WestMonster.pos }

def task5RuleExitGoal (position : Position) : Goal :=
  { kind := GoalKind.goToExit, target := some position }

def task5RuleButtonGoal : Goal :=
  { kind := GoalKind.activateButton, target := some (4, 4) }

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

theorem task5_rule_button_checkpoint :
    RuleGoal task5BackAtButton emptyRuleMemory task5RuleButtonGoal := by
  apply RuleGoal.buttonForConditionalDoor
  · simp [task5BackAtButton, useExitObjectState, task5AfterWestChest,
      openChestObjectState, task5AfterWestMonster,
      attackMonsterObjectState, task5InWest, task5AfterStartChest,
      task5Init, task5StartChest, task5WestChest,
      task5CenterToWest, task5WestToCenter, task5WestMonster,
      applyLoot, damageMonsterObjectAt, keysAfterExit]
  · simp [task5BackAtButton, useExitObjectState, task5AfterWestChest,
      openChestObjectState, task5AfterWestMonster,
      attackMonsterObjectState, task5InWest, task5AfterStartChest,
      task5Init, task5StartChest, task5WestChest,
      task5CenterToWest, task5WestToCenter, task5WestMonster,
      applyLoot, damageMonsterObjectAt, keysAfterExit]
  · simp [emptyRuleMemory]

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

def ruleTask5Certificate : TaskCertificate Task5Goal task5Init :=
  { plan := task5Plan
    final := task5Final
    execution := task5_safe_execution
    completed := task5_goal }

theorem rule_task5_completed : CompletedBy Task5Goal task5Init :=
  taskCertificate_completedBy ruleTask5Certificate

theorem all_rule_task_certificates :
    CompletedBy Task1Goal task1Init ∧
    CompletedBy Task2Goal task2Init ∧
    CompletedBy Task3Goal task3Init ∧
    CompletedBy Task4Goal task4Init ∧
    CompletedBy Task5Goal task5Init :=
  ⟨rule_task1_completed, rule_task2_completed, rule_task3_completed,
    rule_task4_completed, rule_task5_completed⟩
end RuleBasedSubmission.Formalization