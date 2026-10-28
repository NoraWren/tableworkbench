# Tasks

## 1. 改动

- [x] 1.1 编辑器把选中文字放进 `SQLSelectionBus`，选区为空时清空
- [x] 1.2 运行命令有选区只跑选区，没有跑整篇

## 2. 验收

- [x] 2.1 断言：选中一段时槽位是这段，无选区时清空
- [x] 2.2 千万行 GROUP BY 实测 0.075 / 0.065 / 0.020 秒，写进 bench-history
- [x] 2.3 `TableWorkbenchTests` 全绿

## 不在这次范围

取消正在执行的 SQL。需要上游暴露中断接口，或者自带一份 Cduckdb 依赖。
