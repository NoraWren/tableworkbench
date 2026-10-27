# Tasks

## 1. 脚本

- [x] 1.1 新增 `scripts/bench-record.py`：构建、跑 3 轮、拼一行
      验证：`--dry-run` 打印出完整一行，四个数字与终端里 bench.sh 的输出一致
- [x] 1.2 追加写回，只插入不改历史行
      验证：`git diff docs/bench-history.md` 只有一条以 `+` 开头的新增行
- [x] 1.3 与同机型上一行比对，退化超过 10% 标 ⚠️ 并返回 1
      验证：把基线第 100 块改成 0.100 s，`--dry-run` 报退化且退出码为 1
- [x] 1.4 `--from-logs` 补录、机型从 sysctl 取、换机型跳过比对
      验证：`--from-logs --dry-run` 用现有 /tmp 日志也能出完整一行
- [x] 1.5 基准程序加 `--cache-dir`，让每轮都是冷打开
      验证：不换目录量到 0.024 秒（缓存命中），换空目录后是 1.5–1.9 秒

## 2. 实测

- [x] 2.1 真跑一次 `./scripts/bench-record.py`，追加一行真实记录
      验证：表尾多出一行，日期是 2026-10-27，提交号是当前 HEAD
- [x] 2.2 连跑两次，确认历史行没被改动
      验证：`git diff` 里只有新增行，没有 `-` 行

## 3. 文档

- [x] 3.1 bench-history 补「怎么记」小节，写命令、阈值、退出码
- [x] 3.2 `docs/requirements/08-performance.md` 勾掉 R-PERF-07 两条验收，状态改已完成
- [x] 3.3 `docs/requirements/README.md` 状态表同步 08-performance 一行
- [x] 3.4 `AGENTS.md` 的运行命令补 `./scripts/bench-record.py`

## 4. 收尾

- [x] 4.1 `openspec validate --all --strict` 全过（24 passed）
- [x] 4.2 归档 change，同步 `openspec/specs/bench-history`（已补写 Purpose，24 项校验全过）
