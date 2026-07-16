# Formalization 形式化证明报告

## 1. 报告范围

本报告依据 `formalization/` 中的五个 Lean 文件整理：

| 文件 | 形式化内容 |
| --- | --- |
| `Environment.lean` | 两条路线共用的符号环境、对象语义、状态转移、执行轨迹、五关目标与公共参考场景 |
| `Rule_based_Strategy.lean` | Rule-based 的记忆、目标合法性、优先级、planner、executor、战斗反射和 safety shield |
| `Rule_based_TaskProofs.lean` | Rule-based 在 Task 1-5 关键状态上的策略检查点与通关证书 |
| `RL_based_Strategy.lean` | RL 的共享状态投影、特征编码、高层 option、action mask、模型接口和 primitive shield |
| `RL_based_TaskProofs.lean` | RL 的环境 readiness、mask 检查点以及 Task 1-5 通关证书 |

依赖关系为：

```text
Environment.lean
├── Rule_based_Strategy.lean
│   └── Rule_based_TaskProofs.lean
└── RL_based_Strategy.lean
    └── RL_based_TaskProofs.lean
```

其中 `Environment.lean` 是唯一的环境语义。RL 文件中的 `Strategy.SymbolicState`
只是神经网络编码器读取的定长视图，通过 `ofSharedState` 从公共环境状态投影得到。

## 2. 形式化变量与数据结构

### 2.1 常用变量约定

Lean 定理中反复出现的绑定变量含义如下：

| 变量 | 类型 | 含义 |
| --- | --- | --- |
| `s`、`t`、`u` | `MathLogic.Formalization.SymbolicState` | 环境转移前、中、后的符号状态 |
| `p`、`q`、`target`、`to` | `Position` | 房间内 tile 坐标 |
| `room` | `RoomCoord` | 多房间地图中的房间坐标 |
| `a`、`raw`、`out` | `Action` | 环境动作、shield 前动作和 shield 后动作 |
| `plan`、`rest` | `List Action` | 完整动作序列或剩余动作序列 |
| `g`、`goal` | `Goal` 或 `SymbolicState → Prop` | 高层目标或任务目标谓词 |
| `m` | `AgentMemory` | Rule-based 策略记忆 |
| `frontier` | `List Position` | BFS 已覆盖的搜索前沿 |
| `features` | `FeatureVector` | RL 模型输入特征 |
| `mask`、`rawMask` | `List Bool` | 高层 option 的可用性位向量 |
| `selected`、`option` | `HighLevelAction` 或 `Task5Action` | RL 选择的高层 option |
| `policy` | `MaskablePolicy` 或 `Task5MaskablePolicy` | 接收特征和 mask 的抽象策略函数 |

### 2.2 公共基础类型与常量

| Lean 名称 | 构造或取值 | 形式化含义 |
| --- | --- | --- |
| `Position` | `Int × Int` | 单房间内坐标 `(x, y)` |
| `RoomCoord` | `Int × Int` | 多房间地图坐标，允许负坐标 |
| `boardWidth` | `10` | 单房间宽度 |
| `boardHeight` | `8` | 单房间高度 |
| `task5DrainInterval` | `200` | Task 5 周期掉血间隔 |
| `GlobalPosition` | `room`, `pos` | 房间坐标与房间内坐标的组合 |
| `ObjectKind` | `wall`, `chest`, `monster`, `trap`, `button`, `switch`, `bridge`, `gap`, `exit`, `npc` | 环境对象类别 |
| `Direction` | `north`, `south`, `west`, `east` | 玩家朝向和移动方向 |
| `Action` | `wait`, `up`, `down`, `left`, `right`, `pressA`, `pressB`, `useExit`, `envTick` | 玩家动作及扩展环境动作 |
| `Item` | `sword`, `shield`, `boots`, `bridgeTool` | 装备和道具 |
| `Loot` | `none`, `key n`, `gold n`, `heal n`, `item i` | 宝箱或怪物奖励 |
| `MonsterKind` | `chaser`, `patroller`, `ambusher`, `guardian` | 怪物类别 |
| `BridgeState` | `northSouth`, `eastWest`, `openAll`, `closed` | 旋转桥状态 |
| `ExitKind` | `normal`, `lockedKey`, `allMonstersAndKey`, `buttonGate`, `itemGate` | 普通门、钥匙门、清怪钥匙门、按钮门和物品门 |
| `GoalKind` | `openChest`, `attackMonster`, `activateButton`, `activateSwitch`, `goToExit`, `explore`, `wait` | 公共高层环境目标类别 |

### 2.3 结构化环境对象

| 结构 | 字段 | 含义 |
| --- | --- | --- |
| `Chest` | `pos`, `loot`, `opened`, `room`, `completesTask` | 宝箱位置、奖励、打开状态、所属房间和是否触发任务完成 |
| `Monster` | `pos`, `hp`, `kind`, `damage`, `loot`, `room` | 怪物位置、血量、类别、接触伤害、掉落和所属房间 |
| `Exit` | `pos`, `targetRoom`, `targetSpawn`, `kind`, `sourceRoom`, `completesTask` | 出口位置、目标房间、出生点、门条件、来源房间和完成标记 |
| `Goal` | `kind`, `target` | 高层目标类别和可选目标坐标 |

### 2.4 公共 `SymbolicState`

`MathLogic.Formalization.SymbolicState` 是所有环境转移和两条路线任务证明共同使用的状态。

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `player` | `Position` | 玩家 tile 坐标 |
| `playerCenterPx` | `Option Position` | 可选的玩家像素中心 |
| `room` | `RoomCoord` | 当前房间坐标 |
| `walls` | `List Position` | 墙格 |
| `chests` | `List Position` | 轻量宝箱位置 |
| `monsters` | `List Position` | 轻量怪物位置 |
| `exits` | `List Position` | 兼容旧接口的出口位置 |
| `normalExits` | `List Position` | 普通出口 |
| `lockedExits` | `List Position` | 钥匙门出口 |
| `conditionalExits` | `List Position` | 条件门出口 |
| `traps` | `List Position` | 陷阱位置 |
| `buttons` | `List Position` | 按钮位置 |
| `switches` | `List Position` | 开关位置 |
| `bridges` | `List Position` | 当前直接可用桥格 |
| `bridgeNS`、`bridgeEW` | `List Position` | 南北向、东西向桥格 |
| `bridgeState` | `BridgeState` | 当前桥状态 |
| `gaps` | `List Position` | 沟壑位置 |
| `npcs` | `List Position` | NPC 位置 |
| `keys`、`gold` | `Nat` | 当前钥匙和金币数量 |
| `health` | `Option Nat` | 可选精确血量；`none` 表示当前证明不依赖精确值 |
| `maxHealth` | `Nat` | 最大血量 |
| `steps`、`maxSteps` | `Nat` | 当前步数和最大步数 |
| `facing` | `Direction` | 玩家朝向 |
| `items` | `List Item` | 背包物品 |
| `hasSword`、`hasShield` | `Bool` | 剑和盾的快速状态字段 |
| `shieldUp` | `Bool` | 当前是否举盾 |
| `activated` | `List Position` | 轻量语义中已激活机关 |
| `pressedButtons` | `List Position` | 已按下按钮 |
| `chestObjects` | `List Chest` | 结构化宝箱对象 |
| `monsterObjects` | `List Monster` | 结构化怪物对象 |
| `exitObjects` | `List Exit` | 结构化出口对象 |
| `keysCollected` | `Nat` | 累计获得钥匙数 |
| `chestsOpened` | `Nat` | 累计打开宝箱数 |
| `monstersKilled` | `Nat` | 累计击杀怪物数 |
| `buttonsPressed` | `Nat` | 累计按下按钮数 |
| `switchesActivated` | `Nat` | 累计激活开关数 |
| `roomsChanged` | `Nat` | 累计换房次数 |
| `worldCompleted` | `Bool` | 环境任务完成标记 |

累计字段用于定义任务里程碑，避免钥匙被门消耗后无法从最终背包状态判断曾经获得过钥匙。

### 2.5 感知边界变量

| 名称 | 字段或函数类型 | 含义 |
| --- | --- | --- |
| `ColorMode` | 六种颜色模式 | `default`、`grayscale`、`dark`、`bright`、`highContrast`、`inverted` |
| `PixelFrame` | `width`, `height`, `channels`, `pixels` | 输入 RGB 帧 |
| `ValidPixelFrame` | `PixelFrame → Prop` | 要求帧为 `160 × 128 × 3` 且像素值不超过 255 |
| `ColorNormalizer` | `ColorMode → PixelFrame → PixelFrame` | 颜色归一化器接口 |
| `SymbolExtractor` | `PixelFrame → SymbolicState` | 视觉到符号状态提取器接口 |
| `PerceptionSound` | 归一化器、提取器、真值关系 → `Prop` | 感知输出满足外部真值关系的契约 |
| `ColorModeInvariant` | 归一化器、提取器 → `Prop` | 不同颜色模式产生相同符号状态的契约 |

### 2.6 轨迹与任务证书变量

| 名称 | 参数或字段 | 含义 |
| --- | --- | --- |
| `EnvStep s a t` | 起点、动作、终点 | 轻量一步环境语义 |
| `FullEnvStep s a t` | 起点、动作、终点 | 包含结构化对象、怪物 tick、盾牌和时间的完整一步语义 |
| `Exec s plan t` | 起点、动作序列、终点 | 基于 `EnvStep` 的多步轨迹 |
| `FullExec s plan t` | 起点、动作序列、终点 | 基于 `FullEnvStep` 的多步轨迹 |
| `SafeFullExec s plan t` | 起点、动作序列、终点 | 每个状态都满足 `¬ FailedState` 的完整轨迹 |
| `TaskCertificate goal init` | `plan`, `final`, `execution`, `completed` | 安全动作计划、终态、安全轨迹证明和目标证明 |

### 2.7 Rule-based 策略变量

`AgentMemory` 保存影响规则决策的状态：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `lastGoal` | `Option Goal` | 可继续执行的上一目标 |
| `openedChests` | `List GlobalPosition` | 已打开宝箱记忆 |
| `activatedButtons` | `List GlobalPosition` | 已触发按钮记忆 |
| `activatedSwitches` | `List GlobalPosition` | 全局开关触发记忆 |
| `visitActivatedSwitches` | `List GlobalPosition` | 本次访问中已触发开关 |
| `usedExits` | `List GlobalPosition` | 已使用出口 |
| `roomSteps` | `Nat` | 当前房间停留步数 |
| `switchButtonCooldown` | `Nat` | 机关冷却计数 |

`RuleGoal s m g` 的构造子对应规则目标来源：

```text
sticky
adjacentChest
reachableChest
adjacentMonster
requiredMonster
buttonForConditionalDoor
conditionalMonster
unusedConditionalExit
unusedLockedExit
unusedLegacyExit
unusedNormalExit
switchMechanism
usedLegacyExitFallback
usedNormalExitFallback
usedConditionalExitFallback
usedLockedExitFallback
explore
wait
```

策略管线的主要关系变量为：

| 名称 | 含义 |
| --- | --- |
| `RuleSelector := SymbolicState → AgentMemory → Goal` | 抽象目标选择器 |
| `RulePriorityContract selector` | 选择器合法性、宝箱优先、按钮优先、战斗/出口/恢复守卫 |
| `PositionReachable s n p` | 最多 `n` 步安全移动可到达 `p` |
| `PlannerStep s goals a` | planner 为目标集合输出安全第一步 `a` |
| `CombatReflex s a` | 紧急攻击、格挡或安全撤退 |
| `ActionForGoal s g a` | executor 将目标 `g` 转为动作 `a` |
| `Shielded s raw out` | shield 将原始动作过滤为最终动作 |

### 2.8 RL-based 策略变量

#### 基础动作与特征类型

| 名称 | 构造或字段 | 含义 |
| --- | --- | --- |
| `PrimitiveAction` | `wait`, 四方向、`buttonA`, `buttonB` | 最终送入环境的七个 primitive 动作 |
| `HighLevelAction` | `openChest`, `attackMonster`, `activateMechanism`, `takeNewExit`, `returnOrRevisit`, `exploreRoom`, `wait` | Task 1-4 的七个高层 option |
| `Strategy.GoalKind` | 开箱、攻击、开关、按钮、出口、探索、等待 | RL option 解析后的目标类型 |
| `TileLabel` | 地板、墙、宝箱、怪物、三类出口、陷阱、机关、gap、桥、NPC | 网格特征标签 |
| `FeatureValue` | `tile`, `coord`, `clipped`, `flag`, `maskBit`, `oneHotBit`, `memoryCounter`, `signedCounter`, `missingMonster` | 有类型的单个特征值 |
| `FeatureVector` | `values : List FeatureValue` | 模型输入向量 |

#### RL 编码视图

`Strategy.SymbolicState` 包含 `player`、`walls`、`chests`、`monsters`、`exits`、
`traps`、`mechanisms`、`gaps`、`bridges`、`npcs`、`keys`、`gold`、`hasSword`、
`hasShield` 和 `hasHeal`。它由公共状态通过 `ofSharedState` 产生。

| 结构 | 字段 | 含义 |
| --- | --- | --- |
| `MemorySummary` | `visitedRooms`, `openedChests`, `killedMonsters`, `activatedSwitches`, `usedExits`, `roomSteps` | Task 1-4 的六个记忆计数器 |
| `HighLevelInput` | `state`, `actionMask`, `lastOption`, `memory` | 115 维编码输入 |
| `Task5StateView` | `base`, `normalExits`, `lockedExits`, `conditionalExits` | 保留出口分类的 Task 5 状态视图 |
| `Task5MemorySummary` | 基础六项加 `roomX`, `roomY`, `elapsedSteps` | Task 5 的九个记忆/时间特征 |
| `Task5HighLevelInput` | `state`, `actionMask`, `lastOption`, `memory` | 122 维编码输入 |
| `PolicyInterface` | `optionCount`, `inputDim` | 模型动作数和输入维数 |
| `SafeInfo` | `taskId` | 评测器传入的安全任务编号 |

#### Task 5 mask 上下文

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `rawMask` | `List Bool` | 环境产生的原始九位 mask |
| `usedDirections` | `List Task5Action` | 已使用的方向出口 |
| `lockedDirections` | `List Task5Action` | 当前钥匙门方向 |
| `conditionalDirections` | `List Task5Action` | 当前条件门方向 |
| `hasKey` | `Bool` | 当前是否持有钥匙 |
| `attackIsProgress` | `Bool` | 当前怪物是否阻挡必要进度 |

`PrimitiveDecision` 由 `action : PrimitiveAction` 和 `setupOnly : Bool` 组成。
`setupOnly = true` 表示仅用于朝向或对齐；否则动作必须经过 `shield`。

## 3. 已形式化机制及对应函数

### 3.1 公共环境机制

| 机制 | 对应 Lean 定义或函数 | 形式化内容 |
| --- | --- | --- |
| 坐标和方向转换 | `actionOfDirection`, `directionOfAction`, `delta`, `nextPosition`, `nextRoom` | 动作与位移、跨房间坐标变化 |
| 玩家朝向交互 | `facingTarget`, `inFront`, `adjacent`, `manhattan` | 面前一格和四邻域交互条件 |
| 边界与门口 | `inBounds`, `isDoorExit`, `exitPushAllowed` | 合法网格范围和边界出口推动作 |
| 桥与 gap | `activeBridges`, `toggleBridgeState` | 不同桥状态下可通行桥格及旋转切换 |
| 地形通行 | `terrainPassable`, `isWalkable`, `SafePosition` | 墙、gap、宝箱、怪物、陷阱对移动安全的约束 |
| 血量与失败 | `damageHealth`, `takeDamage`, `healHealth`, `AliveState`, `DeadState`, `TimedOut`, `FailedState` | 伤害、治疗、死亡和超时 |
| Task 5 周期掉血 | `task5DrainDue`, `task5TimedDrainState`, `task5DrainInterval` | 每 200 个 tick 触发一次额外伤害 |
| 环境时钟 | `advanceClock` | `steps` 增加一 |
| 奖励应用 | `lootKeys`, `lootGold`, `applyLoot` | 钥匙、金币、治疗和装备更新 |
| 宝箱交互 | `canOpenChestObject`, `removeChestObjectAt`, `openChestObjectState` | 面向宝箱、移除对象、应用奖励和记录里程碑 |
| 怪物攻击 | `canAttackObject`, `damageMonsterObjectAt`, `attackMonsterObjectState` | 持剑攻击、扣除怪物血量、击杀与掉落 |
| 怪物行动 | `monsterThreatens`, `monsterCanOccupy`, `monsterMoveAllowed`, `moveMonsterObjectAt`, `monsterDamageState` | 威胁判定、移动约束和接触伤害 |
| NPC 对话 | `canTalkNpc` | NPC 必须在列表中并位于玩家面前 |
| 盾牌 | `shieldBlockState` 及 `FullEnvStep.pressShield`、`monsterDamageBlocked` | 举盾和抵消一次怪物伤害 |
| 按钮与开关 | `FullEnvStep.pressButton`, `FullEnvStep.pressSwitch`, `toggleBridgeState` | 记录按钮、切换桥并累计机关里程碑 |
| 出口条件 | `exitCondition`, `canUseExitObject`, `keysAfterExit`, `useExitObjectState` | 五类门条件、钥匙消耗、换房和出生点更新 |
| 终止条件 | `TerminalState` | 目标成立或失败时终止 |
| 轻量一步语义 | `EnvStep` | 安全移动、陷阱、阻挡、轻量出口、开箱、攻击、机关、B 键和等待 |
| 完整一步语义 | `FullEnvStep` | 结构化对象、按钮、开关、NPC、盾牌、出口、怪物 tick、周期掉血和时钟 |
| 多步轨迹 | `Exec`, `FullExec`, `SafeFullExec` | 轻量轨迹、完整轨迹和逐状态无失败轨迹 |
| 五关目标 | `Task1Goal` 至 `Task5Goal` | 每关完成标记和关键累计里程碑 |
| 通关证书 | `CompletedBy`, `TaskCertificate` | 通关存在性与带安全轨迹的证书 |
| BFS 抽象完备性 | `BoundedReachable`, `BoundedGoalReachable`, `BfsFrontierComplete`, `BfsFindsGoal` | 有界可达、frontier 覆盖和目标发现 |
| 感知契约 | `ValidPixelFrame`, `PerceptionSound`, `ColorModeInvariant` | 像素输入形状、感知正确性和颜色模式不变性 |

### 3.2 Rule-based 机制

| 机制 | 对应 Lean 定义或函数 | 形式化内容 |
| --- | --- | --- |
| 记忆去重 | `noUnopenedChests`, `noUnusedMechanisms`, `noUnusedDoorExits` | 避免重复选择已完成对象 |
| 房间耗尽判断 | `noVisibleChests`, `noVisibleSwitches`, `noVisibleButtons`, `roomExhaustedBeforeCombat` | 判断何时允许清怪 fallback |
| 条件门准备 | `visibleButtonsSatisfied`, `conditionalDoorReady` | 按钮已满足且怪物前置条件完成 |
| 目标合法性 | `ExitGoalAdmissible`, `GoalAdmissible` | 每类出口和目标的资源、对象、记忆前置条件 |
| 位置可达 | `PositionReachable`, `PlannerCanReach` | 目标可由有限步安全移动到达 |
| 规则目标生成 | `RuleGoal` | sticky、宝箱、怪物、按钮、开关、出口、探索和等待 |
| 具体进度检测 | `HasReachableFreshChest`, `HasReachableFreshButton`, `HasReachableNewExit`, `HasReachableFreshSwitch`, `HasConcreteProgress` | 判断当前是否存在比恢复动作更高优先级的目标 |
| 十二级优先链契约 | `RulePriorityContract` | 输出合法、宝箱/按钮优先、战斗/出口/恢复动作受守卫约束 |
| 紧急战斗反射 | `CombatReflex` | 相邻攻击、有盾格挡和安全撤退 |
| 目标邻接格 | `approachTiles` | 开箱、攻击和机关交互前的四个邻接 tile |
| planner 第一步 | `PlannerStep` | 输出必须是走向目标集合的安全移动 |
| planner 完备性 | `PlannerFrontierComplete`, `PlannerGoalReachable`, `PlannerFindsGoal` | frontier 不变量推出可达目标被发现 |
| 出口推动作 | `exitPushAction`, `pushesOut` | 玩家站在边界门上时继续向外移动 |
| action mask 规格 | `ActionAllowed` | 等待、交互、安全移动或合法出门 |
| executor | `interactionKind`, `ActionForGoal` | 将目标转换成按键、规划移动、出门或等待 |
| safety shield | `Shielded` | 放行安全动作，将不安全移动改成 `wait` |
| 完整规则管线 | `RuleGoal` + `ActionForGoal` + `Shielded` | 从目标选择到最终动作的合法性和安全性 |

### 3.3 RL-based 机制

| 机制 | 对应 Lean 定义或函数 | 形式化内容 |
| --- | --- | --- |
| 公共状态投影 | `ofSharedState`, `task5ViewOfSharedState` | 从唯一公共环境状态得到模型输入视图 |
| 网格枚举 | `allTiles` | 按行枚举 `10 × 8 = 80` 个 tile |
| tile 编码 | `tileLabelAt`, `task5TileLabelAt`, `gridFeatures`, `task5GridFeatures` | 基础对象标签及 Task 5 三类出口标签 |
| 玩家编码 | `coordFeature`, `playerFeatures` | 两个裁剪坐标特征 |
| 怪物编码 | `monsterBefore`, `orderedMonsters`, `monsterSlotFeatures`, `monsterFeatures` | 按距离和坐标稳定排序，保留四个怪物槽位 |
| 背包编码 | `clippedFeature`, `inventoryFeatures` | 钥匙、金币、剑、盾和治疗标记 |
| 记忆编码 | `memoryFeature`, `signedMemoryFeature`, `memoryFeatures`, `task5MemoryFeatures` | 基础六项及 Task 5 房间坐标、时间信息 |
| mask/历史编码 | `fixedMaskFeatures`, `oneHotForLast`, `task5FixedMaskFeatures`, `task5OneHotForLast` | 当前 action mask 和上一 option one-hot |
| 特征合法性 | `FeatureValue.Valid`, `FeaturesValid`, `WellFormedFeatures`, `Task5WellFormedFeatures` | 分母为正、数值裁剪合法、总长度正确 |
| 115 维编码 | `encodeHighLevelState`, `featureDim` | `80 + 2 + 8 + 5 + 7 + 7 + 6 = 115` |
| 122 维编码 | `encodeTask5State`, `task5FeatureDim` | `80 + 2 + 8 + 5 + 9 + 9 + 9 = 122` |
| 七动作 option 解析 | `actionIndex`, `actionAtMask`, `canonicalGoalForOption`, `CompatibleGoal`, `resolveFromMask` | mask 中的基础 option 解析为兼容目标 |
| 七动作策略契约 | `MaskablePolicy`, `RespectsMask` | 抽象策略必须只选择 mask 为真的 option |
| 基础优先 mask | `prioritizedAttackAllowed`, `localProgress`, `prioritizedReturnAllowed`, `firstResolvedProgress`, `normalizedMask` | 宝箱/机关压制攻击，新出口/本地进度压制回退，进度压制探索和等待 |
| Task 5 九动作 | `Task5Action`, `task5ActionIndex`, `task5ActionAtMask` | 四个方向出口组成九个高层 option |
| Task 5 option 解析 | `task5CanonicalGoalForOption`, `Task5CompatibleGoal`, `task5ResolveFromMask` | 九动作 option 解析为兼容目标 |
| Task 5 出口优先 | `task5PreferredDirections`, `task5DirectionUsed`, `task5HasNewExit`, `task5ExitBit` | 钥匙门/条件门方向选择和已用出口抑制 |
| Task 5 本地进度优先 | `task5ChestBit`, `task5MechanismBit`, `task5AttackBit`, `task5ConcreteProgress` | 宝箱、机关与阻路怪物的优先关系 |
| Task 5 最终 mask | `task5NormalizedMask`, `Task5MaskContext` | 九位 mask、恢复动作抑制和等待兜底 |
| task_id 接口选择 | `TaskId`, `PolicyInterface`, `interfaceFor`, `interfaceFromSafeInfo` | Task 1-4 选择 7/115，Task 5 选择 9/122 |
| primitive 安全 | `isMove`, `isBlocked`, `safeTile`, `shield`, `appliedPrimitive` | 非 setup 移动经过最终安全过滤 |
| 环境 readiness | `chestReady`, `monsterReady`, `mechanismReady`, `exitReady`, `task5DirectionalExitReady` | Bool 判定与公共环境可执行谓词连接 |
| 固定 mask 输入 | `baseRawMask`, `task5RawMask`, `baseInputFromShared`, `task5InputFromShared` | 构造固定长度 mask 和模型输入 |
| RL 检查点 | `BaseCheckpoint`, `Task5Checkpoint` | 同时要求 mask 允许、resolver 成功和环境对象可执行 |

## 4. 已证明性质与定理

### 4.1 `Environment.lean` 定理

#### 感知、方向与轨迹基础

| 定理 | 已证明性质 |
| --- | --- |
| `color_mode_invariant_extract_eq` | 颜色模式不变契约直接推出任意两种模式提取结果相同 |
| `actionOfDirection_mem_movementActions` | 任意方向对应动作都属于四方向移动集合 |
| `safeFullExec_to_fullExec` | 无失败轨迹可遗忘安全见证得到普通完整轨迹 |
| `taskCertificate_completedBy` | 安全任务证书推出任务完成存在性 |

#### 移动、执行和资源不变量

| 定理 | 已证明性质 |
| --- | --- |
| `walkable_terrain_passable` | 安全可走蕴含地形可通过 |
| `walkable_is_safe_position` | 安全可走蕴含目标位置安全 |
| `move_safe_player_eq` | `EnvStep.moveSafe` 后玩家位置等于 `nextPosition` |
| `move_blocked_player_eq` | 阻挡移动保持玩家位置不变 |
| `safe_move_preserves_safe_position` | 安全移动的终点满足 `SafePosition` |
| `open_chest_increases_keys` | 轻量开箱使钥匙数增加一 |
| `attack_monster_removes_target` | 轻量攻击从怪物列表移除目标 |
| `activate_switch_records` | 机关交互把位置加入 `activated` |
| `env_step_keys_monotone` | 轻量一步语义中钥匙数量不下降 |
| `exec_append` | 两段轻量执行轨迹可以拼接 |
| `exec_keys_monotone` | 轻量多步轨迹中钥匙数量不下降 |
| `env_step_is_full_step` | 任意轻量一步都可提升为完整一步 |
| `full_exec_append` | 两段完整执行轨迹可以拼接 |

#### 血量、对象、机关和出口不变量

| 定理 | 已证明性质 |
| --- | --- |
| `takeDamage_preserves_player` | 扣血不改变玩家位置 |
| `task5TimedDrainState_preserves_player` | Task 5 周期掉血不改变玩家位置 |
| `takeDamage_some_health_eq` | 已知血量时扣血结果为截断减法 |
| `healHealth_preserves_player` | 治疗不改变玩家位置 |
| `healHealth_some_le_maxHealth` | 治疗后的已知血量不超过最大血量 |
| `advanceClock_steps_eq` | 环境时钟使步数精确增加一 |
| `advanceClock_preserves_player` | 时钟推进不改变玩家位置 |
| `apply_key_loot_keys` | 钥匙奖励正确更新当前和累计钥匙数 |
| `apply_gold_loot_gold` | 金币奖励正确更新金币数 |
| `apply_item_loot_items` | 装备奖励被加入背包 |
| `applyLoot_preserves_player` | 应用任意奖励不改变玩家位置 |
| `openChestObjectState_preserves_player` | 结构化开箱不改变玩家位置 |
| `attackMonsterObjectState_preserves_player` | 结构化攻击不改变玩家位置 |
| `canTalkNpc_listed`、`canTalkNpc_in_front` | 可对话 NPC 必须在列表中且位于玩家面前 |
| `monsterThreatens_listed`、`monsterThreatens_alive` | 威胁玩家的怪物必须在列表中且存活 |
| `monsterMoveAllowed_target_inBounds`、`monsterMoveAllowed_target_not_wall` | 合法怪物移动终点在界内且不是墙 |
| `monsterDamageState_preserves_player` | 怪物伤害不改变玩家位置 |
| `shieldBlockState_shieldUp_false` | 抵挡后举盾状态被清除 |
| `shieldBlockState_preserves_player` | 盾牌抵挡不改变玩家位置 |
| `pressButton_records_player` | 按钮动作记录玩家所在按钮 |
| `pressButton_preserves_player` | 按钮动作不改变玩家位置 |
| `toggleBridge_twice` | 桥状态连续切换两次回到原状态 |
| `pressSwitch_preserves_player` | 开关动作不改变玩家位置 |
| `canUseExitObject_listed`、`canUseExitObject_at_player` | 可用出口必须在对象列表中且位于玩家脚下 |
| `useExitObject_room_eq`、`useExitObject_player_eq` | 使用出口后房间和出生位置等于出口目标字段 |
| `lockedExit_condition_implies_enough_keys` | 锁门条件成立蕴含钥匙数量满足要求 |

#### 失败、终止和搜索

| 定理 | 已证明性质 |
| --- | --- |
| `terminal_of_goal` | 目标成立推出终止状态 |
| `terminal_of_failed` | 失败状态推出终止状态 |
| `failed_of_dead` | 死亡推出失败 |
| `failed_of_timedOut` | 超时推出失败 |
| `bfs_completeness_from_frontier_invariant` | frontier 覆盖有界可达状态且目标有界可达时，BFS 一定找到目标 |

#### 五关公共参考场景

| 任务 | 公开定理 | 性质 |
| --- | --- | --- |
| Task 1 | `task1_safe_execution`, `task1_goal` | 计划形成无失败轨迹，终态满足钥匙箱和出口目标 |
| Task 2 | `task2_safe_execution`, `task2_goal`, `task2_exit_blocked_while_monster_alive` | 证明击杀、开箱、条件门通关，并证明活怪物存在时门被阻挡 |
| Task 3 | `task3_safe_execution`, `task3_goal`, `task3_final_exit_blocked_without_key` | 证明跨房取钥匙并返回锁门，且无钥匙不能通过最终门 |
| Task 4 | `task4_safe_execution`, `task4_goal`, `task4_east_gate_does_not_consume_key`, `task4_guardian_requires_sword` | 证明两次旋桥、取钥匙/剑、击杀守卫和最终开箱 |
| Task 5 | `task5_safe_execution`, `task5_goal`, `task5_south_gate_blocked_before_button`, `task5_east_gate_blocked_without_key` | 证明按钮门、钥匙门和四宝箱路线 |
| Task 5 掉血 | `task5_drain_example_due`, `task5_drain_example_survives` | 200 步时掉血触发，示例状态掉血后仍存活 |

Task 4 的内部轨迹连接引理为：

```text
task4_step_switch1
task4_step_to_center
task4_step_to_north
task4_step_open_key
task4_step_back_for_east
task4_step_to_east
task4_step_open_sword
task4_step_back_to_switch
task4_step_switch2
task4_step_to_south
task4_step_kill_guardian
task4_step_back_to_final
task4_step_open_final
```

Task 5 的内部轨迹连接引理为：

```text
task5_step_open_start
task5_step_to_west
task5_step_kill_west_monster
task5_step_open_west
task5_step_back_to_button
task5_step_press_button
task5_step_to_south
task5_step_open_south
task5_step_back_to_east_gate
task5_step_to_east
task5_step_open_east
```

### 4.2 `Rule_based_Strategy.lean` 定理

| 定理 | 已证明性质 |
| --- | --- |
| `exit_goal_admissible_mem_allExits` | 合法出口目标一定属于公共出口集合 |
| `planner_can_reach_player` | 玩家当前位置零步可达 |
| `rule_goal_admissible` | 任意 `RuleGoal` 输出都满足 `GoalAdmissible` |
| `selector_chest_first` | 存在可达未开宝箱时，满足契约的选择器必须选开箱 |
| `selector_cannot_wait_with_progress` | 存在具体进度时，满足契约的选择器不能等待 |
| `priority_selector_goal_admissible` | 优先链选择器输出始终合法 |
| `combat_reflex_action_allowed` | 紧急攻击、格挡和撤退均满足动作约束 |
| `planner_step_safe` | planner 第一步是移动且终点 `isWalkable` |
| `planner_completeness_from_frontier_invariant` | 完整 frontier 会发现有界可达目标 |
| `planner_finds_singleton_of_reachable` | 单目标可达时完整 frontier 包含该目标 |
| `action_for_goal_move_safe_or_exit` | executor 输出的移动安全或属于合法出门 |
| `action_for_goal_allowed` | executor 输出满足 `ActionAllowed` |
| `shielded_move_safe_or_exit` | shield 后仍为移动时，该移动安全或合法出门 |
| `shielded_output_allowed` | shield 最终输出满足 `ActionAllowed` |
| `shield_blocks_unsafe_movement` | 不安全且非出门的移动只能被过滤为 `wait` |
| `raw_rule_action_safe_or_exit` | 规则目标经 executor 后的原始移动安全或合法出门 |
| `shielded_rule_action_safe_or_exit` | 完整规则管线的最终移动安全或合法出门 |
| `shielded_rule_action_safe_position_or_exit` | 最终移动不会主动进入危险位置 |
| `rule_pipeline_output_allowed` | `RuleGoal + ActionForGoal + Shielded` 的最终输出满足 action mask 规格 |

### 4.3 `Rule_based_TaskProofs.lean` 定理

| 任务 | 策略检查点定理 | 通关定理 |
| --- | --- | --- |
| Task 1 | `task1_rule_chest_checkpoint`, `task1_rule_locked_exit_checkpoint` | `rule_task1_completed` |
| Task 2 | `task2_rule_monster_checkpoint`, `task2_rule_chest_checkpoint`, `task2_rule_conditional_exit_checkpoint` | `rule_task2_completed` |
| Task 3 | `task3_rule_start_exit_checkpoint`, `task3_rule_hall_monster_checkpoint`, `task3_rule_key_chest_checkpoint`, `task3_rule_final_locked_exit_checkpoint` | `rule_task3_completed` |
| Task 4 | `task4_rule_first_switch_checkpoint`, `task4_rule_key_chest_checkpoint`, `task4_rule_east_locked_exit_checkpoint`, `task4_rule_sword_chest_checkpoint`, `task4_rule_second_switch_checkpoint`, `task4_rule_guardian_checkpoint`, `task4_rule_final_chest_checkpoint` | `rule_task4_completed` |
| Task 5 | `task5_rule_start_chest_checkpoint`, `task5_rule_west_exit_checkpoint`, `task5_rule_west_monster_checkpoint`, `task5_rule_west_chest_checkpoint`, `task5_rule_button_checkpoint`, `task5_rule_conditional_exit_checkpoint`, `task5_rule_south_chest_checkpoint`, `task5_rule_east_locked_exit_checkpoint`, `task5_rule_east_chest_checkpoint` | `rule_task5_completed` |

每个检查点构造一个具体 `RuleGoal`，证明该目标可由规则关系产生。
`all_rule_task_certificates` 同时给出 Task 1-5 的 `CompletedBy` 结论。

### 4.4 `RL_based_Strategy.lean` 定理

#### 状态投影、option 与基础 mask

| 定理组 | 已证明性质 |
| --- | --- |
| `ofSharedState_player`, `ofSharedState_inventory`, `ofSharedState_objects` | 公共状态投影保持玩家、资源和关键对象字段 |
| `allTiles_length`, `allTiles_contains` | 网格枚举恰有 80 格，并覆盖所有合法自然数坐标 |
| `canonicalGoal_compatible` | 每个基础 option 的规范目标都与该 option 兼容 |
| `activateMechanism_allows_pressed_button`, `activateMechanism_allows_rotating_switch` | 机关 option 同时兼容按钮和旋转开关 |
| `resolve_some_of_mask_true`, `resolve_none_of_mask_false` | mask 位为真时 resolver 返回目标，为假时返回 `none` |
| `mask_respecting_policy_resolves` | 尊重 mask 的策略输出总能解析为兼容目标 |
| `normalizedMask_length` | 基础最终 mask 长度恒为 7 |
| `normalizedMask_attack_disabled_of_chest` | 有宝箱 option 时关闭主动攻击 |
| `normalizedMask_attack_disabled_of_mechanism` | 有机关 option 时关闭主动攻击 |
| `normalizedMask_return_disabled_of_new_exit` | 有新出口时关闭返回/重访 |
| `normalizedMask_return_disabled_of_local_progress` | 有本地进度时关闭返回/重访 |
| `normalizedMask_explore_disabled_of_resolved_progress` | 有确定进度时关闭探索 |
| `normalizedMask_wait_disabled_of_resolved_progress` | 有确定进度时关闭等待 |
| `normalizedMask_wait_fallback` | 无进度且不能探索时重新打开等待，保证 mask 非空 |

#### 115 维特征编码

| 定理组 | 已证明性质 |
| --- | --- |
| `tileLabelAt_player` | 玩家格编码为 floor，不额外引入玩家 tile 类别 |
| `gridFeatures_length` | 网格特征长度为 80 |
| `playerFeatures_length` | 玩家坐标特征长度为 2 |
| `monsterSlotFeatures_length` | 单个怪物槽长度为 2 |
| `orderedMonsters_perm`, `orderedMonsters_length` | 排序保持怪物多重集合和长度 |
| `monsterFeatures_length` | 四个怪物槽总长度为 8 |
| `inventoryFeatures_length` | 背包特征长度为 5 |
| `fixedMaskFeatures_length` | 基础 mask 特征长度为 7 |
| `oneHotForLast_length` | 上一 option one-hot 长度为 7 |
| `memoryFeatures_length` | 基础记忆特征长度为 6 |
| `featuresValid_append` | 两段合法特征拼接后仍合法 |
| `coordFeature_valid`, `clippedFeature_valid`, `memoryFeature_valid`, `signedMemoryFeature_valid` | 各类裁剪数值特征满足分母和范围约束 |
| `gridFeatures_valid`, `playerFeatures_valid`, `monsterSlotFeatures_valid`, `monsterFeatures_valid` | 网格、玩家和怪物特征值均合法 |
| `inventoryFeatures_valid`, `fixedMaskFeatures_valid`, `oneHotForLast_valid`, `memoryFeatures_valid` | 背包、mask、历史和记忆特征值均合法 |
| `encodeHighLevelState_wellFormed` | 完整基础编码长度为 115，且每个特征值合法 |

#### Task 5 编码、接口和 mask

| 定理组 | 已证明性质 |
| --- | --- |
| `task5CanonicalGoal_compatible` | 每个 Task 5 option 的规范目标都兼容 |
| `task5_resolve_some_of_mask_true`, `task5_resolve_none_of_mask_false` | Task 5 resolver 与 mask 位一致 |
| `task5_mask_respecting_policy_resolves` | 尊重九位 mask 的策略输出可解析为兼容目标 |
| `task5ViewOfSharedState_classifies_exits` | Task 5 投影保持普通、锁门和条件门分类 |
| `task5TileLabelAt_player` | Task 5 中玩家格编码为 floor |
| `task5GridFeatures_length` | Task 5 网格特征长度为 80 |
| `task5FixedMaskFeatures_length` | Task 5 mask 特征长度为 9 |
| `task5OneHotForLast_length` | Task 5 上一 option one-hot 长度为 9 |
| `task5MemoryFeatures_length` | Task 5 记忆特征长度为 9 |
| `task5GridFeatures_valid`, `task5FixedMaskFeatures_valid`, `task5OneHotForLast_valid`, `task5MemoryFeatures_valid` | Task 5 各特征段值域合法 |
| `encodeTask5State_wellFormed` | Task 5 完整编码长度为 122，且每个值合法 |
| `task1_interface`, `task2_interface`, `task3_interface`, `task4_interface` | Task 1-4 接口均为 7 个 option、115 维输入 |
| `task5_interface` | Task 5 接口为 9 个 option、122 维输入 |
| `safeInfo_selects_exact_interface` | `SafeInfo.taskId` 精确决定模型接口 |
| `task5_exit_north_disabled_of_local_resource`, `task5_exit_east_disabled_of_local_resource`, `task5_exit_south_disabled_of_local_resource`, `task5_exit_west_disabled_of_local_resource` | 存在本地宝箱或机关时四个方向出口全部关闭 |
| `task5NormalizedMask_length` | Task 5 最终 mask 长度恒为 9 |
| `task5_locked_directions_preferred` | 有钥匙且存在锁门方向时优先锁门方向 |
| `task5_conditional_directions_preferred_without_key` | 无钥匙时优先条件门方向 |
| `task5_nonpreferred_exit_disabled` | 存在优选方向时关闭非优选出口 |
| `task5_used_exit_disabled_when_frontier_exists` | 存在新出口时关闭已用出口 |
| `task5_all_exits_disabled_of_local_resource` | 本地资源存在时四个出口位均为假 |
| `task5_chest_precedes_mechanism_without_blocking_monster` | 无阻路怪物时宝箱优先于机关 |
| `task5_optional_attack_disabled_in_resource_room` | 资源房中关闭非必要攻击 |
| `task5_blocking_attack_precedes_local_interaction` | 阻路怪物优先于宝箱和机关 |
| `task5_recovery_disabled_of_concrete_progress` | 有具体进度时关闭探索和等待 |
| `task5_wait_fallback` | 无具体进度且不能探索时启用等待 |

#### Primitive shield

| 定理 | 已证明性质 |
| --- | --- |
| `shared_walkable_projects_to_safe` | 公共环境中的可走位置投影后满足 RL `safeTile`，额外要求不是 NPC |
| `shielded_non_setup_move_safe` | 非 setup 决策经过 shield 后，如果仍输出移动，则目标 tile 安全 |

### 4.5 `RL_based_TaskProofs.lean` 定理

#### Readiness 与公共环境语义等价

| 定理 | 已证明性质 |
| --- | --- |
| `chestObjectReady_iff` | 单个宝箱 Bool readiness 等价于 `canOpenChestObject` |
| `monsterObjectReady_iff` | 单个怪物 Bool readiness 等价于 `canAttackObject` |
| `exitConditionReady_iff` | Bool 出口条件等价于公共 `exitCondition` |
| `exitObjectReady_iff` | 单个出口 Bool readiness 等价于 `canUseExitObject` |
| `chestReady_iff` | 开箱 option ready 等价于存在可打开宝箱 |
| `monsterReady_iff` | 攻击 option ready 等价于存在可攻击怪物 |
| `mechanismReady_iff` | 机关 ready 等价于玩家位于按钮或开关位置 |
| `exitReady_iff` | 出口 option ready 等价于存在可用出口 |

#### 输入与检查点通用性质

| 定理 | 已证明性质 |
| --- | --- |
| `base_shared_input_wellFormed` | 任意公共状态生成的基础输入满足 115 维特征契约 |
| `task5_shared_input_wellFormed` | 任意公共状态和 Task 5 上下文生成的输入满足 122 维契约 |
| `every_base_checkpoint_goal_compatible` | 任意基础检查点 option 的规范目标都兼容 |
| `every_task5_checkpoint_goal_compatible` | 任意 Task 5 检查点 option 的规范目标都兼容 |

#### 五关 RL 检查点与通关

| 任务 | 检查点定理 | 通关定理 |
| --- | --- | --- |
| Task 1 | `task1_rl_chest_checkpoint`, `task1_rl_locked_exit_checkpoint` | `rl_task1_completed` |
| Task 2 | `task2_rl_monster_checkpoint`, `task2_rl_chest_checkpoint`, `task2_rl_conditional_exit_checkpoint` | `rl_task2_completed` |
| Task 3 | `task3_rl_start_exit_checkpoint`, `task3_rl_hall_monster_checkpoint`, `task3_rl_key_chest_checkpoint`, `task3_rl_return_from_key_room_checkpoint`, `task3_rl_return_to_start_checkpoint`, `task3_rl_final_locked_exit_checkpoint` | `rl_task3_completed` |
| Task 4 | `task4_rl_first_switch_checkpoint`, `task4_rl_key_chest_checkpoint`, `task4_rl_east_locked_exit_checkpoint`, `task4_rl_sword_chest_checkpoint`, `task4_rl_second_switch_checkpoint`, `task4_rl_guardian_checkpoint`, `task4_rl_final_chest_checkpoint` | `rl_task4_completed` |
| Task 5 | `task5_rl_start_chest_checkpoint`, `task5_rl_west_exit_checkpoint`, `task5_rl_blocking_monster_checkpoint`, `task5_rl_west_chest_checkpoint`, `task5_rl_button_checkpoint`, `task5_rl_conditional_south_exit_checkpoint`, `task5_rl_south_chest_checkpoint`, `task5_rl_return_north_checkpoint`, `task5_rl_locked_east_exit_checkpoint`, `task5_rl_east_chest_checkpoint` | `rl_task5_completed` |

`task5_rl_button_option_accepts_button_goal` 另外证明 Task 5 的 `activateMechanism`
option 可以合法解析为按钮目标。`all_rl_tasks_completed` 同时给出五关完成结论。

## 5. 五关目标和证书结论

| 任务目标 | 目标字段 | 公共轨迹 | Rule-based 证书 | RL-based 证书 |
| --- | --- | --- | --- | --- |
| `Task1Goal` | 完成世界、至少取 1 把钥匙、开 1 个宝箱 | `task1Plan` / `task1_safe_execution` | `ruleTask1Certificate` | `rlTask1Certificate` |
| `Task2Goal` | 完成世界、杀 1 怪、取 1 钥匙、开 1 箱 | `task2Plan` / `task2_safe_execution` | `ruleTask2Certificate` | `rlTask2Certificate` |
| `Task3Goal` | 完成世界、换房至少 5 次、杀怪、取钥匙、开箱 | `task3Plan` / `task3_safe_execution` | `ruleTask3Certificate` | `rlTask3Certificate` |
| `Task4Goal` | 完成世界、两次开关、取钥匙、持剑、杀怪、开 3 箱 | `task4Plan` / `task4_safe_execution` | `ruleTask4Certificate` | `rlTask4Certificate` |
| `Task5Goal` | 完成世界、开 4 箱、换房至少 5 次、按按钮、取钥匙 | `task5Plan` / `task5_safe_execution` | `ruleTask5Certificate` | `rlTask5Certificate` |

两条路线共享相同的环境状态、计划、完整转移和目标谓词。路线特有文件分别证明：

- Rule-based 在关键状态能够构造符合规则语义的 `RuleGoal`；
- RL-based 在关键状态的最终 mask 允许预期 option，resolver 成功，并且环境对象确实 ready；
- 两条路线最终都把公共 `SafeFullExec` 封装为同一种 `TaskCertificate`。

## 6. 形式化边界

Lean 形式化从视觉抽取后的公共 `SymbolicState` 开始。当前证明覆盖：

- 符号环境对象、资源、门、机关、伤害、失败和执行轨迹；
- Rule-based 目标合法性、优先链接口、planner 第一步、executor 和 safety shield；
- RL 状态投影、特征长度和值域、action mask、option 解析、task_id 接口和 primitive shield；
- 两条路线在五个参考任务上的关键策略检查点和安全通关证书。

当前证明不包含：

- 对具体 Python/CV 代码的逐行等价证明；
- 对所有像素输入无条件保证视觉识别正确；
- 对 PPO 训练收敛、任意权重或任意随机种子必然通关的证明；
- 对 Python primitive 队列和每一帧连续运动的 Lean 重放。

神经网络被视为满足 `RespectsMask` 或 `Task5RespectsMask` 的不透明策略函数。
因此 RL 结论验证模型外围符号接口和一条认证路线，不声称任意模型权重都会自动选择该路线。

## 7. 验证方法

在项目根目录执行：

```powershell
lake build formalization
```

逐文件检查：

```powershell
lake env lean .\formalization\Environment.lean
lake env lean .\formalization\Rule_based_Strategy.lean
lake env lean .\formalization\Rule_based_TaskProofs.lean
lake env lean .\formalization\RL_based_Strategy.lean
lake env lean .\formalization\RL_based_TaskProofs.lean
```

检查未完成证明占位：

```powershell
rg -n "\b(sorry|admit|axiom)\b" .\formalization -g "*.lean"
```

有效结果应满足：

1. `lake build formalization` 退出码为 0；
2. 五个 Lean 文件均无编译错误；
3. `sorry|admit|axiom` 扫描无匹配；
4. 两条路线都存在 Task 1-5 的 `TaskCertificate` 和总完成定理。
