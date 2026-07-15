# 纯 RL 策略正式鲁棒性评测报告

## 评测配置

- 原始结果：`results/rl_robustness_official_500.json`
- 策略入口：`RL_based_submission/high_level_agent.py`
- 策略组成：Task 1-5 全部使用对应的 PPO 模型
- 信息模式：`safe`
- 评测模式：助教原版 `--robustness-suite`
- Episode 数：每个 Task 100 个，共 500 个
- 每个 Task 分布：60 个原图、30 个空间变体、10 个颜色变体

```bash
conda activate nesylink

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
  --json-out results/rl_robustness_official_500.json
```

## 总体结果

| 指标 | 结果 |
| --- | ---: |
| 总成功数 | 470 / 500 |
| 总成功率 | **94.00%** |
| 平均步数 | 660.2 |
| 平均奖励 | 161.095 |

## 各 Task 结果

| Task | 成功数 | 成功率 | 平均步数 | 平均奖励 |
| --- | ---: | ---: | ---: | ---: |
| Task 1 | 100 / 100 | **100.00%** | 256.4 | 127.386 |
| Task 2 | 100 / 100 | **100.00%** | 246.8 | 123.412 |
| Task 3 | 100 / 100 | **100.00%** | 574.4 | 164.256 |
| Task 4 | 100 / 100 | **100.00%** | 1155.7 | 255.118 |
| Task 5 | 70 / 100 | **70.00%** | 1067.5 | 135.305 |

## 各阶段结果

| 阶段 | 成功数 | 成功率 | 平均步数 | 平均奖励 |
| --- | ---: | ---: | ---: | ---: |
| 原始地图 | 300 / 300 | **100.00%** | 649.4 | 167.936 |
| 空间变体 | 120 / 150 | **80.00%** | 685.3 | 145.134 |
| 颜色变体 | 50 / 50 | **100.00%** | 649.4 | 167.936 |

## Task 与阶段明细

| Task | 原始地图 | 空间变体 | 颜色变体 |
| --- | ---: | ---: | ---: |
| Task 1 | 60 / 60 | 30 / 30 | 10 / 10 |
| Task 2 | 60 / 60 | 30 / 30 | 10 / 10 |
| Task 3 | 60 / 60 | 30 / 30 | 10 / 10 |
| Task 4 | 60 / 60 | 30 / 30 | 10 / 10 |
| Task 5 | 60 / 60 | 0 / 30 | 10 / 10 |

## 空间变体明细

每种空间变体在每个 Task 中各运行 10 次。

| Task | spatial_a | spatial_b | spatial_c |
| --- | ---: | ---: | ---: |
| Task 1 | 10 / 10 | 10 / 10 | 10 / 10 |
| Task 2 | 10 / 10 | 10 / 10 | 10 / 10 |
| Task 3 | 10 / 10 | 10 / 10 | 10 / 10 |
| Task 4 | 10 / 10 | 10 / 10 | 10 / 10 |
| Task 5 | 0 / 10 | 0 / 10 | 0 / 10 |

Task 1-4 对全部三种空间变化均能稳定泛化。Task 5 的空间变化是当前纯 RL 策略唯一明确的薄弱项。

## 颜色变体明细

每种颜色变体共运行 10 次，即五个 Task 各 2 次。

| 颜色变体 | 成功数 | 成功率 |
| --- | ---: | ---: |
| grayscale | 10 / 10 | **100.00%** |
| dark | 10 / 10 | **100.00%** |
| bright | 10 / 10 | **100.00%** |
| high_contrast | 10 / 10 | **100.00%** |
| inverted | 10 / 10 | **100.00%** |

五种颜色模式下，每个 Task 的步数和奖励都与对应原图完全一致。这表明新视觉模块不仅能够识别颜色变体，而且没有向上层 PPO 引入可观察的行为偏移。

## Task 5 失败分析

全部 30 个失败均来自 Task 5 空间变体，终止原因全部为 `agent_dead`，没有接口错误、非法动作、模型加载失败或视觉模块导入失败。

| 变体 | 成功数 | 平均步数 | 平均奖励 | 终止原因 |
| --- | ---: | ---: | ---: | --- |
| spatial_a | 0 / 10 | 1094.0 | 27.910 | agent_dead |
| spatial_b | 0 / 10 | 1000.0 | 58.850 | agent_dead |
| spatial_c | 0 / 10 | 1000.0 | 51.300 | agent_dead |

这 30 个 episode 都完成了钥匙、金币、宝箱、治疗、按钮、开门、房间切换和至少一次击杀，说明策略能够识别变体地图并推进大部分任务流程，但在变化后的战斗位置和路径条件下无法存活到最终完成。问题更接近 Task 5 的空间与战斗策略泛化，而不是视觉识别失败。

## 结论

纯 RL 策略在助教正式 500 集评测中的总完成率为 **94.00%**。Task 1-4 在原图、空间变体和颜色变体上全部达到 100%；Task 5 的原图与全部颜色变体也达到 100%。室友更新的视觉层已经成功接入 RL，并完整解决了五种颜色变体识别问题。

当前性能损失全部来自 Task 5 空间变体。若与室友的全规则策略对比，应重点比较 Task 5 的三种空间地图；其他阶段的纯 RL 结果已经达到满成功率。
