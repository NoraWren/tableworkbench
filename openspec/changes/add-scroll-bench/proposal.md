# Proposal

## 对应需求

- R-PERF-03：滚动与交互必须跟手，1000 万行 60fps、掉帧低于 5%。
- R-PERF-07：基准记录要能复现、能对比。

## Why

这台机器没有 Xcode，Instruments 用不了，滚动帧率一直记成“未测”。可 README 第一屏要有三个数字，其中一个就是滚动。用自动点鼠标的办法也测不准：自动化发出的滚动是跳着走的，帧间隔被人为拉长。

## What Changes

- 新增可执行程序 TableWorkbenchScrollBench：在离屏窗口里按 60Hz 连续改滚动偏移，每次强制布局与绘制，记录主线程每帧耗时。
- 输出均值、中位数、p95、最大值，以及超过 16.7 ms 的帧占比。
- 新增 scripts/bench-scroll.sh 串联几份样本，结果写进 docs/bench-history.md。

## Capabilities

### New Capabilities

- scroll-bench：滚动帧耗时的可重复测量。

### Modified Capabilities

无。

## Impact

- Package.swift 增加一个可执行 target。
- 新增基准脚本。
- 文档补一节滚动数据。

## 性能与只读

基准自己开窗口、自己滚，不写源文件，不改缓存。它量的是主线程每帧的布局与绘制耗时，不等于合成器的掉帧率：真实掉帧还要加上显卡合成的时间。这一点会写进记录，不冒充 Instruments。

## 不做什么

- 不采集真实用户输入。
- 不做逐帧打点上报。
- 不替代 Instruments，只是没有 Xcode 时的替代口径。
