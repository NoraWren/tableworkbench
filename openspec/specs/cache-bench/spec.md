# cache-bench Specification

## Purpose
给「后台把 CSV 转成 Parquet 要多久」一个能重复跑的数字，并同时守住两条底线：转换中退出不动源文件，中断留下的半截文件不会被当成缓存命中。没有它，R-PERF-02 的 20 秒预算就只能靠导出通道的数字猜。

## Requirements

### Requirement: 一条命令量出缓存转换耗时

项目 SHALL 提供 scripts/bench-cache.sh，无人值守地量出 500 MB CSV 后台转 Parquet 的耗时，
并与 20 秒预算比较给出通过或未通过的判定。

脚本 MUST 在计时前删掉该文件已有的缓存，否则量到的是命中缓存而不是转换。

#### Scenario: 跑一次基准
- **WHEN** 执行 ./scripts/bench-cache.sh
- **THEN** 脚本清掉目标缓存、重新打开文件、等待后台转换完成，打印耗时并判定是否落在 20 秒内

#### Scenario: 缺数据
- **WHEN** bench-data/500mb.csv 不存在
- **THEN** 脚本提示先跑 make-bench-data.sh 并以非零码退出

### Requirement: 转换中退出不得损坏源文件

转换被强制中断后，源文件的字节内容 MUST 保持不变，且不得产生被当作正式缓存命中的半截文件。

#### Scenario: 转换中途被杀
- **WHEN** 转换进行到一半时进程被 SIGKILL
- **THEN** 源文件校验和与中断前一致，下一次打开不会读到半截缓存
