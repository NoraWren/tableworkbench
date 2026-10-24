# Design

## Context

见 proposal.md。当前打开流程是 FileImporter.open(url:) 同步返回，xlsx 固定取第一张表。设置窗口还不存在，缓存上限是常量 10GB。

## Goals / Non-Goals

**Goals:**

- 设置项可改、即时生效。
- 多表 xlsx 能选。
- 不引入新的后台服务。

**Non-Goals:**

- AI 设置、账号、同步。
- 缓存文件列表管理。

## Decisions

### D1 Settings scene + @AppStorage

用 SwiftUI 的 Settings scene，三个 Tab。偏好存 UserDefaults（@AppStorage），不写自定义配置文件。

### D2 缓存上限改成可变

ParquetCache.limitBytes 改为 var，设置变化时调用 setLimitBytes，立即 evictIfNeeded。新增 clearAll 和 totalSizeBytes。

### D3 工作表选择放在打开流程

打开/拖入 xlsx 时先读工作表列表（只解析工作簿元数据，很快）。多张表就弹选择器，用 pendingURL 暂存；确认后调用 model.open(url:sheetName:)，取消则丢弃。

### D4 FileImporter 支持 sheetName

open(url:sheetName:) 传到底层 openXLSX；缓存 variant 仍然是 xlsx:<表名>。

### D5 导出默认格式来自设置

导出面板读 UserDefaults 的 defaultExportFormat，决定默认文件名和格式。

## Risks / Trade-offs

- [多文件同时拖入且都多表] → v1 只对单个 xlsx 弹选择器，其余按第一张导入。
- [设置页清除缓存时正在转换] → 清空目录，进行中的任务完成后再淘汰；不阻塞 UI。
- [默认格式改了但导出面板已打开] → 下次打开生效。

## Migration Plan

新增设置与选择器，没有数据迁移。回滚删除 Settings scene 和选择器，FileImporter 回到默认第一张。

## Open Questions

无。
