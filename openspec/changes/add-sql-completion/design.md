# Design

## Context

见 proposal.md。原有编辑器是 SwiftUI 的 `TextEditor`，它不暴露光标位置，也拦不住 Tab（Tab 会被拿去切焦点）。补全必须在按键层拦截，所以换 `NSTextView`。

## Goals / Non-Goals

**Goals:**

- 前缀匹配弹候选，键盘接受。
- 该弹时弹、该静时静。
- 中文列名可用。

**Non-Goals:**

- 语法分析、别名解析、跨表推断。

## Decisions

### D1 换 NSTextView，包在 NSViewRepresentable 里

`TextEditor` 拿不到 `selectedRange`，也拿不到按键事件。`NSTextView` 两样都有。SwiftUI 侧只保留一个 `Binding<String>`，其余逻辑全在 AppKit 视图里。

### D2 补全判断放 Features，视图只负责弹窗

`SQLCompletion.context(in:caret:tables:)` 只看光标前的一段文本，返回"该补表名还是列名、前缀是什么"，纯函数，没有 AppKit 依赖，所以能直接断言。视图层拿到候选后只管定位与按键。

### D3 上下文靠上一个词判断

`FROM` / `JOIN` / `INTO` / `TABLE` / `USING` / `UPDATE` 之后的词按表名补；词里带点且点在已知表名后，按那一张表的列补；其他位置关键字与列名混排。不做括号深度和子查询作用域的推断，代价是少数位置会给多几个候选，但不会给错。

### D4 字符串与注释里不弹

扫一遍光标前的字符，维护单引号、双引号的开合状态；遇到 `--` 就跳到行尾。在字面量或注释里直接返回 nil。否则用户写 `WHERE 城市 = '杭` 时会被候选挡住。

### D5 拒绝"已完整"的候选

前缀 `SELECT` 时不再给出 `SELECT` 本身。否则接受补全后光标仍在词尾，下一轮前缀还是 `SELECT`，弹窗重开，Tab 被吃掉，用户按 Tab 不能切焦点。

### D6 弹窗用无边框 NSPanel

候选面板是 `.borderless` + `.nonactivatingPanel`，不抢焦点，所以输入法状态和光标不会丢。定位在光标下方，下方放不下翻到上方。

### D7 独立 SQLEditorUI 目标

App 目标不可测（没有界面自动化）。把编辑器拆成库目标后，测试可以自己建 `NSPanel`、塞一个 `CompletionTextView`、调 `refreshCompletion()` 和 `acceptSuggestion(at:)`，验证真实视图行为而不依赖鼠标。

## Risks / Trade-offs

- [NSTextView 与 SwiftUI 的绑定双向更新打架] → 用 `isEditing` 标记：编辑中不反向覆盖 `string`，只在外部改动时同步。
- [中文输入法组合期间触发补全] → 组合期间的 `didChangeText` 前缀通常是拼音字母，弹的是关键字候选，不会插入错内容；接受时按字符偏移替换，不破坏组合串。
- [候选面板在屏幕外] → 先试光标下方，越界则翻到上方，再夹进 `visibleFrame`。

## Migration Plan

纯新增。原有 SQL 文本、历史、片段都不受影响；编辑器的 `Binding<String>` 语义与 `TextEditor` 一致。

## Open Questions

无。

