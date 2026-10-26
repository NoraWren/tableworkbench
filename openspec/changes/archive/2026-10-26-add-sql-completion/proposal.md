# Proposal

## 对应需求

- R-SQL-05：表名与列名自动补全。

## Why

SQL 抽屉现在只有历史与片段，编辑器是个纯文本框。用户要记得表叫 `data`，还要一个字符一个字符敲中文列名，错一个就报错。R-SQL-05 要求输入前缀时弹候选。

## What Changes

- 编辑器从 SwiftUI 的 `TextEditor` 换成 AppKit 的 `NSTextView`。只有它能拿到光标位置、拦 Tab 和回车。
- 敲出词前缀后，光标下方弹出候选面板；上下键选、Tab 或回车接受、Esc 关闭。
- 候选来源分三种：`FROM` / `JOIN` 之后只给表名；`data.` 之后只给这张表的列；其他位置关键字与列名混排，前缀命中的排在包含命中的前面。
- 光标在字符串字面量或 `--` 注释里时不弹候选。
- 已经完整敲出来的词不再出现在候选里，否则接受补全后弹窗会立刻重开，把 Tab 吃掉。

## Capabilities

### New Capabilities

- sql-completion：SQL 编辑器的表名、列名与关键字补全。

### Modified Capabilities

- sql-console：编辑器从 `TextEditor` 换成可拦按键的 `NSTextView`，外观与快捷键不变。

## Impact

- `Features/SQLCompletion.swift`：上下文判断与候选计算，纯逻辑，可直接测。
- 新增 `SQLEditorUI` 目标：`SQLTextView`、`CompletionTextView`、`CompletionPopup`。拆成独立目标是为了让测试能起真实窗口验证按键交互。
- `TableWorkbenchApp` 依赖 `SQLEditorUI`，SQL 抽屉换掉编辑器。
- 新增 `TableWorkbenchSQLSnapshot`，离屏渲染编辑器与候选面板，用于检查外观。

## 性能与只读

补全只读内存里的关键字与列名两份数组，前缀匹配在几十项里线性扫一遍，单次耗时在微秒级，不查询 DuckDB。不联网。

## 不做什么

- 不做语法分析、不做跨表 JOIN 的列归属推断。
- 不做跨库、跨会话的语义补全。
- 不做表别名（`FROM data AS d` 后写 `d.`）的补全，v0.1 只认表名限定。
- 不做参数化片段与格式化。

