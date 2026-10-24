# Design

## Context

见 proposal.md。columnStats 已经算 totalRows/nonNull/distinct/min/max 等，可以在文本列上多算一个 numericCount。

## Goals / Non-Goals

**Goals:**

- 识别"看起来像数字但整列是文本"的列。
- 给出可核对的反例。
- 不误报纯文本。

**Non-Goals:**

- 自动类型修复、日期冲突。

## Decisions

### D1 文本列额外算 numericCount

SELECT count(*) FROM table WHERE col IS NOT NULL AND TRY_CAST(col AS DOUBLE) IS NOT NULL。

### D2 只在 0 < numericCount < nonNull 时取反例

纯文本 numericCount 为 0，不提示；全数字但推断成文本的情况仍会提示，这是有用的。

### D3 反例最多两个

SELECT CAST(col AS VARCHAR) ... WHERE TRY_CAST(col AS DOUBLE) IS NULL LIMIT 2。

### D4 提示只在界面

不改变列类型，不影响导出和 SQL。

## Risks / Trade-offs

- [大表多两次扫描] → 文本列统计本来就要扫，实测后决定是否采样。
- [数字字符串带千分位] → TRY_CAST 失败，会被当成冲突，提示里能看到反例。

## Migration Plan

新增字段，没有数据迁移。

## Open Questions

无。
