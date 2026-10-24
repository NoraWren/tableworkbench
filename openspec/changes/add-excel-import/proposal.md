# Proposal

## Why

用户拖进来的文件里，xlsx 比 CSV 更常见。现在只支持 CSV/TSV，等于把一半的日常场景挡在门外。R-IMP-06 是 v0.1 的 P0。

## What Changes

- 支持 .xlsx：解析工作簿、共享字符串和单元格值，写成临时 UTF-8 CSV，再走现有的物化与缓存链路。
- 读取第一个工作表作为默认；转换层支持指定工作表名，给后续的工作表选择器用。
- 公式单元格取缓存值，拿不到就留空。
- 合并单元格只保留左上角的值，其余留空。
- xlsx 的缓存键加入工作表名，二次打开直接命中 Parquet。
- 打开面板和拖放支持 .xlsx。

## Capabilities

### New Capabilities

- data-import：Excel 读取与缓存。

### Modified Capabilities

无。openspec/specs 尚未归档，这里追加新的 requirement。

## Impact

- 新增 CoreXLSX 依赖（Apache-2.0），它会带 ZIPFoundation。
- 新增 XLSXConverter。
- FileImporter 增加 xlsx 分支。
- 打开面板的类型列表增加 xlsx。

## 不做什么

- 不做格式、颜色、批注、图片、图表。
- 不重算公式，只读缓存值。
- 不做多工作表同时导入。
- 不做合并单元格的还原。
- 工作表选择器这一轮只留接口，界面选择放到后面（屏幕锁着，无法验收）。

## 性能与只读

一个 20MB、3 个工作表、20 万行的 xlsx，转换目标 10 秒内。源文件只读，临时 CSV 在转换完成后删除。
