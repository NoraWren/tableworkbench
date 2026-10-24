# Tasks

## 1. 基准程序

- [x] 1.1 Package.swift 增加 TableWorkbenchScrollBench，验证 release 构建通过
- [x] 1.2 离屏窗口托管 DataGridView，验证能拿到 NSTableView 与行数
- [x] 1.3 60Hz 改偏移并强制绘制，验证输出 300/600 次采样
- [x] 1.4 输出中位数、p95、最大值与超预算占比，验证数字可读

## 2. 脚本与记录

- [x] 2.1 增加 scripts/bench-scroll.sh，验证一条命令跑完多份样本
- [x] 2.2 结果写进 docs/bench-history.md，写明口径与局限
- [ ] 2.3 用真实录屏交叉验证离屏数字（已录 30 秒演示，但自动化发出的滚动是成段的跳转，静止帧与掉帧分不开，需人工用触控板连续滚动再录一次）

## 3. 验证

- [x] 3.1 1017 万行 20 列跑 10 秒，记录分布
- [x] 3.2 100 列 10 万行跑 5 秒，记录分布
- [x] 3.3 运行 openspec validate --strict add-scroll-bench
