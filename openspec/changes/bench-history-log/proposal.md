# Proposal

## 对应需求

- R-PERF-07 基准记录。

## Why

`docs/bench-history.md` 的「记录」表从 10-23 到今天只有两行，都是手抄的：跑完
`scripts/bench.sh`，人从终端里挑四个数字，再敲进 Markdown。三个问题：

1. **抄错没人发现。** 10-24 那行塞了「重跑 1.33 s」「0.91 GB（重跑 0.99 GB）」
   这种括号注，格式本身就没有约定，下一次抄进去什么样全看当时心情。
2. **没有比对。** 「说明」段写着「退化超过 10% 时在提交说明里写原因」，但没写拿哪
   一行当基线，也没有任何东西会把两组数字放在一起看。实际上从 10-24 起就没人比过。
3. **成本高。** 抄一次表要来回切窗口。跑十次就会想跳过，跳过的那次就没有记录。

这一轮把抄表变成一条命令：跑基准、取四个数字、和同一台机器的上一行比、只往表尾
追加一行。退化超过 10% 的时候，标记直接落在出问题的那个单元格里。

## What Changes

- 新增 `scripts/bench-record.py`：调用 `scripts/bench.sh`，从它 tee 出来的两份
  JSON 日志里取 500MB 打开、第 1 块、第 100 块，从 `/usr/bin/time -l` 的输出里取
  峰值 RSS，加上日期、提交、机型，拼成一行追加到「记录」表末尾。
- 基线取「同一机型的最后一行」。任一项比基线慢/高超过 10%，就在那个单元格后面标
  `⚠️ +N%`，终端列出全部退化项，退出码非零。
- 脚本只做插入：解析表尾、在最后一行数据之后加一行，已有行一个字节都不动。
- `--from-logs` 用上一次留下的 `/tmp` 日志补录，`--dry-run` 只打印要追加的行。
- 机型从 `sysctl` 取（型号、CPU 品牌串、内存），和上一行机型不同时跳过比对并提示
  另起一节，但仍然追加，不让这次测量白跑。
- 补 `docs/bench-history.md` 的「怎么记」小节，把命令和退出码约定写清；更新
  `AGENTS.md` 的运行命令、`docs/requirements/08-performance.md` 的 R-PERF-07 与
  `docs/requirements/README.md` 的状态表。

## Capabilities

### New Capabilities

- `bench-history`：基准记录怎么写——什么时候追加、基线怎么取、退化了怎么显示。

### Modified Capabilities

无。`bench-datasets`、`launch-bench`、`memory-bench` 各自管自己的测量口径，
这一轮只消费 `bench.sh` 的输出，不改它们的判定逻辑。

## Impact

- `scripts/bench-record.py`：新增，约 300 行 Python 标准库，不引入依赖。
- `docs/bench-history.md`：新增一行真实记录和一小节用法说明，历史行保持原样。
- `AGENTS.md`、`docs/requirements/08-performance.md`、`docs/requirements/README.md`：
  命令与状态。
- 不改应用代码，不改 `bench.sh` 的输出格式。

## 性能与只读

只读。脚本读 `bench-data/` 下的数据集、写 `docs/bench-history.md` 一行，不碰
DuckDB 数据库文件，不联网。比对阈值 10% 直接来自 R-PERF-07 的验收描述。

## 不做什么

- 不在 CI 里跑。R-PERF-07 的边界写明「手动执行」，基准对机器状态敏感，CI 机器
  换了就等于换了一把尺子。
- 不改 `bench.sh` 的输出。已有的数字格式被别的文档引用，改格式的收益不足以抵消
  牵连。
- 不做历史行的重新格式化。10-23、10-24 两行的括号注就留着，那是当时的事实。
- 不自动提交。脚本只改工作区，提交仍然由人看过 diff 之后决定。
