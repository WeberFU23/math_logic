import formalization.Environment

/-!
  `origin/rl` 分支的高层 RL 接口形式化。

  更新后的 RL 路线不再让 PPO 直接在 primitive action 上训练。
  `RL_based_submission/high_level_core.py` 针对任务 1-4，在七个符号 option 上训练
  MaskablePPO 策略。任务 5 使用 `task5_learning.py`，它提供带方向出口的九动作专用接口。

  本文件验证的边界如下：
  * 基础高层特征编码有 115 个字段：
    80 个网格字段 + 2 个玩家坐标 + 8 个怪物槽位 + 5 个背包字段 + 7 位 action mask
    + 7 位上一 option one-hot + 6 个记忆计数器；
  * 任务 5 的特征编码有 122 个字段：
    80 个网格字段 + 2 个玩家坐标 + 8 个怪物槽位 + 5 个背包字段 + 9 位 action mask
    + 9 位上一 option one-hot + 9 个记忆/时间计数器；
  * 遵守 mask 的高层策略总会选出能解析为兼容符号目标的 option；
  * 非 setup / 仅朝向调整的 primitive 移动会经过 shield，所以当它返回移动动作时，
    目标 tile 一定安全。

  神经网络权重在这里被视为不透明对象，本文件只验证围绕模型的符号接口契约。
-/

namespace RLBasedSubmission.Formalization.Strategy

abbrev Position := Int × Int

inductive PrimitiveAction where
  | wait
  | up
  | down
  | left
  | right
  | buttonA
  | buttonB
  deriving DecidableEq, Repr

inductive HighLevelAction where
  | openChest
  | attackMonster
  | activateMechanism
  | takeNewExit
  | returnOrRevisit
  | exploreRoom
  | wait
  deriving DecidableEq, Repr

inductive GoalKind where
  | openChest
  | attackMonster
  | activateSwitch
  | pressButton
  | goToExit
  | explore
  | wait
  deriving DecidableEq, Repr

inductive TileLabel where
  | floor
  | wall
  | chest
  | monster
  | exit
  | lockedExit
  | conditionalExit
  | trap
  | mechanism
  | gap
  | bridge
  | npc
  deriving DecidableEq, Repr

inductive FeatureValue where
  | tile : TileLabel → FeatureValue
  | coord : Nat → Nat → FeatureValue
  | clipped : Nat → Nat → FeatureValue
  | flag : Bool → FeatureValue
  | maskBit : Bool → FeatureValue
  | oneHotBit : Bool → FeatureValue
  | memoryCounter : Nat → Nat → FeatureValue
  | signedCounter : Bool → Nat → Nat → FeatureValue
  | missingMonster
  deriving DecidableEq, Repr

namespace FeatureValue

def Valid : FeatureValue → Prop
  | FeatureValue.tile _ => True
  | FeatureValue.coord numerator denominator =>
      0 < denominator ∧ numerator ≤ denominator
  | FeatureValue.clipped numerator denominator =>
      0 < denominator ∧ numerator ≤ denominator
  | FeatureValue.flag _ => True
  | FeatureValue.maskBit _ => True
  | FeatureValue.oneHotBit _ => True
  | FeatureValue.memoryCounter numerator denominator =>
      0 < denominator ∧ numerator ≤ denominator
  | FeatureValue.signedCounter _ numerator denominator =>
      0 < denominator ∧ numerator ≤ denominator
  | FeatureValue.missingMonster => True

end FeatureValue

structure FeatureVector where
  values : List FeatureValue
  deriving Repr

structure SymbolicState where
  player : Position
  walls : List Position
  chests : List Position
  monsters : List Position
  exits : List Position
  traps : List Position
  mechanisms : List Position
  gaps : List Position
  bridges : List Position
  npcs : List Position
  keys : Nat
  gold : Nat
  hasSword : Bool
  hasShield : Bool
  hasHeal : Bool
  deriving DecidableEq, Repr

/-!
`SymbolicState` 只是神经网络编码器读取的定长视图，不是第二套环境。
实际环境状态始终使用 `Environment.lean` 中的共享类型；`ofSharedState` 是二者之间
唯一的投影边界。
-/
abbrev SharedState := MathLogic.Formalization.SymbolicState

def ofSharedState (s : SharedState) : SymbolicState :=
  { player := s.player
    walls := s.walls
    chests := s.chests
    monsters := s.monsters
    exits := s.exits ++ s.normalExits ++ s.lockedExits ++ s.conditionalExits
    traps := s.traps
    mechanisms := s.buttons ++ s.switches
    gaps := s.gaps
    bridges := MathLogic.Formalization.activeBridges s
    npcs := s.npcs
    keys := s.keys
    gold := s.gold
    hasSword := s.hasSword
    hasShield := s.hasShield
    hasHeal := false }

@[simp] theorem ofSharedState_player (s : SharedState) :
    (ofSharedState s).player = s.player := rfl

@[simp] theorem ofSharedState_inventory (s : SharedState) :
    (ofSharedState s).keys = s.keys ∧
    (ofSharedState s).gold = s.gold ∧
    (ofSharedState s).hasSword = s.hasSword ∧
    (ofSharedState s).hasShield = s.hasShield := by
  simp [ofSharedState]

@[simp] theorem ofSharedState_objects (s : SharedState) :
    (ofSharedState s).chests = s.chests ∧
    (ofSharedState s).monsters = s.monsters ∧
    (ofSharedState s).mechanisms = s.buttons ++ s.switches := by
  simp [ofSharedState]

structure MemorySummary where
  visitedRooms : Nat
  openedChests : Nat
  killedMonsters : Nat
  activatedSwitches : Nat
  usedExits : Nat
  roomSteps : Nat
  deriving DecidableEq, Repr

structure HighLevelInput where
  state : SymbolicState
  actionMask : List Bool
  lastOption : Option HighLevelAction
  memory : MemorySummary
  deriving Repr

def gridWidth : Nat := 10
def gridHeight : Nat := 8
def actionCount : Nat := 7
def featureDim : Nat := gridWidth * gridHeight + 2 + 4 * 2 + 5 + actionCount + actionCount + 6

def allTiles : List Position :=
  (List.range gridHeight).flatMap fun row =>
    (List.range gridWidth).map fun col => (Int.ofNat col, Int.ofNat row)

theorem allTiles_length : allTiles.length = 80 := by
  native_decide

theorem allTiles_contains
    {col row : Nat} (hcol : col < gridWidth) (hrow : row < gridHeight) :
    (Int.ofNat col, Int.ofNat row) ∈ allTiles := by
  apply List.mem_flatMap.mpr
  refine ⟨row, List.mem_range.mpr hrow, ?_⟩
  exact List.mem_map.mpr ⟨col, List.mem_range.mpr hcol, rfl⟩
def listGet? {α : Type} : List α → Nat → Option α
  | [], _ => none
  | x :: _, 0 => some x
  | _ :: xs, n + 1 => listGet? xs n

def boolAt : List Bool → Nat → Bool
  | [], _ => false
  | x :: _, 0 => x
  | _ :: xs, n + 1 => boolAt xs n

def actionIndex : HighLevelAction → Nat
  | HighLevelAction.openChest => 0
  | HighLevelAction.attackMonster => 1
  | HighLevelAction.activateMechanism => 2
  | HighLevelAction.takeNewExit => 3
  | HighLevelAction.returnOrRevisit => 4
  | HighLevelAction.exploreRoom => 5
  | HighLevelAction.wait => 6

def actionAtMask (mask : List Bool) (a : HighLevelAction) : Bool :=
  boolAt mask (actionIndex a)

def canonicalGoalForOption : HighLevelAction → GoalKind
  | HighLevelAction.openChest => GoalKind.openChest
  | HighLevelAction.attackMonster => GoalKind.attackMonster
  | HighLevelAction.activateMechanism => GoalKind.activateSwitch
  | HighLevelAction.takeNewExit => GoalKind.goToExit
  | HighLevelAction.returnOrRevisit => GoalKind.goToExit
  | HighLevelAction.exploreRoom => GoalKind.explore
  | HighLevelAction.wait => GoalKind.wait

def CompatibleGoal : HighLevelAction → GoalKind → Prop
  | HighLevelAction.openChest, GoalKind.openChest => True
  | HighLevelAction.attackMonster, GoalKind.attackMonster => True
  | HighLevelAction.activateMechanism, GoalKind.activateSwitch => True
  | HighLevelAction.activateMechanism, GoalKind.pressButton => True
  | HighLevelAction.takeNewExit, GoalKind.goToExit => True
  | HighLevelAction.returnOrRevisit, GoalKind.goToExit => True
  | HighLevelAction.exploreRoom, GoalKind.explore => True
  | HighLevelAction.wait, GoalKind.wait => True
  | _, _ => False

theorem canonicalGoal_compatible (a : HighLevelAction) :
    CompatibleGoal a (canonicalGoalForOption a) := by
  cases a <;> simp [canonicalGoalForOption, CompatibleGoal]

theorem activateMechanism_allows_pressed_button :
    CompatibleGoal HighLevelAction.activateMechanism GoalKind.pressButton := by
  simp [CompatibleGoal]

theorem activateMechanism_allows_rotating_switch :
    CompatibleGoal HighLevelAction.activateMechanism GoalKind.activateSwitch := by
  simp [CompatibleGoal]

def resolveFromMask (mask : List Bool) (a : HighLevelAction) : Option GoalKind :=
  if actionAtMask mask a then some (canonicalGoalForOption a) else none

theorem resolve_some_of_mask_true
    {mask : List Bool} {a : HighLevelAction}
    (h : actionAtMask mask a = true) :
    resolveFromMask mask a = some (canonicalGoalForOption a) := by
  simp [resolveFromMask, h]

theorem resolve_none_of_mask_false
    {mask : List Bool} {a : HighLevelAction}
    (h : actionAtMask mask a = false) :
    resolveFromMask mask a = none := by
  simp [resolveFromMask, h]

abbrev MaskablePolicy := FeatureVector → List Bool → HighLevelAction

def RespectsMask (policy : MaskablePolicy) : Prop :=
  ∀ features mask, actionAtMask mask (policy features mask) = true

theorem mask_respecting_policy_resolves
    {policy : MaskablePolicy} (hpolicy : RespectsMask policy)
    (features : FeatureVector) (mask : List Bool) :
    ∃ goal,
      resolveFromMask mask (policy features mask) = some goal ∧
      CompatibleGoal (policy features mask) goal := by
  let selected := policy features mask
  have hmask : actionAtMask mask selected = true := hpolicy features mask
  exact
    ⟨ canonicalGoalForOption selected
    , resolve_some_of_mask_true hmask
    , canonicalGoal_compatible selected
    ⟩

def prioritizedAttackAllowed (mask : List Bool) : Bool :=
  if actionAtMask mask HighLevelAction.openChest ||
      actionAtMask mask HighLevelAction.activateMechanism then
    false
  else
    actionAtMask mask HighLevelAction.attackMonster

def localProgress (mask : List Bool) : Bool :=
  actionAtMask mask HighLevelAction.openChest ||
  prioritizedAttackAllowed mask ||
  actionAtMask mask HighLevelAction.activateMechanism

def prioritizedReturnAllowed (mask : List Bool) : Bool :=
  if actionAtMask mask HighLevelAction.takeNewExit then
    false
  else if localProgress mask then
    false
  else
    actionAtMask mask HighLevelAction.returnOrRevisit

def firstResolvedProgress (mask : List Bool) : Bool :=
  actionAtMask mask HighLevelAction.openChest ||
  prioritizedAttackAllowed mask ||
  actionAtMask mask HighLevelAction.activateMechanism ||
  actionAtMask mask HighLevelAction.takeNewExit ||
  prioritizedReturnAllowed mask

/-!
基础七动作 mask 与最终 `high_level_core.py` 的处理顺序一致：
宝箱或机关先压制主动追怪；新出口或本地进度压制回退；存在确定进度时关闭
探索和等待；所有候选都为空时重新打开等待，保证 MaskablePPO 始终有合法动作。
-/
def normalizedMask (raw : List Bool) : List Bool :=
  let progress := firstResolvedProgress raw
  let explore :=
    if progress then
      false
    else
      actionAtMask raw HighLevelAction.exploreRoom
  let waitBeforeFallback :=
    if progress then
      false
    else if actionAtMask raw HighLevelAction.exploreRoom then
      false
    else
      actionAtMask raw HighLevelAction.wait
  let anyBeforeFallback := progress || explore || waitBeforeFallback
  [ actionAtMask raw HighLevelAction.openChest
  , prioritizedAttackAllowed raw
  , actionAtMask raw HighLevelAction.activateMechanism
  , actionAtMask raw HighLevelAction.takeNewExit
  , prioritizedReturnAllowed raw
  , explore
  , if anyBeforeFallback then waitBeforeFallback else true
  ]

theorem normalizedMask_length (raw : List Bool) :
    (normalizedMask raw).length = actionCount := by
  simp [normalizedMask, actionCount]

theorem normalizedMask_attack_disabled_of_chest
    {raw : List Bool}
    (h : actionAtMask raw HighLevelAction.openChest = true) :
    actionAtMask (normalizedMask raw) HighLevelAction.attackMonster = false := by
  simp [normalizedMask, prioritizedAttackAllowed, actionAtMask, actionIndex,
    boolAt] at h ⊢
  simp [h]

theorem normalizedMask_attack_disabled_of_mechanism
    {raw : List Bool}
    (h : actionAtMask raw HighLevelAction.activateMechanism = true) :
    actionAtMask (normalizedMask raw) HighLevelAction.attackMonster = false := by
  simp [normalizedMask, prioritizedAttackAllowed, actionAtMask, actionIndex,
    boolAt] at h ⊢
  simp [h]

theorem normalizedMask_return_disabled_of_new_exit
    {raw : List Bool}
    (h : actionAtMask raw HighLevelAction.takeNewExit = true) :
    actionAtMask (normalizedMask raw) HighLevelAction.returnOrRevisit = false := by
  have h3 : boolAt raw 3 = true := by
    simpa [actionAtMask, actionIndex] using h
  simp [normalizedMask, prioritizedReturnAllowed, firstResolvedProgress,
    prioritizedAttackAllowed, actionAtMask, actionIndex, boolAt, h3]

theorem normalizedMask_return_disabled_of_local_progress
    {raw : List Bool}
    (hnew : actionAtMask raw HighLevelAction.takeNewExit = false)
    (hlocal : localProgress raw = true) :
    actionAtMask (normalizedMask raw) HighLevelAction.returnOrRevisit = false := by
  have h3 : boolAt raw 3 = false := by
    simpa [actionAtMask, actionIndex] using hnew
  simp [normalizedMask, prioritizedReturnAllowed, firstResolvedProgress,
    actionAtMask, actionIndex, boolAt, h3, hlocal]

theorem normalizedMask_explore_disabled_of_resolved_progress
    {raw : List Bool}
    (h : firstResolvedProgress raw = true) :
    actionAtMask (normalizedMask raw) HighLevelAction.exploreRoom = false := by
  simp [normalizedMask, actionAtMask, actionIndex, boolAt, h]

theorem normalizedMask_wait_disabled_of_resolved_progress
    {raw : List Bool}
    (h : firstResolvedProgress raw = true) :
    actionAtMask (normalizedMask raw) HighLevelAction.wait = false := by
  simp [normalizedMask, actionAtMask, actionIndex, boolAt, h]

theorem normalizedMask_wait_fallback
    {raw : List Bool}
    (hprogress : firstResolvedProgress raw = false)
    (hexplore : actionAtMask raw HighLevelAction.exploreRoom = false) :
    actionAtMask (normalizedMask raw) HighLevelAction.wait = true := by
  have h5 : boolAt raw 5 = false := by
    simpa [actionAtMask, actionIndex] using hexplore
  simp [normalizedMask, actionAtMask, actionIndex, boolAt,
    hprogress, h5]

def tileLabelAt (s : SymbolicState) (p : Position) : TileLabel :=
  if p = s.player then TileLabel.floor
  else if p ∈ s.walls then TileLabel.wall
  else if p ∈ s.chests then TileLabel.chest
  else if p ∈ s.monsters then TileLabel.monster
  else if p ∈ s.exits then TileLabel.exit
  else if p ∈ s.traps then TileLabel.trap
  else if p ∈ s.mechanisms then TileLabel.mechanism
  else if p ∈ s.gaps then TileLabel.gap
  else if p ∈ s.bridges then TileLabel.bridge
  else if p ∈ s.npcs then TileLabel.npc
  else TileLabel.floor
@[simp] theorem tileLabelAt_player (state : SymbolicState) :
    tileLabelAt state state.player = TileLabel.floor := by
  simp [tileLabelAt]
def coordFeature (z : Int) (denom : Nat) : FeatureValue :=
  FeatureValue.coord (Nat.min (Int.toNat z) denom) denom

def clippedFeature (n denom : Nat) : FeatureValue :=
  FeatureValue.clipped (Nat.min n denom) denom

def memoryFeature (n denom : Nat) : FeatureValue :=
  FeatureValue.memoryCounter (Nat.min n denom) denom

def signedMemoryFeature (value : Int) (denominator : Nat) : FeatureValue :=
  FeatureValue.signedCounter (decide (value < 0))
    (Nat.min value.natAbs denominator) denominator

def gridFeatures (s : SymbolicState) : List FeatureValue :=
  allTiles.map fun p => FeatureValue.tile (tileLabelAt s p)

theorem gridFeatures_length (s : SymbolicState) : (gridFeatures s).length = 80 := by
  simp [gridFeatures, allTiles_length]

def playerFeatures (s : SymbolicState) : List FeatureValue :=
  [coordFeature s.player.1 9, coordFeature s.player.2 7]

theorem playerFeatures_length (s : SymbolicState) : (playerFeatures s).length = 2 := by
  simp [playerFeatures]

def monsterSlotFeatures : Option Position → List FeatureValue
  | some p => [coordFeature p.1 9, coordFeature p.2 7]
  | none => [FeatureValue.missingMonster, FeatureValue.missingMonster]

theorem monsterSlotFeatures_length (slot : Option Position) :
    (monsterSlotFeatures slot).length = 2 := by
  cases slot <;> simp [monsterSlotFeatures]

def monsterBefore (player first second : Position) : Bool :=
  let firstDistance := MathLogic.Formalization.manhattan first player
  let secondDistance := MathLogic.Formalization.manhattan second player
  if firstDistance < secondDistance then
    true
  else if secondDistance < firstDistance then
    false
  else if first.1 < second.1 then
    true
  else if second.1 < first.1 then
    false
  else
    decide (first.2 ≤ second.2)

def orderedMonsters (state : SymbolicState) : List Position :=
  state.monsters.mergeSort (monsterBefore state.player)

theorem orderedMonsters_perm (state : SymbolicState) :
    (orderedMonsters state).Perm state.monsters := by
  exact List.mergeSort_perm state.monsters (monsterBefore state.player)

theorem orderedMonsters_length (state : SymbolicState) :
    (orderedMonsters state).length = state.monsters.length := by
  exact List.length_mergeSort state.monsters

def monsterFeatures (s : SymbolicState) : List FeatureValue :=
  monsterSlotFeatures (listGet? (orderedMonsters s) 0) ++
  monsterSlotFeatures (listGet? (orderedMonsters s) 1) ++
  monsterSlotFeatures (listGet? (orderedMonsters s) 2) ++
  monsterSlotFeatures (listGet? (orderedMonsters s) 3)

theorem monsterFeatures_length (s : SymbolicState) : (monsterFeatures s).length = 8 := by
  simp [monsterFeatures, monsterSlotFeatures_length]

def inventoryFeatures (s : SymbolicState) : List FeatureValue :=
  [ clippedFeature s.keys 3
  , clippedFeature s.gold 10
  , FeatureValue.flag s.hasSword
  , FeatureValue.flag s.hasShield
  , FeatureValue.flag s.hasHeal
  ]

theorem inventoryFeatures_length (s : SymbolicState) : (inventoryFeatures s).length = 5 := by
  simp [inventoryFeatures]

def fixedMaskFeatures (mask : List Bool) : List FeatureValue :=
  [ FeatureValue.maskBit (boolAt mask 0)
  , FeatureValue.maskBit (boolAt mask 1)
  , FeatureValue.maskBit (boolAt mask 2)
  , FeatureValue.maskBit (boolAt mask 3)
  , FeatureValue.maskBit (boolAt mask 4)
  , FeatureValue.maskBit (boolAt mask 5)
  , FeatureValue.maskBit (boolAt mask 6)
  ]

theorem fixedMaskFeatures_length (mask : List Bool) : (fixedMaskFeatures mask).length = 7 := by
  simp [fixedMaskFeatures]

def oneHotForLast : Option HighLevelAction → List FeatureValue
  | none => List.replicate actionCount (FeatureValue.oneHotBit false)
  | some a =>
      [ FeatureValue.oneHotBit (a = HighLevelAction.openChest)
      , FeatureValue.oneHotBit (a = HighLevelAction.attackMonster)
      , FeatureValue.oneHotBit (a = HighLevelAction.activateMechanism)
      , FeatureValue.oneHotBit (a = HighLevelAction.takeNewExit)
      , FeatureValue.oneHotBit (a = HighLevelAction.returnOrRevisit)
      , FeatureValue.oneHotBit (a = HighLevelAction.exploreRoom)
      , FeatureValue.oneHotBit (a = HighLevelAction.wait)
      ]

theorem oneHotForLast_length (last : Option HighLevelAction) : (oneHotForLast last).length = 7 := by
  cases last <;> simp [oneHotForLast, actionCount]

def memoryFeatures (m : MemorySummary) : List FeatureValue :=
  [ memoryFeature m.visitedRooms 10
  , memoryFeature m.openedChests 10
  , memoryFeature m.killedMonsters 10
  , memoryFeature m.activatedSwitches 10
  , memoryFeature m.usedExits 20
  , memoryFeature m.roomSteps 50
  ]

theorem memoryFeatures_length (m : MemorySummary) : (memoryFeatures m).length = 6 := by
  simp [memoryFeatures]

def FeaturesValid (features : List FeatureValue) : Prop :=
  ∀ feature, feature ∈ features → feature.Valid

theorem featuresValid_append
    {first second : List FeatureValue}
    (hfirst : FeaturesValid first) (hsecond : FeaturesValid second) :
    FeaturesValid (first ++ second) := by
  intro feature hmem
  rcases List.mem_append.mp hmem with hmem | hmem
  · exact hfirst feature hmem
  · exact hsecond feature hmem

theorem coordFeature_valid
    (coordinate : Int) (denominator : Nat) (hpositive : 0 < denominator) :
    (coordFeature coordinate denominator).Valid := by
  exact ⟨hpositive, Nat.min_le_right _ _⟩

theorem clippedFeature_valid
    (value denominator : Nat) (hpositive : 0 < denominator) :
    (clippedFeature value denominator).Valid := by
  exact ⟨hpositive, Nat.min_le_right _ _⟩

theorem memoryFeature_valid
    (value denominator : Nat) (hpositive : 0 < denominator) :
    (memoryFeature value denominator).Valid := by
  exact ⟨hpositive, Nat.min_le_right _ _⟩

theorem signedMemoryFeature_valid
    (value : Int) (denominator : Nat) (hpositive : 0 < denominator) :
    (signedMemoryFeature value denominator).Valid := by
  exact ⟨hpositive, Nat.min_le_right _ _⟩

theorem gridFeatures_valid (state : SymbolicState) :
    FeaturesValid (gridFeatures state) := by
  intro feature hmem
  rcases List.mem_map.mp hmem with ⟨position, _hposition, rfl⟩
  trivial

theorem playerFeatures_valid (state : SymbolicState) :
    FeaturesValid (playerFeatures state) := by
  simp [FeaturesValid, playerFeatures, coordFeature,
    FeatureValue.Valid, Nat.min_le_right]

theorem monsterSlotFeatures_valid (slot : Option Position) :
    FeaturesValid (monsterSlotFeatures slot) := by
  cases slot <;>
    simp [FeaturesValid, monsterSlotFeatures, coordFeature,
      FeatureValue.Valid, Nat.min_le_right]

theorem monsterFeatures_valid (state : SymbolicState) :
    FeaturesValid (monsterFeatures state) := by
  have firstTwo := featuresValid_append
    (monsterSlotFeatures_valid (listGet? (orderedMonsters state) 0))
    (monsterSlotFeatures_valid (listGet? (orderedMonsters state) 1))
  have firstThree := featuresValid_append firstTwo
    (monsterSlotFeatures_valid (listGet? (orderedMonsters state) 2))
  exact featuresValid_append firstThree
    (monsterSlotFeatures_valid (listGet? (orderedMonsters state) 3))

theorem inventoryFeatures_valid (state : SymbolicState) :
    FeaturesValid (inventoryFeatures state) := by
  simp [FeaturesValid, inventoryFeatures, clippedFeature,
    FeatureValue.Valid, Nat.min_le_right]

theorem fixedMaskFeatures_valid (mask : List Bool) :
    FeaturesValid (fixedMaskFeatures mask) := by
  simp [FeaturesValid, fixedMaskFeatures, FeatureValue.Valid]

theorem oneHotForLast_valid (last : Option HighLevelAction) :
    FeaturesValid (oneHotForLast last) := by
  cases last <;>
    simp [FeaturesValid, oneHotForLast, actionCount, FeatureValue.Valid]

theorem memoryFeatures_valid (memory : MemorySummary) :
    FeaturesValid (memoryFeatures memory) := by
  simp [FeaturesValid, memoryFeatures, memoryFeature,
    FeatureValue.Valid, Nat.min_le_right]

def encodeHighLevelState (input : HighLevelInput) : FeatureVector :=
  { values :=
      gridFeatures input.state ++
      playerFeatures input.state ++
      monsterFeatures input.state ++
      inventoryFeatures input.state ++
      fixedMaskFeatures input.actionMask ++
      oneHotForLast input.lastOption ++
      memoryFeatures input.memory }

def WellFormedFeatures (features : FeatureVector) : Prop :=
  features.values.length = featureDim ∧ FeaturesValid features.values

theorem encodeHighLevelState_wellFormed (input : HighLevelInput) :
    WellFormedFeatures (encodeHighLevelState input) := by
  constructor
  · simp [encodeHighLevelState, featureDim, gridWidth, gridHeight, actionCount,
      gridFeatures_length, playerFeatures_length, monsterFeatures_length,
      inventoryFeatures_length, fixedMaskFeatures_length, oneHotForLast_length,
      memoryFeatures_length]
  · have gridPlayer := featuresValid_append
      (gridFeatures_valid input.state)
      (playerFeatures_valid input.state)
    have throughMonsters := featuresValid_append gridPlayer
      (monsterFeatures_valid input.state)
    have throughInventory := featuresValid_append throughMonsters
      (inventoryFeatures_valid input.state)
    have throughMask := featuresValid_append throughInventory
      (fixedMaskFeatures_valid input.actionMask)
    have throughLast := featuresValid_append throughMask
      (oneHotForLast_valid input.lastOption)
    exact featuresValid_append throughLast
      (memoryFeatures_valid input.memory)
/- 任务 5 使用 `task5_learning.py` 中的专用学习接口：九个高层动作、方向出口，
   以及 122 维特征向量。本节验证它的形状约束和符号兼容性契约。 -/

inductive Task5Action where
  | openChest
  | attackMonster
  | activateMechanism
  | exitNorth
  | exitEast
  | exitSouth
  | exitWest
  | exploreRoom
  | wait
  deriving DecidableEq, Repr

def task5ActionCount : Nat := 9

def task5FeatureDim : Nat :=
  gridWidth * gridHeight + 2 + 4 * 2 + 5 + task5ActionCount + task5ActionCount + 9

def task5ActionIndex : Task5Action → Nat
  | Task5Action.openChest => 0
  | Task5Action.attackMonster => 1
  | Task5Action.activateMechanism => 2
  | Task5Action.exitNorth => 3
  | Task5Action.exitEast => 4
  | Task5Action.exitSouth => 5
  | Task5Action.exitWest => 6
  | Task5Action.exploreRoom => 7
  | Task5Action.wait => 8

def task5ActionAtMask (mask : List Bool) (a : Task5Action) : Bool :=
  boolAt mask (task5ActionIndex a)

def task5CanonicalGoalForOption : Task5Action → GoalKind
  | Task5Action.openChest => GoalKind.openChest
  | Task5Action.attackMonster => GoalKind.attackMonster
  | Task5Action.activateMechanism => GoalKind.activateSwitch
  | Task5Action.exitNorth => GoalKind.goToExit
  | Task5Action.exitEast => GoalKind.goToExit
  | Task5Action.exitSouth => GoalKind.goToExit
  | Task5Action.exitWest => GoalKind.goToExit
  | Task5Action.exploreRoom => GoalKind.explore
  | Task5Action.wait => GoalKind.wait

def Task5CompatibleGoal : Task5Action → GoalKind → Prop
  | Task5Action.openChest, GoalKind.openChest => True
  | Task5Action.attackMonster, GoalKind.attackMonster => True
  | Task5Action.activateMechanism, GoalKind.activateSwitch => True
  | Task5Action.activateMechanism, GoalKind.pressButton => True
  | Task5Action.exitNorth, GoalKind.goToExit => True
  | Task5Action.exitEast, GoalKind.goToExit => True
  | Task5Action.exitSouth, GoalKind.goToExit => True
  | Task5Action.exitWest, GoalKind.goToExit => True
  | Task5Action.exploreRoom, GoalKind.explore => True
  | Task5Action.wait, GoalKind.wait => True
  | _, _ => False

theorem task5CanonicalGoal_compatible (a : Task5Action) :
    Task5CompatibleGoal a (task5CanonicalGoalForOption a) := by
  cases a <;> simp [task5CanonicalGoalForOption, Task5CompatibleGoal]

def task5ResolveFromMask (mask : List Bool) (a : Task5Action) : Option GoalKind :=
  if task5ActionAtMask mask a then some (task5CanonicalGoalForOption a) else none

theorem task5_resolve_some_of_mask_true
    {mask : List Bool} {a : Task5Action}
    (h : task5ActionAtMask mask a = true) :
    task5ResolveFromMask mask a = some (task5CanonicalGoalForOption a) := by
  simp [task5ResolveFromMask, h]

theorem task5_resolve_none_of_mask_false
    {mask : List Bool} {a : Task5Action}
    (h : task5ActionAtMask mask a = false) :
    task5ResolveFromMask mask a = none := by
  simp [task5ResolveFromMask, h]

abbrev Task5MaskablePolicy := FeatureVector → List Bool → Task5Action

def Task5RespectsMask (policy : Task5MaskablePolicy) : Prop :=
  ∀ features mask, task5ActionAtMask mask (policy features mask) = true

theorem task5_mask_respecting_policy_resolves
    {policy : Task5MaskablePolicy} (hpolicy : Task5RespectsMask policy)
    (features : FeatureVector) (mask : List Bool) :
    ∃ goal,
      task5ResolveFromMask mask (policy features mask) = some goal ∧
      Task5CompatibleGoal (policy features mask) goal := by
  let selected := policy features mask
  have hmask : task5ActionAtMask mask selected = true := hpolicy features mask
  refine ⟨task5CanonicalGoalForOption selected, ?_⟩
  change
    task5ResolveFromMask mask selected = some (task5CanonicalGoalForOption selected) ∧
    Task5CompatibleGoal selected (task5CanonicalGoalForOption selected)
  constructor
  · simp [task5ResolveFromMask, hmask]
  · exact task5CanonicalGoal_compatible selected

structure Task5StateView where
  base : SymbolicState
  normalExits : List Position
  lockedExits : List Position
  conditionalExits : List Position
  deriving Repr

def task5ViewOfSharedState (s : SharedState) : Task5StateView :=
  { base := ofSharedState s
    normalExits := s.normalExits
    lockedExits := s.lockedExits
    conditionalExits := s.conditionalExits }

@[simp] theorem task5ViewOfSharedState_classifies_exits (s : SharedState) :
    (task5ViewOfSharedState s).normalExits = s.normalExits ∧
    (task5ViewOfSharedState s).lockedExits = s.lockedExits ∧
    (task5ViewOfSharedState s).conditionalExits = s.conditionalExits := by
  simp [task5ViewOfSharedState]

def task5TileLabelAt (s : Task5StateView) (p : Position) : TileLabel :=
  if p = s.base.player then TileLabel.floor
  else if p ∈ s.base.walls then TileLabel.wall
  else if p ∈ s.base.chests then TileLabel.chest
  else if p ∈ s.base.monsters then TileLabel.monster
  else if p ∈ s.normalExits then TileLabel.exit
  else if p ∈ s.lockedExits then TileLabel.lockedExit
  else if p ∈ s.conditionalExits then TileLabel.conditionalExit
  else if p ∈ s.base.traps then TileLabel.trap
  else if p ∈ s.base.mechanisms then TileLabel.mechanism
  else if p ∈ s.base.gaps then TileLabel.gap
  else if p ∈ s.base.bridges then TileLabel.bridge
  else if p ∈ s.base.npcs then TileLabel.npc
  else TileLabel.floor
@[simp] theorem task5TileLabelAt_player (state : Task5StateView) :
    task5TileLabelAt state state.base.player = TileLabel.floor := by
  simp [task5TileLabelAt]
def task5GridFeatures (s : Task5StateView) : List FeatureValue :=
  allTiles.map fun p => FeatureValue.tile (task5TileLabelAt s p)

theorem task5GridFeatures_length (s : Task5StateView) :
    (task5GridFeatures s).length = 80 := by
  simp [task5GridFeatures, allTiles_length]

def task5FixedMaskFeatures (mask : List Bool) : List FeatureValue :=
  [ FeatureValue.maskBit (boolAt mask 0)
  , FeatureValue.maskBit (boolAt mask 1)
  , FeatureValue.maskBit (boolAt mask 2)
  , FeatureValue.maskBit (boolAt mask 3)
  , FeatureValue.maskBit (boolAt mask 4)
  , FeatureValue.maskBit (boolAt mask 5)
  , FeatureValue.maskBit (boolAt mask 6)
  , FeatureValue.maskBit (boolAt mask 7)
  , FeatureValue.maskBit (boolAt mask 8)
  ]

theorem task5FixedMaskFeatures_length (mask : List Bool) :
    (task5FixedMaskFeatures mask).length = 9 := by
  simp [task5FixedMaskFeatures]

def task5OneHotForLast : Option Task5Action → List FeatureValue
  | none => List.replicate task5ActionCount (FeatureValue.oneHotBit false)
  | some a =>
      [ FeatureValue.oneHotBit (a = Task5Action.openChest)
      , FeatureValue.oneHotBit (a = Task5Action.attackMonster)
      , FeatureValue.oneHotBit (a = Task5Action.activateMechanism)
      , FeatureValue.oneHotBit (a = Task5Action.exitNorth)
      , FeatureValue.oneHotBit (a = Task5Action.exitEast)
      , FeatureValue.oneHotBit (a = Task5Action.exitSouth)
      , FeatureValue.oneHotBit (a = Task5Action.exitWest)
      , FeatureValue.oneHotBit (a = Task5Action.exploreRoom)
      , FeatureValue.oneHotBit (a = Task5Action.wait)
      ]

theorem task5OneHotForLast_length (last : Option Task5Action) :
    (task5OneHotForLast last).length = 9 := by
  cases last <;> simp [task5OneHotForLast, task5ActionCount]

structure Task5MemorySummary where
  visitedRooms : Nat
  openedChests : Nat
  killedMonsters : Nat
  activatedSwitches : Nat
  usedExits : Nat
  roomSteps : Nat
  roomX : Int
  roomY : Int
  elapsedSteps : Nat
  deriving DecidableEq, Repr

def task5MemoryFeatures (m : Task5MemorySummary) : List FeatureValue :=
  [ memoryFeature m.visitedRooms 10
  , memoryFeature m.openedChests 10
  , memoryFeature m.killedMonsters 10
  , memoryFeature m.activatedSwitches 10
  , memoryFeature m.usedExits 20
  , memoryFeature m.roomSteps 50
  , signedMemoryFeature m.roomX 4
  , signedMemoryFeature m.roomY 4
  , memoryFeature m.elapsedSteps 1080
  ]

theorem task5MemoryFeatures_length (m : Task5MemorySummary) :
    (task5MemoryFeatures m).length = 9 := by
  simp [task5MemoryFeatures]

theorem task5GridFeatures_valid (state : Task5StateView) :
    FeaturesValid (task5GridFeatures state) := by
  intro feature hmem
  rcases List.mem_map.mp hmem with ⟨position, _hposition, rfl⟩
  trivial

theorem task5FixedMaskFeatures_valid (mask : List Bool) :
    FeaturesValid (task5FixedMaskFeatures mask) := by
  simp [FeaturesValid, task5FixedMaskFeatures, FeatureValue.Valid]

theorem task5OneHotForLast_valid (last : Option Task5Action) :
    FeaturesValid (task5OneHotForLast last) := by
  cases last <;>
    simp [FeaturesValid, task5OneHotForLast, task5ActionCount,
      FeatureValue.Valid]

theorem task5MemoryFeatures_valid (memory : Task5MemorySummary) :
    FeaturesValid (task5MemoryFeatures memory) := by
  simp [FeaturesValid, task5MemoryFeatures, memoryFeature,
    signedMemoryFeature, FeatureValue.Valid, Nat.min_le_right]

structure Task5HighLevelInput where
  state : Task5StateView
  actionMask : List Bool
  lastOption : Option Task5Action
  memory : Task5MemorySummary
  deriving Repr

def encodeTask5State (input : Task5HighLevelInput) : FeatureVector :=
  { values :=
      task5GridFeatures input.state ++
      playerFeatures input.state.base ++
      monsterFeatures input.state.base ++
      inventoryFeatures input.state.base ++
      task5FixedMaskFeatures input.actionMask ++
      task5OneHotForLast input.lastOption ++
      task5MemoryFeatures input.memory }

def Task5WellFormedFeatures (features : FeatureVector) : Prop :=
  features.values.length = task5FeatureDim ∧ FeaturesValid features.values

theorem encodeTask5State_wellFormed (input : Task5HighLevelInput) :
    Task5WellFormedFeatures (encodeTask5State input) := by
  constructor
  · simp [encodeTask5State, task5FeatureDim, gridWidth, gridHeight,
      task5ActionCount, task5GridFeatures_length, playerFeatures_length,
      monsterFeatures_length, inventoryFeatures_length,
      task5FixedMaskFeatures_length, task5OneHotForLast_length,
      task5MemoryFeatures_length]
  · have gridPlayer := featuresValid_append
      (task5GridFeatures_valid input.state)
      (playerFeatures_valid input.state.base)
    have throughMonsters := featuresValid_append gridPlayer
      (monsterFeatures_valid input.state.base)
    have throughInventory := featuresValid_append throughMonsters
      (inventoryFeatures_valid input.state.base)
    have throughMask := featuresValid_append throughInventory
      (task5FixedMaskFeatures_valid input.actionMask)
    have throughLast := featuresValid_append throughMask
      (task5OneHotForLast_valid input.lastOption)
    exact featuresValid_append throughLast
      (task5MemoryFeatures_valid input.memory)

/-!
运行时从评测器提供的安全 `task_id` 选择模型接口。任务 1-4 共用 7 动作、115 维模型，
任务 5 必须切换到 9 个方向化动作和 122 维模型。
-/
inductive TaskId where
  | task1
  | task2
  | task3
  | task4
  | task5
  deriving DecidableEq, Repr

structure PolicyInterface where
  optionCount : Nat
  inputDim : Nat
  deriving DecidableEq, Repr

def interfaceFor : TaskId → PolicyInterface
  | TaskId.task1 | TaskId.task2 | TaskId.task3 | TaskId.task4 =>
      { optionCount := actionCount, inputDim := featureDim }
  | TaskId.task5 =>
      { optionCount := task5ActionCount, inputDim := task5FeatureDim }

structure SafeInfo where
  taskId : TaskId
  deriving DecidableEq, Repr

def interfaceFromSafeInfo (info : SafeInfo) : PolicyInterface :=
  interfaceFor info.taskId

@[simp] theorem task1_interface :
    interfaceFor TaskId.task1 = { optionCount := 7, inputDim := 115 } := by
  decide

@[simp] theorem task2_interface :
    interfaceFor TaskId.task2 = { optionCount := 7, inputDim := 115 } := by
  decide

@[simp] theorem task3_interface :
    interfaceFor TaskId.task3 = { optionCount := 7, inputDim := 115 } := by
  decide

@[simp] theorem task4_interface :
    interfaceFor TaskId.task4 = { optionCount := 7, inputDim := 115 } := by
  decide

@[simp] theorem task5_interface :
    interfaceFor TaskId.task5 = { optionCount := 9, inputDim := 122 } := by
  decide

@[simp] theorem safeInfo_selects_exact_interface (info : SafeInfo) :
    interfaceFromSafeInfo info = interfaceFor info.taskId := rfl


def task5LocalResource (mask : List Bool) : Bool :=
  task5ActionAtMask mask Task5Action.openChest ||
  task5ActionAtMask mask Task5Action.activateMechanism

def task5ExitSuppressedMask (raw : List Bool) : List Bool :=
  let hasLocal := task5LocalResource raw
  [ task5ActionAtMask raw Task5Action.openChest
  , task5ActionAtMask raw Task5Action.attackMonster
  , task5ActionAtMask raw Task5Action.activateMechanism
  , if hasLocal then false else task5ActionAtMask raw Task5Action.exitNorth
  , if hasLocal then false else task5ActionAtMask raw Task5Action.exitEast
  , if hasLocal then false else task5ActionAtMask raw Task5Action.exitSouth
  , if hasLocal then false else task5ActionAtMask raw Task5Action.exitWest
  , task5ActionAtMask raw Task5Action.exploreRoom
  , task5ActionAtMask raw Task5Action.wait
  ]

theorem task5_exit_north_disabled_of_local_resource
    {raw : List Bool} (h : task5LocalResource raw = true) :
    task5ActionAtMask (task5ExitSuppressedMask raw) Task5Action.exitNorth = false := by
  simp [task5ExitSuppressedMask, task5ActionAtMask, task5ActionIndex, boolAt, h]

theorem task5_exit_east_disabled_of_local_resource
    {raw : List Bool} (h : task5LocalResource raw = true) :
    task5ActionAtMask (task5ExitSuppressedMask raw) Task5Action.exitEast = false := by
  simp [task5ExitSuppressedMask, task5ActionAtMask, task5ActionIndex, boolAt, h]

theorem task5_exit_south_disabled_of_local_resource
    {raw : List Bool} (h : task5LocalResource raw = true) :
    task5ActionAtMask (task5ExitSuppressedMask raw) Task5Action.exitSouth = false := by
  simp [task5ExitSuppressedMask, task5ActionAtMask, task5ActionIndex, boolAt, h]

theorem task5_exit_west_disabled_of_local_resource
    {raw : List Bool} (h : task5LocalResource raw = true) :
    task5ActionAtMask (task5ExitSuppressedMask raw) Task5Action.exitWest = false := by
  simp [task5ExitSuppressedMask, task5ActionAtMask, task5ActionIndex, boolAt, h]

/-!
最终 Task 5 mask 的输入摘要。`lockedDirections`、`conditionalDirections` 和
`usedDirections` 都由符号解析器从当前共享状态和记忆计算；`attackIsProgress` 是
最终实现中的几何阻路检查结果。
-/
structure Task5MaskContext where
  rawMask : List Bool
  usedDirections : List Task5Action := []
  lockedDirections : List Task5Action := []
  conditionalDirections : List Task5Action := []
  hasKey : Bool := false
  attackIsProgress : Bool := false
  deriving DecidableEq, Repr

def task5DirectionActions : List Task5Action :=
  [ Task5Action.exitNorth
  , Task5Action.exitEast
  , Task5Action.exitSouth
  , Task5Action.exitWest
  ]

def task5DirectionUsed (context : Task5MaskContext) (option : Task5Action) : Bool :=
  decide (option ∈ context.usedDirections)

def task5PreferredDirections (context : Task5MaskContext) : List Task5Action :=
  if context.hasKey then
    if context.lockedDirections.isEmpty then
      context.conditionalDirections
    else
      context.lockedDirections
  else
    context.conditionalDirections

def task5PreferredActive (context : Task5MaskContext) : Bool :=
  !(task5PreferredDirections context).isEmpty

def task5RawHasNewExit (context : Task5MaskContext) : Bool :=
  task5DirectionActions.any fun option =>
    task5ActionAtMask context.rawMask option && !task5DirectionUsed context option

def task5HasUsedExit (context : Task5MaskContext) : Bool :=
  task5DirectionActions.any fun option =>
    task5ActionAtMask context.rawMask option && task5DirectionUsed context option

def task5HasNewExit (context : Task5MaskContext) : Bool :=
  task5RawHasNewExit context || task5PreferredActive context

def task5ExitBit (context : Task5MaskContext) (option : Task5Action) : Bool :=
  if task5LocalResource context.rawMask then
    false
  else if task5PreferredActive context &&
      !(decide (option ∈ task5PreferredDirections context)) then
    false
  else if task5HasNewExit context && task5DirectionUsed context option then
    false
  else
    task5ActionAtMask context.rawMask option

def task5ChestBit (context : Task5MaskContext) : Bool :=
  if task5LocalResource context.rawMask && context.attackIsProgress &&
      task5ActionAtMask context.rawMask Task5Action.attackMonster then
    false
  else
    task5ActionAtMask context.rawMask Task5Action.openChest

def task5MechanismBit (context : Task5MaskContext) : Bool :=
  if task5LocalResource context.rawMask then
    if context.attackIsProgress &&
        task5ActionAtMask context.rawMask Task5Action.attackMonster then
      false
    else if task5ActionAtMask context.rawMask Task5Action.openChest &&
        !context.attackIsProgress then
      false
    else
      task5ActionAtMask context.rawMask Task5Action.activateMechanism
  else
    task5ActionAtMask context.rawMask Task5Action.activateMechanism

def task5AttackBit (context : Task5MaskContext) : Bool :=
  if task5LocalResource context.rawMask then
    if context.attackIsProgress then
      task5ActionAtMask context.rawMask Task5Action.attackMonster
    else
      false
  else if (task5HasNewExit context || task5HasUsedExit context) &&
      !context.attackIsProgress then
    false
  else
    task5ActionAtMask context.rawMask Task5Action.attackMonster

def task5ConcreteProgress (context : Task5MaskContext) : Bool :=
  task5ChestBit context ||
  task5AttackBit context ||
  task5MechanismBit context ||
  task5ExitBit context Task5Action.exitNorth ||
  task5ExitBit context Task5Action.exitEast ||
  task5ExitBit context Task5Action.exitSouth ||
  task5ExitBit context Task5Action.exitWest

/-!
该函数逐项对应 `Task5GoalResolver.action_mask` 的最终约束顺序，最后两位仍是
探索与等待恢复动作。兜底分支保证输出 mask 永不因规则过滤而完全为空。
-/
def task5NormalizedMask (context : Task5MaskContext) : List Bool :=
  let concrete := task5ConcreteProgress context
  let explore :=
    if concrete then false
    else task5ActionAtMask context.rawMask Task5Action.exploreRoom
  let waitBeforeFallback :=
    if concrete then
      false
    else if task5ActionAtMask context.rawMask Task5Action.exploreRoom then
      false
    else
      task5ActionAtMask context.rawMask Task5Action.wait
  let anyBeforeFallback := concrete || explore || waitBeforeFallback
  [ task5ChestBit context
  , task5AttackBit context
  , task5MechanismBit context
  , task5ExitBit context Task5Action.exitNorth
  , task5ExitBit context Task5Action.exitEast
  , task5ExitBit context Task5Action.exitSouth
  , task5ExitBit context Task5Action.exitWest
  , explore
  , if anyBeforeFallback then waitBeforeFallback else true
  ]

theorem task5NormalizedMask_length (context : Task5MaskContext) :
    (task5NormalizedMask context).length = task5ActionCount := by
  simp [task5NormalizedMask, task5ActionCount]

theorem task5_locked_directions_preferred
    {context : Task5MaskContext}
    (hkey : context.hasKey = true)
    (hlocked : context.lockedDirections.isEmpty = false) :
    task5PreferredDirections context = context.lockedDirections := by
  simp [task5PreferredDirections, hkey, hlocked]

theorem task5_conditional_directions_preferred_without_key
    {context : Task5MaskContext}
    (hkey : context.hasKey = false) :
    task5PreferredDirections context = context.conditionalDirections := by
  simp [task5PreferredDirections, hkey]

theorem task5_nonpreferred_exit_disabled
    {context : Task5MaskContext} {option : Task5Action}
    (hactive : task5PreferredActive context = true)
    (hnotPreferred : decide (option ∈ task5PreferredDirections context) = false) :
    task5ExitBit context option = false := by
  simp [task5ExitBit, hactive, hnotPreferred]

theorem task5_used_exit_disabled_when_frontier_exists
    {context : Task5MaskContext} {option : Task5Action}
    (hnew : task5HasNewExit context = true)
    (hused : task5DirectionUsed context option = true) :
    task5ExitBit context option = false := by
  simp [task5ExitBit, hnew, hused]

theorem task5_all_exits_disabled_of_local_resource
    {context : Task5MaskContext}
    (hlocal : task5LocalResource context.rawMask = true) :
    task5ActionAtMask (task5NormalizedMask context) Task5Action.exitNorth = false ∧
    task5ActionAtMask (task5NormalizedMask context) Task5Action.exitEast = false ∧
    task5ActionAtMask (task5NormalizedMask context) Task5Action.exitSouth = false ∧
    task5ActionAtMask (task5NormalizedMask context) Task5Action.exitWest = false := by
  simp [task5NormalizedMask, task5ExitBit, task5ActionAtMask,
    task5ActionIndex, boolAt, hlocal]

theorem task5_chest_precedes_mechanism_without_blocking_monster
    {context : Task5MaskContext}
    (hchest : task5ActionAtMask context.rawMask Task5Action.openChest = true)
    (hattack : context.attackIsProgress = false) :
    task5ActionAtMask (task5NormalizedMask context)
      Task5Action.activateMechanism = false := by
  have h0 : boolAt context.rawMask 0 = true := by
    simpa [task5ActionAtMask, task5ActionIndex] using hchest
  simp [task5NormalizedMask, task5MechanismBit, task5LocalResource,
    task5ActionAtMask, task5ActionIndex, boolAt, h0, hattack]

theorem task5_optional_attack_disabled_in_resource_room
    {context : Task5MaskContext}
    (hlocal : task5LocalResource context.rawMask = true)
    (hattack : context.attackIsProgress = false) :
    task5ActionAtMask (task5NormalizedMask context)
      Task5Action.attackMonster = false := by
  simp [task5NormalizedMask, task5AttackBit, task5ActionAtMask,
    task5ActionIndex, boolAt, hlocal, hattack]

theorem task5_blocking_attack_precedes_local_interaction
    {context : Task5MaskContext}
    (hlocal : task5LocalResource context.rawMask = true)
    (hattack : context.attackIsProgress = true)
    (henabled : task5ActionAtMask context.rawMask Task5Action.attackMonster = true) :
    task5ActionAtMask (task5NormalizedMask context) Task5Action.openChest = false ∧
    task5ActionAtMask (task5NormalizedMask context) Task5Action.activateMechanism = false := by
  have h1 : boolAt context.rawMask 1 = true := by
    simpa [task5ActionAtMask, task5ActionIndex] using henabled
  simp [task5NormalizedMask, task5ChestBit, task5MechanismBit,
    task5ActionAtMask, task5ActionIndex, boolAt, hlocal, hattack, h1]

theorem task5_recovery_disabled_of_concrete_progress
    {context : Task5MaskContext}
    (hprogress : task5ConcreteProgress context = true) :
    task5ActionAtMask (task5NormalizedMask context) Task5Action.exploreRoom = false ∧
    task5ActionAtMask (task5NormalizedMask context) Task5Action.wait = false := by
  simp [task5NormalizedMask, task5ActionAtMask, task5ActionIndex,
    boolAt, hprogress]

theorem task5_wait_fallback
    {context : Task5MaskContext}
    (hprogress : task5ConcreteProgress context = false)
    (hexplore : task5ActionAtMask context.rawMask Task5Action.exploreRoom = false) :
    task5ActionAtMask (task5NormalizedMask context) Task5Action.wait = true := by
  have h7 : boolAt context.rawMask 7 = false := by
    simpa [task5ActionAtMask, task5ActionIndex] using hexplore
  simp [task5NormalizedMask, task5ActionAtMask, task5ActionIndex,
    boolAt, hprogress, h7]

/- 原始动作安全层。仅调整朝向的步骤用于刻画 `oriented_action_for_goal` 中的
   朝向/对齐动作；非 setup 的 primitive 移动会经过 `high_level_agent.py` 和
   `high_level_env.py` 中的 `shield`。 -/

def isMove : PrimitiveAction → Prop
  | PrimitiveAction.up | PrimitiveAction.down | PrimitiveAction.left | PrimitiveAction.right => True
  | _ => False

def nextPosition (p : Position) : PrimitiveAction → Position
  | PrimitiveAction.up => (p.1, p.2 - 1)
  | PrimitiveAction.down => (p.1, p.2 + 1)
  | PrimitiveAction.left => (p.1 - 1, p.2)
  | PrimitiveAction.right => (p.1 + 1, p.2)
  | _ => p

def inBounds (p : Position) : Prop :=
  0 ≤ p.1 ∧ p.1 < 10 ∧ 0 ≤ p.2 ∧ p.2 < 8

def isBlocked (s : SymbolicState) (p : Position) : Prop :=
  p ∈ s.walls ∨ p ∈ s.traps ∨ p ∈ s.chests ∨ p ∈ s.monsters ∨
  (p ∈ s.gaps ∧ p ∉ s.bridges) ∨ p ∈ s.npcs

def safeTile (s : SymbolicState) (p : Position) : Prop :=
  inBounds p ∧ ¬ isBlocked s p

theorem shared_walkable_projects_to_safe
    (s : SharedState) (p : Position)
    (hwalk : MathLogic.Formalization.isWalkable s p)
    (hnpc : p ∉ s.npcs) :
    safeTile (ofSharedState s) p := by
  rcases hwalk with ⟨⟨hbounds, hwall, hgap, hchest, hmonster⟩, htrap⟩
  constructor
  · simpa [inBounds, MathLogic.Formalization.inBounds,
      MathLogic.Formalization.boardWidth,
      MathLogic.Formalization.boardHeight] using hbounds
  · change ¬ (
      p ∈ s.walls ∨ p ∈ s.traps ∨ p ∈ s.chests ∨ p ∈ s.monsters ∨
      (p ∈ s.gaps ∧ p ∉ MathLogic.Formalization.activeBridges s) ∨
      p ∈ s.npcs)
    intro hblocked
    rcases hblocked with hwall' | htrap' | hchest' | hmonster' | hgap' | hnpc'
    · exact hwall hwall'
    · exact htrap htrap'
    · exact hchest hchest'
    · exact hmonster hmonster'
    · rcases hgap with hnotGap | hbridge
      · exact hnotGap hgap'.1
      · exact hgap'.2 hbridge
    · exact hnpc hnpc'

noncomputable def shield (s : SymbolicState) (a : PrimitiveAction) : PrimitiveAction := by
  classical
  exact
    match a with
    | PrimitiveAction.up => if safeTile s (nextPosition s.player PrimitiveAction.up) then PrimitiveAction.up else PrimitiveAction.wait
    | PrimitiveAction.down => if safeTile s (nextPosition s.player PrimitiveAction.down) then PrimitiveAction.down else PrimitiveAction.wait
    | PrimitiveAction.left => if safeTile s (nextPosition s.player PrimitiveAction.left) then PrimitiveAction.left else PrimitiveAction.wait
    | PrimitiveAction.right => if safeTile s (nextPosition s.player PrimitiveAction.right) then PrimitiveAction.right else PrimitiveAction.wait
    | other => other

structure PrimitiveDecision where
  action : PrimitiveAction
  setupOnly : Bool
  deriving DecidableEq, Repr

noncomputable def appliedPrimitive (s : SymbolicState) (d : PrimitiveDecision) : PrimitiveAction :=
  if d.setupOnly then d.action else shield s d.action

theorem shielded_non_setup_move_safe
    (s : SymbolicState) (d : PrimitiveDecision)
    (hsetup : d.setupOnly = false) :
    isMove (appliedPrimitive s d) →
      safeTile s (nextPosition s.player (appliedPrimitive s d)) := by
  unfold appliedPrimitive
  rw [hsetup]
  cases d.action with
  | wait => simp [shield, isMove]
  | up =>
      by_cases hs : safeTile s (nextPosition s.player PrimitiveAction.up)
      · simp [shield, hs]
      · simp [shield, hs, isMove]
  | down =>
      by_cases hs : safeTile s (nextPosition s.player PrimitiveAction.down)
      · simp [shield, hs]
      · simp [shield, hs, isMove]
  | left =>
      by_cases hs : safeTile s (nextPosition s.player PrimitiveAction.left)
      · simp [shield, hs]
      · simp [shield, hs, isMove]
  | right =>
      by_cases hs : safeTile s (nextPosition s.player PrimitiveAction.right)
      · simp [shield, hs]
      · simp [shield, hs, isMove]
  | buttonA => simp [shield, isMove]
  | buttonB => simp [shield, isMove]

end RLBasedSubmission.Formalization.Strategy
