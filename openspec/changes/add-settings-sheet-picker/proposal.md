# Proposal

## Why

缓存占多少磁盘、默认导出成什么、数据会不会联网，这些需要给用户一个能看能改的地方。另一个缺口是 xlsx 的工作表选择：现在默认第一张，多表文件没法选。R-SHELL-07 和 R-IMP-06 都需要补。

## What Changes

- 设置窗口：通用、隐私、关于三个页签，Command+, 打开。
- 通用：缓存上限（5/10/20GB）、默认导出格式（CSV/Parquet）、复制是否带表头。
- 隐私：显示缓存占用、清除缓存、当前网络状态说明。
- 关于：版本号、许可证、问题反馈链接。
- 打开多工作表 xlsx 时弹出工作表选择器，取消则不导入。
- 导出面板的默认文件名和格式跟随设置。

## Capabilities

### New Capabilities

- app-settings：设置窗口与偏好项。

### Modified Capabilities

无。openspec/specs 尚未归档；data-import 追加工作表选择。

## Impact

- 新增 Settings scene 与 SettingsView。
- ParquetCache 支持修改上限、清空和统计大小。
- FileImporter 支持指定工作表名。
- 打开流程增加工作表选择。

## 不做什么

- 不做 AI 页签，v0.2 再做。
- 不做账号、同步、多用户配置。
- 不做缓存文件的手动列表管理。

## 性能与只读

设置改动即时生效，不需要重启。缓存上限调整后立即执行淘汰。隐私页不发起任何网络请求。

