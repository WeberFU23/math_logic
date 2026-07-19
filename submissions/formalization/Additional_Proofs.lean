import Rule_based_TaskProofs

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
