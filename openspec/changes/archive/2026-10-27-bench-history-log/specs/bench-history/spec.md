# bench-history Specification

## ADDED Requirements

### Requirement: 一条命令追加一行基准记录

项目 SHALL 提供 `scripts/bench-record.py`，跑一次基准后把日期、提交、机型与四个
关键数字拼成一行，追加到 `docs/bench-history.md` 的「记录」表。

四个关键数字 MUST 出自同一次运行：500MB CSV 打开耗时、峰值内存、第 1 块、第 100 块。

#### Scenario: 正常追加
- **WHEN** 执行 `./scripts/bench-record.py`
- **THEN** 脚本先跑 `scripts/bench.sh`，再在表尾追加一行，四个数字与 bench.sh
  终端输出里的对应数字一致

#### Scenario: 已有日志时补录
- **WHEN** 执行 `./scripts/bench-record.py --from-logs`
- **THEN** 不重新构建、不重跑基准，只用上一次留在 `/tmp` 的两份日志追加记录

#### Scenario: 日志缺失
- **WHEN** 需要的日志不存在或不是合法 JSON
- **THEN** 脚本报错并以非零码退出，表一个字节都不改

### Requirement: 只追加，不改历史行

脚本 MUST 只做插入，MUST NOT 重写任何已有行，MUST NOT 改动表头。

写完 MUST 回读比对：新旧文件除多出的那一行外逐行相同；断言不成立时不写文件。

#### Scenario: 连跑两次
- **WHEN** 在同一提交上连续执行两次
- **THEN** 表里多出两行，之前所有行逐字不变，`git diff` 里没有 `-` 开头的行

#### Scenario: 回读断言失败
- **WHEN** 写回后回读发现除新增行外还有别的差异
- **THEN** 脚本恢复原文件并以非零码退出

### Requirement: 退化超过 10% 时在表里一眼看到

基线 MUST 取「记录」表里同一机型的最后一行，四项逐项比较，新值大于旧值 1.1 倍
即为退化。

退化的数字 MUST 在该单元格后面标 `⚠️` 与实际变化百分比；MUST NOT 通过新增列表达，
新增列会改动表头。

#### Scenario: 某一项退化
- **WHEN** 第 100 块从 0.136 s 变成 0.192 s
- **THEN** 该单元格写作 `0.192 s ⚠️ +41%`，终端列出这条退化，退出码为 1

#### Scenario: 四项都在 10% 以内
- **WHEN** 四项变化都不超过 10%
- **THEN** 单元格只写数字，终端仍打印各项百分比，退出码为 0

### Requirement: 没有可比基线时只追加

表里没有同机型的行时，脚本 MUST 跳过比对并照常追加，MUST 在终端说明原因。
机型与上一行不同时 MUST 同样跳过比对，并提示按约定另起一节。

#### Scenario: 第一次在这台机器上记
- **WHEN** 表里所有行的机型都与当前机器不同
- **THEN** 仍追加一行，终端打印「没有可比基线」，退出码为 0

### Requirement: 预演不写文件

脚本 SHALL 支持 `--dry-run`，打印将要追加的行与比对结果，MUST NOT 修改任何文件。

#### Scenario: 预演
- **WHEN** 执行 `./scripts/bench-record.py --dry-run`
- **THEN** 终端打印待追加行，`docs/bench-history.md` 保持不变
