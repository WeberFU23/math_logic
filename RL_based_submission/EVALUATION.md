# RL 策略评测指令

本文档记录本项目当前助教评测脚本的固定用法。所有命令均在仓库根目录执行。

正式提交策略为 `RL_based_submission/high_level_agent.py`，五个 Task 全部使用各自的 PPO 模型。五个任务虽然使用同一个入口文件，但必须分别通过 `--task-policy` 绑定。这样助教脚本才会在 `safe_info["task_id"]` 中提供任务编号，策略才能加载对应的 RL 模型。

## 只想直接运行

先进入环境：

```bash
conda activate nesylink
```

上面的简写属于共享策略模式，助教不会提供 `task_id`，RL 策略无法判断该加载哪一关的模型。必须保留正式命令中的五个 `--task-policy`。

## 评测口径

- 使用助教原版 `utils/evaluate_policy.py`，不要修改评测逻辑。
- 正式模式固定为 `--info-mode safe`，策略只接收像素、上一步 reward、物品栏和显式绑定的 `task_id`。
- 正式鲁棒性评测使用 `--robustness-suite`。
- `--num-envs 100` 表示每个任务共 100 个 episode：60 个原始地图、30 个空间变体、10 个颜色变体。
- 主要指标是完整通关率 `success_rate`；阶段事件、平均步数和平均 reward 用于辅助分析。
- 不传 `--max-steps` 或 `--action-repeat`，使用任务原始配置。

术语只需要这样理解：

- `safe`：正式输入模式，只给策略允许使用的信息；必须使用。
- `smoke`：我们对“一关只跑 1 局”的简称，用来快速检查代码能否运行，不是助教的新模式。
- `robustness-suite`：正式鲁棒性套件，自动按 60% 原始地图、30% 空间变化、10% 颜色变化运行。

## 进入评测环境

本机已有包含 RL 依赖的 Conda 环境。每次打开新终端后先执行：

```bash
conda activate nesylink
```

## 单关冒烟测试

下面以 Task 1 为例，只跑 1 个原始 episode，用于确认模型能加载、接口能调用、动作合法。替换命令中的两处任务编号即可测试其他关卡。

```bash
python utils/evaluate_policy.py \
  --tasks mathematical_logic/task_1 \
  --task-policy mathematical_logic/task_1=RL_based_submission/high_level_agent.py \
  --info-mode safe \
  --num-envs 1 \
  --json-out results/task_1_smoke.json
```

## 五关快速检查

每关跑 1 个原始 episode，共 5 个 episode。这个命令只检查基本通路，不代表正式成绩。

```bash
python utils/evaluate_policy.py \
  --tasks \
    mathematical_logic/task_1 \
    mathematical_logic/task_2 \
    mathematical_logic/task_3 \
    mathematical_logic/task_4 \
    mathematical_logic/task_5 \
  --task-policy mathematical_logic/task_1=RL_based_submission/high_level_agent.py \
  --task-policy mathematical_logic/task_2=RL_based_submission/high_level_agent.py \
  --task-policy mathematical_logic/task_3=RL_based_submission/high_level_agent.py \
  --task-policy mathematical_logic/task_4=RL_based_submission/high_level_agent.py \
  --task-policy mathematical_logic/task_5=RL_based_submission/high_level_agent.py \
  --info-mode safe \
  --num-envs 1 \
  --json-out results/all_tasks_smoke.json
```

## 小规模鲁棒性检查

每关跑 10 个 episode，共 50 个 episode。每关自动分成 6 个原始、3 个空间变体、1 个颜色变体。

```bash
python utils/evaluate_policy.py \
  --tasks \
    mathematical_logic/task_1 \
    mathematical_logic/task_2 \
    mathematical_logic/task_3 \
    mathematical_logic/task_4 \
    mathematical_logic/task_5 \
  --task-policy mathematical_logic/task_1=RL_based_submission/high_level_agent.py \
  --task-policy mathematical_logic/task_2=RL_based_submission/high_level_agent.py \
  --task-policy mathematical_logic/task_3=RL_based_submission/high_level_agent.py \
  --task-policy mathematical_logic/task_4=RL_based_submission/high_level_agent.py \
  --task-policy mathematical_logic/task_5=RL_based_submission/high_level_agent.py \
  --info-mode safe \
  --robustness-suite \
  --num-envs 10 \
  --json-out results/robustness_quick.json
```

## 正式完整评测

每关跑 100 个 episode，共 500 个 episode。这是应写入实验报告的正式口径。

```bash
python utils/evaluate_policy.py \
  --tasks \
    mathematical_logic/task_1 \
    mathematical_logic/task_2 \
    mathematical_logic/task_3 \
    mathematical_logic/task_4 \
    mathematical_logic/task_5 \
  --task-policy mathematical_logic/task_1=RL_based_submission/high_level_agent.py \
  --task-policy mathematical_logic/task_2=RL_based_submission/high_level_agent.py \
  --task-policy mathematical_logic/task_3=RL_based_submission/high_level_agent.py \
  --task-policy mathematical_logic/task_4=RL_based_submission/high_level_agent.py \
  --task-policy mathematical_logic/task_5=RL_based_submission/high_level_agent.py \
  --info-mode safe \
  --robustness-suite \
  --num-envs 100 \
  --json-out results/robustness_official.json
```

## 关于 full 调试模式

`--info-mode full` 会把环境内部信息交给策略，只能用于本地 oracle 或环境排错，结果不能作为正式成绩。当前统一入口依靠 `safe_info["task_id"]` 选择模型，并会主动过滤其他字段，因此日常检查和正式评测都应使用 `--info-mode safe`。

## 保存报告信息

每次正式评测应同时保存：实际命令、JSON 输出、当前 Git 提交号、未提交改动、模型文件版本，以及是否使用过 `full` 模式训练或调试。可用以下只读命令记录代码状态：

```bash
git rev-parse HEAD
git status --short
```

助教的完整字段说明见 `docs/Mathematical_logic/evaluation.md`。
