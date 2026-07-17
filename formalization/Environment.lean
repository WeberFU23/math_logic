/-!
本文件是 rule-based 与 RL-based 两条路线共用的「模块一：环境形式化」。

本层只形式化游戏环境本身，不依赖任何具体策略。
这样做的原因是：环境语义是策略证明的底座；以后 rule-based 策略、RL-based 策略或第五关策略发生变化时，
本文件中的状态、动作、对象、转移规则和基本不变量应尽量保持不变。

本文件刻画的内容包括：

1. 网格位置、房间坐标、全局位置；
2. 环境动作、任务目标类型和高层目标；
3. 符号状态 `SymbolicState`；
4. 可通行性、安全位置、出口换房等环境谓词；
5. 移动、撞墙、踩陷阱、开箱、攻击、站上按钮和按 A 开关等状态转移；
6. 多步执行轨迹；
7. 基本安全性、不变量和抽象 BFS 完备性引理。

注意：像素图像到符号状态的识别属于感知层，本环境文件不证明视觉识别正确性。
环境形式化从已经抽取出来的 `SymbolicState` 开始。
-/

namespace MathLogic.Formalization

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
中的 `_DRAIN_INTERVAL = 200`。
它表示第五关每经过固定数量的环境 tick 会额外扣除一点生命值。
-/
def task5DrainInterval : Nat := 200

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
当前项目主要使用剑和盾，第五关可继续扩展 boots/bridgeTool 等机制。
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
  | allMonstersAndKey (need : Nat) (consume : Bool)
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
  room : RoomCoord := (0, 0)
  completesTask : Bool := false
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
  room : RoomCoord := (0, 0)
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
  sourceRoom : RoomCoord := (0, 0)
  revealedButtons : List Position := []
  completesTask : Bool := false
  deriving DecidableEq, Repr

/-!
【高层目标类型】
`GoalKind` 对应高层策略中的目标类别。
环境层定义它，是因为目标谓词属于环境规格的一部分；
具体如何选择目标留给策略层证明。
-/
inductive GoalKind where
  | openChest
  | attackMonster
  | activateButton
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
* `activated`：已经按 A 触发的开关位置；
* `pressedButtons`：已经通过站上 tile 自动触发的按钮位置。
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
  buttonLocations : List GlobalPosition := []
  switchLocations : List GlobalPosition := []
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
  keysCollected : Nat := 0
  chestsOpened : Nat := 0
  monstersKilled : Nat := 0
  buttonsPressed : Nat := 0
  switchesActivated : Nat := 0
  roomsChanged : Nat := 0
  worldCompleted : Bool := false
  deriving DecidableEq, Repr

/-!
【颜色模式】
`ColorMode` 对应 `color_vision.py` 和 `advanced_perception.py` 支持的六种渲染变体。
本层只声明模式，不假定某个具体像素模板一定识别正确。
-/
inductive ColorMode where
  | default
  | grayscale
  | dark
  | bright
  | highContrast
  | inverted
  deriving DecidableEq, Repr

/-!
【像素帧】
`PixelFrame` 保存评测时实际传入的 RGB 帧及其形状。
像素值使用自然数表示；`ValidPixelFrame` 再限制标准帧必须是 `160 × 128 × 3`。
-/
structure PixelFrame where
  width : Nat
  height : Nat
  channels : Nat
  pixels : List Nat
  deriving DecidableEq, Repr

def ValidPixelFrame (frame : PixelFrame) : Prop :=
  frame.width = 160 ∧
  frame.height = 128 ∧
  frame.channels = 3 ∧
  frame.pixels.length = 160 * 128 * 3 ∧
  ∀ value, value ∈ frame.pixels → value ≤ 255

/-!
【感知流水线类型】
归一化器先根据颜色模式变换帧，符号提取器再产生共享的 `SymbolicState`。
这正是两条策略路线共用“像素 -> 符号状态”边界的函数类型。
-/
abbrev ColorNormalizer := ColorMode → PixelFrame → PixelFrame
abbrev SymbolExtractor := PixelFrame → SymbolicState

/-!
【感知正确性契约】
`PerceptionSound` 由一个外部符号真值关系 `truth` 参数化。
它要求每个合法帧、每种颜色模式经归一化和提取后都满足同一真值关系。
Lean 在这里验证接口组合；具体 Python/CV 实现需要由单元测试和测评结果建立该前提。
-/
def PerceptionSound
    (normalize : ColorNormalizer)
    (extract : SymbolExtractor)
    (truth : PixelFrame → SymbolicState → Prop) : Prop :=
  ∀ mode frame, ValidPixelFrame frame →
    truth frame (extract (normalize mode frame))

/-!
【颜色模式不变性契约】
如果同一场景以不同颜色模式渲染，归一化和提取后的符号状态必须相同。
该契约对应最终颜色鲁棒性评测关注的语义不变性。
-/
def ColorModeInvariant
    (normalize : ColorNormalizer)
    (extract : SymbolExtractor) : Prop :=
  ∀ first second frame,
    extract (normalize first frame) = extract (normalize second frame)

/-!
【定理：颜色不变契约给出任意两种模式的相同符号状态】
-/
theorem color_mode_invariant_extract_eq
    {normalize : ColorNormalizer} {extract : SymbolExtractor}
    (h : ColorModeInvariant normalize extract)
    (first second : ColorMode) (frame : PixelFrame) :
    extract (normalize first frame) = extract (normalize second frame) :=
  h first second frame
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
【当前房间按钮可见性】
多房间参考状态可以在 `buttonLocations` 中保存按钮所属房间；空列表表示
普通感知状态的 `buttons` 已经只包含当前房间对象。
-/
@[simp] def buttonVisibleAt (s : SymbolicState) (p : Position) : Prop :=
  p ∈ s.buttons ∧
    (s.buttonLocations = [] ∨ globalize s.room p ∈ s.buttonLocations)

/-!
【当前房间开关可见性】
语义与 `buttonVisibleAt` 相同，用于排除其他房间中坐标相同的开关。
-/
@[simp] def switchVisibleAt (s : SymbolicState) (p : Position) : Prop :=
  p ∈ s.switches ∧
    (s.switchLocations = [] ∨ globalize s.room p ∈ s.switchLocations)

instance buttonVisibleAt_decidable (s : SymbolicState) (p : Position) :
    Decidable (buttonVisibleAt s p) := by
  unfold buttonVisibleAt
  infer_instance

instance switchVisibleAt_decidable (s : SymbolicState) (p : Position) :
    Decidable (switchVisibleAt s p) := by
  unfold switchVisibleAt
  infer_instance

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
  | Loot.key n => { s with keys := s.keys + n, keysCollected := s.keysCollected + n }
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
  let opened :=
    { s with
      chests := s.chests.erase c.pos,
      chestObjects := removeChestObjectAt c.pos s.chestObjects,
      chestsOpened := s.chestsOpened + 1,
      worldCompleted := s.worldCompleted || c.completesTask }
  applyLoot c.loot opened

/-!
【可以打开结构化宝箱】
`canOpenChestObject s c` 要求宝箱在当前状态中、尚未打开，并且位于玩家面前。
-/
def canOpenChestObject (s : SymbolicState) (c : Chest) : Prop :=
  c ∈ s.chestObjects ∧
  c.room = s.room ∧
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
  m.room = s.room ∧
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
      monsterObjects := damageMonsterObjectAt m.pos s.monsterObjects,
      monstersKilled := if m.hp ≤ 1 then s.monstersKilled + 1 else s.monstersKilled }
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
  | ExitKind.allMonstersAndKey need _consume => need ≤ s.keys ∧ s.monsters = []
  | ExitKind.buttonGate button => button ∈ s.pressedButtons
  | ExitKind.itemGate item => item ∈ s.items

/-!
【可以使用结构化出口】
`canUseExitObject s e` 要求出口对象在列表中、玩家站在出口上，且出口条件满足。
-/
def canUseExitObject (s : SymbolicState) (e : Exit) : Prop :=
  e ∈ s.exitObjects ∧ e.sourceRoom = s.room ∧
  e.pos = s.player ∧ exitCondition s e

/-!
【通过出口后的钥匙数量】
`keysAfterExit s e` 处理锁门出口是否消耗钥匙。
-/
def keysAfterExit (s : SymbolicState) (e : Exit) : Nat :=
  match e.kind with
  | ExitKind.lockedKey need true => s.keys - need
  | ExitKind.allMonstersAndKey need true => s.keys - need
  | _ => s.keys

/-!
【进入位置后的自动机关语义】
`enterPositionState s p` 统一处理玩家进入 tile `p` 的状态更新。
按钮采用项目与 Python 执行器一致的“站上触发”语义：首次进入未触发按钮时，
立即记录按钮并增加计数；普通位置或已触发按钮只更新玩家位置。
-/
@[simp] def enterPositionState (s : SymbolicState) (p : Position) : SymbolicState :=
  { s with
    player := p
    pressedButtons :=
      if buttonVisibleAt s p ∧ p ∉ s.pressedButtons then
        p :: s.pressedButtons
      else
        s.pressedButtons
    buttonsPressed :=
      if buttonVisibleAt s p ∧ p ∉ s.pressedButtons then
        s.buttonsPressed + 1
      else
        s.buttonsPressed }

/-!
【使用结构化出口后的状态】
`useExitObjectState s e` 更新房间、出生位置和钥匙数量；
如果出生点是未触发按钮，则在到达时自动触发。
-/
def useExitObjectState (s : SymbolicState) (e : Exit) : SymbolicState :=
  enterPositionState
    { s with
      room := e.targetRoom,
      player := e.targetSpawn,
      buttons := e.revealedButtons ++ s.buttons,
      buttonLocations :=
        e.revealedButtons.map (globalize e.targetRoom) ++ s.buttonLocations,
      keys := keysAfterExit s e,
      roomsChanged := s.roomsChanged + 1,
      worldCompleted := s.worldCompleted || e.completesTask }
    e.targetSpawn

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
* 站上按钮时随移动自动触发，以及按 A 激活开关；
* 按 B 键和等待。
-/
inductive EnvStep : SymbolicState → Action → SymbolicState → Prop where
  | moveSafe
      {s : SymbolicState} {a : Action} :
      a ∈ movementActions →
      isWalkable s (nextPosition s.player a) →
      EnvStep s a (enterPositionState s (nextPosition s.player a))
  | moveTrap
      {s : SymbolicState} {a : Action} :
      a ∈ movementActions →
      terrainPassable s (nextPosition s.player a) →
      nextPosition s.player a ∈ s.traps →
      EnvStep s a
        { enterPositionState s (nextPosition s.player a) with
          health := damageHealth s }
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
      p ∈ s.switches →
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

  | pressSwitch
      {s : SymbolicState} :
      s.player ∈ s.switches →
      FullEnvStep s Action.pressA
        { s with
          bridgeState := toggleBridgeState s.bridgeState,
          switchesActivated := s.switchesActivated + 1 }
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
【无失败执行轨迹】
`SafeFullExec` 在 `FullExec` 之外要求轨迹中的每个状态都不是死亡或超时状态。
因此任务证书不能用“已经死亡但目标字段偶然成立”的终点冒充安全通关。
-/
inductive SafeFullExec : SymbolicState → List Action → SymbolicState → Prop where
  | nil {s : SymbolicState} :
      ¬ FailedState s →
      SafeFullExec s [] s
  | cons {s t u : SymbolicState} {a : Action} {rest : List Action} :
      ¬ FailedState s →
      FullEnvStep s a t →
      SafeFullExec t rest u →
      SafeFullExec s (a :: rest) u

/-!
【定理：无失败轨迹可以遗忘安全见证得到普通完整轨迹】
-/
theorem safeFullExec_to_fullExec
    {s t : SymbolicState} {plan : List Action}
    (h : SafeFullExec s plan t) :
    FullExec s plan t := by
  induction h with
  | nil _hsafe =>
      exact FullExec.nil
  | cons _hsafe hstep _hrest ih =>
      exact FullExec.cons hstep ih
/-!
【任务一目标谓词】
`Task1Goal s` 表示已经获得钥匙并到达出口。
它抽象“拿钥匙并从北侧锁门离开”的关键完成条件。
-/
def Task1Goal (s : SymbolicState) : Prop :=
  s.worldCompleted = true ∧
  s.keysCollected ≥ 1 ∧
  s.chestsOpened ≥ 1

/-!
【任务二目标谓词】
`Task2Goal s` 对应“击败怪物、取得钥匙并通过西侧条件门完成任务”。
钥匙可能在开门时被消耗，因此使用累计里程碑而不是最终背包数量。
-/
def Task2Goal (s : SymbolicState) : Prop :=
  s.worldCompleted = true ∧
  s.monstersKilled ≥ 1 ∧
  s.keysCollected ≥ 1 ∧
  s.chestsOpened ≥ 1

/-!
【任务三目标谓词】
`Task3Goal s` 对应“穿过怪物房、在西侧钥匙房取钥匙、返回起点并打开东侧锁门”。
五次换房分别覆盖去怪物房、去钥匙房、两次返回和最终锁门出口。
-/
def Task3Goal (s : SymbolicState) : Prop :=
  s.worldCompleted = true ∧
  s.roomsChanged ≥ 5 ∧
  s.monstersKilled ≥ 1 ∧
  s.keysCollected ≥ 1 ∧
  s.chestsOpened ≥ 1

/-!
【任务四目标谓词】
`Task4Goal s` 对应旋转桥、取得钥匙和剑、击败守卫并打开最终宝箱。
至少三个宝箱分别是钥匙箱、剑箱和最终宝箱。
-/
def Task4Goal (s : SymbolicState) : Prop :=
  s.worldCompleted = true ∧
  s.switchesActivated ≥ 2 ∧
  s.keysCollected ≥ 1 ∧
  s.hasSword = true ∧
  s.monstersKilled ≥ 1 ∧
  s.chestsOpened ≥ 3

/-!
【任务五目标谓词】
`Task5Goal s` 对应探索四个房间并打开全部四个宝箱。
五次换房是覆盖三个分支房间所需的最短房间切换数；南门按钮和东门钥匙也作为必要里程碑记录。
-/
def Task5Goal (s : SymbolicState) : Prop :=
  s.worldCompleted = true ∧
  s.chestsOpened ≥ 4 ∧
  s.roomsChanged ≥ 5 ∧
  s.buttonsPressed ≥ 1 ∧
  s.keysCollected ≥ 1

/-!
【任务完成存在性】
`CompletedBy goal init` 表示存在一条完整环境轨迹到达目标。
它统一替代两条路线过去各自定义的完成谓词。
-/
def CompletedBy (goal : SymbolicState → Prop) (init : SymbolicState) : Prop :=
  ∃ plan final, FullExec init plan final ∧ goal final

/-!
【安全任务证书】
任务证书同时携带动作计划、最终状态、逐状态无失败轨迹和最终目标证明。
规则版与 RL 版的五关证明都必须实例化同一个证书类型。
-/
structure TaskCertificate
    (goal : SymbolicState → Prop) (init : SymbolicState) where
  plan : List Action
  final : SymbolicState
  execution : SafeFullExec init plan final
  completed : goal final

/-!
【定理：安全任务证书推出普通完成存在性】
-/
theorem taskCertificate_completedBy
    {goal : SymbolicState → Prop} {init : SymbolicState}
    (certificate : TaskCertificate goal init) :
    CompletedBy goal init :=
  ⟨certificate.plan, certificate.final,
    safeFullExec_to_fullExec certificate.execution, certificate.completed⟩
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
      simp
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
【定理：激活开关会记录目标位置】
当玩家按 A 激活开关时，目标位置会被加入 `activated` 列表。
-/
theorem activate_switch_records
    {s t : SymbolicState} {p : Position}
    (_hswitch : p ∈ s.switches)
    (_hadj : adjacent s.player p)
    (_hstep : EnvStep s Action.pressA t)
    (hexact : t = { s with activated := p :: s.activated }) :
    p ∈ t.activated := by
  rw [hexact]
  simp

/-!
【定理：一步环境转移不会减少钥匙数量】
在本抽象环境中，钥匙只会因为开箱增加，不会被普通移动、战斗或机关触发减少。
真实环境中的开门消耗可在更细任务模型中额外加入；当前公共环境证明只使用保守资源条件。
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
  let opened :=
    { s with
      chests := s.chests.erase c.pos,
      chestObjects := removeChestObjectAt c.pos s.chestObjects,
      chestsOpened := s.chestsOpened + 1,
      worldCompleted := s.worldCompleted || c.completesTask }
  simpa [openChestObjectState, opened] using
    applyLoot_preserves_player c.loot opened

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
【定理：首次进入按钮会自动记录按钮】
无需额外执行 `pressA`；进入未触发按钮 tile 的同一步就会更新按钮集合。
-/
theorem enterPositionState_records_fresh_button
    {s : SymbolicState} {p : Position}
    (hbutton : buttonVisibleAt s p) (hfresh : p ∉ s.pressedButtons) :
    p ∈ (enterPositionState s p).pressedButtons := by
  change p ∈
    (if buttonVisibleAt s p ∧ p ∉ s.pressedButtons then
      p :: s.pressedButtons else s.pressedButtons)
  rw [if_pos ⟨hbutton, hfresh⟩]
  simp

/-!
【定理：首次进入按钮会把计数增加一】
-/
theorem enterPositionState_counts_fresh_button
    {s : SymbolicState} {p : Position}
    (hbutton : buttonVisibleAt s p) (hfresh : p ∉ s.pressedButtons) :
    (enterPositionState s p).buttonsPressed = s.buttonsPressed + 1 := by
  change (if buttonVisibleAt s p ∧ p ∉ s.pressedButtons then
    s.buttonsPressed + 1 else s.buttonsPressed) = s.buttonsPressed + 1
  rw [if_pos ⟨hbutton, hfresh⟩]

/-!
【定理：重复进入已触发按钮不会重复计数】
-/
theorem enterPositionState_does_not_recount_button
    {s : SymbolicState} {p : Position}
    (hpressed : p ∈ s.pressedButtons) :
    (enterPositionState s p).buttonsPressed = s.buttonsPressed := by
  change (if buttonVisibleAt s p ∧ p ∉ s.pressedButtons then
    s.buttonsPressed + 1 else s.buttonsPressed) = s.buttonsPressed
  rw [if_neg (fun h => h.2 hpressed)]

/-!
【定理：进入位置后玩家位于该位置】
-/
theorem enterPositionState_player (s : SymbolicState) (p : Position) :
    (enterPositionState s p).player = p := by
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
  exact h.2.2.1

/-!
【定理：使用出口后房间等于目标房间】
结构化出口记录了跳转后的房间坐标。
-/
theorem useExitObject_room_eq (s : SymbolicState) (e : Exit) :
    (useExitObjectState s e).room = e.targetRoom := by
  simp [useExitObjectState]

/-!
【定理：使用出口后玩家位置等于目标出生点】
结构化出口记录了跳转后的出生 tile。
-/
theorem useExitObject_player_eq (s : SymbolicState) (e : Exit) :
    (useExitObjectState s e).player = e.targetSpawn := by
  simp [useExitObjectState]

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
  rcases h with ⟨_hlisted, _hroom, _hplayer, hcondition⟩
  simpa [exitCondition, hKind] using hcondition

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

namespace ReferenceTasks

/-!
以下参考场景不是固定像素坐标策略，而是五个公开关卡机制的有限符号投影。
对象位置只用于给 `FullEnvStep` 提供可检查的交互见证；策略正确性仍由各自的策略模块证明。
-/

/-! ## Task 1：开钥匙箱并通过消耗钥匙的北侧锁门 -/

def task1Room : RoomCoord := (0, 0)

def task1Chest : Chest :=
  { pos := (5, 4)
    loot := Loot.key 1
    opened := false
    room := task1Room }

def task1Exit : Exit :=
  { pos := (4, 4)
    targetRoom := (0, -1)
    targetSpawn := (4, 6)
    kind := ExitKind.lockedKey 1 true
    sourceRoom := task1Room
    completesTask := true }

def task1Init : SymbolicState :=
  { player := (4, 4)
    room := task1Room
    chests := [task1Chest.pos]
    lockedExits := [task1Exit.pos]
    health := some 5
    facing := Direction.east
    chestObjects := [task1Chest]
    exitObjects := [task1Exit] }

def task1AfterChest : SymbolicState :=
  openChestObjectState task1Init task1Chest

def task1Final : SymbolicState :=
  useExitObjectState task1AfterChest task1Exit

def task1Plan : List Action :=
  [Action.pressA, Action.useExit]

theorem task1_safe_execution :
    SafeFullExec task1Init task1Plan task1Final := by
  change SafeFullExec task1Init [Action.pressA, Action.useExit] task1Final
  refine SafeFullExec.cons (t := task1AfterChest)
    (by simp [FailedState, DeadState, TimedOut, task1Init]) ?_ ?_
  · exact FullEnvStep.openChestObject (by
      simp [canOpenChestObject, task1Init, task1Chest, task1Room,
        inFront, facingTarget, nextPosition, actionOfDirection, delta])
  · refine SafeFullExec.cons (t := task1Final)
      (by
        simp [FailedState, DeadState, TimedOut, task1AfterChest,
          openChestObjectState, task1Init, task1Chest, applyLoot]) ?_ ?_
    · exact FullEnvStep.useExitObject (by
        simp [canUseExitObject, task1AfterChest, openChestObjectState,
          task1Init, task1Chest, task1Exit, task1Room, applyLoot,
          exitCondition])
    · exact SafeFullExec.nil (by
        simp [FailedState, DeadState, TimedOut, task1Final,
          useExitObjectState, task1AfterChest, openChestObjectState,
          task1Init, task1Chest, task1Exit, applyLoot, keysAfterExit])

theorem task1_goal : Task1Goal task1Final := by
  simp [Task1Goal, task1Final, useExitObjectState, task1AfterChest,
    openChestObjectState, task1Init, task1Chest, task1Exit, applyLoot,
    keysAfterExit]

/-! ## Task 2：击败怪物、取得钥匙并通过西侧条件门 -/

def task2Room : RoomCoord := (0, 0)

def task2Monster : Monster :=
  { pos := (5, 4)
    hp := 1
    kind := MonsterKind.chaser
    damage := 1
    loot := Loot.none
    room := task2Room }

def task2Chest : Chest :=
  { pos := (6, 4)
    loot := Loot.key 1
    opened := false
    room := task2Room }

def task2Exit : Exit :=
  { pos := (5, 4)
    targetRoom := (-1, 0)
    targetSpawn := (8, 4)
    kind := ExitKind.allMonstersAndKey 1 false
    sourceRoom := task2Room
    completesTask := true }

def task2Init : SymbolicState :=
  { player := (4, 4)
    room := task2Room
    chests := [task2Chest.pos]
    monsters := [task2Monster.pos]
    conditionalExits := [task2Exit.pos]
    health := some 5
    facing := Direction.east
    chestObjects := [task2Chest]
    monsterObjects := [task2Monster]
    exitObjects := [task2Exit] }

def task2AfterMonster : SymbolicState :=
  attackMonsterObjectState task2Init task2Monster

def task2AfterMove : SymbolicState :=
  { task2AfterMonster with
    player := nextPosition task2AfterMonster.player Action.right }

def task2AfterChest : SymbolicState :=
  openChestObjectState task2AfterMove task2Chest

def task2Final : SymbolicState :=
  useExitObjectState task2AfterChest task2Exit

def task2Plan : List Action :=
  [Action.pressA, Action.right, Action.pressA, Action.useExit]

theorem task2_safe_execution :
    SafeFullExec task2Init task2Plan task2Final := by
  change SafeFullExec task2Init
    [Action.pressA, Action.right, Action.pressA, Action.useExit] task2Final
  refine SafeFullExec.cons (t := task2AfterMonster)
    (by simp [FailedState, DeadState, TimedOut, task2Init]) ?_ ?_
  · exact FullEnvStep.attackMonsterObject (by
      simp [canAttackObject, task2Init, task2Monster, task2Room,
        inFront, facingTarget, nextPosition, actionOfDirection, delta,
        hasItem])
  · refine SafeFullExec.cons (t := task2AfterMove)
      (by
        simp [FailedState, DeadState, TimedOut, task2AfterMonster,
          attackMonsterObjectState, task2Init, task2Monster, applyLoot,
          damageMonsterObjectAt]) ?_ ?_
    · exact FullEnvStep.basic (EnvStep.moveSafe
        (by simp [movementActions])
        (by
          simp [isWalkable, terrainPassable, task2AfterMonster,
            attackMonsterObjectState, task2Init, task2Monster, task2Chest, applyLoot,
            damageMonsterObjectAt, nextPosition, delta, inBounds,
            boardWidth, boardHeight, activeBridges]))
    · refine SafeFullExec.cons (t := task2AfterChest)
        (by
          simp [FailedState, DeadState, TimedOut, task2AfterMove,
            task2AfterMonster, attackMonsterObjectState, task2Init,
            task2Monster, applyLoot, damageMonsterObjectAt,
            nextPosition, delta]) ?_ ?_
      · exact FullEnvStep.openChestObject (by
          simp [canOpenChestObject, task2AfterMove, task2AfterMonster,
            attackMonsterObjectState, task2Init, task2Monster, task2Chest,
            task2Room, applyLoot, damageMonsterObjectAt, inFront,
            facingTarget, nextPosition, actionOfDirection, delta])
      · refine SafeFullExec.cons (t := task2Final)
          (by
            simp [FailedState, DeadState, TimedOut, task2AfterChest,
              openChestObjectState, task2AfterMove, task2AfterMonster,
              attackMonsterObjectState, task2Init, task2Monster,
              task2Chest, applyLoot, damageMonsterObjectAt,
              nextPosition, delta]) ?_ ?_
        · exact FullEnvStep.useExitObject (by
            simp [canUseExitObject, task2AfterChest, openChestObjectState,
              task2AfterMove, task2AfterMonster, attackMonsterObjectState,
              task2Init, task2Monster, task2Chest, task2Exit, task2Room,
              applyLoot, damageMonsterObjectAt, nextPosition, delta,
              exitCondition])
        · exact SafeFullExec.nil (by
            simp [FailedState, DeadState, TimedOut, task2Final,
              useExitObjectState, task2AfterChest, openChestObjectState,
              task2AfterMove, task2AfterMonster, attackMonsterObjectState,
              task2Init, task2Monster, task2Chest, task2Exit, applyLoot,
              damageMonsterObjectAt, nextPosition, delta, keysAfterExit])

theorem task2_goal : Task2Goal task2Final := by
  simp [Task2Goal, task2Final, useExitObjectState, task2AfterChest,
    openChestObjectState, task2AfterMove, task2AfterMonster,
    attackMonsterObjectState, task2Init, task2Monster, task2Chest,
    task2Exit, applyLoot, damageMonsterObjectAt, nextPosition, delta,
    keysAfterExit]

/-!
【Task 2 必要条件反例】
未击杀怪物时，`allMonstersAndKey` 条件门即使已有钥匙也不可用。
-/
theorem task2_exit_blocked_while_monster_alive :
    ¬ exitCondition { task2Init with keys := 1 } task2Exit := by
  simp [exitCondition, task2Exit, task2Init]

/-! ## Task 3：穿过怪物房取钥匙，返回起点并打开东侧锁门 -/

def task3StartRoom : RoomCoord := (0, 0)
def task3HallRoom : RoomCoord := (-1, 0)
def task3KeyRoom : RoomCoord := (-2, 0)

def task3Monster : Monster :=
  { pos := (8, 3)
    hp := 1
    kind := MonsterKind.chaser
    damage := 1
    loot := Loot.none
    room := task3HallRoom }

def task3Chest : Chest :=
  { pos := (7, 4)
    loot := Loot.key 1
    opened := false
    room := task3KeyRoom }

def task3StartToHall : Exit :=
  { pos := (0, 3)
    targetRoom := task3HallRoom
    targetSpawn := (9, 3)
    kind := ExitKind.normal
    sourceRoom := task3StartRoom }

def task3HallToKey : Exit :=
  { pos := (9, 3)
    targetRoom := task3KeyRoom
    targetSpawn := (8, 4)
    kind := ExitKind.normal
    sourceRoom := task3HallRoom }

def task3KeyToHall : Exit :=
  { pos := (8, 4)
    targetRoom := task3HallRoom
    targetSpawn := (9, 3)
    kind := ExitKind.normal
    sourceRoom := task3KeyRoom }

def task3HallToStart : Exit :=
  { pos := (9, 3)
    targetRoom := task3StartRoom
    targetSpawn := (0, 3)
    kind := ExitKind.normal
    sourceRoom := task3HallRoom }

def task3FinalExit : Exit :=
  { pos := (0, 3)
    targetRoom := (1, 0)
    targetSpawn := (1, 3)
    kind := ExitKind.lockedKey 1 true
    sourceRoom := task3StartRoom
    completesTask := true }

def task3Exits : List Exit :=
  [task3StartToHall, task3HallToKey, task3KeyToHall,
    task3HallToStart, task3FinalExit]

def task3Init : SymbolicState :=
  { player := (0, 3)
    room := task3StartRoom
    chests := [task3Chest.pos]
    monsters := [task3Monster.pos]
    normalExits := [task3StartToHall.pos, task3HallToKey.pos,
      task3KeyToHall.pos, task3HallToStart.pos]
    lockedExits := [task3FinalExit.pos]
    health := some 5
    facing := Direction.west
    chestObjects := [task3Chest]
    monsterObjects := [task3Monster]
    exitObjects := task3Exits }

def task3InHall : SymbolicState :=
  useExitObjectState task3Init task3StartToHall

def task3AfterMonster : SymbolicState :=
  attackMonsterObjectState task3InHall task3Monster

def task3InKeyRoom : SymbolicState :=
  useExitObjectState task3AfterMonster task3HallToKey

def task3AfterChest : SymbolicState :=
  openChestObjectState task3InKeyRoom task3Chest

def task3BackInHall : SymbolicState :=
  useExitObjectState task3AfterChest task3KeyToHall

def task3BackAtStart : SymbolicState :=
  useExitObjectState task3BackInHall task3HallToStart

def task3Final : SymbolicState :=
  useExitObjectState task3BackAtStart task3FinalExit

def task3Plan : List Action :=
  [Action.useExit, Action.pressA, Action.useExit, Action.pressA,
    Action.useExit, Action.useExit, Action.useExit]

theorem task3_safe_execution :
    SafeFullExec task3Init task3Plan task3Final := by
  change SafeFullExec task3Init
    [Action.useExit, Action.pressA, Action.useExit, Action.pressA,
      Action.useExit, Action.useExit, Action.useExit] task3Final
  refine SafeFullExec.cons (t := task3InHall)
    (by simp [FailedState, DeadState, TimedOut, task3Init]) ?_ ?_
  · exact FullEnvStep.useExitObject (by
      simp [canUseExitObject, task3Init, task3StartToHall, task3Exits,
        task3StartRoom, task3HallRoom, exitCondition])
  · refine SafeFullExec.cons (t := task3AfterMonster)
      (by
        simp [FailedState, DeadState, TimedOut, task3InHall,
          useExitObjectState, task3Init, task3StartToHall,
          keysAfterExit]) ?_ ?_
    · exact FullEnvStep.attackMonsterObject (by
        simp [canAttackObject, task3InHall, useExitObjectState, task3Init,
          task3StartToHall, task3Monster, task3StartRoom, task3HallRoom,
          keysAfterExit, inFront, facingTarget, nextPosition,
          actionOfDirection, delta, hasItem])
    · refine SafeFullExec.cons (t := task3InKeyRoom)
        (by
          simp [FailedState, DeadState, TimedOut, task3AfterMonster,
            attackMonsterObjectState, task3InHall, useExitObjectState,
            task3Init, task3StartToHall, task3Monster, applyLoot,
            damageMonsterObjectAt, keysAfterExit]) ?_ ?_
      · exact FullEnvStep.useExitObject (by
          simp [canUseExitObject, task3AfterMonster,
            attackMonsterObjectState, task3InHall, useExitObjectState,
            task3Init, task3StartToHall, task3Monster, task3HallToKey,
            task3Exits, task3StartRoom, task3HallRoom, task3KeyRoom,
            applyLoot, damageMonsterObjectAt, keysAfterExit,
            exitCondition])
      · refine SafeFullExec.cons (t := task3AfterChest)
          (by
            simp [FailedState, DeadState, TimedOut, task3InKeyRoom,
              useExitObjectState, task3AfterMonster,
              attackMonsterObjectState, task3InHall, task3Init,
              task3StartToHall, task3HallToKey, task3Monster,
              applyLoot, damageMonsterObjectAt, keysAfterExit]) ?_ ?_
        · exact FullEnvStep.openChestObject (by
            simp [canOpenChestObject, task3InKeyRoom,
              useExitObjectState, task3AfterMonster,
              attackMonsterObjectState, task3InHall, task3Init,
              task3StartToHall, task3HallToKey, task3Monster,
              task3Chest, task3StartRoom, task3HallRoom, task3KeyRoom,
              applyLoot, damageMonsterObjectAt, keysAfterExit,
              inFront, facingTarget, nextPosition, actionOfDirection,
              delta])
        · refine SafeFullExec.cons (t := task3BackInHall)
            (by
              simp [FailedState, DeadState, TimedOut, task3AfterChest,
                openChestObjectState, task3InKeyRoom,
                useExitObjectState, task3AfterMonster,
                attackMonsterObjectState, task3InHall, task3Init,
                task3StartToHall, task3HallToKey, task3Monster,
                task3Chest, applyLoot, damageMonsterObjectAt,
                keysAfterExit]) ?_ ?_
          · exact FullEnvStep.useExitObject (by
              simp [canUseExitObject, task3AfterChest,
                openChestObjectState, task3InKeyRoom,
                useExitObjectState, task3AfterMonster,
                attackMonsterObjectState, task3InHall, task3Init,
                task3StartToHall, task3HallToKey, task3KeyToHall,
                task3Monster, task3Chest, task3Exits, task3StartRoom,
                task3HallRoom, task3KeyRoom, applyLoot,
                damageMonsterObjectAt, keysAfterExit, exitCondition])
          · refine SafeFullExec.cons (t := task3BackAtStart)
              (by
                simp [FailedState, DeadState, TimedOut,
                  task3BackInHall, useExitObjectState, task3AfterChest,
                  openChestObjectState, task3InKeyRoom,
                  task3AfterMonster, attackMonsterObjectState,
                  task3InHall, task3Init, task3StartToHall,
                  task3HallToKey, task3KeyToHall, task3Monster,
                  task3Chest, applyLoot, damageMonsterObjectAt,
                  keysAfterExit]) ?_ ?_
            · exact FullEnvStep.useExitObject (by
                simp [canUseExitObject, task3BackInHall,
                  useExitObjectState, task3AfterChest,
                  openChestObjectState, task3InKeyRoom,
                  task3AfterMonster, attackMonsterObjectState,
                  task3InHall, task3Init, task3StartToHall,
                  task3HallToKey, task3KeyToHall, task3HallToStart,
                  task3Monster, task3Chest, task3Exits,
                  task3StartRoom, task3HallRoom, task3KeyRoom,
                  applyLoot, damageMonsterObjectAt, keysAfterExit,
                  exitCondition])
            · refine SafeFullExec.cons (t := task3Final)
                (by
                  simp [FailedState, DeadState, TimedOut,
                    task3BackAtStart, useExitObjectState,
                    task3BackInHall, task3AfterChest,
                    openChestObjectState, task3InKeyRoom,
                    task3AfterMonster, attackMonsterObjectState,
                    task3InHall, task3Init, task3StartToHall,
                    task3HallToKey, task3KeyToHall, task3HallToStart,
                    task3Monster, task3Chest, applyLoot,
                    damageMonsterObjectAt, keysAfterExit]) ?_ ?_
              · exact FullEnvStep.useExitObject (by
                  simp [canUseExitObject, task3BackAtStart,
                    useExitObjectState, task3BackInHall,
                    task3AfterChest, openChestObjectState,
                    task3InKeyRoom, task3AfterMonster,
                    attackMonsterObjectState, task3InHall, task3Init,
                    task3StartToHall, task3HallToKey, task3KeyToHall,
                    task3HallToStart, task3FinalExit, task3Monster,
                    task3Chest, task3Exits, task3StartRoom,
                    task3HallRoom, task3KeyRoom, applyLoot,
                    damageMonsterObjectAt, keysAfterExit,
                    exitCondition])
              · exact SafeFullExec.nil (by
                  simp [FailedState, DeadState, TimedOut, task3Final,
                    useExitObjectState, task3BackAtStart,
                    task3BackInHall, task3AfterChest,
                    openChestObjectState, task3InKeyRoom,
                    task3AfterMonster, attackMonsterObjectState,
                    task3InHall, task3Init, task3StartToHall,
                    task3HallToKey, task3KeyToHall, task3HallToStart,
                    task3FinalExit, task3Monster, task3Chest,
                    applyLoot, damageMonsterObjectAt, keysAfterExit])

theorem task3_goal : Task3Goal task3Final := by
  simp [Task3Goal, task3Final, useExitObjectState, task3BackAtStart,
    task3BackInHall, task3AfterChest, openChestObjectState,
    task3InKeyRoom, task3AfterMonster, attackMonsterObjectState,
    task3InHall, task3Init, task3StartToHall, task3HallToKey,
    task3KeyToHall, task3HallToStart, task3FinalExit, task3Monster,
    task3Chest, applyLoot, damageMonsterObjectAt, keysAfterExit]

theorem task3_final_exit_blocked_without_key :
    ¬ exitCondition { task3BackAtStart with keys := 0 } task3FinalExit := by
  simp [exitCondition, task3FinalExit]

/-! ## Task 4：旋转桥、钥匙、剑、守卫与最终宝箱 -/

def task4WestRoom : RoomCoord := (0, 0)
def task4CenterRoom : RoomCoord := (1, 0)
def task4NorthRoom : RoomCoord := (1, -1)
def task4EastRoom : RoomCoord := (2, 0)
def task4SouthRoom : RoomCoord := (1, 1)

def task4KeyChest : Chest :=
  { pos := (3, 4), loot := Loot.key 1, opened := false,
    room := task4NorthRoom }

def task4SwordChest : Chest :=
  { pos := (4, 3), loot := Loot.item Item.sword, opened := false,
    room := task4EastRoom }

def task4FinalChest : Chest :=
  { pos := (4, 5), loot := Loot.gold 1, opened := false,
    room := task4CenterRoom, completesTask := true }

def task4Guardian : Monster :=
  { pos := (4, 5), hp := 1, kind := MonsterKind.guardian,
    damage := 1, loot := Loot.none, room := task4SouthRoom }

def task4WestToCenter : Exit :=
  { pos := (9, 4), targetRoom := task4CenterRoom,
    targetSpawn := (4, 0), kind := ExitKind.normal,
    sourceRoom := task4WestRoom }

def task4CenterToNorth : Exit :=
  { pos := (4, 0), targetRoom := task4NorthRoom,
    targetSpawn := (4, 4), kind := ExitKind.normal,
    sourceRoom := task4CenterRoom }

def task4NorthToCenter : Exit :=
  { pos := (4, 4), targetRoom := task4CenterRoom,
    targetSpawn := (9, 4), kind := ExitKind.normal,
    sourceRoom := task4NorthRoom }

def task4CenterToEast : Exit :=
  { pos := (9, 4), targetRoom := task4EastRoom,
    targetSpawn := (5, 3), kind := ExitKind.lockedKey 1 false,
    sourceRoom := task4CenterRoom }

def task4EastToCenter : Exit :=
  { pos := (5, 3), targetRoom := task4CenterRoom,
    targetSpawn := (4, 4), kind := ExitKind.normal,
    sourceRoom := task4EastRoom }

def task4CenterToSouth : Exit :=
  { pos := (4, 4), targetRoom := task4SouthRoom,
    targetSpawn := (5, 5), kind := ExitKind.normal,
    sourceRoom := task4CenterRoom }

def task4SouthToCenter : Exit :=
  { pos := (5, 5), targetRoom := task4CenterRoom,
    targetSpawn := (5, 5), kind := ExitKind.normal,
    sourceRoom := task4SouthRoom }

def task4Exits : List Exit :=
  [task4WestToCenter, task4CenterToNorth, task4NorthToCenter,
    task4CenterToEast, task4EastToCenter, task4CenterToSouth,
    task4SouthToCenter]

def task4Init : SymbolicState :=
  { player := (9, 4)
    room := task4WestRoom
    chests := [task4KeyChest.pos, task4SwordChest.pos, task4FinalChest.pos]
    monsters := [task4Guardian.pos]
    normalExits := [task4WestToCenter.pos, task4CenterToNorth.pos,
      task4NorthToCenter.pos, task4EastToCenter.pos,
      task4CenterToSouth.pos, task4SouthToCenter.pos]
    lockedExits := [task4CenterToEast.pos]
    switches := [(9, 4), (4, 4)]
    switchLocations := [globalize task4WestRoom (9, 4),
      globalize task4CenterRoom (4, 4)]
    bridgeState := BridgeState.northSouth
    health := some 5
    facing := Direction.west
    items := [Item.shield]
    hasSword := false
    hasShield := true
    chestObjects := [task4KeyChest, task4SwordChest, task4FinalChest]
    monsterObjects := [task4Guardian]
    exitObjects := task4Exits }

def task4AfterFirstSwitch : SymbolicState :=
  { task4Init with
    bridgeState := toggleBridgeState task4Init.bridgeState
    switchesActivated := task4Init.switchesActivated + 1 }

def task4InCenter : SymbolicState :=
  useExitObjectState task4AfterFirstSwitch task4WestToCenter

def task4InNorth : SymbolicState :=
  useExitObjectState task4InCenter task4CenterToNorth

def task4AfterKey : SymbolicState :=
  openChestObjectState task4InNorth task4KeyChest

def task4BackForEast : SymbolicState :=
  useExitObjectState task4AfterKey task4NorthToCenter

def task4InEast : SymbolicState :=
  useExitObjectState task4BackForEast task4CenterToEast

def task4AfterSword : SymbolicState :=
  openChestObjectState task4InEast task4SwordChest

def task4AtCenterSwitch : SymbolicState :=
  useExitObjectState task4AfterSword task4EastToCenter

def task4AfterSecondSwitch : SymbolicState :=
  { task4AtCenterSwitch with
    bridgeState := toggleBridgeState task4AtCenterSwitch.bridgeState
    switchesActivated := task4AtCenterSwitch.switchesActivated + 1 }

def task4InSouth : SymbolicState :=
  useExitObjectState task4AfterSecondSwitch task4CenterToSouth

def task4AfterGuardian : SymbolicState :=
  attackMonsterObjectState task4InSouth task4Guardian

def task4AtFinalChest : SymbolicState :=
  useExitObjectState task4AfterGuardian task4SouthToCenter

def task4Final : SymbolicState :=
  openChestObjectState task4AtFinalChest task4FinalChest

def task4Plan : List Action :=
  [Action.pressA, Action.useExit, Action.useExit, Action.pressA,
    Action.useExit, Action.useExit, Action.pressA, Action.useExit,
    Action.pressA, Action.useExit, Action.pressA, Action.useExit,
    Action.pressA]

private theorem task4_step_switch1 :
    FullEnvStep task4Init Action.pressA task4AfterFirstSwitch :=
  FullEnvStep.pressSwitch (by simp [task4Init])

private theorem task4_step_to_center :
    FullEnvStep task4AfterFirstSwitch Action.useExit task4InCenter :=
  FullEnvStep.useExitObject (by
    simp [canUseExitObject, task4AfterFirstSwitch, task4Init,
      task4WestToCenter, task4Exits, task4WestRoom, task4CenterRoom,
      exitCondition])

private theorem task4_step_to_north :
    FullEnvStep task4InCenter Action.useExit task4InNorth :=
  FullEnvStep.useExitObject (by
    simp [canUseExitObject, task4InCenter, useExitObjectState,
      task4AfterFirstSwitch, task4Init, task4WestToCenter,
      task4CenterToNorth, task4Exits, task4WestRoom,
      task4CenterRoom, task4NorthRoom, keysAfterExit, exitCondition])

private theorem task4_step_open_key :
    FullEnvStep task4InNorth Action.pressA task4AfterKey :=
  FullEnvStep.openChestObject (by
    simp [canOpenChestObject, task4InNorth, useExitObjectState,
      task4InCenter, task4AfterFirstSwitch, task4Init,
      task4WestToCenter, task4CenterToNorth, task4KeyChest,
      task4WestRoom, task4CenterRoom, task4NorthRoom, keysAfterExit,
      inFront, facingTarget, nextPosition, actionOfDirection, delta])

private theorem task4_step_back_for_east :
    FullEnvStep task4AfterKey Action.useExit task4BackForEast :=
  FullEnvStep.useExitObject (by
    simp [canUseExitObject, task4AfterKey, openChestObjectState,
      useExitObjectState,
      task4InNorth, task4InCenter, task4AfterFirstSwitch, task4Init,
      task4WestToCenter, task4CenterToNorth, task4NorthToCenter,
      task4KeyChest, task4Exits, task4WestRoom, task4CenterRoom,
      task4NorthRoom, applyLoot, keysAfterExit, exitCondition])

private theorem task4_step_to_east :
    FullEnvStep task4BackForEast Action.useExit task4InEast :=
  FullEnvStep.useExitObject (by
    simp [canUseExitObject, task4BackForEast, useExitObjectState,
      task4AfterKey, openChestObjectState, task4InNorth, task4InCenter,
      task4AfterFirstSwitch, task4Init, task4WestToCenter,
      task4CenterToNorth, task4NorthToCenter, task4CenterToEast,
      task4KeyChest, task4Exits, task4WestRoom, task4CenterRoom,
      task4NorthRoom, task4EastRoom, applyLoot, keysAfterExit,
      exitCondition])

private theorem task4_step_open_sword :
    FullEnvStep task4InEast Action.pressA task4AfterSword :=
  FullEnvStep.openChestObject (by
    simp [canOpenChestObject, task4InEast, useExitObjectState,
      task4BackForEast, task4AfterKey, openChestObjectState,
      task4InNorth, task4InCenter, task4AfterFirstSwitch, task4Init,
      task4WestToCenter, task4CenterToNorth, task4NorthToCenter,
      task4CenterToEast, task4KeyChest, task4SwordChest,
      task4WestRoom, task4CenterRoom, task4NorthRoom, task4EastRoom,
      applyLoot, removeChestObjectAt, keysAfterExit, inFront,
      facingTarget, nextPosition,
      actionOfDirection, delta])

private theorem task4_step_back_to_switch :
    FullEnvStep task4AfterSword Action.useExit task4AtCenterSwitch :=
  FullEnvStep.useExitObject (by
    simp [canUseExitObject, task4AfterSword, openChestObjectState,
      task4InEast, useExitObjectState, task4BackForEast, task4AfterKey,
      task4InNorth, task4InCenter, task4AfterFirstSwitch, task4Init,
      task4WestToCenter, task4CenterToNorth, task4NorthToCenter,
      task4CenterToEast, task4EastToCenter, task4KeyChest,
      task4SwordChest, task4Exits, task4WestRoom, task4CenterRoom,
      task4NorthRoom, task4EastRoom, applyLoot, keysAfterExit,
      exitCondition])

private theorem task4_step_switch2 :
    FullEnvStep task4AtCenterSwitch Action.pressA task4AfterSecondSwitch :=
  FullEnvStep.pressSwitch (by
    simp [task4AtCenterSwitch, useExitObjectState, task4AfterSword,
      openChestObjectState, task4InEast, task4BackForEast, task4AfterKey,
      task4InNorth, task4InCenter, task4AfterFirstSwitch, task4Init,
      task4WestToCenter, task4CenterToNorth, task4NorthToCenter,
      task4CenterToEast, task4EastToCenter, task4KeyChest,
      task4SwordChest, applyLoot, keysAfterExit])

private theorem task4_step_to_south :
    FullEnvStep task4AfterSecondSwitch Action.useExit task4InSouth :=
  FullEnvStep.useExitObject (by
    simp [canUseExitObject, task4AfterSecondSwitch,
      task4AtCenterSwitch, useExitObjectState, task4AfterSword,
      openChestObjectState, task4InEast, task4BackForEast,
      task4AfterKey, task4InNorth, task4InCenter,
      task4AfterFirstSwitch, task4Init, task4WestToCenter,
      task4CenterToNorth, task4NorthToCenter, task4CenterToEast,
      task4EastToCenter, task4CenterToSouth, task4KeyChest,
      task4SwordChest, task4Exits, task4WestRoom, task4CenterRoom,
      task4NorthRoom, task4EastRoom, task4SouthRoom, applyLoot,
      keysAfterExit, exitCondition])

private theorem task4_step_kill_guardian :
    FullEnvStep task4InSouth Action.pressA task4AfterGuardian :=
  FullEnvStep.attackMonsterObject (by
    simp [canAttackObject, task4InSouth, useExitObjectState,
      task4AfterSecondSwitch, task4AtCenterSwitch, task4AfterSword,
      openChestObjectState, task4InEast, task4BackForEast,
      task4AfterKey, task4InNorth, task4InCenter,
      task4AfterFirstSwitch, task4Init, task4WestToCenter,
      task4CenterToNorth, task4NorthToCenter, task4CenterToEast,
      task4EastToCenter, task4CenterToSouth, task4KeyChest,
      task4SwordChest, task4Guardian, task4WestRoom, task4CenterRoom,
      task4NorthRoom, task4EastRoom, task4SouthRoom, applyLoot,
      keysAfterExit, inFront, facingTarget, nextPosition,
      actionOfDirection, delta, hasItem])

private theorem task4_step_back_to_final :
    FullEnvStep task4AfterGuardian Action.useExit task4AtFinalChest :=
  FullEnvStep.useExitObject (by
    simp [canUseExitObject, task4AfterGuardian,
      attackMonsterObjectState, task4InSouth, useExitObjectState,
      task4AfterSecondSwitch, task4AtCenterSwitch, task4AfterSword,
      openChestObjectState, task4InEast, task4BackForEast,
      task4AfterKey, task4InNorth, task4InCenter,
      task4AfterFirstSwitch, task4Init, task4WestToCenter,
      task4CenterToNorth, task4NorthToCenter, task4CenterToEast,
      task4EastToCenter, task4CenterToSouth, task4SouthToCenter,
      task4KeyChest, task4SwordChest, task4Guardian, task4Exits,
      task4WestRoom, task4CenterRoom, task4NorthRoom, task4EastRoom,
      task4SouthRoom, applyLoot, damageMonsterObjectAt,
      keysAfterExit, exitCondition])

private theorem task4_step_open_final :
    FullEnvStep task4AtFinalChest Action.pressA task4Final :=
  FullEnvStep.openChestObject (by
    simp [canOpenChestObject, task4AtFinalChest, useExitObjectState,
      task4AfterGuardian, attackMonsterObjectState, task4InSouth,
      task4AfterSecondSwitch, task4AtCenterSwitch, task4AfterSword,
      openChestObjectState, task4InEast, task4BackForEast,
      task4AfterKey, task4InNorth, task4InCenter,
      task4AfterFirstSwitch, task4Init, task4WestToCenter,
      task4CenterToNorth, task4NorthToCenter, task4CenterToEast,
      task4EastToCenter, task4CenterToSouth, task4SouthToCenter,
      task4KeyChest, task4SwordChest, task4FinalChest,
      task4Guardian, task4WestRoom, task4CenterRoom, task4NorthRoom,
      task4EastRoom, task4SouthRoom, applyLoot, removeChestObjectAt,
      damageMonsterObjectAt, keysAfterExit, inFront, facingTarget,
      nextPosition, actionOfDirection, delta])

theorem task4_safe_execution :
    SafeFullExec task4Init task4Plan task4Final := by
  change SafeFullExec task4Init
    [Action.pressA, Action.useExit, Action.useExit, Action.pressA,
      Action.useExit, Action.useExit, Action.pressA, Action.useExit,
      Action.pressA, Action.useExit, Action.pressA, Action.useExit,
      Action.pressA] task4Final
  refine SafeFullExec.cons (t := task4AfterFirstSwitch) (by
    simp [FailedState, DeadState, TimedOut, task4Init]) task4_step_switch1 ?_
  refine SafeFullExec.cons (t := task4InCenter) (by
    simp [FailedState, DeadState, TimedOut, task4AfterFirstSwitch,
      task4Init]) task4_step_to_center ?_
  refine SafeFullExec.cons (t := task4InNorth) (by
    simp [FailedState, DeadState, TimedOut, task4InCenter,
      useExitObjectState, task4AfterFirstSwitch, task4Init,
      task4WestToCenter, keysAfterExit]) task4_step_to_north ?_
  refine SafeFullExec.cons (t := task4AfterKey) (by
    simp [FailedState, DeadState, TimedOut, task4InNorth,
      useExitObjectState, task4InCenter, task4AfterFirstSwitch,
      task4Init, task4WestToCenter, task4CenterToNorth,
      keysAfterExit]) task4_step_open_key ?_
  refine SafeFullExec.cons (t := task4BackForEast) (by
    simp [FailedState, DeadState, TimedOut, task4AfterKey,
      openChestObjectState, task4InNorth, useExitObjectState,
      task4InCenter, task4AfterFirstSwitch, task4Init,
      task4WestToCenter, task4CenterToNorth, task4KeyChest,
      applyLoot, keysAfterExit]) task4_step_back_for_east ?_
  refine SafeFullExec.cons (t := task4InEast) (by
    simp [FailedState, DeadState, TimedOut, task4BackForEast,
      useExitObjectState, task4AfterKey, openChestObjectState,
      task4InNorth, task4InCenter, task4AfterFirstSwitch, task4Init,
      task4WestToCenter, task4CenterToNorth, task4NorthToCenter,
      task4KeyChest, applyLoot, keysAfterExit]) task4_step_to_east ?_
  refine SafeFullExec.cons (t := task4AfterSword) (by
    simp [FailedState, DeadState, TimedOut, task4InEast,
      useExitObjectState, task4BackForEast, task4AfterKey,
      openChestObjectState, task4InNorth, task4InCenter,
      task4AfterFirstSwitch, task4Init, task4WestToCenter,
      task4CenterToNorth, task4NorthToCenter, task4CenterToEast,
      task4KeyChest, applyLoot, keysAfterExit]) task4_step_open_sword ?_
  refine SafeFullExec.cons (t := task4AtCenterSwitch) (by
    simp [FailedState, DeadState, TimedOut, task4AfterSword,
      openChestObjectState, task4InEast, useExitObjectState,
      task4BackForEast, task4AfterKey, task4InNorth, task4InCenter,
      task4AfterFirstSwitch, task4Init, task4WestToCenter,
      task4CenterToNorth, task4NorthToCenter, task4CenterToEast,
      task4KeyChest, task4SwordChest, applyLoot,
      keysAfterExit]) task4_step_back_to_switch ?_
  refine SafeFullExec.cons (t := task4AfterSecondSwitch) (by
    simp [FailedState, DeadState, TimedOut, task4AtCenterSwitch,
      useExitObjectState, task4AfterSword, openChestObjectState,
      task4InEast, task4BackForEast, task4AfterKey, task4InNorth,
      task4InCenter, task4AfterFirstSwitch, task4Init,
      task4WestToCenter, task4CenterToNorth, task4NorthToCenter,
      task4CenterToEast, task4EastToCenter, task4KeyChest,
      task4SwordChest, applyLoot, keysAfterExit]) task4_step_switch2 ?_
  refine SafeFullExec.cons (t := task4InSouth) (by
    simp [FailedState, DeadState, TimedOut, task4AfterSecondSwitch,
      task4AtCenterSwitch, useExitObjectState, task4AfterSword,
      openChestObjectState, task4InEast, task4BackForEast,
      task4AfterKey, task4InNorth, task4InCenter,
      task4AfterFirstSwitch, task4Init, task4WestToCenter,
      task4CenterToNorth, task4NorthToCenter, task4CenterToEast,
      task4EastToCenter, task4KeyChest, task4SwordChest,
      applyLoot, keysAfterExit]) task4_step_to_south ?_
  refine SafeFullExec.cons (t := task4AfterGuardian) (by
    simp [FailedState, DeadState, TimedOut, task4InSouth,
      useExitObjectState, task4AfterSecondSwitch, task4AtCenterSwitch,
      task4AfterSword, openChestObjectState, task4InEast,
      task4BackForEast, task4AfterKey, task4InNorth, task4InCenter,
      task4AfterFirstSwitch, task4Init, task4WestToCenter,
      task4CenterToNorth, task4NorthToCenter, task4CenterToEast,
      task4EastToCenter, task4CenterToSouth, task4KeyChest,
      task4SwordChest, applyLoot, keysAfterExit]) task4_step_kill_guardian ?_
  refine SafeFullExec.cons (t := task4AtFinalChest) (by
    simp [FailedState, DeadState, TimedOut, task4AfterGuardian,
      attackMonsterObjectState, task4InSouth, useExitObjectState,
      task4AfterSecondSwitch, task4AtCenterSwitch, task4AfterSword,
      openChestObjectState, task4InEast, task4BackForEast,
      task4AfterKey, task4InNorth, task4InCenter,
      task4AfterFirstSwitch, task4Init, task4WestToCenter,
      task4CenterToNorth, task4NorthToCenter, task4CenterToEast,
      task4EastToCenter, task4CenterToSouth, task4KeyChest,
      task4SwordChest, task4Guardian, applyLoot,
      damageMonsterObjectAt, keysAfterExit]) task4_step_back_to_final ?_
  refine SafeFullExec.cons (t := task4Final) (by
    simp [FailedState, DeadState, TimedOut, task4AtFinalChest,
      useExitObjectState, task4AfterGuardian,
      attackMonsterObjectState, task4InSouth, task4AfterSecondSwitch,
      task4AtCenterSwitch, task4AfterSword, openChestObjectState,
      task4InEast, task4BackForEast, task4AfterKey, task4InNorth,
      task4InCenter, task4AfterFirstSwitch, task4Init,
      task4WestToCenter, task4CenterToNorth, task4NorthToCenter,
      task4CenterToEast, task4EastToCenter, task4CenterToSouth,
      task4SouthToCenter, task4KeyChest, task4SwordChest,
      task4Guardian, applyLoot, damageMonsterObjectAt,
      keysAfterExit]) task4_step_open_final ?_
  exact SafeFullExec.nil (by
    simp [FailedState, DeadState, TimedOut, task4Final,
      openChestObjectState, task4AtFinalChest, useExitObjectState,
      task4AfterGuardian, attackMonsterObjectState, task4InSouth,
      task4AfterSecondSwitch, task4AtCenterSwitch, task4AfterSword,
      task4InEast, task4BackForEast, task4AfterKey, task4InNorth,
      task4InCenter, task4AfterFirstSwitch, task4Init,
      task4WestToCenter, task4CenterToNorth, task4NorthToCenter,
      task4CenterToEast, task4EastToCenter, task4CenterToSouth,
      task4SouthToCenter, task4KeyChest, task4SwordChest,
      task4FinalChest, task4Guardian, applyLoot,
      damageMonsterObjectAt, keysAfterExit])

theorem task4_goal : Task4Goal task4Final := by
  simp [Task4Goal, task4Final, openChestObjectState,
    task4AtFinalChest, useExitObjectState, task4AfterGuardian,
    attackMonsterObjectState, task4InSouth, task4AfterSecondSwitch,
    task4AtCenterSwitch, task4AfterSword, task4InEast,
    task4BackForEast, task4AfterKey, task4InNorth, task4InCenter,
    task4AfterFirstSwitch, task4Init, task4WestToCenter,
    task4CenterToNorth, task4NorthToCenter, task4CenterToEast,
    task4EastToCenter, task4CenterToSouth, task4SouthToCenter,
    task4KeyChest, task4SwordChest, task4FinalChest, task4Guardian,
    applyLoot, damageMonsterObjectAt, keysAfterExit,
    toggleBridgeState]

theorem task4_east_gate_does_not_consume_key :
    (useExitObjectState task4BackForEast task4CenterToEast).keys =
      task4BackForEast.keys := by
  simp [useExitObjectState, keysAfterExit, task4CenterToEast]

theorem task4_guardian_requires_sword
    (state : SymbolicState)
    (hnoSword : state.hasSword = false)
    (hnoItem : Item.sword ∉ state.items) :
    ¬ canAttackObject state task4Guardian := by
  simp [canAttackObject, hasItem, hnoSword, hnoItem]

/-! ## Task 5：探索四房间并打开全部宝箱 -/

def task5CenterRoom : RoomCoord := (0, 0)
def task5WestRoom : RoomCoord := (-1, 0)
def task5SouthRoom : RoomCoord := (0, 1)
def task5EastRoom : RoomCoord := (1, 0)

def task5StartChest : Chest :=
  { pos := (4, 2), loot := Loot.gold 2, opened := false,
    room := task5CenterRoom }

def task5WestChest : Chest :=
  { pos := (7, 4), loot := Loot.gold 5, opened := false,
    room := task5WestRoom }

def task5SouthChest : Chest :=
  { pos := (7, 5), loot := Loot.key 1, opened := false,
    room := task5SouthRoom }

def task5EastChest : Chest :=
  { pos := (7, 1), loot := Loot.heal 1, opened := false,
    room := task5EastRoom, completesTask := true }

def task5WestMonster : Monster :=
  { pos := (7, 4), hp := 1, kind := MonsterKind.chaser,
    damage := 1, loot := Loot.none, room := task5WestRoom }

def task5CenterToWest : Exit :=
  { pos := (5, 2), targetRoom := task5WestRoom,
    targetSpawn := (8, 4), kind := ExitKind.normal,
    sourceRoom := task5CenterRoom }

def task5WestToCenter : Exit :=
  { pos := (8, 4), targetRoom := task5CenterRoom,
    targetSpawn := (4, 4), kind := ExitKind.normal,
    sourceRoom := task5WestRoom, revealedButtons := [(4, 4)] }

def task5CenterToSouth : Exit :=
  { pos := (4, 4), targetRoom := task5SouthRoom,
    targetSpawn := (8, 5), kind := ExitKind.buttonGate (4, 4),
    sourceRoom := task5CenterRoom }

def task5SouthToCenter : Exit :=
  { pos := (8, 5), targetRoom := task5CenterRoom,
    targetSpawn := (9, 4), kind := ExitKind.normal,
    sourceRoom := task5SouthRoom }

def task5CenterToEast : Exit :=
  { pos := (9, 4), targetRoom := task5EastRoom,
    targetSpawn := (8, 1), kind := ExitKind.lockedKey 1 true,
    sourceRoom := task5CenterRoom }

def task5Exits : List Exit :=
  [task5CenterToWest, task5WestToCenter, task5CenterToSouth,
    task5SouthToCenter, task5CenterToEast]

def task5Init : SymbolicState :=
  { player := (5, 2)
    room := task5CenterRoom
    chests := [task5StartChest.pos, task5WestChest.pos,
      task5SouthChest.pos, task5EastChest.pos]
    monsters := [task5WestMonster.pos]
    normalExits := [task5CenterToWest.pos, task5WestToCenter.pos,
      task5SouthToCenter.pos]
    lockedExits := [task5CenterToEast.pos]
    conditionalExits := [task5CenterToSouth.pos]
    buttonLocations := [globalize task5CenterRoom (4, 4)]
    health := some 5
    facing := Direction.west
    chestObjects := [task5StartChest, task5WestChest,
      task5SouthChest, task5EastChest]
    monsterObjects := [task5WestMonster]
    exitObjects := task5Exits }

def task5AfterStartChest : SymbolicState :=
  openChestObjectState task5Init task5StartChest

def task5InWest : SymbolicState :=
  useExitObjectState task5AfterStartChest task5CenterToWest

def task5AfterWestMonster : SymbolicState :=
  attackMonsterObjectState task5InWest task5WestMonster

def task5AfterWestChest : SymbolicState :=
  openChestObjectState task5AfterWestMonster task5WestChest

def task5BackAtButton : SymbolicState :=
  useExitObjectState task5AfterWestChest task5WestToCenter

def task5AfterButton : SymbolicState :=
  task5BackAtButton

def task5InSouth : SymbolicState :=
  useExitObjectState task5AfterButton task5CenterToSouth

def task5AfterSouthChest : SymbolicState :=
  openChestObjectState task5InSouth task5SouthChest

def task5BackAtEastGate : SymbolicState :=
  useExitObjectState task5AfterSouthChest task5SouthToCenter

def task5InEast : SymbolicState :=
  useExitObjectState task5BackAtEastGate task5CenterToEast

def task5Final : SymbolicState :=
  openChestObjectState task5InEast task5EastChest

def task5Plan : List Action :=
  [Action.pressA, Action.useExit, Action.pressA, Action.pressA,
    Action.useExit, Action.useExit, Action.pressA, Action.useExit,
    Action.useExit, Action.pressA]

private theorem task5_step_open_start :
    FullEnvStep task5Init Action.pressA task5AfterStartChest :=
  FullEnvStep.openChestObject (by
    simp [canOpenChestObject, task5Init, task5StartChest,
      task5CenterRoom, inFront, facingTarget, nextPosition,
      actionOfDirection, delta])

private theorem task5_step_to_west :
    FullEnvStep task5AfterStartChest Action.useExit task5InWest :=
  FullEnvStep.useExitObject (by
    simp [canUseExitObject, task5AfterStartChest, openChestObjectState,
      task5Init, task5StartChest, task5CenterToWest, task5Exits,
      task5CenterRoom, task5WestRoom, applyLoot,
      removeChestObjectAt, exitCondition])

private theorem task5_step_kill_west_monster :
    FullEnvStep task5InWest Action.pressA task5AfterWestMonster :=
  FullEnvStep.attackMonsterObject (by
    simp [canAttackObject, task5InWest, useExitObjectState,
      task5AfterStartChest, openChestObjectState, task5Init,
      task5StartChest, task5CenterToWest, task5WestMonster,
      task5CenterRoom, task5WestRoom, applyLoot, removeChestObjectAt,
      keysAfterExit, inFront, facingTarget, nextPosition,
      actionOfDirection, delta, hasItem])

private theorem task5_step_open_west :
    FullEnvStep task5AfterWestMonster Action.pressA task5AfterWestChest :=
  FullEnvStep.openChestObject (by
    simp [canOpenChestObject, task5AfterWestMonster,
      attackMonsterObjectState, task5InWest, useExitObjectState,
      task5AfterStartChest, openChestObjectState, task5Init,
      task5StartChest, task5WestChest, task5CenterToWest,
      task5WestMonster, task5CenterRoom, task5WestRoom, applyLoot,
      removeChestObjectAt, damageMonsterObjectAt, keysAfterExit,
      inFront, facingTarget, nextPosition, actionOfDirection, delta])

private theorem task5_step_back_to_button :
    FullEnvStep task5AfterWestChest Action.useExit task5BackAtButton :=
  FullEnvStep.useExitObject (by
    simp [canUseExitObject, task5AfterWestChest,
      openChestObjectState, task5AfterWestMonster,
      attackMonsterObjectState, task5InWest, useExitObjectState,
      task5AfterStartChest, task5Init, task5StartChest, task5WestChest,
      task5CenterToWest, task5WestToCenter, task5WestMonster,
      task5Exits, task5CenterRoom, task5WestRoom, applyLoot,
      removeChestObjectAt, damageMonsterObjectAt, keysAfterExit,
      exitCondition])

private theorem task5_step_to_south :
    FullEnvStep task5AfterButton Action.useExit task5InSouth :=
  FullEnvStep.useExitObject (by
    simp [canUseExitObject, task5AfterButton, task5BackAtButton,
      useExitObjectState, task5AfterWestChest, openChestObjectState,
      task5AfterWestMonster, attackMonsterObjectState, task5InWest,
      task5AfterStartChest, task5Init, task5StartChest, task5WestChest,
      task5CenterToWest, task5WestToCenter, task5CenterToSouth,
      task5WestMonster, task5Exits, task5CenterRoom, task5WestRoom,
      task5SouthRoom, applyLoot, removeChestObjectAt,
      damageMonsterObjectAt, keysAfterExit, exitCondition])

private theorem task5_step_open_south :
    FullEnvStep task5InSouth Action.pressA task5AfterSouthChest :=
  FullEnvStep.openChestObject (by
    simp [canOpenChestObject, task5InSouth, useExitObjectState,
      task5AfterButton, task5BackAtButton, task5AfterWestChest,
      openChestObjectState, task5AfterWestMonster,
      attackMonsterObjectState, task5InWest, task5AfterStartChest,
      task5Init, task5StartChest, task5WestChest, task5SouthChest,
      task5CenterToWest, task5WestToCenter, task5CenterToSouth,
      task5WestMonster, task5CenterRoom, task5WestRoom,
      task5SouthRoom, applyLoot, removeChestObjectAt,
      damageMonsterObjectAt, keysAfterExit, inFront, facingTarget,
      nextPosition, actionOfDirection, delta])

private theorem task5_step_back_to_east_gate :
    FullEnvStep task5AfterSouthChest Action.useExit task5BackAtEastGate :=
  FullEnvStep.useExitObject (by
    simp [canUseExitObject, task5AfterSouthChest,
      openChestObjectState, task5InSouth, useExitObjectState,
      task5AfterButton, task5BackAtButton, task5AfterWestChest,
      task5AfterWestMonster, attackMonsterObjectState, task5InWest,
      task5AfterStartChest, task5Init, task5StartChest, task5WestChest,
      task5SouthChest, task5CenterToWest, task5WestToCenter,
      task5CenterToSouth, task5SouthToCenter, task5WestMonster,
      task5Exits, task5CenterRoom, task5WestRoom, task5SouthRoom,
      applyLoot, removeChestObjectAt, damageMonsterObjectAt,
      keysAfterExit, exitCondition])

private theorem task5_step_to_east :
    FullEnvStep task5BackAtEastGate Action.useExit task5InEast :=
  FullEnvStep.useExitObject (by
    simp [canUseExitObject, task5BackAtEastGate, useExitObjectState,
      task5AfterSouthChest, openChestObjectState, task5InSouth,
      task5AfterButton, task5BackAtButton, task5AfterWestChest,
      task5AfterWestMonster, attackMonsterObjectState, task5InWest,
      task5AfterStartChest, task5Init, task5StartChest, task5WestChest,
      task5SouthChest, task5CenterToWest, task5WestToCenter,
      task5CenterToSouth, task5SouthToCenter, task5CenterToEast,
      task5WestMonster, task5Exits, task5CenterRoom, task5WestRoom,
      task5SouthRoom, task5EastRoom, applyLoot, removeChestObjectAt,
      damageMonsterObjectAt, keysAfterExit, exitCondition])

private theorem task5_step_open_east :
    FullEnvStep task5InEast Action.pressA task5Final :=
  FullEnvStep.openChestObject (by
    simp [canOpenChestObject, task5InEast, useExitObjectState,
      task5BackAtEastGate, task5AfterSouthChest,
      openChestObjectState, task5InSouth, task5AfterButton,
      task5BackAtButton, task5AfterWestChest, task5AfterWestMonster,
      attackMonsterObjectState, task5InWest, task5AfterStartChest,
      task5Init, task5StartChest, task5WestChest, task5SouthChest,
      task5EastChest, task5CenterToWest, task5WestToCenter,
      task5CenterToSouth, task5SouthToCenter, task5CenterToEast,
      task5WestMonster, task5CenterRoom, task5WestRoom,
      task5SouthRoom, task5EastRoom, applyLoot, removeChestObjectAt,
      damageMonsterObjectAt, keysAfterExit, inFront, facingTarget,
      nextPosition, actionOfDirection, delta])

theorem task5_safe_execution :
    SafeFullExec task5Init task5Plan task5Final := by
  change SafeFullExec task5Init
    [Action.pressA, Action.useExit, Action.pressA, Action.pressA,
      Action.useExit, Action.useExit, Action.pressA, Action.useExit,
      Action.useExit, Action.pressA] task5Final
  refine SafeFullExec.cons (t := task5AfterStartChest) (by
    simp [FailedState, DeadState, TimedOut, task5Init]) task5_step_open_start ?_
  refine SafeFullExec.cons (t := task5InWest) (by
    simp [FailedState, DeadState, TimedOut, task5AfterStartChest,
      openChestObjectState, task5Init, task5StartChest, applyLoot])
    task5_step_to_west ?_
  refine SafeFullExec.cons (t := task5AfterWestMonster) (by
    simp [FailedState, DeadState, TimedOut, task5InWest,
      useExitObjectState, task5AfterStartChest, openChestObjectState,
      task5Init, task5StartChest, task5CenterToWest, applyLoot,
      keysAfterExit]) task5_step_kill_west_monster ?_
  refine SafeFullExec.cons (t := task5AfterWestChest) (by
    simp [FailedState, DeadState, TimedOut, task5AfterWestMonster,
      attackMonsterObjectState, task5InWest, useExitObjectState,
      task5AfterStartChest, openChestObjectState, task5Init,
      task5StartChest, task5CenterToWest, task5WestMonster,
      applyLoot, damageMonsterObjectAt, keysAfterExit])
    task5_step_open_west ?_
  refine SafeFullExec.cons (t := task5BackAtButton) (by
    simp [FailedState, DeadState, TimedOut, task5AfterWestChest,
      openChestObjectState, task5AfterWestMonster,
      attackMonsterObjectState, task5InWest, useExitObjectState,
      task5AfterStartChest, task5Init, task5StartChest,
      task5WestChest, task5CenterToWest, task5WestMonster,
      applyLoot, damageMonsterObjectAt, keysAfterExit])
    task5_step_back_to_button ?_
  refine SafeFullExec.cons (t := task5InSouth) (by
    simp [FailedState, DeadState, TimedOut,
      task5BackAtButton, useExitObjectState, task5AfterWestChest,
      openChestObjectState, task5AfterWestMonster,
      attackMonsterObjectState, task5InWest, task5AfterStartChest,
      task5Init, task5StartChest, task5WestChest,
      task5CenterToWest, task5WestToCenter, task5WestMonster,
      applyLoot, damageMonsterObjectAt, keysAfterExit])
    task5_step_to_south ?_
  refine SafeFullExec.cons (t := task5AfterSouthChest) (by
    simp [FailedState, DeadState, TimedOut, task5InSouth,
      useExitObjectState, task5AfterButton, task5BackAtButton,
      task5AfterWestChest, openChestObjectState,
      task5AfterWestMonster, attackMonsterObjectState, task5InWest,
      task5AfterStartChest, task5Init, task5StartChest,
      task5WestChest, task5CenterToWest, task5WestToCenter,
      task5CenterToSouth, task5WestMonster, applyLoot,
      damageMonsterObjectAt, keysAfterExit]) task5_step_open_south ?_
  refine SafeFullExec.cons (t := task5BackAtEastGate) (by
    simp [FailedState, DeadState, TimedOut, task5AfterSouthChest,
      openChestObjectState, task5InSouth, useExitObjectState,
      task5AfterButton, task5BackAtButton, task5AfterWestChest,
      task5AfterWestMonster, attackMonsterObjectState, task5InWest,
      task5AfterStartChest, task5Init, task5StartChest,
      task5WestChest, task5SouthChest, task5CenterToWest,
      task5WestToCenter, task5CenterToSouth, task5WestMonster,
      applyLoot, damageMonsterObjectAt, keysAfterExit])
    task5_step_back_to_east_gate ?_
  refine SafeFullExec.cons (t := task5InEast) (by
    simp [FailedState, DeadState, TimedOut, task5BackAtEastGate,
      useExitObjectState, task5AfterSouthChest, openChestObjectState,
      task5InSouth, task5AfterButton, task5BackAtButton,
      task5AfterWestChest, task5AfterWestMonster,
      attackMonsterObjectState, task5InWest, task5AfterStartChest,
      task5Init, task5StartChest, task5WestChest, task5SouthChest,
      task5CenterToWest, task5WestToCenter, task5CenterToSouth,
      task5SouthToCenter, task5WestMonster, applyLoot,
      damageMonsterObjectAt, keysAfterExit]) task5_step_to_east ?_
  refine SafeFullExec.cons (t := task5Final) (by
    simp [FailedState, DeadState, TimedOut, task5InEast,
      useExitObjectState, task5BackAtEastGate, task5AfterSouthChest,
      openChestObjectState, task5InSouth, task5AfterButton,
      task5BackAtButton, task5AfterWestChest, task5AfterWestMonster,
      attackMonsterObjectState, task5InWest, task5AfterStartChest,
      task5Init, task5StartChest, task5WestChest, task5SouthChest,
      task5CenterToWest, task5WestToCenter, task5CenterToSouth,
      task5SouthToCenter, task5CenterToEast, task5WestMonster,
      applyLoot, damageMonsterObjectAt, keysAfterExit])
    task5_step_open_east ?_
  exact SafeFullExec.nil (by
    simp [FailedState, DeadState, TimedOut, task5Final,
      openChestObjectState, task5InEast, useExitObjectState,
      task5BackAtEastGate, task5AfterSouthChest, task5InSouth,
      task5AfterButton, task5BackAtButton, task5AfterWestChest,
      task5AfterWestMonster, attackMonsterObjectState, task5InWest,
      task5AfterStartChest, task5Init, task5StartChest,
      task5WestChest, task5SouthChest, task5EastChest,
      task5CenterToWest, task5WestToCenter, task5CenterToSouth,
      task5SouthToCenter, task5CenterToEast, task5WestMonster,
      applyLoot, healHealth, damageMonsterObjectAt, keysAfterExit])

theorem task5_goal : Task5Goal task5Final := by
  simp [Task5Goal, task5Final, openChestObjectState, task5InEast,
    useExitObjectState, task5BackAtEastGate, task5AfterSouthChest,
    task5InSouth, task5AfterButton, task5BackAtButton,
    task5AfterWestChest, task5AfterWestMonster,
    attackMonsterObjectState, task5InWest, task5AfterStartChest,
    task5Init, task5StartChest, task5WestChest, task5SouthChest,
    task5EastChest, task5CenterToWest, task5WestToCenter,
    task5CenterToSouth, task5SouthToCenter, task5CenterToEast,
    task5WestMonster, applyLoot, healHealth, removeChestObjectAt,
    damageMonsterObjectAt, keysAfterExit]

theorem task5_button_triggered_on_entry :
    (4, 4) ∈ task5BackAtButton.pressedButtons ∧
      task5BackAtButton.buttonsPressed = 1 := by
  simp [task5BackAtButton, useExitObjectState, task5AfterWestChest,
    openChestObjectState, task5AfterWestMonster,
    attackMonsterObjectState, task5InWest, task5AfterStartChest,
    task5Init, task5StartChest, task5WestChest, task5CenterToWest,
    task5WestToCenter, task5WestMonster, applyLoot,
    removeChestObjectAt, damageMonsterObjectAt, keysAfterExit]

theorem task5_south_gate_blocked_before_button :
    ¬ exitCondition task5AfterWestChest task5CenterToSouth := by
  simp [exitCondition, task5CenterToSouth, task5AfterWestChest,
    openChestObjectState, task5AfterWestMonster,
    attackMonsterObjectState, task5InWest, useExitObjectState,
    task5AfterStartChest, task5Init, task5StartChest, task5WestChest,
    task5CenterToWest, task5WestMonster, applyLoot,
    removeChestObjectAt, damageMonsterObjectAt, keysAfterExit]

theorem task5_east_gate_blocked_without_key :
    ¬ exitCondition { task5BackAtEastGate with keys := 0 }
      task5CenterToEast := by
  simp [exitCondition, task5CenterToEast]

def task5DrainExample : SymbolicState :=
  { task5Init with steps := task5DrainInterval, health := some 2 }

theorem task5_drain_example_due : task5DrainDue task5DrainExample := by
  simp [task5DrainDue, task5DrainExample, task5DrainInterval]

theorem task5_drain_example_survives :
    (task5TimedDrainState task5DrainExample).health = some 1 ∧
    AliveState (task5TimedDrainState task5DrainExample) := by
  unfold task5TimedDrainState
  rw [if_pos task5_drain_example_due]
  simp [task5DrainExample, takeDamage, AliveState]

end ReferenceTasks

end MathLogic.Formalization
