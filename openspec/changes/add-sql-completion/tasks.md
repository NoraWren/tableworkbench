# Tasks

## 1. 补全引擎

- [x] 1.1 `SQLCompletion.context` 判断前缀、表名限定与语境，验证 `sel` / `FROM da` / `data.金` 三种
- [x] 1.2 `SQLCompletion.candidates` 前缀优先、去重、忽略大小写，验证 `cou` 与 `count` 只出一次
- [x] 1.3 `SQLCompletion.apply` 替换词前缀并保留表名限定，验证 `data.金` → `data.金额`
- [x] 1.4 字面量与注释检测，验证引号内与注释内都不弹
- [x] 1.5 拒绝已完整敲出的词，验证接受 `SELECT` 后弹窗不重开

## 2. 编辑器视图

- [x] 2.1 新增 `SQLEditorUI` 目标，`SQLTextView` 包 `NSTextView`，验证 App 构建通过
- [x] 2.2 `CompletionPopup` 无边框面板，上下键移动、点击接受，验证真实窗口里能弹
- [x] 2.3 Tab / 回车 / Esc 在候选可见时归弹窗，验证接受与关闭
- [x] 2.4 弹窗定位在光标下方，越界翻到上方
- [x] 2.5 SQL 抽屉换掉 `TextEditor`，传当前文件的列名，验证构建通过

## 3. 验证

- [x] 3.1 测试程序覆盖上下文、候选、接受、四种不弹场景，全部通过
- [x] 3.2 真实窗口测试：`NSPanel` 里塞 `CompletionTextView`，验证弹窗出现、Tab 接受、Esc 关闭
- [x] 3.3 `TableWorkbenchSQLSnapshot` 离屏渲染编辑器与候选面板，确认中文列名显示正常
- [x] 3.4 `openspec validate --strict add-sql-completion` 通过

