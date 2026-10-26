# Tasks

## 1. 修展示态残留

- [x] 1.1 `WorkspaceModel` 新增 `resetPresentation()`，清列统计、选中行、行详情、单图、一键分析、SQL 结果与进行中标记；验收：阅读实现，`selection` 的 `didSet` 与 `closeSelected()` 都调用它
- [x] 1.2 `closeSelected()` 改成先清展示态、再 `session.close()`、最后删 entry；验收：关闭文件后 `autoCharts` 与 `sqlResult` 都是 nil

另加一条：`runSQL` / `runPivot` / `runChart` / `runAutoAnalysis` 四个异步任务回写前用 `isOpen(entryID)` 确认文件还开着，避免关闭瞬间把结果写回到已经删掉的 entry 上。

## 2. 验证

- [x] 2.1 补两条断言：关掉文件后展示态全空；换文件时上一份的一键分析结果被清掉；验收：`swift run TableWorkbenchTests` 全过（实测 423 项 PASS、0 FAIL，上一轮基线 412）
- [x] 2.2 真机走一遍：500mb.csv 跑一键分析 → 文件 > 关闭文件 → 中栏回到拖放区；验收：截图 `docs/media/verification/close-file-after.png`（修复前 `close-file-before.png`）。顺手验了切文件：A 的图不跟到 B，见 `switch-file-after.png`
- [x] 2.3 全量构建无新增警告；验收：`swift build` 输出，只剩既有的 ld `search path` 警告
