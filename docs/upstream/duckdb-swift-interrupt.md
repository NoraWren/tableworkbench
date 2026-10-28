# 给 duckdb-swift 补一个中断接口（上游提案）

## 为什么需要

本地表格工作台的三处等待都没法取消：千万行排序、SQL 抽屉里的查询、大表导出。用户点了之后只能等，界面上连一个可用的取消按钮都没有（菜单里的「取消」是禁用占位）。

DuckDB 的 C API 早就提供了 `duckdb_interrupt(duckdb_connection)`，符号也确实链接进了我们的二进制（`nm` 能看到 `T _duckdb_interrupt`），但 duckdb-swift 的 Swift 封装没有暴露它：`Connection` 里存句柄的 `ptr` 是 private，应用侧取不到。

## 试过但走不通的两条路

1. **直接 import Cduckdb**：`Cduckdb` 是 duckdb-swift 的包内 target，包只导出 `DuckDB` 一个产品，SwiftPM 不允许跨包依赖 target，`import Cduckdb` 编不过。
2. **dlsym 找符号 + Mirror 取句柄**：符号能找到，但 `ptr` 的运行时类型是 `UnsafeMutablePointer<Optional<UnsafeMutablePointer<_duckdb_connection>>>`。`_duckdb_connection` 是不可命名的 opaque 类型，在我们模块里写不出这个类型，`as?` 转换必然失败，实测打印出来就是这一行 `拿不到底层句柄`。

## 建议的上游改动

在 `Sources/DuckDB/Connection.swift` 里加一个公开方法，三行：

```swift
/// 请求中断正在这条连接上执行的查询。
/// 被中断的查询会以错误返回，连接本身仍然可用。
public func interrupt() {
  duckdb_interrupt(ptr.pointee)
}
```

对应的接口文档可以写：线程安全，可从任意线程调用；被中断的查询抛 `DatabaseError.connectionQueryError`；中断后同一条连接可以继续查询。

## 拿到之后应用侧怎么用

`DuckDBSession` 里给 `apply(view:)`、`runSQL`、`export` 三条长查询路径加一个「当前查询可中断」的句柄：界面上的取消按钮调用它，查询以错误返回后清掉结果占位、恢复可编辑状态。这条实现不依赖别的改动。

## 在那之前

应用侧不做假取消。菜单里的「取消」保持禁用占位，文档（CHANGELOG 已知限制、R-DEC-24、04 与 07 两页验收）写明「执行中无法中断」以及原因，而不是写「不能取消」。

## 验证记录（2026-10-28）

- `nm -gU build/TableWorkbench.app/Contents/MacOS/TableWorkbench` 里有 `T _duckdb_interrupt` 与 `T _duckdb_query_progress`。
- `Mirror(reflecting: connection)` 能看到两个字段：`database`（Database）与 `ptr`（上一节那个不可命名的指针类型）。
- 结论：不接触上游，应用侧拿不到 `duckdb_connection`，中断做不到。
