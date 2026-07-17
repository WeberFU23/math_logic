import formalization.Rule_based_TaskProofs
import formalization.RL_based_TaskProofs

open MathLogic.Formalization
open MathLogic.Formalization.ReferenceTasks

/-!
本文件补充两条路线共用的强化定理：安全轨迹闭包、进度单调性、
mask 完备性与可靠性、shield 性质、颜色不变性提升、门前置条件、
两路线证书一致性以及搜索规格的可靠性和完备性。
-/

namespace MathLogic.Formalization

/-! ## 安全轨迹的闭包性质 -/

theorem safeFullExec_final_not_failed
    {start finish : SymbolicState} {plan : List Action}
    (execution : SafeFullExec start plan finish) :
    ¬ FailedState finish := by
  induction execution with
  | nil hsafe =>
      exact hsafe
  | cons _hstart _hstep _hrest ih =>
      exact ih

theorem safeFullExec_append
    {start middle finish : SymbolicState}
    {first second : List Action}
    (firstExecution : SafeFullExec start first middle)
    (secondExecution : SafeFullExec middle second finish) :
    SafeFullExec start (first ++ second) finish := by
  induction firstExecution with
  | nil _hsafe =>
      simpa using secondExecution
  | cons hsafe hstep _hrest ih =>
      exact SafeFullExec.cons hsafe hstep (ih secondExecution)

/-!
`ProgressLe` 只比较累计任务里程碑。当前钥匙数可以被锁门消耗，
因此不属于这个单调关系；累计钥匙数 `keysCollected` 才属于。
-/
def ProgressLe (before after : SymbolicState) : Prop :=
  before.keysCollected ≤ after.keysCollected ∧
  before.chestsOpened ≤ after.chestsOpened ∧
  before.monstersKilled ≤ after.monstersKilled ∧
  before.buttonsPressed ≤ after.buttonsPressed ∧
  before.switchesActivated ≤ after.switchesActivated ∧
  before.roomsChanged ≤ after.roomsChanged

theorem progressLe_refl (state : SymbolicState) :
    ProgressLe state state := by
  simp [ProgressLe]

theorem progressLe_trans
    {first second third : SymbolicState}
    (hFirst : ProgressLe first second)
    (hSecond : ProgressLe second third) :
    ProgressLe first third := by
  rcases hFirst with ⟨hkeys₁, hchests₁, hmonsters₁, hbuttons₁,
    hswitches₁, hrooms₁⟩
  rcases hSecond with ⟨hkeys₂, hchests₂, hmonsters₂, hbuttons₂,
    hswitches₂, hrooms₂⟩
  exact ⟨Nat.le_trans hkeys₁ hkeys₂,
    Nat.le_trans hchests₁ hchests₂,
    Nat.le_trans hmonsters₁ hmonsters₂,
    Nat.le_trans hbuttons₁ hbuttons₂,
    Nat.le_trans hswitches₁ hswitches₂,
    Nat.le_trans hrooms₁ hrooms₂⟩

theorem envStep_progressLe
    {before after : SymbolicState} {action : Action}
    (step : EnvStep before action after) :
    ProgressLe before after := by
  cases step <;> simp [ProgressLe, enterPositionState] <;>
    split <;> simp_all

theorem applyLoot_progressLe (loot : Loot) (state : SymbolicState) :
    ProgressLe state (applyLoot loot state) := by
  cases loot <;> cases hhealth : state.health <;>
    simp [ProgressLe, applyLoot, healHealth, hhealth]

theorem openChestObjectState_progressLe (state : SymbolicState) (chest : Chest) :
    ProgressLe state (openChestObjectState state chest) := by
  cases hloot : chest.loot <;> cases hhealth : state.health <;>
    simp [ProgressLe, openChestObjectState, applyLoot, healHealth, hloot, hhealth]

theorem attackMonsterObjectState_progressLe
    (state : SymbolicState) (monster : Monster) :
    ProgressLe state (attackMonsterObjectState state monster) := by
  by_cases hlethal : monster.hp ≤ 1
  · cases hloot : monster.loot <;> cases hhealth : state.health <;>
      simp [ProgressLe, attackMonsterObjectState, hlethal,
        applyLoot, healHealth, hloot, hhealth]
  · simp [ProgressLe, attackMonsterObjectState, hlethal]

theorem takeDamage_progressLe (damage : Nat) (state : SymbolicState) :
    ProgressLe state (takeDamage damage state) := by
  cases hhealth : state.health <;> simp [ProgressLe, takeDamage, hhealth]

theorem task5TimedDrainState_progressLe (state : SymbolicState) :
    ProgressLe state (task5TimedDrainState state) := by
  by_cases hdue : task5DrainDue state
  · simpa [task5TimedDrainState, hdue] using takeDamage_progressLe 1 state
  · simp [ProgressLe, task5TimedDrainState, hdue]

theorem fullEnvStep_progressLe
    {before after : SymbolicState} {action : Action}
    (step : FullEnvStep before action after) :
    ProgressLe before after := by
  cases step with
  | basic basicStep =>
      exact envStep_progressLe basicStep
  | openChestObject _hready =>
      exact openChestObjectState_progressLe _ _
  | attackMonsterObject _hready =>
      exact attackMonsterObjectState_progressLe _ _
  | pressSwitch =>
      simp [ProgressLe]
  | talkNpc =>
      simp [ProgressLe]
  | pressShield =>
      simp [ProgressLe]
  | pressShieldNoItem =>
      simp [ProgressLe]
  | useExitObject _hready =>
      simp [ProgressLe, useExitObjectState, enterPositionState]
      split <;> simp_all
  | monsterDamage _hthreat _hshield =>
      exact takeDamage_progressLe _ _
  | monsterDamageBlocked _hthreat _hshield =>
      simp [ProgressLe, shieldBlockState]
  | monsterMove =>
      simp [ProgressLe]
  | task5TimedDrain _hdue =>
      exact task5TimedDrainState_progressLe _
  | advanceClock =>
      simp [ProgressLe, advanceClock]
  | envNoImmediateThreat =>
      simp [ProgressLe]

theorem fullExec_progressLe
    {start finish : SymbolicState} {plan : List Action}
    (execution : FullExec start plan finish) :
    ProgressLe start finish := by
  induction execution with
  | nil =>
      exact progressLe_refl _
  | cons step _rest ih =>
      exact progressLe_trans (fullEnvStep_progressLe step) ih

theorem safeFullExec_progressLe
    {start finish : SymbolicState} {plan : List Action}
    (execution : SafeFullExec start plan finish) :
    ProgressLe start finish :=
  fullExec_progressLe (safeFullExec_to_fullExec execution)


/-! ## 世界完成标记的单调性 -/

def WorldCompletedMonotone (before after : SymbolicState) : Prop :=
  before.worldCompleted = true → after.worldCompleted = true

theorem worldCompletedMonotone_refl (state : SymbolicState) :
    WorldCompletedMonotone state state := by
  intro hdone
  exact hdone

theorem worldCompletedMonotone_trans
    {first second third : SymbolicState}
    (hFirst : WorldCompletedMonotone first second)
    (hSecond : WorldCompletedMonotone second third) :
    WorldCompletedMonotone first third := by
  intro hdone
  exact hSecond (hFirst hdone)

theorem envStep_worldCompletedMonotone
    {before after : SymbolicState} {action : Action}
    (step : EnvStep before action after) :
    WorldCompletedMonotone before after := by
  cases step <;> simp [WorldCompletedMonotone]

theorem openChestObjectState_worldCompletedMonotone
    (state : SymbolicState) (chest : Chest) :
    WorldCompletedMonotone state (openChestObjectState state chest) := by
  intro hdone
  cases hloot : chest.loot <;> cases hhealth : state.health <;>
    simp [openChestObjectState, applyLoot, healHealth, hloot, hhealth, hdone]

theorem attackMonsterObjectState_worldCompletedMonotone
    (state : SymbolicState) (monster : Monster) :
    WorldCompletedMonotone state (attackMonsterObjectState state monster) := by
  intro hdone
  by_cases hlethal : monster.hp ≤ 1
  · cases hloot : monster.loot <;> cases hhealth : state.health <;>
      simp [attackMonsterObjectState, hlethal, applyLoot, healHealth,
        hloot, hhealth, hdone]
  · simp [attackMonsterObjectState, hlethal, hdone]

theorem fullEnvStep_worldCompletedMonotone
    {before after : SymbolicState} {action : Action}
    (step : FullEnvStep before action after) :
    WorldCompletedMonotone before after := by
  cases step with
  | basic basicStep =>
      exact envStep_worldCompletedMonotone basicStep
  | openChestObject _hready =>
      exact openChestObjectState_worldCompletedMonotone _ _
  | attackMonsterObject _hready =>
      exact attackMonsterObjectState_worldCompletedMonotone _ _
  | pressSwitch =>
      simp [WorldCompletedMonotone]
  | talkNpc =>
      simp [WorldCompletedMonotone]
  | pressShield =>
      simp [WorldCompletedMonotone]
  | pressShieldNoItem =>
      simp [WorldCompletedMonotone]
  | useExitObject _hready =>
      intro hdone
      simp [useExitObjectState, hdone]
  | monsterDamage _hthreat _hshield =>
      intro hdone
      cases hhealth : before.health <;>
        simp [monsterDamageState, takeDamage, hhealth, hdone]
  | monsterDamageBlocked _hthreat _hshield =>
      simp [WorldCompletedMonotone, shieldBlockState]
  | monsterMove =>
      simp [WorldCompletedMonotone]
  | task5TimedDrain _hdue =>
      intro hdone
      by_cases hdue : task5DrainDue before
      · cases hhealth : before.health <;>
          simp [task5TimedDrainState, takeDamage, hdue, hhealth, hdone]
      · simp [task5TimedDrainState, hdue, hdone]
  | advanceClock =>
      simp [WorldCompletedMonotone, advanceClock]
  | envNoImmediateThreat =>
      simp [WorldCompletedMonotone]

theorem fullExec_worldCompletedMonotone
    {start finish : SymbolicState} {plan : List Action}
    (execution : FullExec start plan finish) :
    WorldCompletedMonotone start finish := by
  induction execution with
  | nil =>
      exact worldCompletedMonotone_refl _
  | cons step _rest ih =>
      exact worldCompletedMonotone_trans
        (fullEnvStep_worldCompletedMonotone step) ih

theorem safeFullExec_worldCompletedMonotone
    {start finish : SymbolicState} {plan : List Action}
    (execution : SafeFullExec start plan finish) :
    WorldCompletedMonotone start finish :=
  fullExec_worldCompletedMonotone (safeFullExec_to_fullExec execution)


end MathLogic.Formalization

namespace RLBasedSubmission.Formalization.Strategy

/-! ## Action mask 的非空性和保守性 -/

def BaseMaskHasEnabled (mask : List Bool) : Prop :=
  actionAtMask mask HighLevelAction.openChest = true ∨
  actionAtMask mask HighLevelAction.attackMonster = true ∨
  actionAtMask mask HighLevelAction.activateMechanism = true ∨
  actionAtMask mask HighLevelAction.takeNewExit = true ∨
  actionAtMask mask HighLevelAction.returnOrRevisit = true ∨
  actionAtMask mask HighLevelAction.exploreRoom = true ∨
  actionAtMask mask HighLevelAction.wait = true

theorem normalizedMask_has_enabled (raw : List Bool) :
    BaseMaskHasEnabled (normalizedMask raw) := by
  cases h0 : boolAt raw 0 <;>
  cases h1 : boolAt raw 1 <;>
  cases h2 : boolAt raw 2 <;>
  cases h3 : boolAt raw 3 <;>
  cases h4 : boolAt raw 4 <;>
  cases h5 : boolAt raw 5 <;>
  cases h6 : boolAt raw 6 <;>
  simp [BaseMaskHasEnabled, normalizedMask, firstResolvedProgress,
    prioritizedAttackAllowed, prioritizedReturnAllowed, localProgress,
    actionAtMask, actionIndex, boolAt, h0, h1, h2, h3, h4, h5, h6]

theorem normalizedMask_enabled_exists (raw : List Bool) :
    ∃ option, actionAtMask (normalizedMask raw) option = true := by
  rcases normalizedMask_has_enabled raw with h | h | h | h | h | h | h
  · exact ⟨HighLevelAction.openChest, h⟩
  · exact ⟨HighLevelAction.attackMonster, h⟩
  · exact ⟨HighLevelAction.activateMechanism, h⟩
  · exact ⟨HighLevelAction.takeNewExit, h⟩
  · exact ⟨HighLevelAction.returnOrRevisit, h⟩
  · exact ⟨HighLevelAction.exploreRoom, h⟩
  · exact ⟨HighLevelAction.wait, h⟩

end RLBasedSubmission.Formalization.Strategy

namespace RLBasedSubmission.Formalization.Strategy

def Task5MaskHasEnabled (mask : List Bool) : Prop :=
  task5ActionAtMask mask Task5Action.openChest = true ∨
  task5ActionAtMask mask Task5Action.attackMonster = true ∨
  task5ActionAtMask mask Task5Action.activateMechanism = true ∨
  task5ActionAtMask mask Task5Action.exitNorth = true ∨
  task5ActionAtMask mask Task5Action.exitEast = true ∨
  task5ActionAtMask mask Task5Action.exitSouth = true ∨
  task5ActionAtMask mask Task5Action.exitWest = true ∨
  task5ActionAtMask mask Task5Action.exploreRoom = true ∨
  task5ActionAtMask mask Task5Action.wait = true

theorem task5ConcreteProgress_cases
    {context : Task5MaskContext}
    (hprogress : task5ConcreteProgress context = true) :
    task5ChestBit context = true ∨
    task5AttackBit context = true ∨
    task5MechanismBit context = true ∨
    task5ExitBit context Task5Action.exitNorth = true ∨
    task5ExitBit context Task5Action.exitEast = true ∨
    task5ExitBit context Task5Action.exitSouth = true ∨
    task5ExitBit context Task5Action.exitWest = true := by
  have hleft :
      (((((task5ChestBit context = true ∨
          task5AttackBit context = true) ∨
        task5MechanismBit context = true) ∨
        task5ExitBit context Task5Action.exitNorth = true) ∨
        task5ExitBit context Task5Action.exitEast = true) ∨
        task5ExitBit context Task5Action.exitSouth = true) ∨
        task5ExitBit context Task5Action.exitWest = true := by
    simpa [task5ConcreteProgress, Bool.or_eq_true] using hprogress
  rcases hleft with hsix | hwest
  · rcases hsix with hfive | hsouth
    · rcases hfive with hfour | heast
      · rcases hfour with hthree | hnorth
        · rcases hthree with htwo | hmechanism
          · rcases htwo with hchest | hattack
            · exact Or.inl hchest
            · exact Or.inr (Or.inl hattack)
          · exact Or.inr (Or.inr (Or.inl hmechanism))
        · exact Or.inr (Or.inr (Or.inr (Or.inl hnorth)))
      · exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inl heast))))
    · exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inl hsouth)))))
  · exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr hwest)))))

theorem task5NormalizedMask_has_enabled (context : Task5MaskContext) :
    Task5MaskHasEnabled (task5NormalizedMask context) := by
  cases hprogress : task5ConcreteProgress context with
  | false =>
      cases hexplore :
        task5ActionAtMask context.rawMask Task5Action.exploreRoom <;>
        simp_all [Task5MaskHasEnabled, task5NormalizedMask,
          task5ActionAtMask, task5ActionIndex, boolAt]
  | true =>
      rcases task5ConcreteProgress_cases hprogress with
        h | h | h | h | h | h | h
      all_goals
        simp [Task5MaskHasEnabled, task5NormalizedMask,
          task5ActionAtMask, task5ActionIndex, boolAt, hprogress, h]

theorem task5NormalizedMask_enabled_exists (context : Task5MaskContext) :
    ∃ option, task5ActionAtMask (task5NormalizedMask context) option = true := by
  rcases task5NormalizedMask_has_enabled context with
    h | h | h | h | h | h | h | h | h
  · exact ⟨Task5Action.openChest, h⟩
  · exact ⟨Task5Action.attackMonster, h⟩
  · exact ⟨Task5Action.activateMechanism, h⟩
  · exact ⟨Task5Action.exitNorth, h⟩
  · exact ⟨Task5Action.exitEast, h⟩
  · exact ⟨Task5Action.exitSouth, h⟩
  · exact ⟨Task5Action.exitWest, h⟩
  · exact ⟨Task5Action.exploreRoom, h⟩
  · exact ⟨Task5Action.wait, h⟩

theorem normalizedMask_nonwait_conservative
    (raw : List Bool) (option : HighLevelAction)
    (hnotWait : option ≠ HighLevelAction.wait)
    (henabled : actionAtMask (normalizedMask raw) option = true) :
    actionAtMask raw option = true := by
  cases option <;>
    simp_all [normalizedMask, prioritizedAttackAllowed,
      prioritizedReturnAllowed, firstResolvedProgress, localProgress,
      actionAtMask, actionIndex, boolAt]

theorem task5ChestBit_true_implies_raw
    {context : Task5MaskContext}
    (henabled : task5ChestBit context = true) :
    task5ActionAtMask context.rawMask Task5Action.openChest = true := by
  by_cases hblocked :
      (task5LocalResource context.rawMask && context.attackIsProgress &&
        task5ActionAtMask context.rawMask Task5Action.attackMonster) = true
  · simp [task5ChestBit, hblocked] at henabled
  · simpa [task5ChestBit, hblocked] using henabled

theorem task5MechanismBit_true_implies_raw
    {context : Task5MaskContext}
    (henabled : task5MechanismBit context = true) :
    task5ActionAtMask context.rawMask Task5Action.activateMechanism = true := by
  by_cases hlocal : task5LocalResource context.rawMask = true
  · by_cases hattack :
        (context.attackIsProgress &&
          task5ActionAtMask context.rawMask Task5Action.attackMonster) = true
    · simp [task5MechanismBit, hlocal, hattack] at henabled
    · by_cases hchest :
          (task5ActionAtMask context.rawMask Task5Action.openChest &&
            !context.attackIsProgress) = true
      · simp [task5MechanismBit, hlocal, hattack, hchest] at henabled
      · simpa [task5MechanismBit, hlocal, hattack, hchest] using henabled
  · simpa [task5MechanismBit, hlocal] using henabled

theorem task5AttackBit_true_implies_raw
    {context : Task5MaskContext}
    (henabled : task5AttackBit context = true) :
    task5ActionAtMask context.rawMask Task5Action.attackMonster = true := by
  by_cases hlocal : task5LocalResource context.rawMask = true
  · by_cases hprogress : context.attackIsProgress = true
    · simpa [task5AttackBit, hlocal, hprogress] using henabled
    · simp [task5AttackBit, hlocal, hprogress] at henabled
  · by_cases hexit :
        ((task5HasNewExit context || task5HasUsedExit context) &&
          !context.attackIsProgress) = true
    · simp [task5AttackBit, hlocal, hexit] at henabled
    · simpa [task5AttackBit, hlocal, hexit] using henabled

theorem task5ExitBit_true_implies_raw
    {context : Task5MaskContext} {option : Task5Action}
    (henabled : task5ExitBit context option = true) :
    task5ActionAtMask context.rawMask option = true := by
  by_cases hlocal : task5LocalResource context.rawMask = true
  · simp [task5ExitBit, hlocal] at henabled
  · by_cases hpreferred :
        (task5PreferredActive context &&
          !(decide (option ∈ task5PreferredDirections context))) = true
    · simp [task5ExitBit, hlocal, hpreferred] at henabled
    · by_cases hused :
          (task5HasNewExit context && task5DirectionUsed context option) = true
      · simp [task5ExitBit, hlocal, hpreferred, hused] at henabled
      · simpa [task5ExitBit, hlocal, hpreferred, hused] using henabled

theorem task5NormalizedMask_nonwait_conservative
    (context : Task5MaskContext) (option : Task5Action)
    (hnotWait : option ≠ Task5Action.wait)
    (henabled :
      task5ActionAtMask (task5NormalizedMask context) option = true) :
    task5ActionAtMask context.rawMask option = true := by
  cases option with
  | openChest =>
      apply task5ChestBit_true_implies_raw
      simpa [task5NormalizedMask, task5ActionAtMask,
        task5ActionIndex, boolAt] using henabled
  | attackMonster =>
      apply task5AttackBit_true_implies_raw
      simpa [task5NormalizedMask, task5ActionAtMask,
        task5ActionIndex, boolAt] using henabled
  | activateMechanism =>
      apply task5MechanismBit_true_implies_raw
      simpa [task5NormalizedMask, task5ActionAtMask,
        task5ActionIndex, boolAt] using henabled
  | exitNorth =>
      apply task5ExitBit_true_implies_raw
      simpa [task5NormalizedMask, task5ActionAtMask,
        task5ActionIndex, boolAt] using henabled
  | exitEast =>
      apply task5ExitBit_true_implies_raw
      simpa [task5NormalizedMask, task5ActionAtMask,
        task5ActionIndex, boolAt] using henabled
  | exitSouth =>
      apply task5ExitBit_true_implies_raw
      simpa [task5NormalizedMask, task5ActionAtMask,
        task5ActionIndex, boolAt] using henabled
  | exitWest =>
      apply task5ExitBit_true_implies_raw
      simpa [task5NormalizedMask, task5ActionAtMask,
        task5ActionIndex, boolAt] using henabled
  | exploreRoom =>
      cases hprogress : task5ConcreteProgress context with
      | false =>
          simpa [task5NormalizedMask, task5ActionAtMask,
            task5ActionIndex, boolAt, hprogress] using henabled
      | true =>
          simp [task5NormalizedMask, task5ActionAtMask,
            task5ActionIndex, boolAt, hprogress] at henabled
  | wait =>
      exact False.elim (hnotWait rfl)

end RLBasedSubmission.Formalization.Strategy

namespace RLBasedSubmission.Formalization

open Strategy

/-! ## 最终 mask 相对公共环境 readiness 的可靠性 -/

def BaseRawMaskSound (state : SharedState) (raw : List Bool) : Prop :=
  ∀ option, actionAtMask raw option = true →
    baseOptionReady state option = true

def Task5RawMaskSound
    (state : SharedState) (context : Task5MaskContext) : Prop :=
  ∀ option, task5ActionAtMask context.rawMask option = true →
    task5OptionReady state option = true

theorem normalizedMask_sound
    {state : SharedState} {raw : List Bool}
    (hsound : BaseRawMaskSound state raw) :
    ∀ option, actionAtMask (normalizedMask raw) option = true →
      baseOptionReady state option = true := by
  intro option henabled
  by_cases hwait : option = HighLevelAction.wait
  · subst option
    simp [baseOptionReady]
  · exact hsound option
      (normalizedMask_nonwait_conservative raw option hwait henabled)

theorem task5NormalizedMask_sound
    {state : SharedState} {context : Task5MaskContext}
    (hsound : Task5RawMaskSound state context) :
    ∀ option,
      task5ActionAtMask (task5NormalizedMask context) option = true →
      task5OptionReady state option = true := by
  intro option henabled
  by_cases hwait : option = Task5Action.wait
  · subst option
    simp [task5OptionReady]
  · exact hsound option
      (task5NormalizedMask_nonwait_conservative
        context option hwait henabled)

theorem mask_respecting_policy_selects_ready
    {policy : MaskablePolicy} (hpolicy : RespectsMask policy)
    {state : SharedState} {raw : List Bool}
    (hsound : BaseRawMaskSound state raw)
    (features : FeatureVector) :
    baseOptionReady state
      (policy features (normalizedMask raw)) = true := by
  apply normalizedMask_sound hsound
  exact hpolicy features (normalizedMask raw)

theorem task5_mask_respecting_policy_selects_ready
    {policy : Task5MaskablePolicy} (hpolicy : Task5RespectsMask policy)
    {state : SharedState} {context : Task5MaskContext}
    (hsound : Task5RawMaskSound state context)
    (features : FeatureVector) :
    task5OptionReady state
      (policy features (task5NormalizedMask context)) = true := by
  apply task5NormalizedMask_sound hsound
  exact hpolicy features (task5NormalizedMask context)

theorem mask_respecting_policy_ready_resolution
    {policy : MaskablePolicy} (hpolicy : RespectsMask policy)
    {state : SharedState} {raw : List Bool}
    (hsound : BaseRawMaskSound state raw)
    (features : FeatureVector) :
    ∃ goal,
      resolveFromMask (normalizedMask raw)
          (policy features (normalizedMask raw)) = some goal ∧
      CompatibleGoal (policy features (normalizedMask raw)) goal ∧
      baseOptionReady state
          (policy features (normalizedMask raw)) = true := by
  rcases mask_respecting_policy_resolves
      hpolicy features (normalizedMask raw) with
    ⟨goal, hresolve, hcompatible⟩
  exact ⟨goal, hresolve, hcompatible,
    mask_respecting_policy_selects_ready hpolicy hsound features⟩

theorem task5_mask_respecting_policy_ready_resolution
    {policy : Task5MaskablePolicy} (hpolicy : Task5RespectsMask policy)
    {state : SharedState} {context : Task5MaskContext}
    (hsound : Task5RawMaskSound state context)
    (features : FeatureVector) :
    ∃ goal,
      task5ResolveFromMask (task5NormalizedMask context)
          (policy features (task5NormalizedMask context)) = some goal ∧
      Task5CompatibleGoal
          (policy features (task5NormalizedMask context)) goal ∧
      task5OptionReady state
          (policy features (task5NormalizedMask context)) = true := by
  rcases task5_mask_respecting_policy_resolves
      hpolicy features (task5NormalizedMask context) with
    ⟨goal, hresolve, hcompatible⟩
  exact ⟨goal, hresolve, hcompatible,
    task5_mask_respecting_policy_selects_ready
      hpolicy hsound features⟩

end RLBasedSubmission.Formalization

namespace RLBasedSubmission.Formalization.Strategy

/-! ## Primitive shield 的代数性质 -/

theorem shield_preserves_safe_move
    (state : SymbolicState) (action : PrimitiveAction)
    (hmove : isMove action)
    (hsafe : safeTile state (nextPosition state.player action)) :
    shield state action = action := by
  cases action <;> simp_all [isMove, shield]

theorem shield_idempotent
    (state : SymbolicState) (action : PrimitiveAction) :
    shield state (shield state action) = shield state action := by
  classical
  cases action with
  | wait => rfl
  | buttonA => rfl
  | buttonB => rfl
  | up =>
      by_cases hsafe :
          safeTile state (nextPosition state.player PrimitiveAction.up)
      · simp [shield, hsafe]
      · simp [shield, hsafe]
  | down =>
      by_cases hsafe :
          safeTile state (nextPosition state.player PrimitiveAction.down)
      · simp [shield, hsafe]
      · simp [shield, hsafe]
  | left =>
      by_cases hsafe :
          safeTile state (nextPosition state.player PrimitiveAction.left)
      · simp [shield, hsafe]
      · simp [shield, hsafe]
  | right =>
      by_cases hsafe :
          safeTile state (nextPosition state.player PrimitiveAction.right)
      · simp [shield, hsafe]
      · simp [shield, hsafe]
theorem shield_move_output_safe
    (state : SymbolicState) (action : PrimitiveAction)
    (hmove : isMove (shield state action)) :
    safeTile state (nextPosition state.player (shield state action)) := by
  let decision : PrimitiveDecision :=
    { action := action, setupOnly := false }
  have hsafe := shielded_non_setup_move_safe state decision rfl hmove
  simpa [decision, appliedPrimitive] using hsafe

end RLBasedSubmission.Formalization.Strategy

namespace RuleBasedSubmission.Formalization

/-! ## Rule-based shield 的全定义性和确定性 -/

def AgentControllableAction (action : Action) : Prop :=
  action = Action.wait ∨
  action = Action.pressA ∨
  action = Action.pressB ∨
  action ∈ movementActions

theorem exitPushAllowed_not_walkable
    {state : SymbolicState} {action : Action}
    (hexit : exitPushAllowed state action) :
    ¬ isWalkable state (nextPosition state.player action) := by
  intro hwalkable
  exact hexit.2.2.2 hwalkable.1.1

theorem shielded_total
    {state : SymbolicState} {raw : Action}
    (hsupported : AgentControllableAction raw) :
    ∃ out, Shielded state raw out := by
  rcases hsupported with hwait | hA | hB | hmove
  · subst raw
    exact ⟨Action.wait, Shielded.passWait⟩
  · subst raw
    exact ⟨Action.pressA, Shielded.passA⟩
  · subst raw
    exact ⟨Action.pressB, Shielded.passB⟩
  · by_cases hexit : exitPushAllowed state raw
    · exact ⟨raw, Shielded.allowExit hexit⟩
    · by_cases hsafe : isWalkable state (nextPosition state.player raw)
      · exact ⟨raw, Shielded.allowSafe hmove hsafe⟩
      · exact ⟨Action.wait, Shielded.blockUnsafe hmove hexit hsafe⟩

theorem shielded_deterministic
    {state : SymbolicState} {raw first second : Action}
    (hfirst : Shielded state raw first)
    (hsecond : Shielded state raw second) :
    first = second := by
  cases hfirst <;> cases hsecond <;>
    simp_all [movementActions, exitPushAllowed_not_walkable]

theorem shielded_exists_unique
    {state : SymbolicState} {raw : Action}
    (hsupported : AgentControllableAction raw) :
    ∃ out, Shielded state raw out ∧
      ∀ other, Shielded state raw other → other = out := by
  rcases shielded_total hsupported with ⟨out, hout⟩
  exact ⟨out, hout, fun other hother =>
    shielded_deterministic hother hout⟩
end RuleBasedSubmission.Formalization

namespace RLBasedSubmission.Formalization

open Strategy

/-! ## 颜色模式不变性向特征和策略输出的提升 -/

theorem color_mode_base_features_invariant
    {normalize : ColorNormalizer} {extract : SymbolExtractor}
    (hinvariant : ColorModeInvariant normalize extract)
    (first second : ColorMode) (frame : PixelFrame)
    (enabled : List HighLevelAction) :
    encodeHighLevelState
        (baseInputFromShared (extract (normalize first frame)) enabled) =
      encodeHighLevelState
        (baseInputFromShared (extract (normalize second frame)) enabled) := by
  rw [hinvariant first second frame]

theorem color_mode_task5_features_invariant
    {normalize : ColorNormalizer} {extract : SymbolExtractor}
    (hinvariant : ColorModeInvariant normalize extract)
    (first second : ColorMode) (frame : PixelFrame)
    (context : Task5MaskContext) :
    encodeTask5State
        (task5InputFromShared (extract (normalize first frame)) context) =
      encodeTask5State
        (task5InputFromShared (extract (normalize second frame)) context) := by
  rw [hinvariant first second frame]

theorem color_mode_base_policy_output_invariant
    (policy : MaskablePolicy)
    {normalize : ColorNormalizer} {extract : SymbolExtractor}
    (hinvariant : ColorModeInvariant normalize extract)
    (first second : ColorMode) (frame : PixelFrame)
    (enabled : List HighLevelAction) :
    policy
        (encodeHighLevelState
          (baseInputFromShared (extract (normalize first frame)) enabled))
        (normalizedMask (baseRawMask enabled)) =
      policy
        (encodeHighLevelState
          (baseInputFromShared (extract (normalize second frame)) enabled))
        (normalizedMask (baseRawMask enabled)) := by
  rw [hinvariant first second frame]

theorem color_mode_task5_policy_output_invariant
    (policy : Task5MaskablePolicy)
    {normalize : ColorNormalizer} {extract : SymbolExtractor}
    (hinvariant : ColorModeInvariant normalize extract)
    (first second : ColorMode) (frame : PixelFrame)
    (context : Task5MaskContext) :
    policy
        (encodeTask5State
          (task5InputFromShared (extract (normalize first frame)) context))
        (task5NormalizedMask context) =
      policy
        (encodeTask5State
          (task5InputFromShared (extract (normalize second frame)) context))
        (task5NormalizedMask context) := by
  rw [hinvariant first second frame]

end RLBasedSubmission.Formalization

namespace MathLogic.Formalization

/-! ## 结构化出口的必要前置条件 -/

theorem buttonGate_exit_requires_pressed
    {state : SymbolicState} {exit : Exit} {button : Position}
    (husable : canUseExitObject state exit)
    (hkind : exit.kind = ExitKind.buttonGate button) :
    button ∈ state.pressedButtons := by
  have hcondition := husable.2.2.2
  simpa [exitCondition, hkind] using hcondition

theorem allMonstersAndKey_exit_requires_resources
    {state : SymbolicState} {exit : Exit}
    {need : Nat} {consume : Bool}
    (husable : canUseExitObject state exit)
    (hkind : exit.kind = ExitKind.allMonstersAndKey need consume) :
    need ≤ state.keys ∧ state.monsters = [] := by
  have hcondition := husable.2.2.2
  simpa [exitCondition, hkind] using hcondition

theorem itemGate_exit_requires_item
    {state : SymbolicState} {exit : Exit} {item : Item}
    (husable : canUseExitObject state exit)
    (hkind : exit.kind = ExitKind.itemGate item) :
    item ∈ state.items := by
  have hcondition := husable.2.2.2
  simpa [exitCondition, hkind] using hcondition

theorem fullEnvStep_useExit_has_usable_exit
    {state next : SymbolicState}
    (step : FullEnvStep state Action.useExit next) :
    ∃ exit, canUseExitObject state exit ∧
      next = useExitObjectState state exit := by
  cases step with
  | basic basicStep =>
      cases basicStep <;> simp [movementActions, exitPushAllowed] at *
  | useExitObject husable =>
      exact ⟨_, husable, rfl⟩

end MathLogic.Formalization

namespace MathLogic.Formalization.Additional

open RuleBasedSubmission.Formalization
open RLBasedSubmission.Formalization

/-! ## 两条路线证书的公共轨迹一致性 -/

def CertificatesShareTrace
    {goal : SymbolicState → Prop} {init : SymbolicState}
    (first second : TaskCertificate goal init) : Prop :=
  first.plan = second.plan ∧ first.final = second.final

theorem task1_route_certificates_share_trace :
    CertificatesShareTrace ruleTask1Certificate.toTaskCertificate rlTask1Certificate := by
  constructor <;> rfl

theorem task2_route_certificates_share_trace :
    CertificatesShareTrace ruleTask2Certificate.toTaskCertificate rlTask2Certificate := by
  constructor <;> rfl

theorem task3_route_certificates_share_trace :
    CertificatesShareTrace ruleTask3Certificate.toTaskCertificate rlTask3Certificate := by
  constructor <;> rfl

theorem task4_route_certificates_share_trace :
    CertificatesShareTrace ruleTask4Certificate.toTaskCertificate rlTask4Certificate := by
  constructor <;> rfl

theorem task5_route_certificates_share_trace :
    CertificatesShareTrace ruleTask5Certificate.toTaskCertificate rlTask5Certificate := by
  constructor <;> rfl

theorem all_route_certificates_share_trace :
    CertificatesShareTrace ruleTask1Certificate.toTaskCertificate rlTask1Certificate ∧
    CertificatesShareTrace ruleTask2Certificate.toTaskCertificate rlTask2Certificate ∧
    CertificatesShareTrace ruleTask3Certificate.toTaskCertificate rlTask3Certificate ∧
    CertificatesShareTrace ruleTask4Certificate.toTaskCertificate rlTask4Certificate ∧
    CertificatesShareTrace ruleTask5Certificate.toTaskCertificate rlTask5Certificate :=
  ⟨task1_route_certificates_share_trace,
    task2_route_certificates_share_trace,
    task3_route_certificates_share_trace,
    task4_route_certificates_share_trace,
    task5_route_certificates_share_trace⟩

end MathLogic.Formalization.Additional

namespace RuleBasedSubmission.Formalization

/-! ## 可计算的逐层安全搜索及其可靠性、完备性 -/

/--
从位置 position 可执行的安全移动。List.filter 使该函数可以直接计算；
它只保留公共环境 isWalkable 判定为真的四方向动作。
-/
instance isWalkable_decidable
    (state : SymbolicState) (position : Position) :
    Decidable (isWalkable state position) := by
  unfold isWalkable terrainPassable inBounds
  infer_instance
def safeActionsFrom
    (state : SymbolicState) (position : Position) : List Action := by
  exact movementActions.filter fun action =>
    decide (isWalkable { state with player := position }
      (nextPosition position action))

theorem mem_safeActionsFrom_iff
    {state : SymbolicState} {position : Position} {action : Action} :
    action ∈ safeActionsFrom state position ↔
      action ∈ movementActions ∧
      isWalkable { state with player := position }
        (nextPosition position action) := by
  classical
  simp [safeActionsFrom]

def safeSuccessors (state : SymbolicState) (position : Position) :
    List Position :=
  (safeActionsFrom state position).map (nextPosition position)

theorem mem_safeSuccessors_iff
    {state : SymbolicState} {position target : Position} :
    target ∈ safeSuccessors state position ↔
      ∃ action,
        action ∈ movementActions ∧
        isWalkable { state with player := position }
          (nextPosition position action) ∧
        nextPosition position action = target := by
  simp [safeSuccessors, mem_safeActionsFrom_iff, and_assoc]

/--
breadthFrontier state depth 是恰好 depth 步安全可达的位置层。
定义对 depth 做结构递归，因此搜索层构造在 Lean 中必然终止。
-/
def breadthFrontier (state : SymbolicState) : Nat → List Position
  | 0 => [state.player]
  | depth + 1 =>
      (breadthFrontier state depth).flatMap (safeSuccessors state)

theorem mem_breadthFrontier_iff_positionReachable
    (state : SymbolicState) (depth : Nat) (target : Position) :
    target ∈ breadthFrontier state depth ↔
      PositionReachable state depth target := by
  induction depth generalizing target with
  | zero =>
      constructor
      · intro hmem
        simp [breadthFrontier] at hmem
        subst target
        exact PositionReachable.zero
      · intro hreach
        cases hreach
        simp [breadthFrontier]
  | succ depth ih =>
      constructor
      · intro hmem
        rw [breadthFrontier] at hmem
        rcases List.mem_flatMap.mp hmem with
          ⟨previous, hprevious, hsuccessor⟩
        rcases mem_safeSuccessors_iff.mp hsuccessor with
          ⟨action, hmove, hwalkable, htarget⟩
        subst target
        exact PositionReachable.step
          ((ih previous).mp hprevious) hmove hwalkable
      · intro hreach
        cases hreach with
        | step hprevious hmove hwalkable =>
            rw [breadthFrontier]
            apply List.mem_flatMap.mpr
            exact ⟨_, (ih _).mpr hprevious,
              mem_safeSuccessors_iff.mpr
                ⟨_, hmove, hwalkable, rfl⟩⟩

theorem breadthFrontier_complete
    (state : SymbolicState) (depth : Nat) :
    PlannerFrontierComplete state depth (breadthFrontier state depth) := by
  intro target hreachable
  exact (mem_breadthFrontier_iff_positionReachable
    state depth target).mpr hreachable

theorem breadthFrontier_sound
    (state : SymbolicState) (depth : Nat) :
    ∀ target, target ∈ breadthFrontier state depth →
      PositionReachable state depth target := by
  intro target hmem
  exact (mem_breadthFrontier_iff_positionReachable
    state depth target).mp hmem

theorem breadth_search_complete
    {state : SymbolicState} {depth : Nat} {goals : List Position}
    (hreachable : PlannerGoalReachable state depth goals) :
    PlannerFindsGoal (breadthFrontier state depth) goals :=
  planner_completeness_from_frontier_invariant
    (breadthFrontier_complete state depth) hreachable

theorem breadth_search_sound
    {state : SymbolicState} {depth : Nat} {goals : List Position}
    (hfound : PlannerFindsGoal (breadthFrontier state depth) goals) :
    PlannerGoalReachable state depth goals := by
  rcases hfound with ⟨target, hfrontier, hgoal⟩
  exact ⟨target,
    (mem_breadthFrontier_iff_positionReachable
      state depth target).mp hfrontier,
    hgoal⟩

theorem breadth_search_sound_and_complete
    (state : SymbolicState) (depth : Nat) (goals : List Position) :
    PlannerFindsGoal (breadthFrontier state depth) goals ↔
      PlannerGoalReachable state depth goals :=
  ⟨breadth_search_sound, breadth_search_complete⟩

end RuleBasedSubmission.Formalization

namespace RuleBasedSubmission.Formalization

/-! ## 搜索结果的动作计划证书 -/

def breadthFindsGoal
    (state : SymbolicState) (depth : Nat) (goals : List Position) : Bool :=
  (breadthFrontier state depth).any fun position =>
    decide (position ∈ goals)

theorem breadthFindsGoal_eq_true_iff
    (state : SymbolicState) (depth : Nat) (goals : List Position) :
    breadthFindsGoal state depth goals = true ↔
      PlannerGoalReachable state depth goals := by
  simp [breadthFindsGoal, PlannerGoalReachable,
    mem_breadthFrontier_iff_positionReachable]

inductive SafeMovePlan (state : SymbolicState) :
    List Action → Position → Prop where
  | nil :
      SafeMovePlan state [] state.player
  | snoc
      {plan : List Action} {current : Position} {action : Action} :
      SafeMovePlan state plan current →
      action ∈ movementActions →
      isWalkable { state with player := current }
        (nextPosition current action) →
      SafeMovePlan state (plan ++ [action])
        (nextPosition current action)

theorem safeMovePlan_positionReachable
    {state : SymbolicState} {plan : List Action} {target : Position}
    (hsafe : SafeMovePlan state plan target) :
    PositionReachable state plan.length target := by
  induction hsafe with
  | nil =>
      exact PositionReachable.zero
  | snoc _hplan hmove hwalkable ih =>
      simpa using PositionReachable.step ih hmove hwalkable

theorem positionReachable_has_safeMovePlan
    {state : SymbolicState} {depth : Nat} {target : Position}
    (hreachable : PositionReachable state depth target) :
    ∃ plan, plan.length = depth ∧ SafeMovePlan state plan target := by
  induction hreachable with
  | zero =>
      exact ⟨[], rfl, SafeMovePlan.nil⟩
  | step hprevious hmove hwalkable ih =>
      rcases ih with ⟨plan, hlength, hsafe⟩
      exact ⟨plan ++ [_], by simp [hlength],
        SafeMovePlan.snoc hsafe hmove hwalkable⟩

theorem safeMovePlan_exec
    {state : SymbolicState} {plan : List Action} {target : Position}
    (hsafe : SafeMovePlan state plan target)
    (hbuttons : state.buttons = []) :
    Exec state plan { state with player := target } := by
  induction hsafe with
  | nil =>
      simpa using (Exec.nil : Exec state [] state)
  | @snoc plan current action hplan hmove hwalkable ih =>
      have hstep :
          EnvStep { state with player := current } action
            (enterPositionState { state with player := current }
              (nextPosition current action)) :=
        EnvStep.moveSafe hmove hwalkable
      have henter :
          enterPositionState { state with player := current }
              (nextPosition current action) =
            { state with player := nextPosition current action } := by
        simp [enterPositionState, hbuttons]
      rw [henter] at hstep
      have oneStep :
          Exec { state with player := current } [action]
            { state with player := nextPosition current action } :=
        Exec.cons hstep Exec.nil
      exact exec_append ih oneStep

structure VerifiedSearchResult
    (state : SymbolicState) (goals : List Position) where
  plan : List Action
  target : Position
  target_mem : target ∈ goals
  safe : SafeMovePlan state plan target

theorem verifiedSearchResult_sound
    {state : SymbolicState} {goals : List Position}
    (result : VerifiedSearchResult state goals)
    (hbuttons : state.buttons = []) :
    Exec state result.plan { state with player := result.target } ∧
      result.target ∈ goals := by
  exact ⟨safeMovePlan_exec result.safe hbuttons, result.target_mem⟩

theorem breadth_found_has_verified_plan
    {state : SymbolicState} {depth : Nat} {goals : List Position}
    (hfound : PlannerFindsGoal (breadthFrontier state depth) goals) :
    ∃ result : VerifiedSearchResult state goals,
      result.plan.length = depth := by
  rcases breadth_search_sound hfound with
    ⟨target, hreachable, hgoal⟩
  rcases positionReachable_has_safeMovePlan hreachable with
    ⟨plan, hlength, hsafe⟩
  let result : VerifiedSearchResult state goals :=
    { plan := plan
      target := target
      target_mem := hgoal
      safe := hsafe }
  exact ⟨result, hlength⟩

theorem verified_search_result_iff_reachable
    (state : SymbolicState) (goals : List Position) :
    Nonempty (VerifiedSearchResult state goals) ↔
      ∃ depth, PlannerGoalReachable state depth goals := by
  constructor
  · rintro ⟨result⟩
    exact ⟨result.plan.length, result.target,
      safeMovePlan_positionReachable result.safe,
      result.target_mem⟩
  · rintro ⟨depth, target, hreachable, hgoal⟩
    rcases positionReachable_has_safeMovePlan hreachable with
      ⟨plan, _hlength, hsafe⟩
    let result : VerifiedSearchResult state goals :=
      { plan := plan
        target := target
        target_mem := hgoal
        safe := hsafe }
    exact ⟨result⟩

end RuleBasedSubmission.Formalization
