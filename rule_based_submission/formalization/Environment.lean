/-!
本文件是规则版提交的「模块一：环境形式化」。

本层只形式化游戏环境本身，不依赖任何具体策略。
这样做的原因是：环境语义是策略证明的底座；以后规则策略或第五关策略发生变化时，
本文件中的状态、动作、对象、转移规则和基本不变量应尽量保持不变。

本文件刻画的内容包括：

1. 网格位置、房间坐标、全局位置；
2. 环境动作、任务目标类型和高层目标；
3. 符号状态 `SymbolicState`；
4. 可通行性、安全位置、出口换房等环境谓词；
5. 移动、撞墙、踩陷阱、开箱、攻击、按钮/开关触发等状态转移；
6. 多步执行轨迹；
7. 基本安全性、不变量和抽象 BFS 完备性引理。

注意：像素图像到符号状态的识别属于感知层，本环境文件不证明视觉识别正确性。
环境形式化从已经抽取出来的 `SymbolicState` 开始。
-/

namespace RuleBasedSubmission.Formalization

/-!
【基础坐标】
`Position` 表示单个房间内部的 tile 坐标 `(x, y)`。
Python 环境中房间大小为 `10 × 8`，但这里先把坐标类型定义为整数对，
再用 `inBounds` 谓词限制合法范围。
-/
abbrev Position := Int × Int

/-!
【房间坐标】
`RoomCoord` 表示多房间地图中的房间坐标。
例如 Task3、Task4、Task5 都会用房间坐标描述跨房间移动。
-/
abbrev RoomCoord := Int × Int

/-!
【棋盘宽度】
`boardWidth` 记录单房间横向 tile 数。
它用于说明 `inBounds` 中的常量 `10` 来自环境规格。
-/
def boardWidth : Int := 10

/-!
【棋盘高度】
`boardHeight` 记录单房间纵向 tile 数。
它用于说明 `inBounds` 中的常量 `8` 来自环境规格。
-/
def boardHeight : Int := 8

/-!
【第五关周期掉血间隔】
`task5DrainInterval` 对应 `nesylink/rewards/mathematical_logic/task_5.py`
中的 `_DRAIN_INTERVAL = 180`。
它表示第五关每经过固定数量的环境 tick 会额外扣除一点生命值。
-/
def task5DrainInterval : Nat := 180

/-!
【全局位置】
`GlobalPosition` 把房间坐标和房间内 tile 坐标组合起来。
Python 记忆模块中 `opened_chests`、`used_exits` 等集合实际使用的就是这种思想。
-/
structure GlobalPosition where
  room : RoomCoord
  pos : Position
  deriving DecidableEq, Repr

/-!
【对象类型】
`ObjectKind` 枚举环境中会影响规划和目标判断的主要对象。
它不是策略决策本身，只是环境中对象种类的抽象。
-/
inductive ObjectKind where
  | wall
  | chest
  | monster
  | trap
  | button
  | switch
  | bridge
  | gap
  | exit
  | npc
  deriving DecidableEq, Repr

/-!
【方向】
`Direction` 是移动方向和玩家朝向的符号抽象。
当前 Python 规则 Agent 用最近一次移动方向近似玩家朝向。
-/
inductive Direction where
  | north
  | south
  | west
  | east
  deriving DecidableEq, Repr

/-!
【动作空间】
`Action` 对应 Python 环境中的 7 个离散动作：
等待、四方向移动、A 键交互/攻击、B 键盾牌。
另外保留 `useExit` 和 `envTick` 作为扩展环境语义中的高层抽象动作：
`useExit` 表示一次显式出口跳转，`envTick` 表示怪物移动/伤害等环境自动结算。
-/
inductive Action where
  | wait
  | up
  | down
  | left
  | right
  | pressA
  | pressB
  | useExit
  | envTick
  deriving DecidableEq, Repr

/-!
【方向到动作】
`actionOfDirection d` 把方向转换成对应的移动动作。
这让扩展环境语义可以同时描述“动作”和“朝向”。
-/
def actionOfDirection : Direction → Action
  | Direction.north => Action.up
  | Direction.south => Action.down
  | Direction.west => Action.left
  | Direction.east => Action.right

/-!
【动作到方向】
`directionOfAction a` 在 `a` 是移动动作时返回对应方向，
否则返回 `none`。
-/
def directionOfAction : Action → Option Direction
  | Action.up => some Direction.north
  | Action.down => some Direction.south
  | Action.left => some Direction.west
  | Action.right => some Direction.east
  | _ => none

/-!
【物品类型】
`Item` 抽象背包中可能影响环境规则的装备或道具。
当前规则版主要使用剑和盾，第五关可继续扩展 boots/bridgeTool 等机制。
-/
inductive Item where
  | sword
  | shield
  | boots
  | bridgeTool
  deriving DecidableEq, Repr

/-!
【宝箱或怪物掉落奖励】
`Loot` 描述开箱或击杀怪物后获得的奖励。
这比轻量状态中的“开箱固定加一把钥匙”更完整。
-/
inductive Loot where
  | none
  | key (n : Nat)
  | gold (n : Nat)
  | heal (n : Nat)
  | item (i : Item)
  deriving DecidableEq, Repr

/-!
【怪物类型】
`MonsterKind` 保留怪物行为类别。
环境层只记录类别，具体追逐/巡逻策略可作为后续动态语义继续细化。
-/
inductive MonsterKind where
  | chaser
  | patroller
  | ambusher
  | guardian
  deriving DecidableEq, Repr

/-!
【桥状态】
`BridgeState` 用于形式化 Task4 的旋转桥和 Task5 中可能出现的机关桥。
-/
inductive BridgeState where
  | northSouth
  | eastWest
  | openAll
  | closed
  deriving DecidableEq, Repr

/-!
【出口条件】
`ExitKind` 描述出口是否无条件开放、是否需要钥匙、按钮或物品。
`lockedKey need consume` 中 `consume` 表示通过后是否消耗钥匙。
-/
inductive ExitKind where
  | normal
  | lockedKey (need : Nat) (consume : Bool)
  | buttonGate (button : Position)
  | itemGate (item : Item)
  deriving DecidableEq, Repr

/-!
【结构化宝箱对象】
`Chest` 比轻量状态中的 `chests : List Position` 更完整，
记录宝箱位置、奖励内容和是否已打开。
-/
structure Chest where
  pos : Position
  loot : Loot
  opened : Bool
  deriving DecidableEq, Repr

/-!
【结构化怪物对象】
`Monster` 记录怪物位置、生命值、种类、接触伤害和死亡掉落。
-/
structure Monster where
  pos : Position
  hp : Nat
  kind : MonsterKind
  damage : Nat
  loot : Loot
  deriving DecidableEq, Repr

/-!
【结构化出口对象】
`Exit` 记录出口位置、目标房间、目标出生点和出口条件。
-/
structure Exit where
  pos : Position
  targetRoom : RoomCoord
  targetSpawn : Position
  kind : ExitKind
  deriving DecidableEq, Repr

/-!
【高层目标类型】
`GoalKind` 对应规则策略中的目标类别。
环境层定义它，是因为目标谓词属于环境规格的一部分；
具体如何选择目标留给策略层证明。
-/
inductive GoalKind where
  | openChest
  | attackMonster
  | activateSwitch
  | goToExit
  | explore
  | wait
  deriving DecidableEq, Repr

/-!
【高层目标】
`Goal` 由目标类型和可选目标位置组成。
例如打开某个宝箱是 `openChest + some p`，等待是 `wait + none`。
-/
structure Goal where
  kind : GoalKind
  target : Option Position := none
  deriving DecidableEq, Repr

/-!
【符号状态】
`SymbolicState` 是 Lean 中的核心环境状态。
它对应 Python `rule_based_submission/symbolic.py` 中的 `SymbolicState`。

字段含义：
* `player`：玩家 tile 坐标；
* `room`：当前房间坐标；
* 各对象列表：当前房间中被感知到的对象位置；
* `keys`：钥匙数量；
* `health`：血量；`none` 表示当前证明不依赖精确血量；
* `hasSword / hasShield`：装备状态；
* `activated`：已经触发的按钮/开关位置。
-/
structure SymbolicState where
  player : Position
  playerCenterPx : Option Position := none
  room : RoomCoord := (0, 0)
  walls : List Position := []
  chests : List Position := []
  monsters : List Position := []
  exits : List Position := []
  normalExits : List Position := []
  lockedExits : List Position := []
  conditionalExits : List Position := []
  traps : List Position := []
  buttons : List Position := []
  switches : List Position := []
  bridges : List Position := []
  bridgeNS : List Position := []
  bridgeEW : List Position := []
  bridgeState : BridgeState := BridgeState.openAll
  gaps : List Position := []
  npcs : List Position := []
  keys : Nat := 0
  gold : Nat := 0
  health : Option Nat := none
  maxHealth : Nat := 5
  steps : Nat := 0
  maxSteps : Nat := 2000
  facing : Direction := Direction.east
  items : List Item := []
  hasSword : Bool := true
  hasShield : Bool := true
  shieldUp : Bool := false
  activated : List Position := []
  pressedButtons : List Position := []
  chestObjects : List Chest := []
  monsterObjects : List Monster := []
  exitObjects : List Exit := []
  deriving DecidableEq, Repr

/-!
【所有出口集合】
`allExits s` 对应 Python `SymbolicState.all_exits` 属性，
把普通出口、锁门出口和条件出口合并。
保留旧字段 `exits` 是为了兼容较早的轻量语义和已有证明。
-/
def allExits (s : SymbolicState) : List Position :=
  s.exits ++ s.normalExits ++ s.lockedExits ++ s.conditionalExits

/-!
【全局化函数】
`globalize room pos` 把房间内位置转成全局位置。
它对应 Python 中 `globalize(room, pos)` 的抽象。
-/
def globalize (room : RoomCoord) (pos : Position) : GlobalPosition :=
  { room := room, pos := pos }

/-!
【移动动作集合】
`movementActions` 收集四个会改变玩家位置或房间的动作。
后续安全证明只需要讨论这些动作。
-/
def movementActions : List Action :=
  [Action.up, Action.down, Action.left, Action.right]

/-!
【方向动作都是移动动作】
任意方向转换得到的动作都属于 `movementActions`。
后续扩展转移中，用它证明方向移动是普通移动动作。
-/
theorem actionOfDirection_mem_movementActions (d : Direction) :
    actionOfDirection d ∈ movementActions := by
  cases d <;> simp [actionOfDirection, movementActions]

/-!
【边界谓词】
`inBounds p` 表示位置 `p` 位于单个房间的 `10 × 8` tile 网格内。
这是环境形式化中的基本合法性条件。
-/
def inBounds (p : Position) : Prop :=
  0 ≤ p.1 ∧ p.1 < boardWidth ∧ 0 ≤ p.2 ∧ p.2 < boardHeight

/-!
【动作位移】
`delta a` 给出一个动作在当前房间内对应的坐标增量。
非移动动作的增量为 `(0, 0)`。
-/
def delta : Action → Position
  | Action.up => (0, -1)
  | Action.down => (0, 1)
  | Action.left => (-1, 0)
  | Action.right => (1, 0)
  | _ => (0, 0)

/-!
【下一 tile 位置】
`nextPosition p a` 表示在位置 `p` 执行动作 `a` 后尝试到达的房间内位置。
是否真正移动还要由环境转移规则决定。
-/
def nextPosition (p : Position) (a : Action) : Position :=
  (p.1 + (delta a).1, p.2 + (delta a).2)

/-!
【下一房间坐标】
`nextRoom r a` 表示玩家从出口向外移动时切换到的相邻房间。
只有 `exitPushAllowed` 成立时才会实际使用这个函数更新房间。
-/
def nextRoom (r : RoomCoord) : Action → RoomCoord
  | Action.up => (r.1, r.2 - 1)
  | Action.down => (r.1, r.2 + 1)
  | Action.left => (r.1 - 1, r.2)
  | Action.right => (r.1 + 1, r.2)
  | _ => r

/-!
【玩家面前位置】
`facingTarget s` 表示玩家当前朝向前方一格。
它用于刻画开箱、攻击、NPC 对话等“面向交互”的环境规则。
-/
def facingTarget (s : SymbolicState) : Position :=
  nextPosition s.player (actionOfDirection s.facing)

/-!
【位于玩家面前】
`inFront s p` 表示位置 `p` 正好是玩家朝向前方一格。
-/
def inFront (s : SymbolicState) (p : Position) : Prop :=
  facingTarget s = p

/-!
【整数差的自然数绝对值】
`absDiff a b` 用于定义曼哈顿距离。
-/
def absDiff (a b : Int) : Nat :=
  Int.natAbs (a - b)

/-!
【曼哈顿距离】
`manhattan a b` 是网格上两点的曼哈顿距离。
规则策略、交互相邻性和最近目标排序都使用这个距离。
-/
def manhattan (a b : Position) : Nat :=
  absDiff a.1 b.1 + absDiff a.2 b.2

/-!
【相邻谓词】
`adjacent a b` 表示两个 tile 在四邻域意义下相邻。
开箱、攻击、激活机关都要求玩家与目标相邻。
-/
def adjacent (a b : Position) : Prop :=
  manhattan a b = 1

/-!
【血量安全谓词】
`healthSafe s` 表示当前状态允许主动近战。
如果没有精确血量信息，则证明层把它视为不阻止攻击；
如果有血量，则要求大于 1。
-/
def healthSafe (s : SymbolicState) : Prop :=
  match s.health with
  | none => True
  | some hp => hp > 1

/-!
【门口形状谓词】
`isDoorExit p` 刻画 NesyLink 房间边界上的门 tile。
上下门位于第 0/7 行的第 4/5 列，左右门位于第 0/9 列的第 3/4 行。
-/
def isDoorExit (p : Position) : Prop :=
  ((p.2 = 0 ∨ p.2 = 7) ∧ (p.1 = 4 ∨ p.1 = 5)) ∨
  ((p.1 = 0 ∨ p.1 = 9) ∧ (p.2 = 3 ∨ p.2 = 4))

/-!
【当前激活桥格】
`activeBridges s` 表示当前桥状态下可以当作通路的桥 tile。
`bridges` 字段表示视觉层直接识别出的当前可用桥；
`bridgeNS / bridgeEW` 字段用于更细地描述可切换桥。
-/
def activeBridges (s : SymbolicState) : List Position :=
  match s.bridgeState with
  | BridgeState.northSouth => s.bridges ++ s.bridgeNS
  | BridgeState.eastWest => s.bridges ++ s.bridgeEW
  | BridgeState.openAll => s.bridges ++ s.bridgeNS ++ s.bridgeEW
  | BridgeState.closed => s.bridges

/-!
【地形可通过谓词】
`terrainPassable s p` 表示地形层面可以进入：
不能越界，不能进墙，不能掉入未被桥覆盖的 gap，不能进入宝箱或怪物占据的格子。

陷阱没有在这里排除，因为真实环境中陷阱通常是“可以踩上去但会受伤”。
安全移动会额外要求目标不是陷阱。
-/
def terrainPassable (s : SymbolicState) (p : Position) : Prop :=
  inBounds p ∧
  p ∉ s.walls ∧
  (p ∉ s.gaps ∨ p ∈ activeBridges s) ∧
  p ∉ s.chests ∧
  p ∉ s.monsters

/-!
【安全可通行谓词】
`isWalkable s p` 表示策略可以主动走向的位置：
它在地形上可通过，并且不是陷阱。
-/
def isWalkable (s : SymbolicState) (p : Position) : Prop :=
  terrainPassable s p ∧ p ∉ s.traps

/-!
【安全位置谓词】
`SafePosition s p` 是安全性定理使用的后置条件：
位置在边界内，且不是墙、未桥接 gap、陷阱或怪物。
宝箱被视为阻挡物，但开箱交互不要求玩家站到宝箱上。
-/
def SafePosition (s : SymbolicState) (p : Position) : Prop :=
  inBounds p ∧
  p ∉ s.walls ∧
  (p ∉ s.gaps ∨ p ∈ activeBridges s) ∧
  p ∉ s.traps ∧
  p ∉ s.monsters

/-!
【合法出门动作】
`exitPushAllowed s a` 表示玩家站在出口 tile 上，并向房间外移动。
这种动作的 `nextPosition` 会越出当前房间边界，但它不是错误，
而是触发换房语义。
-/
def exitPushAllowed (s : SymbolicState) (a : Action) : Prop :=
  a ∈ movementActions ∧
  s.player ∈ allExits s ∧
  isDoorExit s.player ∧
  ¬ inBounds (nextPosition s.player a)

/-!
【扣血函数】
`damageHealth s` 表示踩陷阱后的血量变化。
如果血量未知则保持未知；如果已知则自然数减一。
-/
def damageHealth (s : SymbolicState) : Option Nat :=
  match s.health with
  | none => none
  | some hp => some (hp - 1)

/-!
【持有物品谓词】
`hasItem s i` 表示玩家背包中含有物品 `i`。
它比 `hasSword / hasShield` 布尔字段更一般。
-/
def hasItem (s : SymbolicState) (i : Item) : Prop :=
  i ∈ s.items

/-!
【至少有一把钥匙】
`hasKey s` 是常用资源谓词。
-/
def hasKey (s : SymbolicState) : Prop :=
  s.keys > 0

/-!
【奖励中的钥匙数量】
`lootKeys l` 读取奖励 `l` 中携带的钥匙数；非钥匙奖励记为 0。
-/
def lootKeys : Loot → Nat
  | Loot.key n => n
  | _ => 0

/-!
【奖励中的金币数量】
`lootGold l` 读取奖励 `l` 中携带的金币数；非金币奖励记为 0。
-/
def lootGold : Loot → Nat
  | Loot.gold n => n
  | _ => 0

/-!
【受到指定伤害】
`takeDamage n s` 从状态 `s` 的生命值中扣除 `n`。
如果生命值未知，则保持未知；如果已知，Nat 减法会在 0 处截断。
-/
def takeDamage (n : Nat) (s : SymbolicState) : SymbolicState :=
  match s.health with
  | none => s
  | some hp => { s with health := some (hp - n) }

/-!
【第五关周期掉血触发谓词】
`task5DrainDue s` 抽象 Task5 reward 中的周期扣血机制：
当步数是 `task5DrainInterval` 的正倍数时，触发一次额外扣血。
Python 中使用 reward 调用次数计数；Lean 中用 `steps` 字段表达同一类时间压力。
-/
def task5DrainDue (s : SymbolicState) : Prop :=
  s.steps % task5DrainInterval = 0 ∧ s.steps ≠ 0

/-!
【第五关周期掉血条件可判定】
`task5DrainDue` 只包含自然数取模、等式和不等式，
因此 Lean 可以判定它是否成立。
-/
instance task5DrainDue_decidable (s : SymbolicState) :
    Decidable (task5DrainDue s) := by
  unfold task5DrainDue
  infer_instance

/-!
【第五关周期掉血状态更新】
`task5TimedDrainState s` 在周期到达时扣 1 点血，否则保持状态不变。
如果当前证明不依赖精确血量，即 `health = none`，则扣血保持未知。
-/
def task5TimedDrainState (s : SymbolicState) : SymbolicState :=
  if task5DrainDue s then takeDamage 1 s else s

/-!
【回血】
`healHealth n s` 给玩家恢复 `n` 点生命值，并截断在 `maxHealth` 内。
如果生命值未知，则保持未知。
-/
def healHealth (n : Nat) (s : SymbolicState) : SymbolicState :=
  match s.health with
  | none => s
  | some hp => { s with health := some (Nat.min s.maxHealth (hp + n)) }

/-!
【存活状态】
`AliveState s` 表示玩家没有死亡。
如果血量未知，环境层不把它判定为死亡。
-/
def AliveState (s : SymbolicState) : Prop :=
  match s.health with
  | none => True
  | some hp => hp > 0

/-!
【死亡状态】
`DeadState s` 用精确血量 0 表示玩家死亡。
-/
def DeadState (s : SymbolicState) : Prop :=
  s.health = some 0

/-!
【超时状态】
`TimedOut s` 表示环境步数已经达到最大步数。
-/
def TimedOut (s : SymbolicState) : Prop :=
  s.maxSteps ≤ s.steps

/-!
【失败状态】
`FailedState s` 表示玩家死亡或回合超时。
-/
def FailedState (s : SymbolicState) : Prop :=
  DeadState s ∨ TimedOut s

/-!
【推进环境时钟】
`advanceClock s` 表示一次环境 step 后步数加一。
-/
def advanceClock (s : SymbolicState) : SymbolicState :=
  { s with steps := s.steps + 1 }

/-!
【应用奖励】
`applyLoot l s` 把奖励 `l` 应用到玩家状态上。
钥匙、金币、治疗和物品奖励都会更新对应字段；
剑/盾物品也同步更新 `hasSword / hasShield` 布尔字段。
-/
def applyLoot (l : Loot) (s : SymbolicState) : SymbolicState :=
  match l with
  | Loot.none => s
  | Loot.key n => { s with keys := s.keys + n }
  | Loot.gold n => { s with gold := s.gold + n }
  | Loot.heal n => healHealth n s
  | Loot.item i =>
      { s with
        items := i :: s.items,
        hasSword := s.hasSword || (i == Item.sword),
        hasShield := s.hasShield || (i == Item.shield) }

/-!
【从结构化宝箱列表中移除指定位置宝箱】
`removeChestObjectAt p xs` 删除所有位置为 `p` 的宝箱对象。
-/
def removeChestObjectAt (p : Position) : List Chest → List Chest
  | [] => []
  | c :: cs =>
      if c.pos = p then
        removeChestObjectAt p cs
      else
        c :: removeChestObjectAt p cs

/-!
【打开结构化宝箱后的状态】
`openChestObjectState s c` 同时更新轻量位置列表、结构化宝箱列表和奖励字段。
-/
def openChestObjectState (s : SymbolicState) (c : Chest) : SymbolicState :=
  applyLoot c.loot
    { s with
      chests := s.chests.erase c.pos,
      chestObjects := removeChestObjectAt c.pos s.chestObjects }

/-!
【可以打开结构化宝箱】
`canOpenChestObject s c` 要求宝箱在当前状态中、尚未打开，并且位于玩家面前。
-/
def canOpenChestObject (s : SymbolicState) (c : Chest) : Prop :=
  c ∈ s.chestObjects ∧
  c.opened = false ∧
  inFront s c.pos

/-!
【对结构化怪物造成一点伤害】
`damageMonsterObjectAt p xs` 对位置为 `p` 的怪物造成 1 点伤害；
生命值不超过 1 的怪物会从列表中移除。
-/
def damageMonsterObjectAt (p : Position) : List Monster → List Monster
  | [] => []
  | m :: ms =>
      if m.pos = p then
        if m.hp ≤ 1 then
          damageMonsterObjectAt p ms
        else
          { m with hp := m.hp - 1 } :: damageMonsterObjectAt p ms
      else
        m :: damageMonsterObjectAt p ms

/-!
【可以攻击结构化怪物】
`canAttackObject s m` 要求怪物在列表中、仍然存活、位于玩家面前，且玩家有剑。
-/
def canAttackObject (s : SymbolicState) (m : Monster) : Prop :=
  m ∈ s.monsterObjects ∧
  m.hp > 0 ∧
  inFront s m.pos ∧
  (s.hasSword = true ∨ hasItem s Item.sword)

/-!
【攻击结构化怪物后的状态】
`attackMonsterObjectState s m` 更新轻量怪物位置列表和结构化怪物列表；
如果怪物被击杀，则额外应用其掉落奖励。
-/
def attackMonsterObjectState (s : SymbolicState) (m : Monster) : SymbolicState :=
  let base :=
    { s with
      monsters := if m.hp ≤ 1 then s.monsters.erase m.pos else s.monsters,
      monsterObjects := damageMonsterObjectAt m.pos s.monsterObjects }
  if m.hp ≤ 1 then
    applyLoot m.loot base
  else
    base

/-!
【可以和 NPC 对话】
`canTalkNpc s p` 要求 NPC 位置在状态中并位于玩家面前。
-/
def canTalkNpc (s : SymbolicState) (p : Position) : Prop :=
  p ∈ s.npcs ∧ inFront s p

/-!
【怪物威胁玩家】
`monsterThreatens s m` 表示活怪物与玩家同格或相邻，因此可能造成接触伤害。
-/
def monsterThreatens (s : SymbolicState) (m : Monster) : Prop :=
  m ∈ s.monsterObjects ∧
  m.hp > 0 ∧
  (m.pos = s.player ∨ adjacent m.pos s.player)

/-!
【怪物可占据位置】
`monsterCanOccupy s p` 表示怪物可以移动到位置 `p`：
该位置在界内，不是墙、危险 gap 或陷阱。
-/
def monsterCanOccupy (s : SymbolicState) (p : Position) : Prop :=
  inBounds p ∧
  p ∉ s.walls ∧
  (p ∉ s.gaps ∨ p ∈ activeBridges s) ∧
  p ∉ s.traps

/-!
【怪物移动合法性】
`monsterMoveAllowed s m to` 表示怪物 `m` 可以移动到相邻位置 `to`。
-/
def monsterMoveAllowed (s : SymbolicState) (m : Monster) (to : Position) : Prop :=
  m ∈ s.monsterObjects ∧
  m.hp > 0 ∧
  adjacent m.pos to ∧
  monsterCanOccupy s to ∧
  ¬ (∃ other, other ∈ s.monsterObjects ∧ other.hp > 0 ∧ other.pos = to)

/-!
【移动结构化怪物】
`moveMonsterObjectAt src to xs` 把位置为 `src` 的怪物移动到 `to`。
-/
def moveMonsterObjectAt (src to : Position) : List Monster → List Monster
  | [] => []
  | m :: ms =>
      if m.pos = src then
        { m with pos := to } :: moveMonsterObjectAt src to ms
      else
        m :: moveMonsterObjectAt src to ms

/-!
【怪物伤害结算】
`monsterDamageState s m` 让怪物 `m` 对玩家造成自身伤害。
-/
def monsterDamageState (s : SymbolicState) (m : Monster) : SymbolicState :=
  takeDamage m.damage s

/-!
【盾牌抵挡结算】
`shieldBlockState s` 表示盾牌抵挡一次伤害后，举盾状态被取消。
-/
def shieldBlockState (s : SymbolicState) : SymbolicState :=
  { s with shieldUp := false }

/-!
【切换桥状态】
`toggleBridgeState b` 抽象按钮/开关触发后的旋转桥变化。
连续切换两次会回到原状态。
-/
def toggleBridgeState : BridgeState → BridgeState
  | BridgeState.northSouth => BridgeState.eastWest
  | BridgeState.eastWest => BridgeState.northSouth
  | BridgeState.openAll => BridgeState.closed
  | BridgeState.closed => BridgeState.openAll

/-!
【出口条件】
`exitCondition s e` 判断出口 `e` 在状态 `s` 中是否满足通过条件。
-/
def exitCondition (s : SymbolicState) (e : Exit) : Prop :=
  match e.kind with
  | ExitKind.normal => True
  | ExitKind.lockedKey need _consume => need ≤ s.keys
  | ExitKind.buttonGate button => button ∈ s.pressedButtons
  | ExitKind.itemGate item => item ∈ s.items

/-!
【可以使用结构化出口】
`canUseExitObject s e` 要求出口对象在列表中、玩家站在出口上，且出口条件满足。
-/
def canUseExitObject (s : SymbolicState) (e : Exit) : Prop :=
  e ∈ s.exitObjects ∧ e.pos = s.player ∧ exitCondition s e

/-!
【通过出口后的钥匙数量】
`keysAfterExit s e` 处理锁门出口是否消耗钥匙。
-/
def keysAfterExit (s : SymbolicState) (e : Exit) : Nat :=
  match e.kind with
  | ExitKind.lockedKey need true => s.keys - need
  | _ => s.keys

/-!
【使用结构化出口后的状态】
`useExitObjectState s e` 更新房间、出生位置和钥匙数量。
-/
def useExitObjectState (s : SymbolicState) (e : Exit) : SymbolicState :=
  { s with room := e.targetRoom, player := e.targetSpawn, keys := keysAfterExit s e }

/-!
【终止状态】
`TerminalState s goal` 表示状态已经满足任务目标，或已经失败。
-/
def TerminalState (s : SymbolicState) (goal : SymbolicState → Prop) : Prop :=
  goal s ∨ FailedState s

/-!
【环境一步转移】
`EnvStep s a t` 是环境从状态 `s` 执行动作 `a` 到状态 `t` 的关系语义。

它刻画了：
* 安全移动；
* 踩陷阱移动；
* 撞墙/被阻挡；
* 出口换房；
* 开箱；
* 攻击怪物；
* 激活按钮/开关；
* B 键和等待。
-/
inductive EnvStep : SymbolicState → Action → SymbolicState → Prop where
  | moveSafe
      {s : SymbolicState} {a : Action} :
      a ∈ movementActions →
      isWalkable s (nextPosition s.player a) →
      EnvStep s a { s with player := nextPosition s.player a }
  | moveTrap
      {s : SymbolicState} {a : Action} :
      a ∈ movementActions →
      terrainPassable s (nextPosition s.player a) →
      nextPosition s.player a ∈ s.traps →
      EnvStep s a
        { s with player := nextPosition s.player a, health := damageHealth s }
  | moveBlocked
      {s : SymbolicState} {a : Action} :
      a ∈ movementActions →
      ¬ terrainPassable s (nextPosition s.player a) →
      ¬ exitPushAllowed s a →
      EnvStep s a s
  | exitRoom
      {s : SymbolicState} {a : Action} :
      exitPushAllowed s a →
      EnvStep s a { s with room := nextRoom s.room a }
  | openChest
      {s : SymbolicState} {c : Position} :
      c ∈ s.chests →
      adjacent s.player c →
      EnvStep s Action.pressA
        { s with chests := s.chests.erase c, keys := s.keys + 1 }
  | attackMonster
      {s : SymbolicState} {m : Position} :
      m ∈ s.monsters →
      adjacent s.player m →
      s.hasSword = true →
      healthSafe s →
      EnvStep s Action.pressA { s with monsters := s.monsters.erase m }
  | activateSwitch
      {s : SymbolicState} {p : Position} :
      (p ∈ s.switches ∨ p ∈ s.buttons) →
      adjacent s.player p →
      EnvStep s Action.pressA { s with activated := p :: s.activated }
  | pressB
      {s : SymbolicState} :
      EnvStep s Action.pressB s
  | wait
      {s : SymbolicState} :
      EnvStep s Action.wait s

/-!
【扩展环境一步转移】
`FullEnvStep s a t` 是更完整的环境语义。
它包含轻量 `EnvStep` 的所有情形，同时补充结构化宝箱/怪物/出口、
NPC、盾牌、怪物环境 tick 和步数推进等机制。

保留 `EnvStep` 的原因是策略层已经依赖它作为轻量符号接口；
新增 `FullEnvStep` 则用于报告中展示更完整的环境建模。
-/
inductive FullEnvStep : SymbolicState → Action → SymbolicState → Prop where
  | basic
      {s t : SymbolicState} {a : Action} :
      EnvStep s a t →
      FullEnvStep s a t
  | openChestObject
      {s : SymbolicState} {c : Chest} :
      canOpenChestObject s c →
      FullEnvStep s Action.pressA (openChestObjectState s c)
  | attackMonsterObject
      {s : SymbolicState} {m : Monster} :
      canAttackObject s m →
      FullEnvStep s Action.pressA (attackMonsterObjectState s m)
  | pressButton
      {s : SymbolicState} :
      s.player ∈ s.buttons →
      FullEnvStep s Action.pressA
        { s with pressedButtons := s.player :: s.pressedButtons }
  | pressSwitch
      {s : SymbolicState} :
      s.player ∈ s.switches →
      FullEnvStep s Action.pressA
        { s with bridgeState := toggleBridgeState s.bridgeState }
  | talkNpc
      {s : SymbolicState} {p : Position} :
      canTalkNpc s p →
      FullEnvStep s Action.pressA s
  | pressShield
      {s : SymbolicState} :
      (s.hasShield = true ∨ hasItem s Item.shield) →
      FullEnvStep s Action.pressB { s with shieldUp := true }
  | pressShieldNoItem
      {s : SymbolicState} :
      s.hasShield = false →
      Item.shield ∉ s.items →
      FullEnvStep s Action.pressB s
  | useExitObject
      {s : SymbolicState} {e : Exit} :
      canUseExitObject s e →
      FullEnvStep s Action.useExit (useExitObjectState s e)
  | monsterDamage
      {s : SymbolicState} {m : Monster} :
      monsterThreatens s m →
      s.shieldUp = false →
      FullEnvStep s Action.envTick (monsterDamageState s m)
  | monsterDamageBlocked
      {s : SymbolicState} {m : Monster} :
      monsterThreatens s m →
      s.shieldUp = true →
      FullEnvStep s Action.envTick (shieldBlockState s)
  | monsterMove
      {s : SymbolicState} {m : Monster} {to : Position} :
      monsterMoveAllowed s m to →
      FullEnvStep s Action.envTick
        { s with monsterObjects := moveMonsterObjectAt m.pos to s.monsterObjects }
  | task5TimedDrain
      {s : SymbolicState} :
      task5DrainDue s →
      FullEnvStep s Action.envTick (task5TimedDrainState s)
  | advanceClock
      {s : SymbolicState} :
      FullEnvStep s Action.envTick (advanceClock s)
  | envNoImmediateThreat
      {s : SymbolicState} :
      (∀ m, m ∈ s.monsterObjects → ¬ monsterThreatens s m) →
      FullEnvStep s Action.envTick s

/-!
【多步执行轨迹】
`Exec s plan t` 表示从状态 `s` 依次执行动作列表 `plan` 后可以到达状态 `t`。
-/
inductive Exec : SymbolicState → List Action → SymbolicState → Prop where
  | nil {s : SymbolicState} :
      Exec s [] s
  | cons {s t u : SymbolicState} {a : Action} {rest : List Action} :
      EnvStep s a t →
      Exec t rest u →
      Exec s (a :: rest) u

/-!
【扩展多步执行轨迹】
`FullExec s plan t` 使用 `FullEnvStep` 作为一步语义，
因此可以覆盖更完整的环境机制。
-/
inductive FullExec : SymbolicState → List Action → SymbolicState → Prop where
  | nil {s : SymbolicState} :
      FullExec s [] s
  | cons {s t u : SymbolicState} {a : Action} {rest : List Action} :
      FullEnvStep s a t →
      FullExec t rest u →
      FullExec s (a :: rest) u

/-!
【任务一目标谓词】
`Task1Goal s` 表示已经获得钥匙并到达出口。
它抽象“拿钥匙并从北侧锁门离开”的关键完成条件。
-/
def Task1Goal (s : SymbolicState) : Prop :=
  s.keys > 0 ∧ s.player ∈ allExits s

/-!
【任务二目标谓词】
`Task2Goal s` 表示怪物已清空、拥有钥匙并到达出口。
-/
def Task2Goal (s : SymbolicState) : Prop :=
  s.monsters = [] ∧ s.keys > 0 ∧ s.player ∈ allExits s

/-!
【任务三目标谓词】
`Task3Goal s` 表示跨房间拿到钥匙并回到出口。
具体房间拓扑由执行轨迹和 `room` 字段表达。
-/
def Task3Goal (s : SymbolicState) : Prop :=
  s.keys > 0 ∧ s.player ∈ allExits s

/-!
【任务四目标谓词】
`Task4Goal s` 表示获得剑、清除关键怪物并保有通关资源。
最终宝箱/胜利事件可以在任务证明层继续细化。
-/
def Task4Goal (s : SymbolicState) : Prop :=
  s.hasSword = true ∧ s.monsters = [] ∧ s.keys > 0

/-!
【任务五目标谓词】
`Task5Goal s` 把第五关目标抽象为“打开所有仍可见宝箱”。
这里保留一个可验证的符号完成判定：
最终视觉状态中不再存在需要处理的宝箱。更细的出口、奖励或胜利事件
可以在 `TaskProofs.lean` 中通过轨迹拼接继续加强。
-/
def Task5Goal (s : SymbolicState) : Prop :=
  s.chests = []

/-!
【定理：安全可通行蕴含地形可通过】
如果一个位置 `isWalkable`，那么它一定满足更弱的 `terrainPassable`。
-/
theorem walkable_terrain_passable
    {s : SymbolicState} {p : Position}
    (h : isWalkable s p) :
    terrainPassable s p := by
  exact h.1

/-!
【定理：安全可通行蕴含安全位置】
如果一个位置可被策略主动走向，则它不会越界，也不会是墙、危险 gap、陷阱或怪物。
-/
theorem walkable_is_safe_position
    {s : SymbolicState} {p : Position}
    (h : isWalkable s p) :
    SafePosition s p := by
  rcases h with ⟨hterrain, hntrap⟩
  rcases hterrain with ⟨hin, hnwall, hgap, _hnchest, hnmonster⟩
  exact ⟨hin, hnwall, hgap, hntrap, hnmonster⟩

/-!
【定理：安全移动后的玩家位置等于目标位置】
如果一步转移使用的是 `moveSafe` 情形，则玩家位置更新为 `nextPosition`。
-/
theorem move_safe_player_eq
    {s t : SymbolicState} {a : Action}
    (h : EnvStep s a t)
    (hmove : a ∈ movementActions)
    (hsafe : isWalkable s (nextPosition s.player a)) :
    t.player = nextPosition s.player a := by
  cases h with
  | moveSafe _ hsafe' =>
      rfl
  | moveTrap _ _ htrap =>
      exact False.elim (hsafe.2 htrap)
  | moveBlocked _ hblocked _ =>
      exact False.elim (hblocked (walkable_terrain_passable hsafe))
  | exitRoom hexit =>
      rcases hexit with ⟨_, _, _, hout⟩
      exact False.elim (hout (walkable_terrain_passable hsafe).1)
  | openChest _ _ =>
      cases hmove <;> contradiction
  | attackMonster _ _ _ _ =>
      cases hmove <;> contradiction
  | activateSwitch _ _ =>
      cases hmove <;> contradiction
  | pressB =>
      cases hmove <;> contradiction
  | wait =>
      cases hmove <;> contradiction

/-!
【定理：被阻挡移动保持玩家位置不变】
如果目标位置在地形上不可通过，且不是合法出门动作，那么移动动作不会改变玩家位置。
-/
theorem move_blocked_player_eq
    {s t : SymbolicState} {a : Action}
    (h : EnvStep s a t)
    (hmove : a ∈ movementActions)
    (hblocked : ¬ terrainPassable s (nextPosition s.player a))
    (hnotExit : ¬ exitPushAllowed s a) :
    t.player = s.player := by
  cases h with
  | moveSafe _ hsafe =>
      exact False.elim (hblocked (walkable_terrain_passable hsafe))
  | moveTrap _ hterrain _ =>
      exact False.elim (hblocked hterrain)
  | moveBlocked _ _ _ =>
      rfl
  | exitRoom hexit =>
      exact False.elim (hnotExit hexit)
  | openChest _ _ =>
      cases hmove <;> contradiction
  | attackMonster _ _ _ _ =>
      cases hmove <;> contradiction
  | activateSwitch _ _ =>
      cases hmove <;> contradiction
  | pressB =>
      cases hmove <;> contradiction
  | wait =>
      cases hmove <;> contradiction

/-!
【定理：安全移动保持安全位置不变量】
如果环境执行的是安全移动，那么新玩家位置满足 `SafePosition`。
-/
theorem safe_move_preserves_safe_position
    {s t : SymbolicState} {a : Action}
    (h : EnvStep s a t)
    (hmove : a ∈ movementActions)
    (hsafe : isWalkable s (nextPosition s.player a)) :
    SafePosition s t.player := by
  have hplayer := move_safe_player_eq h hmove hsafe
  rw [hplayer]
  exact walkable_is_safe_position hsafe

/-!
【定理：开箱会使钥匙数量加一】
当 `pressA` 按开相邻宝箱并产生指定后继状态时，后继状态的钥匙数为原状态加一。
-/
theorem open_chest_increases_keys
    {s t : SymbolicState} {c : Position}
    (_hchest : c ∈ s.chests)
    (_hadj : adjacent s.player c)
    (_hstep : EnvStep s Action.pressA t)
    (hexact : t = { s with chests := s.chests.erase c, keys := s.keys + 1 }) :
    t.keys = s.keys + 1 := by
  rw [hexact]

/-!
【定理：攻击会从怪物列表中移除目标怪物】
当攻击相邻怪物并产生指定后继状态时，后继状态的怪物列表等于删除目标后的列表。
-/
theorem attack_monster_removes_target
    {s t : SymbolicState} {m : Position}
    (_hmon : m ∈ s.monsters)
    (_hadj : adjacent s.player m)
    (_hsword : s.hasSword = true)
    (_hhp : healthSafe s)
    (_hstep : EnvStep s Action.pressA t)
    (hexact : t = { s with monsters := s.monsters.erase m }) :
    t.monsters = s.monsters.erase m := by
  rw [hexact]

/-!
【定理：激活机关会记录目标位置】
当玩家激活按钮或开关时，目标位置会被加入 `activated` 列表。
-/
theorem activate_switch_records
    {s t : SymbolicState} {p : Position}
    (_hmech : p ∈ s.switches ∨ p ∈ s.buttons)
    (_hadj : adjacent s.player p)
    (_hstep : EnvStep s Action.pressA t)
    (hexact : t = { s with activated := p :: s.activated }) :
    p ∈ t.activated := by
  rw [hexact]
  simp

/-!
【定理：一步环境转移不会减少钥匙数量】
在本抽象环境中，钥匙只会因为开箱增加，不会被普通移动、战斗或机关触发减少。
真实环境中的开门消耗可在更细任务模型中额外加入；当前规则证明只使用保守资源条件。
-/
theorem env_step_keys_monotone
    {s t : SymbolicState} {a : Action}
    (h : EnvStep s a t) :
    s.keys ≤ t.keys := by
  cases h <;> simp

/-!
【定理：执行轨迹可以拼接】
如果 `s` 能通过计划 `p` 到达 `t`，且 `t` 能通过计划 `q` 到达 `u`，
那么 `s` 能通过 `p ++ q` 到达 `u`。
-/
theorem exec_append
    {s t u : SymbolicState} {p q : List Action}
    (hp : Exec s p t)
    (hq : Exec t q u) :
    Exec s (p ++ q) u := by
  induction hp with
  | nil =>
      exact hq
  | cons hstep hexec ih =>
      exact Exec.cons hstep (ih hq)

/-!
【定理：多步执行不会减少钥匙数量】
由 `env_step_keys_monotone` 对执行轨迹归纳得到：
沿着任何 `Exec` 轨迹，钥匙数量单调不减。
-/
theorem exec_keys_monotone
    {s t : SymbolicState} {plan : List Action}
    (h : Exec s plan t) :
    s.keys ≤ t.keys := by
  induction h with
  | nil =>
      exact Nat.le_refl _
  | cons hstep _hexec ih =>
      exact Nat.le_trans (env_step_keys_monotone hstep) ih

/-!
【定理：轻量一步转移也是扩展一步转移】
`FullEnvStep` 包含 `EnvStep`，因此任何轻量环境转移都可直接提升为扩展转移。
-/
theorem env_step_is_full_step
    {s t : SymbolicState} {a : Action}
    (h : EnvStep s a t) :
    FullEnvStep s a t :=
  FullEnvStep.basic h

/-!
【定理：扩展执行轨迹可以拼接】
这是 `exec_append` 在完整环境语义 `FullExec` 上的对应版本。
-/
theorem full_exec_append
    {s t u : SymbolicState} {p q : List Action}
    (hp : FullExec s p t)
    (hq : FullExec t q u) :
    FullExec s (p ++ q) u := by
  induction hp with
  | nil =>
      exact hq
  | cons hstep hexec ih =>
      exact FullExec.cons hstep (ih hq)

/-!
【定理：受到伤害不会移动玩家】
`takeDamage` 只影响生命值，不改变玩家位置。
-/
theorem takeDamage_preserves_player (s : SymbolicState) (n : Nat) :
    (takeDamage n s).player = s.player := by
  unfold takeDamage
  cases s.health <;> rfl

/-!
【定理：第五关周期掉血不移动玩家】
`task5TimedDrainState` 只可能通过 `takeDamage` 改变生命值，
不会改变玩家 tile 位置。
-/
theorem task5TimedDrainState_preserves_player (s : SymbolicState) :
    (task5TimedDrainState s).player = s.player := by
  unfold task5TimedDrainState
  by_cases h : task5DrainDue s
  · simp [h, takeDamage_preserves_player]
  · simp [h]

/-!
【定理：已知血量时受到伤害的生命值结果】
如果当前生命值为 `hp`，则 `takeDamage n` 后生命值为 `hp - n`。
-/
theorem takeDamage_some_health_eq (s : SymbolicState) (n hp : Nat) :
    (takeDamage n { s with health := some hp }).health = some (hp - n) := by
  rfl

/-!
【定理：回血不会移动玩家】
`healHealth` 只影响生命值，不改变玩家位置。
-/
theorem healHealth_preserves_player (s : SymbolicState) (n : Nat) :
    (healHealth n s).player = s.player := by
  unfold healHealth
  cases s.health <;> rfl

/-!
【定理：已知血量时回血不会超过最大血量】
如果回血前生命值为 `hp`，则回血后的精确生命值不超过 `maxHealth`。
-/
theorem healHealth_some_le_maxHealth (s : SymbolicState) (n hp : Nat) :
    ∃ outHp,
      (healHealth n { s with health := some hp }).health = some outHp ∧
      outHp ≤ s.maxHealth := by
  exact ⟨Nat.min s.maxHealth (hp + n), rfl, Nat.min_le_left _ _⟩

/-!
【定理：推进时钟会使步数加一】
`advanceClock` 对应环境 step 计数的推进。
-/
theorem advanceClock_steps_eq (s : SymbolicState) :
    (advanceClock s).steps = s.steps + 1 := by
  rfl

/-!
【定理：推进时钟不会移动玩家】
`advanceClock` 只改变步数，不改变玩家位置。
-/
theorem advanceClock_preserves_player (s : SymbolicState) :
    (advanceClock s).player = s.player := by
  rfl

/-!
【定理：钥匙奖励增加钥匙数量】
应用 `Loot.key n` 后钥匙数量增加 `n`。
-/
theorem apply_key_loot_keys (s : SymbolicState) (n : Nat) :
    (applyLoot (Loot.key n) s).keys = s.keys + n := by
  rfl

/-!
【定理：金币奖励增加金币数量】
应用 `Loot.gold n` 后金币数量增加 `n`。
-/
theorem apply_gold_loot_gold (s : SymbolicState) (n : Nat) :
    (applyLoot (Loot.gold n) s).gold = s.gold + n := by
  rfl

/-!
【定理：物品奖励会把物品放入背包】
应用 `Loot.item i` 后，`i` 成为背包列表头部。
-/
theorem apply_item_loot_items (s : SymbolicState) (i : Item) :
    (applyLoot (Loot.item i) s).items = i :: s.items := by
  rfl

/-!
【定理：应用奖励不会移动玩家】
钥匙、金币、治疗、物品奖励都不改变玩家位置。
-/
theorem applyLoot_preserves_player (l : Loot) (s : SymbolicState) :
    (applyLoot l s).player = s.player := by
  cases l with
  | none => rfl
  | key n => rfl
  | gold n => rfl
  | heal n =>
      unfold applyLoot healHealth
      cases s.health <;> rfl
  | item i => rfl

/-!
【定理：打开结构化宝箱不会移动玩家】
开箱只更新宝箱列表和奖励字段，不改变玩家位置。
-/
theorem openChestObjectState_preserves_player
    (s : SymbolicState) (c : Chest) :
    (openChestObjectState s c).player = s.player := by
  simpa [openChestObjectState] using
    applyLoot_preserves_player c.loot
      { s with
        chests := s.chests.erase c.pos,
        chestObjects := removeChestObjectAt c.pos s.chestObjects }

/-!
【定理：结构化攻击不会移动玩家】
攻击只更新怪物列表和可能的掉落奖励，不改变玩家位置。
-/
theorem attackMonsterObjectState_preserves_player
    (s : SymbolicState) (m : Monster) :
    (attackMonsterObjectState s m).player = s.player := by
  unfold attackMonsterObjectState
  by_cases h : m.hp ≤ 1
  · simp [h, applyLoot_preserves_player]
  · simp [h]

/-!
【定理：可对话 NPC 必在 NPC 列表中】
`canTalkNpc` 的第一部分直接给出 NPC 在当前状态中。
-/
theorem canTalkNpc_listed
    {s : SymbolicState} {p : Position}
    (h : canTalkNpc s p) :
    p ∈ s.npcs := by
  exact h.1

/-!
【定理：可对话 NPC 位于玩家面前】
`canTalkNpc` 的第二部分给出面向关系。
-/
theorem canTalkNpc_in_front
    {s : SymbolicState} {p : Position}
    (h : canTalkNpc s p) :
    inFront s p := by
  exact h.2

/-!
【定理：威胁玩家的怪物在结构化怪物列表中】
`monsterThreatens` 保证怪物对象属于当前状态。
-/
theorem monsterThreatens_listed
    {s : SymbolicState} {m : Monster}
    (h : monsterThreatens s m) :
    m ∈ s.monsterObjects := by
  exact h.1

/-!
【定理：威胁玩家的怪物仍然存活】
`monsterThreatens` 保证怪物生命值大于 0。
-/
theorem monsterThreatens_alive
    {s : SymbolicState} {m : Monster}
    (h : monsterThreatens s m) :
    m.hp > 0 := by
  exact h.2.1

/-!
【定理：怪物合法移动目标在边界内】
由 `monsterMoveAllowed` 可推出目标位置满足 `inBounds`。
-/
theorem monsterMoveAllowed_target_inBounds
    {s : SymbolicState} {m : Monster} {to : Position}
    (h : monsterMoveAllowed s m to) :
    inBounds to := by
  rcases h with ⟨_hlist, _halive, _hadj, hcan, _hnoOther⟩
  exact hcan.1

/-!
【定理：怪物合法移动目标不是墙】
由 `monsterMoveAllowed` 可推出目标位置不在墙列表中。
-/
theorem monsterMoveAllowed_target_not_wall
    {s : SymbolicState} {m : Monster} {to : Position}
    (h : monsterMoveAllowed s m to) :
    to ∉ s.walls := by
  rcases h with ⟨_hlist, _halive, _hadj, hcan, _hnoOther⟩
  exact hcan.2.1

/-!
【定理：怪物伤害不会移动玩家】
怪物接触伤害只改变生命值，不改变位置。
-/
theorem monsterDamageState_preserves_player
    (s : SymbolicState) (m : Monster) :
    (monsterDamageState s m).player = s.player := by
  unfold monsterDamageState
  exact takeDamage_preserves_player s m.damage

/-!
【定理：盾牌抵挡后举盾状态为 false】
一次抵挡会消耗当前举盾姿态。
-/
theorem shieldBlockState_shieldUp_false (s : SymbolicState) :
    (shieldBlockState s).shieldUp = false := by
  rfl

/-!
【定理：盾牌抵挡不会移动玩家】
盾牌抵挡只更新盾牌姿态，不改变玩家位置。
-/
theorem shieldBlockState_preserves_player (s : SymbolicState) :
    (shieldBlockState s).player = s.player := by
  rfl

/-!
【定理：按按钮记录玩家当前位置】
按钮触发会把玩家当前 tile 加入 `pressedButtons`。
-/
theorem pressButton_records_player (s : SymbolicState) :
    s.player ∈ ({ s with pressedButtons := s.player :: s.pressedButtons }.pressedButtons) := by
  simp

/-!
【定理：按按钮不会移动玩家】
按钮触发只改变按钮记忆，不改变玩家位置。
-/
theorem pressButton_preserves_player (s : SymbolicState) :
    ({ s with pressedButtons := s.player :: s.pressedButtons }.player) = s.player := by
  rfl

/-!
【定理：桥状态切换两次回到原状态】
旋转桥或开闭桥连续触发两次会恢复原状态。
-/
theorem toggleBridge_twice (b : BridgeState) :
    toggleBridgeState (toggleBridgeState b) = b := by
  cases b <;> rfl

/-!
【定理：拉开关不会移动玩家】
开关只切换桥状态，不改变玩家位置。
-/
theorem pressSwitch_preserves_player (s : SymbolicState) :
    ({ s with bridgeState := toggleBridgeState s.bridgeState }.player) = s.player := by
  rfl

/-!
【定理：可使用出口说明出口在列表中】
`canUseExitObject` 的第一部分给出出口对象属于当前状态。
-/
theorem canUseExitObject_listed
    {s : SymbolicState} {e : Exit}
    (h : canUseExitObject s e) :
    e ∈ s.exitObjects := by
  exact h.1

/-!
【定理：可使用出口说明玩家站在出口上】
`canUseExitObject` 的第二部分给出出口位置等于玩家位置。
-/
theorem canUseExitObject_at_player
    {s : SymbolicState} {e : Exit}
    (h : canUseExitObject s e) :
    e.pos = s.player := by
  exact h.2.1

/-!
【定理：使用出口后房间等于目标房间】
结构化出口记录了跳转后的房间坐标。
-/
theorem useExitObject_room_eq (s : SymbolicState) (e : Exit) :
    (useExitObjectState s e).room = e.targetRoom := by
  rfl

/-!
【定理：使用出口后玩家位置等于目标出生点】
结构化出口记录了跳转后的出生 tile。
-/
theorem useExitObject_player_eq (s : SymbolicState) (e : Exit) :
    (useExitObjectState s e).player = e.targetSpawn := by
  rfl

/-!
【定理：锁门出口可用蕴含钥匙足够】
如果出口条件是 `lockedKey need consume` 且出口可用，
那么当前钥匙数量至少为 `need`。
-/
theorem lockedExit_condition_implies_enough_keys
    {s : SymbolicState} {e : Exit} {need : Nat} {consume : Bool}
    (hKind : e.kind = ExitKind.lockedKey need consume)
    (h : canUseExitObject s e) :
    need ≤ s.keys := by
  unfold canUseExitObject at h
  unfold exitCondition at h
  simp [hKind] at h
  exact h.2.2

/-!
【定理：满足目标则是终止状态】
任意目标谓词成立时，`TerminalState` 成立。
-/
theorem terminal_of_goal
    {s : SymbolicState} {goal : SymbolicState → Prop}
    (h : goal s) :
    TerminalState s goal := by
  exact Or.inl h

/-!
【定理：失败则是终止状态】
死亡或超时都能推出 `TerminalState`。
-/
theorem terminal_of_failed
    {s : SymbolicState} {goal : SymbolicState → Prop}
    (h : FailedState s) :
    TerminalState s goal := by
  exact Or.inr h

/-!
【定理：死亡推出失败】
死亡状态是失败状态的一种。
-/
theorem failed_of_dead
    {s : SymbolicState}
    (h : DeadState s) :
    FailedState s := by
  exact Or.inl h

/-!
【定理：超时推出失败】
超时状态是失败状态的一种。
-/
theorem failed_of_timedOut
    {s : SymbolicState}
    (h : TimedOut s) :
    FailedState s := by
  exact Or.inr h


/-!
【有界可达谓词】
`BoundedReachable init n target` 表示从 `init` 出发，
存在长度不超过 `n` 的执行计划到达 `target`。
-/
def BoundedReachable
    (init : SymbolicState) (n : Nat) (target : SymbolicState) : Prop :=
  ∃ plan, plan.length ≤ n ∧ Exec init plan target

/-!
【有界目标可达谓词】
`BoundedGoalReachable init n goal` 表示步数上界 `n` 内可以到达某个满足目标谓词的状态。
-/
def BoundedGoalReachable
    (init : SymbolicState) (n : Nat) (goal : SymbolicState → Prop) : Prop :=
  ∃ final, BoundedReachable init n final ∧ goal final

/-!
【BFS frontier 完备性谓词】
`BfsFrontierComplete init n frontier` 表示 frontier 覆盖了所有 `n` 步内可达状态。
这是把 Python BFS 正确性抽象成可证明不变量的接口。
-/
def BfsFrontierComplete
    (init : SymbolicState)
    (n : Nat)
    (frontier : List SymbolicState) : Prop :=
  ∀ final, BoundedReachable init n final → final ∈ frontier

/-!
【BFS 找到目标谓词】
`BfsFindsGoal frontier goal` 表示 frontier 中存在满足目标谓词的状态。
-/
def BfsFindsGoal
    (frontier : List SymbolicState) (goal : SymbolicState → Prop) : Prop :=
  ∃ final, final ∈ frontier ∧ goal final

/-!
【定理：BFS frontier 完备性推出可达目标会被发现】
只要 BFS frontier 已经覆盖所有有界可达状态，
那么任何有界可达目标都一定出现在 frontier 中。
-/
theorem bfs_completeness_from_frontier_invariant
    {init : SymbolicState} {n : Nat} {frontier : List SymbolicState}
    {goal : SymbolicState → Prop}
    (hcomplete : BfsFrontierComplete init n frontier)
    (hreachable : BoundedGoalReachable init n goal) :
    BfsFindsGoal frontier goal := by
  rcases hreachable with ⟨final, hbounded, hgoal⟩
  exact ⟨final, hcomplete final hbounded, hgoal⟩

end RuleBasedSubmission.Formalization
