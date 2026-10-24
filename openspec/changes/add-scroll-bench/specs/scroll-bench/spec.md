# Spec Delta

## Purpose

描述滚动基准怎么跑、输出什么，以及它的适用边界。

## ADDED Requirements

### Requirement: 可重复的滚动测量

项目 SHALL 提供一个命令，在不需要人工操作的情况下量出网格滚动时主线程每帧的耗时，并输出中位数、p95、最大值和超过 16.7 ms 的帧占比。

#### Scenario: 跑一次 1000 万行样本
- **WHEN** 执行滚动基准并指定 10m.csv 与 10 秒
- **THEN** 输出 600 次滚动的分布，p95 与超预算帧占比都有数字

### Requirement: 口径写清楚

记录 SHALL 说明该数字是主线程每帧耗时，不含显卡合成与垂直同步，不能等同于 Instruments 的掉帧率。

#### Scenario: 写进基准记录
- **WHEN** 把结果抄进 docs/bench-history.md
- **THEN** 同一节里写明测量方式与局限
