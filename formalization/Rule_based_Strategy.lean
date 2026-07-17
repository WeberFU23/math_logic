import formalization.Environment

open MathLogic.Formalization

/-!
本文件是规则版提交的「模块二：策略形式化与证明」。

本层依赖 `Environment.lean` 中已经定义好的环境语义。
它不重新定义环境，只形式化当前规则版 Agent 中可验证的策略层：

1. 关系式规则说明 `RuleGoal` 与可执行选择器 `ruleBasedChooseGoal`；
2. 实际选择器满足的具体优先级契约 `RulePriorityContract`；
3. BFS/planner 输出第一步的安全契约 `PlannerStep`；
4. executor 从目标生成动作的关系 `ActionForGoal`；
5. safety shield 的过滤关系 `Shielded`；
6. 确定的 `AgentMemory` 更新；
7. 串联选择器、executor、shield、环境与记忆的 `RulePolicyStep` 和
   `RulePolicyExec`；
8. 携带策略生成证明的 `RuleTaskCertificate`。

本文件对应 Python 文件：

* `strategy.py`：高层目标优先级；
* `planner.py`：BFS 路径规划；
* `executor.py`：目标到动作；
* `shield.py`：最终动作安全过滤。
-/

namespace RuleBasedSubmission.Formalization

/-!
【Agent 记忆】
`AgentMemory` 抽象 Python `AgentMemory` 中和策略证明有关的字段。
这里不形式化全部调试字段，只保留影响目标合法性的记忆：
上一目标、已开宝箱、已触发机关、已使用出口。
-/
structure AgentMemory where
  lastGoal : Option Goal := none
  openedChests : List GlobalPosition := []
  activatedButtons : List GlobalPosition := []
  activatedSwitches : List GlobalPosition := []
  visitActivatedSwitches : List GlobalPosition := []
  usedExits : List GlobalPosition := []
  roomSteps : Nat := 0
  switchButtonCooldown : Nat := 0
  deriving DecidableEq, Repr

/-!
【无未开宝箱谓词】
`noUnopenedChests s m` 表示当前可见宝箱都已经在记忆中标记为打开。
规则策略只有在没有更高价值宝箱目标时，才会考虑某些战斗/出口 fallback。
-/
def noUnopenedChests (s : SymbolicState) (m : AgentMemory) : Prop :=
  ∀ c, c ∈ s.chests → globalize s.room c ∈ m.openedChests

/-!
【无未用机关谓词】
`noUnusedMechanisms s m` 表示当前可见按钮/开关都已经被记忆为触发过。
这对应 `strategy.py` 中避免过早打怪、优先探索机关的逻辑。
-/
def noUnusedMechanisms (s : SymbolicState) (m : AgentMemory) : Prop :=
  (∀ p, p ∈ s.buttons → globalize s.room p ∈ m.activatedButtons) ∧
  (∀ p, p ∈ s.switches → globalize s.room p ∈ m.visitActivatedSwitches)

/-!
【无可见宝箱谓词】
`noVisibleChests s` 表示视觉层当前没有仍然挡路或可交互的宝箱。
当前 `strategy.py` 的清怪 fallback 使用 `bool(state.chests)`，
因此这里用可见列表为空来表达“宝箱已经处理完”。
-/
def noVisibleChests (s : SymbolicState) : Prop :=
  s.chests = []

/-!
【无可见开关谓词】
`noVisibleSwitches s` 表示当前房间没有仍然可见的开关。
规则版只会在没有开关、按钮、宝箱和未用出口时，把清怪作为离开前的 fallback。
-/
def noVisibleSwitches (s : SymbolicState) : Prop :=
  s.switches = []

/-!
【无可见按钮谓词】
`noVisibleButtons s` 表示当前房间没有仍然可见的按钮。
这对应条件门逻辑中“按钮已经踩完或不再需要处理”的状态。
-/
def noVisibleButtons (s : SymbolicState) : Prop :=
  s.buttons = []

/-!
【无未用门出口谓词】
`noUnusedDoorExits s m` 表示当前房间所有门形出口都已经在记忆中记录为用过。
它抽象 `strategy.py` 的 `_has_unused_exits` 为否的情况。
-/
def noUnusedDoorExits (s : SymbolicState) (m : AgentMemory) : Prop :=
  ∀ p, p ∈ allExits s → isDoorExit p →
    globalize s.room p ∈ m.usedExits

/-!
【清怪前房间耗尽谓词】
`roomExhaustedBeforeCombat s m` 表示房间中没有更优先的宝箱、开关、按钮或未用出口。
这是 `_must_clear_monsters_before_exit` 的可验证抽象。
-/
def roomExhaustedBeforeCombat (s : SymbolicState) (m : AgentMemory) : Prop :=
  noVisibleChests s ∧
  noVisibleSwitches s ∧
  noVisibleButtons s ∧
  noUnusedDoorExits s m

/-!
【条件门准备好谓词】
`conditionalDoorReady s` 表示条件门的本地前置条件已经满足：
按钮列表为空，并且房间内没有仍需清理的怪物。
Python 策略只有在这个条件成立时才会选择条件门出口。
-/
def visibleButtonsSatisfied (s : SymbolicState) : Prop :=
  s.buttons.all (fun button =>
    decide (button ∈ s.pressedButtons ∨ button ∈ s.activated)) = true

def conditionalDoorReady (s : SymbolicState) : Prop :=
  visibleButtonsSatisfied s ∧
  (s.buttons ≠ [] ∨ s.monsters = [])

/-!
【出口目标合法性谓词】
`ExitGoalAdmissible s p` 细分三类出口：
普通出口可直接作为目标；锁门出口需要至少一把钥匙；
条件门出口需要按钮和怪物前置条件已经完成。
`s.exits` 是兼容早期形式化的旧字段，按普通出口处理。
-/
def ExitGoalAdmissible (s : SymbolicState) (p : Position) : Prop :=
  p ∈ s.exits ∨
  p ∈ s.normalExits ∨
  (p ∈ s.lockedExits ∧ s.keys > 0) ∨
  (p ∈ s.conditionalExits ∧ conditionalDoorReady s)

/-!
【定理：合法出口目标一定属于所有出口集合】
如果一个出口目标满足 `ExitGoalAdmissible`，则它一定出现在 `allExits s` 中。
这个定理把细分出口规则和环境层统一出口集合连接起来。
-/
theorem exit_goal_admissible_mem_allExits
    {s : SymbolicState} {p : Position}
    (h : ExitGoalAdmissible s p) :
    p ∈ allExits s := by
  rcases h with hlegacy | hnormal | hlocked | hcond
  · simp [allExits, hlegacy]
  · simp [allExits, hnormal]
  · rcases hlocked with ⟨hlocked, _hkeys⟩
    simp [allExits, hlocked]
  · rcases hcond with ⟨hcond, _hready⟩
    simp [allExits, hcond]

/-!
【可接受目标谓词】
`GoalAdmissible s m g` 表示目标 `g` 在状态 `s` 和记忆 `m` 下语义合法。
例如：开箱目标必须真的是未打开宝箱，攻击目标必须真的是怪物且有剑。
-/
def GoalAdmissible (s : SymbolicState) (m : AgentMemory) (g : Goal) : Prop :=
  match g.kind, g.target with
  | GoalKind.openChest, some p =>
      p ∈ s.chests ∧ globalize s.room p ∉ m.openedChests
  | GoalKind.attackMonster, some p =>
      p ∈ s.monsters ∧ s.hasSword = true ∧ healthSafe s
  | GoalKind.activateButton, some p =>
      p ∈ s.buttons ∧ s.conditionalExits ≠ [] ∧
      globalize s.room p ∉ m.activatedButtons
  | GoalKind.activateSwitch, some p =>
      p ∈ s.switches ∧
      globalize s.room p ∉ m.visitActivatedSwitches ∧
      m.switchButtonCooldown = 0
  | GoalKind.goToExit, some p =>
      ExitGoalAdmissible s p
  | GoalKind.explore, some p =>
      isWalkable s p
  | GoalKind.wait, none =>
      True
  | _, _ =>
      False

/-!
【位置层有界可达】
`PositionReachable s n p` 表示从状态 `s.player` 出发，
最多经过 `n` 步安全移动可以到达位置 `p`。
这是 planner/BFS 正确性证明中使用的可达性规格。
-/
inductive PositionReachable (s : SymbolicState) : Nat → Position → Prop where
  | zero :
      PositionReachable s 0 s.player
  | step
      {n : Nat} {p : Position} {a : Action} :
      PositionReachable s n p →
      a ∈ movementActions →
      isWalkable { s with player := p } (nextPosition p a) →
      PositionReachable s (n + 1) (nextPosition p a)

/-!
【规划器可达接口】
`PlannerCanReach s target` 是对 BFS 可达性的抽象接口。
它不再是空洞占位，而是要求目标位置在某个有限步数内可由安全移动到达。
具体队列、父指针和 visited 集合仍由 Python 执行；Lean 侧证明使用这个规格。
-/
def PlannerCanReach (s : SymbolicState) (target : Position) : Prop :=
  ∃ n, PositionReachable s n target

/-!
【定理：当前位置总是 planner 可达】
零步路径即可到达当前玩家所在位置。
这是可达性规格的基本自反性。
-/
theorem planner_can_reach_player (s : SymbolicState) :
    PlannerCanReach s s.player := by
  exact ⟨0, PositionReachable.zero⟩

/-!
【策略选择器使用的有限可计算可达性】
Python `is_reachable` 在 10×8 棋盘上运行 BFS。这里用累计前沿计算同一类
安全可达位置；80 轮覆盖有限棋盘上所有不重复位置组成的简单路径。
-/
instance policy_isWalkable_decidable
    (state : SymbolicState) (position : Position) :
    Decidable (isWalkable state position) := by
  unfold isWalkable terrainPassable inBounds
  infer_instance

def policySafeSuccessors
    (state : SymbolicState) (position : Position) : List Position :=
  (movementActions.filter fun action =>
    decide (isWalkable { state with player := position }
      (nextPosition position action))).map (nextPosition position)

def policyReachablePositions (state : SymbolicState) : Nat → List Position
  | 0 => [state.player]
  | depth + 1 =>
      let reached := policyReachablePositions state depth
      (reached ++ reached.flatMap (policySafeSuccessors state)).eraseDups

def policyCanReachAny
    (state : SymbolicState) (targets : List Position) : Bool :=
  (policyReachablePositions state 80).any fun position =>
    decide (position ∈ targets)

def policyApproachTiles (position : Position) : List Position :=
  [nextPosition position Action.up,
    nextPosition position Action.down,
    nextPosition position Action.left,
    nextPosition position Action.right]

/-!
【规则目标选择关系】
`RuleGoal s m g` 表示当前规则策略可以在状态 `s` 和记忆 `m` 下选择目标 `g`。
构造子顺序对应 `strategy.py` 的优先级思想：
sticky goal、相邻宝箱、可达宝箱、相邻怪物、房间耗尽后的必要清怪、
条件门按钮、条件门清怪、条件门出口、锁门出口、普通出口、开关、
fallback 出口、探索、等待。
-/
inductive RuleGoal : SymbolicState → AgentMemory → Goal → Prop where
  | sticky
      {s : SymbolicState} {m : AgentMemory} {g : Goal} :
      m.lastGoal = some g →
      GoalAdmissible s m g →
      RuleGoal s m g
  | adjacentChest
      {s : SymbolicState} {m : AgentMemory} {c : Position} :
      c ∈ s.chests →
      globalize s.room c ∉ m.openedChests →
      adjacent s.player c →
      RuleGoal s m { kind := GoalKind.openChest, target := some c }
  | reachableChest
      {s : SymbolicState} {m : AgentMemory} {c : Position} :
      c ∈ s.chests →
      globalize s.room c ∉ m.openedChests →
      PlannerCanReach s c →
      RuleGoal s m { kind := GoalKind.openChest, target := some c }
  | adjacentMonster
      {s : SymbolicState} {m : AgentMemory} {p : Position} :
      p ∈ s.monsters →
      adjacent s.player p →
      s.hasSword = true →
      healthSafe s →
      RuleGoal s m { kind := GoalKind.attackMonster, target := some p }
  | requiredMonster
      {s : SymbolicState} {m : AgentMemory} {p : Position} :
      p ∈ s.monsters →
      s.hasSword = true →
      healthSafe s →
      roomExhaustedBeforeCombat s m →
      RuleGoal s m { kind := GoalKind.attackMonster, target := some p }
  | buttonForConditionalDoor
      {s : SymbolicState} {m : AgentMemory} {p : Position} :
      s.conditionalExits ≠ [] →
      p ∈ s.buttons →
      globalize s.room p ∉ m.activatedButtons →
      RuleGoal s m { kind := GoalKind.activateButton, target := some p }
  | conditionalMonster
      {s : SymbolicState} {m : AgentMemory} {p : Position} :
      s.conditionalExits ≠ [] →
      noVisibleButtons s →
      p ∈ s.monsters →
      s.hasSword = true →
      healthSafe s →
      RuleGoal s m { kind := GoalKind.attackMonster, target := some p }
  | unusedConditionalExit
      {s : SymbolicState} {m : AgentMemory} {p : Position} :
      p ∈ s.conditionalExits →
      conditionalDoorReady s →
      globalize s.room p ∉ m.usedExits →
      RuleGoal s m { kind := GoalKind.goToExit, target := some p }
  | unusedLockedExit
      {s : SymbolicState} {m : AgentMemory} {p : Position} :
      p ∈ s.lockedExits →
      s.keys > 0 →
      globalize s.room p ∉ m.usedExits →
      RuleGoal s m { kind := GoalKind.goToExit, target := some p }
  | unusedLegacyExit
      {s : SymbolicState} {m : AgentMemory} {p : Position} :
      p ∈ s.exits →
      globalize s.room p ∉ m.usedExits →
      RuleGoal s m { kind := GoalKind.goToExit, target := some p }
  | unusedNormalExit
      {s : SymbolicState} {m : AgentMemory} {p : Position} :
      p ∈ s.normalExits →
      globalize s.room p ∉ m.usedExits →
      RuleGoal s m { kind := GoalKind.goToExit, target := some p }
  | switchMechanism
      {s : SymbolicState} {m : AgentMemory} {p : Position} :
      p ∈ s.switches →
      globalize s.room p ∉ m.visitActivatedSwitches →
      m.switchButtonCooldown = 0 →
      RuleGoal s m { kind := GoalKind.activateSwitch, target := some p }
  | usedLegacyExitFallback
      {s : SymbolicState} {m : AgentMemory} {p : Position} :
      p ∈ s.exits →
      RuleGoal s m { kind := GoalKind.goToExit, target := some p }
  | usedNormalExitFallback
      {s : SymbolicState} {m : AgentMemory} {p : Position} :
      p ∈ s.normalExits →
      RuleGoal s m { kind := GoalKind.goToExit, target := some p }
  | usedConditionalExitFallback
      {s : SymbolicState} {m : AgentMemory} {p : Position} :
      p ∈ s.conditionalExits →
      conditionalDoorReady s →
      RuleGoal s m { kind := GoalKind.goToExit, target := some p }
  | usedLockedExitFallback
      {s : SymbolicState} {m : AgentMemory} {p : Position} :
      p ∈ s.lockedExits →
      s.keys > 0 →
      RuleGoal s m { kind := GoalKind.goToExit, target := some p }
  | explore
      {s : SymbolicState} {m : AgentMemory} {p : Position} :
      isWalkable s p →
      RuleGoal s m { kind := GoalKind.explore, target := some p }
  | wait
      {s : SymbolicState} {m : AgentMemory} :
      RuleGoal s m { kind := GoalKind.wait, target := none }

/-!
【定理：规则策略只会选择可接受目标】
这是 `strategy.py` 高层目标选择的核心正确性：
不管目标来自 sticky、宝箱、怪物、出口、机关、探索还是等待，
它都满足 `GoalAdmissible`。
-/
theorem rule_goal_admissible
    {s : SymbolicState} {m : AgentMemory} {g : Goal}
    (h : RuleGoal s m g) :
    GoalAdmissible s m g := by
  cases h with
  | sticky _ hadm =>
      exact hadm
  | adjacentChest hchest hclosed _hadj =>
      simpa [GoalAdmissible] using And.intro hchest hclosed
  | reachableChest hchest hclosed _hreach =>
      simpa [GoalAdmissible] using And.intro hchest hclosed
  | adjacentMonster hmon _hadj hsword hhp =>
      simpa [GoalAdmissible] using ⟨hmon, hsword, hhp⟩
  | requiredMonster hmon hsword hhp _hexhausted =>
      simpa [GoalAdmissible] using ⟨hmon, hsword, hhp⟩
  | unusedLegacyExit hlegacy _hunused =>
      simpa [GoalAdmissible, ExitGoalAdmissible] using
        Or.inl hlegacy
  | unusedNormalExit hnormal _hunused =>
      simpa [GoalAdmissible, ExitGoalAdmissible] using
        Or.inr (Or.inl hnormal)
  | buttonForConditionalDoor hcond hbutton hfresh =>
      simpa [GoalAdmissible] using ⟨hbutton, hcond, hfresh⟩
  | conditionalMonster _hcond _hbuttons hmon hsword hhp =>
      simpa [GoalAdmissible] using ⟨hmon, hsword, hhp⟩
  | unusedConditionalExit hcondExit hready _hunused =>
      simpa [GoalAdmissible, ExitGoalAdmissible] using
        Or.inr (Or.inr (Or.inr ⟨hcondExit, hready⟩))
  | unusedLockedExit hlocked hkeys _hunused =>
      simpa [GoalAdmissible, ExitGoalAdmissible] using
        Or.inr (Or.inr (Or.inl ⟨hlocked, hkeys⟩))
  | switchMechanism hswitch hfresh hcooldown =>
      simpa [GoalAdmissible] using ⟨hswitch, hfresh, hcooldown⟩
  | usedLegacyExitFallback hlegacy =>
      simpa [GoalAdmissible, ExitGoalAdmissible] using
        Or.inl hlegacy
  | usedNormalExitFallback hnormal =>
      simpa [GoalAdmissible, ExitGoalAdmissible] using
        Or.inr (Or.inl hnormal)
  | usedConditionalExitFallback hcondExit hready =>
      simpa [GoalAdmissible, ExitGoalAdmissible] using
        Or.inr (Or.inr (Or.inr ⟨hcondExit, hready⟩))
  | usedLockedExitFallback hlocked hkeys =>
      simpa [GoalAdmissible, ExitGoalAdmissible] using
        Or.inr (Or.inr (Or.inl ⟨hlocked, hkeys⟩))
  | explore hwalk =>
      simpa [GoalAdmissible] using hwalk
  | wait =>
      simp [GoalAdmissible]

/-!
【带合法性证明的规则目标】
具体选择器只从该子类型返回目标，因此合法性不是调用者提供的假设。
-/
abbrev VerifiedRuleGoal (s : SymbolicState) (m : AgentMemory) :=
  { goal : Goal // GoalAdmissible s m goal }

instance adjacent_decidable (first second : Position) :
    Decidable (adjacent first second) := by
  unfold adjacent manhattan absDiff
  infer_instance

instance inFront_decidable (s : SymbolicState) (position : Position) :
    Decidable (inFront s position) := by
  unfold inFront facingTarget
  infer_instance

instance exitCondition_decidable (s : SymbolicState) (exit : Exit) :
    Decidable (exitCondition s exit) := by
  unfold exitCondition
  split <;> infer_instance

instance canOpenChestObject_decidable (s : SymbolicState) (chest : Chest) :
    Decidable (canOpenChestObject s chest) := by
  unfold canOpenChestObject
  infer_instance


instance canUseExitObject_decidable (s : SymbolicState) (exit : Exit) :
    Decidable (canUseExitObject s exit) := by
  unfold canUseExitObject
  infer_instance
instance healthSafe_decidable (s : SymbolicState) :
    Decidable (healthSafe s) := by
  unfold healthSafe
  cases s.health <;> infer_instance

instance conditionalDoorReady_decidable (s : SymbolicState) :
    Decidable (conditionalDoorReady s) := by
  unfold conditionalDoorReady visibleButtonsSatisfied
  infer_instance

instance exitGoalAdmissible_decidable (s : SymbolicState) (position : Position) :
    Decidable (ExitGoalAdmissible s position) := by
  unfold ExitGoalAdmissible
  infer_instance
instance goalAdmissible_decidable
    (s : SymbolicState) (m : AgentMemory) (goal : Goal) :
    Decidable (GoalAdmissible s m goal) := by
  unfold GoalAdmissible
  split <;> infer_instance

def firstAdmissibleGoal
    (s : SymbolicState) (m : AgentMemory) :
    List Goal → Option (VerifiedRuleGoal s m)
  | [] => none
  | goal :: rest =>
      if h : GoalAdmissible s m goal then
        some ⟨goal, h⟩
      else
        firstAdmissibleGoal s m rest

/-!
【当前房间候选对象】
公共参考状态会保留多房间结构化对象；选择器只把 `room` 等于当前房间的
对象送入优先链，与 Python 每帧只接收当前房间感知结果的行为一致。
-/
def currentRoomChestPositions (s : SymbolicState) : List Position :=
  s.chestObjects.filterMap fun chest =>
    if chest.room = s.room ∧ chest.pos ∈ s.chests ∧
        (chest.completesTask = false ∨ s.monsters = []) then
      some chest.pos
    else
      none

def currentRoomMonsterPositions (s : SymbolicState) : List Position :=
  s.monsterObjects.filterMap fun monster =>
    if monster.room = s.room ∧ monster.pos ∈ s.monsters then
      some monster.pos
    else
      none

def currentRoomExitObjects (s : SymbolicState) : List Exit :=
  s.exitObjects.filter fun exit => decide (exit.sourceRoom = s.room)

def currentRoomExitPositions (s : SymbolicState) : List Position :=
  ((currentRoomExitObjects s).map fun exit => exit.pos).eraseDups

def currentRoomButtonPositions (s : SymbolicState) : List Position :=
  s.buttons.filter fun position => decide (buttonVisibleAt s position)

def currentRoomSwitchPositions (s : SymbolicState) : List Position :=
  s.switches.filter fun position => decide (switchVisibleAt s position)

def goalsAt (kind : GoalKind) (positions : List Position) : List Goal :=
  positions.map fun position => { kind := kind, target := some position }

def reachableInteractionPositions
    (s : SymbolicState) (positions : List Position) : List Position :=
  positions.filter fun position =>
    policyCanReachAny s (policyApproachTiles position)

def reachableTilePositions
    (s : SymbolicState) (positions : List Position) : List Position :=
  positions.filter fun position => policyCanReachAny s [position]

def unusedExitPositions
    (s : SymbolicState) (m : AgentMemory)
    (positions : List Position) : List Position :=
  positions.filter fun position =>
    decide (globalize s.room position ∉ m.usedExits)

def policyExitCondition (s : SymbolicState) (exit : Exit) : Bool :=
  match exit.kind with
  | ExitKind.normal => true
  | ExitKind.lockedKey need _consume => decide (need ≤ s.keys)
  | ExitKind.allMonstersAndKey need _consume =>
      decide (need ≤ s.keys ∧ s.monsters = [])
  | ExitKind.buttonGate button => decide (button ∈ s.pressedButtons)
  | ExitKind.itemGate item => decide (item ∈ s.items)

def readyExitPositions
    (s : SymbolicState) (positions : List Position) : List Position :=
  positions.filter fun position =>
    (currentRoomExitObjects s).any fun exit =>
      decide (exit.pos = position) && policyExitCondition s exit



/-!
【各优先级候选】
这些函数与 Python `choose_goal` 中的候选集合一一对应。目标排序沿用
`exitObjects/chestObjects/monsterObjects` 的确定顺序；每类候选再由
`firstAdmissibleGoal` 检查钥匙、血量、按钮记忆和冷却等条件。
-/
def chestChoice (s : SymbolicState) (m : AgentMemory) :
    Option (VerifiedRuleGoal s m) :=
  firstAdmissibleGoal s m <|
    goalsAt GoalKind.openChest <|
      reachableInteractionPositions s (currentRoomChestPositions s)

def monsterChoice (s : SymbolicState) (m : AgentMemory) :
    Option (VerifiedRuleGoal s m) :=
  firstAdmissibleGoal s m <|
    goalsAt GoalKind.attackMonster <|
      reachableInteractionPositions s (currentRoomMonsterPositions s)

def conditionalExitPositions (s : SymbolicState) : List Position :=
  ((currentRoomExitObjects s).filterMap fun exit =>
    match exit.kind with
    | ExitKind.allMonstersAndKey _ _ => some exit.pos
    | ExitKind.buttonGate _ => some exit.pos
    | ExitKind.itemGate _ => some exit.pos
    | _ => none).eraseDups

def lockedExitPositions (s : SymbolicState) : List Position :=
  ((currentRoomExitObjects s).filterMap fun exit =>
    match exit.kind with
    | ExitKind.lockedKey _ _ => some exit.pos
    | _ => none).eraseDups

def normalExitPositions (s : SymbolicState) : List Position :=
  ((currentRoomExitObjects s).filterMap fun exit =>
    match exit.kind with
    | ExitKind.normal => some exit.pos
    | _ => none).eraseDups

/-!
【机关遮蔽的出口】
参考关卡把“按开关”和随后穿门压缩在同一符号位置。Python 感知在开关尚未
触发时把该 tile 识别为开关，而不会同时把底层出口送入 `choose_goal`。
这里利用跨房间开关记忆表达同一可见性规则；触发后出口才进入候选集合。
-/
def exitVisibleToSelector
    (s : SymbolicState) (m : AgentMemory) (position : Position) : Bool :=
  decide (position ∉ currentRoomSwitchPositions s ∨
    globalize s.room position ∈ m.activatedSwitches)

def selectorVisibleExitPositions
    (s : SymbolicState) (m : AgentMemory) (positions : List Position) :
    List Position :=
  positions.filter (exitVisibleToSelector s m)

def buttonChoice (s : SymbolicState) (m : AgentMemory) :
    Option (VerifiedRuleGoal s m) :=
  if conditionalExitPositions s = [] then
    none
  else
    firstAdmissibleGoal s m <|
      goalsAt GoalKind.activateButton <|
        reachableTilePositions s (currentRoomButtonPositions s)

def conditionalMonsterChoice (s : SymbolicState) (m : AgentMemory) :
    Option (VerifiedRuleGoal s m) :=
  if conditionalExitPositions s ≠ [] ∧ currentRoomButtonPositions s = [] then
    monsterChoice s m
  else
    none

def requiredMonsterChoice (s : SymbolicState) (m : AgentMemory) :
    Option (VerifiedRuleGoal s m) :=
  if currentRoomChestPositions s = [] ∧
      currentRoomButtonPositions s = [] ∧
      currentRoomSwitchPositions s = [] ∧
      unusedExitPositions s m (currentRoomExitPositions s) = [] then
    monsterChoice s m
  else
    none

def conditionalExitChoice
    (s : SymbolicState) (m : AgentMemory) (onlyUnused : Bool) :
    Option (VerifiedRuleGoal s m) :=
  let positions := readyExitPositions s <|
    selectorVisibleExitPositions s m (conditionalExitPositions s)
  let candidates :=
    if onlyUnused then unusedExitPositions s m positions else positions
  firstAdmissibleGoal s m <|
    goalsAt GoalKind.goToExit (reachableTilePositions s candidates)

def lockedExitChoice
    (s : SymbolicState) (m : AgentMemory) (onlyUnused : Bool) :
    Option (VerifiedRuleGoal s m) :=
  let positions := readyExitPositions s <|
    selectorVisibleExitPositions s m (lockedExitPositions s)
  let candidates :=
    if onlyUnused then unusedExitPositions s m positions else positions
  firstAdmissibleGoal s m <|
    goalsAt GoalKind.goToExit (reachableTilePositions s candidates)

def normalExitChoice
    (s : SymbolicState) (m : AgentMemory) (onlyUnused : Bool) :
    Option (VerifiedRuleGoal s m) :=
  let positions := readyExitPositions s <|
    selectorVisibleExitPositions s m (normalExitPositions s)
  let candidates :=
    if onlyUnused then unusedExitPositions s m positions else positions
  firstAdmissibleGoal s m <|
    goalsAt GoalKind.goToExit (reachableTilePositions s candidates)



def switchChoice (s : SymbolicState) (m : AgentMemory) :
    Option (VerifiedRuleGoal s m) :=
  firstAdmissibleGoal s m <|
    goalsAt GoalKind.activateSwitch <|
      reachableInteractionPositions s (currentRoomSwitchPositions s)

def exploreChoice (s : SymbolicState) (m : AgentMemory) :
    Option (VerifiedRuleGoal s m) :=
  firstAdmissibleGoal s m <|
    goalsAt GoalKind.explore <|
      movementActions.filterMap fun action =>
        let target := nextPosition s.player action
        if isWalkable s target then some target else none

/-!
【sticky goal 的具体判定】
房间切换会在记忆更新中清空 `lastGoal`；同一房间内则只在对象仍属于当前
感知、目标仍合法且按钮尚未踩中时继续上一目标。
-/
def goalStillVisible (s : SymbolicState) (goal : Goal) : Bool :=
  match goal.kind, goal.target with
  | GoalKind.openChest, some position =>
      decide (position ∈ currentRoomChestPositions s)
  | GoalKind.attackMonster, some position =>
      decide (position ∈ currentRoomMonsterPositions s)
  | GoalKind.activateButton, some position =>
      decide (position ∈ currentRoomButtonPositions s ∧
        position ≠ s.player ∧ position ∉ s.pressedButtons)
  | GoalKind.activateSwitch, some position =>
      decide (position ∈ currentRoomSwitchPositions s)
  | GoalKind.goToExit, some position =>
      decide (position ∈ currentRoomExitPositions s)
  | GoalKind.explore, some position =>
      decide (isWalkable s position ∧ position ≠ s.player)
  | _, _ => false

def continuingGoalChoice (s : SymbolicState) (m : AgentMemory) :
    Option (VerifiedRuleGoal s m) :=
  match m.lastGoal with
  | none => none
  | some goal =>
      if goalStillVisible s goal then
        firstAdmissibleGoal s m [goal]
      else
        none

/-!
【无 sticky 时的具体十二级优先链】
分支顺序对应 Python `RuleBasedPolicy.choose_goal`：宝箱、必要清怪、条件门
按钮/怪物/新出口、新锁门、新普通门、开关、普通门回退、条件门回退、
锁门回退、探索和等待。
-/
def chooseNewVerifiedRuleGoal
    (s : SymbolicState) (m : AgentMemory) : VerifiedRuleGoal s m :=
  match chestChoice s m with
  | some goal => goal
  | none =>
    match requiredMonsterChoice s m with
    | some goal => goal
    | none =>
      match buttonChoice s m with
      | some goal => goal
      | none =>
        match conditionalMonsterChoice s m with
        | some goal => goal
        | none =>
          match conditionalExitChoice s m true with
          | some goal => goal
          | none =>
            match lockedExitChoice s m true with
            | some goal => goal
            | none =>
              match normalExitChoice s m true with
              | some goal => goal
              | none =>
                match switchChoice s m with
                | some goal => goal
                | none =>
                  match normalExitChoice s m false with
                  | some goal => goal
                  | none =>
                    match conditionalExitChoice s m false with
                    | some goal => goal
                    | none =>
                      match lockedExitChoice s m false with
                      | some goal => goal
                      | none =>
                        match exploreChoice s m with
                        | some goal => goal
                        | none =>
                          ⟨{ kind := GoalKind.wait, target := none }, by
                            simp [GoalAdmissible]⟩

def chooseVerifiedRuleGoal
    (s : SymbolicState) (m : AgentMemory) : VerifiedRuleGoal s m :=
  match continuingGoalChoice s m with
  | some goal => goal
  | none => chooseNewVerifiedRuleGoal s m

abbrev RuleSelector := SymbolicState → AgentMemory → Goal

/-!
【Python 规则选择器的 Lean 实现】
该函数不是契约参数，而是可执行的具体选择器。
-/
def ruleBasedChooseGoal : RuleSelector := fun state memory =>
  (chooseVerifiedRuleGoal state memory).1

/-!
【实际选择器输出合法】
合法性直接来自 `chooseVerifiedRuleGoal` 携带的证明。
-/
theorem ruleBasedChooseGoal_admissible
    (s : SymbolicState) (m : AgentMemory) :
    GoalAdmissible s m (ruleBasedChooseGoal s m) :=
  (chooseVerifiedRuleGoal s m).2

/-!
【具体优先级契约】
契约同时要求实现就是 `ruleBasedChooseGoal`、输出合法，并精确规定 sticky
分支和重新规划分支。因而不能再用一个未实例化的任意 selector 代替实际策略。
-/
structure RulePriorityContract (selector : RuleSelector) : Prop where
  implementation : selector = ruleBasedChooseGoal
  admissible : ∀ s m, GoalAdmissible s m (selector s m)
  stickyFirst : ∀ s m goal,
    continuingGoalChoice s m = some goal → selector s m = goal.1
  restartPriority : ∀ s m,
    continuingGoalChoice s m = none →
      selector s m = (chooseNewVerifiedRuleGoal s m).1

theorem ruleBasedChooseGoal_priorityContract :
    RulePriorityContract ruleBasedChooseGoal := by
  refine
    { implementation := rfl
      admissible := ruleBasedChooseGoal_admissible
      stickyFirst := ?_
      restartPriority := ?_ }
  · intro s m goal hgoal
    simp [ruleBasedChooseGoal, chooseVerifiedRuleGoal, hgoal]
  · intro s m hnone
    simp [ruleBasedChooseGoal, chooseVerifiedRuleGoal, hnone]

/-!
【定理：无 sticky 时宝箱分支严格优先】
-/
theorem concrete_selector_chest_first
    {s : SymbolicState} {m : AgentMemory}
    (hsticky : continuingGoalChoice s m = none)
    {goal : VerifiedRuleGoal s m}
    (hchest : chestChoice s m = some goal) :
    ruleBasedChooseGoal s m = goal.1 := by
  simp [ruleBasedChooseGoal, chooseVerifiedRuleGoal, hsticky,
    chooseNewVerifiedRuleGoal, hchest]

/-!
【定理：前三类均不可用时，条件门按钮分支优先】
-/
theorem concrete_selector_conditional_button_first
    {s : SymbolicState} {m : AgentMemory}
    (hsticky : continuingGoalChoice s m = none)
    (hchest : chestChoice s m = none)
    (hrequired : requiredMonsterChoice s m = none)
    {goal : VerifiedRuleGoal s m}
    (hbutton : buttonChoice s m = some goal) :
    ruleBasedChooseGoal s m = goal.1 := by
  simp [ruleBasedChooseGoal, chooseVerifiedRuleGoal, hsticky,
    chooseNewVerifiedRuleGoal, hchest, hrequired, hbutton]

/-!
【定理：具体选择器确实满足优先级契约】
该名称保留通用接口风格，但证明参数已由实际实现构造。
-/
theorem priority_selector_goal_admissible
    (s : SymbolicState) (m : AgentMemory) :
    GoalAdmissible s m (ruleBasedChooseGoal s m) :=
  ruleBasedChooseGoal_priorityContract.admissible s m
/-!
【紧急战斗反射】
最终 `agent.py` 会在普通规划前处理中断队列：面向相邻怪物时攻击，有盾时格挡，
低血量撤退时只允许走向安全 tile。该关系把三种可验证输出独立于高层优先链建模。
-/
inductive CombatReflex : SymbolicState → Action → Prop where
  | attack
      {s : SymbolicState} {monster : Position} :
      monster ∈ s.monsters →
      adjacent s.player monster →
      s.hasSword = true →
      healthSafe s →
      CombatReflex s Action.pressA
  | block
      {s : SymbolicState} {monster : Monster} :
      monsterThreatens s monster →
      (s.hasShield = true ∨ hasItem s Item.shield) →
      CombatReflex s Action.pressB
  | retreat
      {s : SymbolicState} {action : Action} :
      action ∈ movementActions →
      isWalkable s (nextPosition s.player action) →
      CombatReflex s action

/-!
【目标邻接格】
`approachTiles p` 给出与目标 `p` 相邻的四个 tile。
开箱、攻击怪物和激活机关都需要先走到这些邻接格之一。
-/
def approachTiles (p : Position) : List Position :=
  [
    nextPosition p Action.up,
    nextPosition p Action.down,
    nextPosition p Action.left,
    nextPosition p Action.right
  ]

/-!
【BFS 第一步契约】
`PlannerStep s goals a` 表示 BFS/planner 在状态 `s` 中，
为了到达某个目标格集合 `goals`，输出第一步动作 `a`。
该关系直接把“第一步必须是安全移动”写成证明前提。
-/
inductive PlannerStep (s : SymbolicState) (goals : List Position) : Action → Prop where
  | step
      {a : Action} {first : Position} :
      a ∈ movementActions →
      nextPosition s.player a = first →
      first ∈ goals →
      isWalkable s first →
      PlannerStep s goals a

/-!
【定理：planner 输出的第一步是安全移动】
如果 `PlannerStep` 输出动作 `a`，那么 `a` 是移动动作，
且目标 tile 满足 `isWalkable`。
-/
theorem planner_step_safe
    {s : SymbolicState} {goals : List Position} {a : Action}
    (h : PlannerStep s goals a) :
    a ∈ movementActions ∧ isWalkable s (nextPosition s.player a) := by
  cases h with
  | step hmove hnext _hgoal hwalk =>
      constructor
      · exact hmove
      · simpa [hnext] using hwalk

/-!
【planner frontier 完备性】
`PlannerFrontierComplete s n frontier` 表示搜索 frontier 已覆盖所有
`n` 步内安全可达的位置。
-/
def PlannerFrontierComplete
    (s : SymbolicState) (n : Nat) (frontier : List Position) : Prop :=
  ∀ p, PositionReachable s n p → p ∈ frontier

/-!
【目标位置有界可达】
`PlannerGoalReachable s n goals` 表示目标集合 `goals` 中至少有一个位置
在 `n` 步内安全可达。
-/
def PlannerGoalReachable
    (s : SymbolicState) (n : Nat) (goals : List Position) : Prop :=
  ∃ p, PositionReachable s n p ∧ p ∈ goals

/-!
【planner 找到目标】
`PlannerFindsGoal frontier goals` 表示 frontier 中已经出现目标位置。
-/
def PlannerFindsGoal
    (frontier : List Position) (goals : List Position) : Prop :=
  ∃ p, p ∈ frontier ∧ p ∈ goals

/-!
【定理：planner frontier 完备性推出可达目标会被发现】
这是搜索完备性的抽象形式：
如果 BFS/frontier 覆盖了所有 `n` 步内安全可达位置，
且某个目标位置在 `n` 步内可达，则 frontier 中一定存在目标。
-/
theorem planner_completeness_from_frontier_invariant
    {s : SymbolicState} {n : Nat}
    {frontier goals : List Position}
    (hcomplete : PlannerFrontierComplete s n frontier)
    (hreachable : PlannerGoalReachable s n goals) :
    PlannerFindsGoal frontier goals := by
  rcases hreachable with ⟨p, hreach, hgoal⟩
  exact ⟨p, hcomplete p hreach, hgoal⟩

/-!
【定理：单目标可达时完备 frontier 会发现它】
这是上一条完备性定理的单目标版本：
如果目标 `target` 在 `n` 步内安全可达，并且 BFS frontier 覆盖所有
`n` 步安全可达位置，那么 frontier 中一定包含该目标。
-/
theorem planner_finds_singleton_of_reachable
    {s : SymbolicState} {n : Nat}
    {frontier : List Position} {target : Position}
    (hcomplete : PlannerFrontierComplete s n frontier)
    (hreachable : PositionReachable s n target) :
    PlannerFindsGoal frontier [target] := by
  exact planner_completeness_from_frontier_invariant
    hcomplete
    ⟨target, hreachable, by simp⟩

/-!
【出口推动作】
`exitPushAction target` 对应 `executor.py` 中 `_exit_push_action`：
如果玩家已经站在边界出口 tile 上，就继续朝门外方向移动。
-/
def exitPushAction (target : Position) : Action :=
  if target.2 = 0 then Action.up
  else if target.2 = 7 then Action.down
  else if target.1 = 0 then Action.left
  else if target.1 = 9 then Action.right
  else Action.wait

/-!
【推出房间谓词】
`pushesOut p a` 表示从位置 `p` 执行动作 `a` 会离开当前房间边界。
这用于证明出口动作不是普通越界，而是合法换房。
-/
def pushesOut (p : Position) (a : Action) : Prop :=
  a ∈ movementActions ∧ ¬ inBounds (nextPosition p a)

/-!
【相邻按 A 目标谓词】
`interactionKind k` 表示目标类型需要相邻后按 A 完成：
开箱和攻击怪物属于这一类。
Python 实现中按钮是踩上去自动触发，开关才是相邻按 A，
所以 `activateSwitch` 不再放在这里统一处理。
-/
def interactionKind (k : GoalKind) : Prop :=
  k = GoalKind.openChest ∨
  k = GoalKind.attackMonster

/-!
【动作允许谓词】
`ActionAllowed s a` 是 action mask 的规格：
非移动交互动作允许；移动动作只有在合法出门或走向安全可通行格时允许。
-/
def ActionAllowed (s : SymbolicState) (a : Action) : Prop :=
  a = Action.wait ∨
  a = Action.pressA ∨
  a = Action.pressB ∨
  a = Action.useExit ∨
  exitPushAllowed s a ∨
  (a ∈ movementActions ∧ isWalkable s (nextPosition s.player a))

/-!
【定理：紧急战斗反射输出满足动作安全约束】
-/
theorem combat_reflex_action_allowed
    {s : SymbolicState} {action : Action}
    (h : CombatReflex s action) :
    ActionAllowed s action := by
  cases h with
  | attack _hmonster _hadj _hsword _hhealth =>
      exact Or.inr (Or.inl rfl)
  | block _hthreat _hshield =>
      exact Or.inr (Or.inr (Or.inl rfl))
  | retreat hmove hwalk =>
      exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr ⟨hmove, hwalk⟩))))
/-!
【目标到动作的执行器关系】
`ActionForGoal s g a` 对应 `executor.py` 的 `action_for_goal`：
* 等待目标输出等待；
* 开箱/攻击目标相邻时按 A，否则走向邻接格；
* 按钮目标走到按钮格，已经在按钮上则等待；
* 开关目标相邻时按 A，否则走向邻接格；
* 出口目标在门上时推出房间，否则走向出口；
* 探索目标走向目标格；
* 没有计划时等待。
-/
inductive ActionForGoal : SymbolicState → Goal → Action → Prop where
  | waitGoal
      {s : SymbolicState} :
      ActionForGoal s { kind := GoalKind.wait, target := none } Action.wait
  | interactAdjacent
      {s : SymbolicState} {k : GoalKind} {p : Position} :
      interactionKind k →
      adjacent s.player p →
      ActionForGoal s { kind := k, target := some p } Action.pressA
  | interactPlan
      {s : SymbolicState} {k : GoalKind} {p : Position} {a : Action} :
      interactionKind k →
      PlannerStep s (approachTiles p) a →
      ActionForGoal s { kind := k, target := some p } a
  | buttonAlreadyOn
      {s : SymbolicState} {p : Position} :
      p ∈ s.buttons →
      s.player = p →
      ActionForGoal s { kind := GoalKind.activateButton, target := some p }
        Action.wait
  | buttonPlan
      {s : SymbolicState} {p : Position} {a : Action} :
      p ∈ s.buttons →
      PlannerStep s [p] a →
      ActionForGoal s { kind := GoalKind.activateButton, target := some p } a
  | switchOn
      {s : SymbolicState} {p : Position} :
      switchVisibleAt s p →
      s.player = p →
      ActionForGoal s { kind := GoalKind.activateSwitch, target := some p }
        Action.pressA
  | switchAdjacent
      {s : SymbolicState} {p : Position} :
      p ∈ s.switches →
      adjacent s.player p →
      ActionForGoal s { kind := GoalKind.activateSwitch, target := some p }
        Action.pressA
  | switchPlan
      {s : SymbolicState} {p : Position} {a : Action} :
      p ∈ s.switches →
      PlannerStep s (approachTiles p) a →
      ActionForGoal s { kind := GoalKind.activateSwitch, target := some p } a
  | structuredExit
      {s : SymbolicState} {exit : Exit} :
      canUseExitObject s exit →
      ActionForGoal s
        { kind := GoalKind.goToExit, target := some exit.pos }
        Action.useExit
  | exitPush
      {s : SymbolicState} {p : Position} :
      p ∈ allExits s →
      s.player = p →
      isDoorExit p →
      pushesOut p (exitPushAction p) →
      ActionForGoal s { kind := GoalKind.goToExit, target := some p }
        (exitPushAction p)
  | exitPlan
      {s : SymbolicState} {p : Position} {a : Action} :
      p ∈ allExits s →
      PlannerStep s [p] a →
      ActionForGoal s { kind := GoalKind.goToExit, target := some p } a
  | explorePlan
      {s : SymbolicState} {p : Position} {a : Action} :
      PlannerStep s [p] a →
      ActionForGoal s { kind := GoalKind.explore, target := some p } a
  | noPlan
      {s : SymbolicState} {g : Goal} :
      ActionForGoal s g Action.wait

/-!
【按钮目标不会输出 A 键】
按钮由进入目标格自动触发，因此执行器处理按钮目标时只能输出安全移动或等待，
不会在到达后额外执行 `pressA`。
-/
theorem button_action_for_goal_ne_pressA
    {s : SymbolicState} {position : Position} {action : Action}
    (execution : ActionForGoal s
      { kind := GoalKind.activateButton, target := some position } action) :
    action ≠ Action.pressA := by
  intro hpress
  subst action
  cases execution with
  | interactAdjacent hkind _hadjacent =>
      simp [interactionKind] at hkind
  | interactPlan hkind _plan =>
      simp [interactionKind] at hkind
  | buttonPlan _hbutton plan =>
      have hmove := (planner_step_safe plan).1
      simp [movementActions] at hmove

/-!
【定理：executor 输出的移动动作安全或合法出门】
如果 `ActionForGoal` 输出的是移动动作，那么这个移动要么是合法出门，
要么走向 `isWalkable` 的安全格。
-/
theorem action_for_goal_move_safe_or_exit
    {s : SymbolicState} {g : Goal} {a : Action}
    (h : ActionForGoal s g a)
    (ha : a ∈ movementActions) :
    exitPushAllowed s a ∨ isWalkable s (nextPosition s.player a) := by
  cases h with
  | waitGoal =>
      simp [movementActions] at ha
  | interactAdjacent _hkind _hadj =>
      simp [movementActions] at ha
  | interactPlan _hkind hplan =>
      exact Or.inr (planner_step_safe hplan).2
  | buttonAlreadyOn _hbutton _hplayer =>
      simp [movementActions] at ha
  | buttonPlan _hbutton hplan =>
      exact Or.inr (planner_step_safe hplan).2
  | switchOn _hvisible _hplayer =>
      simp [movementActions] at ha
  | switchAdjacent _hswitch _hadj =>
      simp [movementActions] at ha
  | switchPlan _hswitch hplan =>
      exact Or.inr (planner_step_safe hplan).2
  | structuredExit _husable =>
      simp [movementActions] at ha
  | exitPush hexit hplayer hdoor hpush =>
      rcases hpush with ⟨hmove, hout⟩
      exact Or.inl ⟨hmove, by simpa [hplayer] using hexit,
        by simpa [hplayer] using hdoor,
        by simpa [hplayer] using hout⟩
  | exitPlan _hexit hplan =>
      exact Or.inr (planner_step_safe hplan).2
  | explorePlan hplan =>
      exact Or.inr (planner_step_safe hplan).2
  | noPlan =>
      simp [movementActions] at ha
/-!
【定理：executor 输出满足 action mask】
`ActionForGoal` 产生的动作一定满足 `ActionAllowed`：
等待和交互直接允许，移动动作必须安全或合法出门。
-/
theorem action_for_goal_allowed
    {s : SymbolicState} {g : Goal} {a : Action}
    (h : ActionForGoal s g a) :
    ActionAllowed s a := by
  cases h with
  | waitGoal =>
      exact Or.inl rfl
  | interactAdjacent _hkind _hadj =>
      exact Or.inr (Or.inl rfl)
  | interactPlan _hkind hplan =>
      have hs := planner_step_safe hplan
      exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr hs))))
  | buttonAlreadyOn _hbutton _hplayer =>
      exact Or.inl rfl
  | buttonPlan _hbutton hplan =>
      have hs := planner_step_safe hplan
      exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr hs))))
  | switchOn _hvisible _hplayer =>
      exact Or.inr (Or.inl rfl)
  | switchAdjacent _hswitch _hadj =>
      exact Or.inr (Or.inl rfl)
  | switchPlan _hswitch hplan =>
      have hs := planner_step_safe hplan
      exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr hs))))
  | structuredExit _husable =>
      exact Or.inr (Or.inr (Or.inr (Or.inl rfl)))
  | exitPush hexit hplayer hdoor hpush =>
      rcases hpush with ⟨hmove, hout⟩
      exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inl
        ⟨hmove, by simpa [hplayer] using hexit,
          by simpa [hplayer] using hdoor,
          by simpa [hplayer] using hout⟩))))
  | exitPlan _hexit hplan =>
      have hs := planner_step_safe hplan
      exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr hs))))
  | explorePlan hplan =>
      have hs := planner_step_safe hplan
      exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr hs))))
  | noPlan =>
      exact Or.inl rfl
/-!
【最终安全过滤关系】
`Shielded s raw out` 对应 `shield.py`：
* 非移动动作直接放行；
* 合法出门动作放行；
* 不安全移动改成等待；
* 安全移动放行。
-/
inductive Shielded : SymbolicState → Action → Action → Prop where
  | passWait
      {s : SymbolicState} :
      Shielded s Action.wait Action.wait
  | passA
      {s : SymbolicState} :
      Shielded s Action.pressA Action.pressA
  | passB
      {s : SymbolicState} :
      Shielded s Action.pressB Action.pressB
  | passUseExit
      {s : SymbolicState} :
      Shielded s Action.useExit Action.useExit
  | allowExit
      {s : SymbolicState} {a : Action} :
      exitPushAllowed s a →
      Shielded s a a
  | blockUnsafe
      {s : SymbolicState} {a : Action} :
      a ∈ movementActions →
      ¬ exitPushAllowed s a →
      ¬ isWalkable s (nextPosition s.player a) →
      Shielded s a Action.wait
  | allowSafe
      {s : SymbolicState} {a : Action} :
      a ∈ movementActions →
      isWalkable s (nextPosition s.player a) →
      Shielded s a a

/-!
【定理：shield 输出移动动作时必安全或合法出门】
经过 shield 后，如果最终输出仍然是移动动作，
那么它要么满足 `exitPushAllowed`，要么目标格 `isWalkable`。
-/
theorem shielded_move_safe_or_exit
    {s : SymbolicState} {raw out : Action}
    (h : Shielded s raw out)
    (hout : out ∈ movementActions) :
    exitPushAllowed s out ∨ isWalkable s (nextPosition s.player out) := by
  cases h with
  | passWait =>
      simp [movementActions] at hout
  | passA =>
      simp [movementActions] at hout
  | passB =>
      simp [movementActions] at hout
  | passUseExit =>
      simp [movementActions] at hout
  | allowExit hexit =>
      exact Or.inl hexit
  | blockUnsafe _hmove _hnotExit _hunsafe =>
      simp [movementActions] at hout
  | allowSafe _hmove hsafe =>
      exact Or.inr hsafe
/-!
【定理：shield 输出满足 action mask】
无论原始动作是什么，只要 `Shielded s raw out` 成立，
输出动作 `out` 一定满足 `ActionAllowed`。
-/
theorem shielded_output_allowed
    {s : SymbolicState} {raw out : Action}
    (h : Shielded s raw out) :
    ActionAllowed s out := by
  cases h with
  | passWait =>
      exact Or.inl rfl
  | passA =>
      exact Or.inr (Or.inl rfl)
  | passB =>
      exact Or.inr (Or.inr (Or.inl rfl))
  | passUseExit =>
      exact Or.inr (Or.inr (Or.inr (Or.inl rfl)))
  | allowExit hexit =>
      exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inl hexit))))
  | blockUnsafe _hmove _hnotExit _hunsafe =>
      exact Or.inl rfl
  | allowSafe hmove hsafe =>
      exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr
        ⟨hmove, hsafe⟩))))
/-!
【定理：不安全移动会被 shield 改成等待】
如果原始动作是移动动作，但既不是合法出门，也不是安全可通行移动，
那么符合 `Shielded` 关系的输出只能是 `wait`。
-/
theorem shield_blocks_unsafe_movement
    {s : SymbolicState} {raw out : Action}
    (hshield : Shielded s raw out)
    (hmove : raw ∈ movementActions)
    (hnotExit : ¬ exitPushAllowed s raw)
    (hunsafe : ¬ isWalkable s (nextPosition s.player raw)) :
    out = Action.wait := by
  cases hshield with
  | passWait =>
      rfl
  | passA =>
      cases hmove <;> contradiction
  | passB =>
      cases hmove <;> contradiction
  | passUseExit =>
      cases hmove <;> contradiction
  | allowExit hexit =>
      exact False.elim (hnotExit hexit)
  | blockUnsafe _ _ _ =>
      rfl
  | allowSafe _ hsafe =>
      exact False.elim (hunsafe hsafe)
/-!
【定理：规则目标经过 executor 后的原始移动安全或合法出门】
把 `RuleGoal` 和 `ActionForGoal` 串起来：
只要 executor 输出移动动作，它不会要求玩家主动进入危险格。
-/
theorem raw_rule_action_safe_or_exit
    {s : SymbolicState} {m : AgentMemory} {g : Goal} {raw : Action}
    (_hgoal : RuleGoal s m g)
    (hact : ActionForGoal s g raw)
    (hmove : raw ∈ movementActions) :
    exitPushAllowed s raw ∨ isWalkable s (nextPosition s.player raw) :=
  action_for_goal_move_safe_or_exit hact hmove

/-!
【定理：规则策略加 shield 后的最终移动安全或合法出门】
这是规则版 Agent 最重要的安全性结论：
策略选目标、executor 生成动作、shield 过滤后，如果最终动作是移动，
则它一定安全或是合法换房。
-/
theorem shielded_rule_action_safe_or_exit
    {s : SymbolicState} {m : AgentMemory} {g : Goal} {raw out : Action}
    (_hgoal : RuleGoal s m g)
    (_hact : ActionForGoal s g raw)
    (hshield : Shielded s raw out)
    (hout : out ∈ movementActions) :
    exitPushAllowed s out ∨ isWalkable s (nextPosition s.player out) :=
  shielded_move_safe_or_exit hshield hout

/-!
【定理：最终移动不会主动进入危险位置】
在上一个定理基础上进一步展开 `isWalkable`：
最终移动动作要么是合法出门，要么目标位置满足 `SafePosition`。
-/
theorem shielded_rule_action_safe_position_or_exit
    {s : SymbolicState} {m : AgentMemory} {g : Goal} {raw out : Action}
    (hgoal : RuleGoal s m g)
    (hact : ActionForGoal s g raw)
    (hshield : Shielded s raw out)
    (hout : out ∈ movementActions) :
    exitPushAllowed s out ∨ SafePosition s (nextPosition s.player out) := by
  have h := shielded_rule_action_safe_or_exit hgoal hact hshield hout
  cases h with
  | inl hexit =>
      exact Or.inl hexit
  | inr hwalk =>
      exact Or.inr (walkable_is_safe_position hwalk)

/-!
【定理：规则策略、executor、shield 串联后满足 action mask】
这是对最终动作合法性的总括证明：
高层规则目标、目标到动作、最终 shield 串起来后，输出动作满足 `ActionAllowed`。
-/
theorem rule_pipeline_output_allowed
    {s : SymbolicState} {m : AgentMemory} {g : Goal} {raw out : Action}
    (_hgoal : RuleGoal s m g)
    (_hact : ActionForGoal s g raw)
    (hshield : Shielded s raw out) :
    ActionAllowed s out :=
  shielded_output_allowed hshield

/-!
【记忆集合插入】
只在元素尚未出现时插入，保持 Python `set` 字段的幂等语义。
-/
def rememberGlobal
    (position : GlobalPosition) (positions : List GlobalPosition) :
    List GlobalPosition :=
  if position ∈ positions then positions else position :: positions

def openedChestsAfter
    (before after : SymbolicState) (selected : Option Goal)
    (memory : AgentMemory) : List GlobalPosition :=
  match selected with
  | some goal =>
      match goal.kind, goal.target with
      | GoalKind.openChest, some position =>
          if position ∉ after.chests then
            rememberGlobal (globalize before.room position)
              memory.openedChests
          else
            memory.openedChests
      | _, _ => memory.openedChests
  | none => memory.openedChests

def activatedSwitchesAfter
    (before after : SymbolicState) (selected : Option Goal)
    (memory : AgentMemory) : List GlobalPosition :=
  match selected with
  | some goal =>
      match goal.kind, goal.target with
      | GoalKind.activateSwitch, some position =>
          if before.switchesActivated < after.switchesActivated then
            rememberGlobal (globalize before.room position)
              memory.activatedSwitches
          else
            memory.activatedSwitches
      | _, _ => memory.activatedSwitches
  | none => memory.activatedSwitches

def visitActivatedSwitchesAfter
    (before after : SymbolicState) (selected : Option Goal)
    (memory : AgentMemory) : List GlobalPosition :=
  match selected with
  | some goal =>
      match goal.kind, goal.target with
      | GoalKind.activateSwitch, some position =>
          if before.switchesActivated < after.switchesActivated then
            rememberGlobal (globalize before.room position)
              memory.visitActivatedSwitches
          else
            memory.visitActivatedSwitches
      | _, _ => memory.visitActivatedSwitches
  | none => memory.visitActivatedSwitches

def activatedButtonsAfter
    (after : SymbolicState) (memory : AgentMemory) :
    List GlobalPosition :=
  if buttonVisibleAt after after.player ∧
      after.player ∈ after.pressedButtons then
    rememberGlobal (globalize after.room after.player)
      memory.activatedButtons
  else
    memory.activatedButtons

def usedExitsAfter
    (before after : SymbolicState) (selected : Option Goal)
    (memory : AgentMemory) : List GlobalPosition :=
  if before.room = after.room then
    memory.usedExits
  else
    match selected with
    | some goal =>
        match goal.kind, goal.target with
        | GoalKind.goToExit, some position =>
            rememberGlobal (globalize before.room position)
              memory.usedExits
        | _, _ => memory.usedExits
    | none => memory.usedExits

/-!
【AgentMemory 的确定更新】
房间变化时清除 sticky goal 和本次访问开关集合；自动按钮依据转移后的
`pressedButtons` 更新，其余对象依据已执行目标和环境差分更新。
-/
def updateRuleMemory
    (before : SymbolicState) (memory : AgentMemory)
    (selected : Option Goal) (after : SymbolicState) : AgentMemory :=
  { lastGoal :=
      if before.room = after.room then
        match selected with
        | some goal => some goal
        | none => memory.lastGoal
      else
        none
    openedChests := openedChestsAfter before after selected memory
    activatedButtons := activatedButtonsAfter after memory
    activatedSwitches :=
      activatedSwitchesAfter before after selected memory
    visitActivatedSwitches :=
      if before.room = after.room then
        visitActivatedSwitchesAfter before after selected memory
      else
        []
    usedExits := usedExitsAfter before after selected memory
    roomSteps := if before.room = after.room then memory.roomSteps + 1 else 0
    switchButtonCooldown :=
      if before.room ≠ after.room then
        0
      else if before.switchesActivated < after.switchesActivated then
        40
      else
        memory.switchButtonCooldown - 1 }

/-!
【规则 Agent 单步】
`planned` 构造子逐项串联具体 `ruleBasedChooseGoal`、executor、shield、
共享环境和记忆更新。`reflex` 对应 `agent.py` 在高层规划前执行的紧急战斗分支。
-/
inductive RulePolicyStep :
    SymbolicState → AgentMemory → Action →
      SymbolicState → AgentMemory → Prop where
  | planned
      {before after : SymbolicState} {memory nextMemory : AgentMemory}
      {goal : Goal} {raw output : Action} :
      ruleBasedChooseGoal before memory = goal →
      ActionForGoal before goal raw →
      Shielded before raw output →
      FullEnvStep before output after →
      nextMemory = updateRuleMemory before memory (some goal) after →
      RulePolicyStep before memory output after nextMemory
  | reflex
      {before after : SymbolicState} {memory nextMemory : AgentMemory}
      {raw output : Action} :
      CombatReflex before raw →
      Shielded before raw output →
      FullEnvStep before output after →
      nextMemory = updateRuleMemory before memory none after →
      RulePolicyStep before memory output after nextMemory

/-!
【规则 Agent 多步执行】
动作列表中的每一步都必须由同一个 `RulePolicyStep` 关系生成；中间状态和
中间记忆同时作为归纳索引传给下一步。
-/
inductive RulePolicyExec :
    SymbolicState → AgentMemory → List Action →
      SymbolicState → AgentMemory → Prop where
  | nil
      {state : SymbolicState} {memory : AgentMemory} :
      RulePolicyExec state memory [] state memory
  | cons
      {state next final : SymbolicState}
      {memory nextMemory finalMemory : AgentMemory}
      {action : Action} {plan : List Action} :
      RulePolicyStep state memory action next nextMemory →
      RulePolicyExec next nextMemory plan final finalMemory →
      RulePolicyExec state memory (action :: plan) final finalMemory

/-!
【定理：策略生成执行投影为共享环境执行】
-/
theorem rulePolicyExec_to_fullExec
    {state final : SymbolicState} {memory finalMemory : AgentMemory}
    {plan : List Action}
    (execution : RulePolicyExec state memory plan final finalMemory) :
    FullExec state plan final := by
  induction execution with
  | nil => exact FullExec.nil
  | cons policyStep _tail ih =>
      apply FullExec.cons
      · cases policyStep with
        | planned _selected _executor _shield environment _memory =>
            exact environment
        | reflex _reflex _shield environment _memory =>
            exact environment
      · exact ih

/-!
【规则路线强化任务证书】
除公共安全轨迹和目标外，还携带初末 AgentMemory 以及由具体规则策略生成
同一动作列表、同一最终状态的证明。
-/
structure RuleTaskCertificate
    (goal : SymbolicState → Prop) (init : SymbolicState) where
  plan : List Action
  final : SymbolicState
  execution : SafeFullExec init plan final
  completed : goal final
  initialMemory : AgentMemory
  finalMemory : AgentMemory
  generated : RulePolicyExec init initialMemory plan final finalMemory

/-!
【由具体规则策略完成任务】
`CompletedByRulePolicy goal init` 不只是断言环境中存在一条通关路线，还要求
同一动作列表和同一最终状态由 `RulePolicyExec` 生成。该命题把具体目标选择器、
executor、shield、环境转移和记忆更新与安全通关结论绑定在一起。
-/
def CompletedByRulePolicy
    (goal : SymbolicState → Prop) (init : SymbolicState) : Prop :=
  ∃ plan final initialMemory finalMemory,
    SafeFullExec init plan final ∧
    goal final ∧
    RulePolicyExec init initialMemory plan final finalMemory

def RuleTaskCertificate.toTaskCertificate
    {goal : SymbolicState → Prop} {init : SymbolicState}
    (certificate : RuleTaskCertificate goal init) :
    TaskCertificate goal init :=
  { plan := certificate.plan
    final := certificate.final
    execution := certificate.execution
    completed := certificate.completed }

theorem ruleTaskCertificate_completedBy
    {goal : SymbolicState → Prop} {init : SymbolicState}
    (certificate : RuleTaskCertificate goal init) :
    CompletedBy goal init :=
  taskCertificate_completedBy certificate.toTaskCertificate

/-!
【强化证书推出规则策略完成性】
证书中的三个核心字段使用相同的 `plan` 和 `final`，因此不能把手写环境轨迹
与另一条策略轨迹拼接后冒充策略通关证明。
-/
theorem ruleTaskCertificate_completedByRulePolicy
    {goal : SymbolicState → Prop} {init : SymbolicState}
    (certificate : RuleTaskCertificate goal init) :
    CompletedByRulePolicy goal init :=
  ⟨certificate.plan, certificate.final, certificate.initialMemory,
    certificate.finalMemory, certificate.execution, certificate.completed,
    certificate.generated⟩

/-!
【规则策略完成性可投影为环境完成性】
-/
theorem completedByRulePolicy_to_completedBy
    {goal : SymbolicState → Prop} {init : SymbolicState}
    (completed : CompletedByRulePolicy goal init) :
    CompletedBy goal init := by
  rcases completed with
    ⟨plan, final, _initialMemory, _finalMemory,
      execution, goalReached, _generated⟩
  exact ⟨plan, final, safeFullExec_to_fullExec execution, goalReached⟩
end RuleBasedSubmission.Formalization
