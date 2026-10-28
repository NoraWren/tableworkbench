# Spec Delta

## Purpose

给 `data-import` 补两条外部可见行为：拖入 500MB 级 CSV 时从松手到表格能滚动的等待上限，以及分块取数后行序仍然连续。打开格式本身、编码识别、缓存命中的行为不变。

## ADDED Requirements

### Requirement: 拖入大文件的等待上限

用户把 500 MB 级 CSV 从访达拖进窗口后，从松手到表格出现首屏且能滚动 SHALL 不超过 2 秒（M 系列或更新、Apple 内建 SSD，不含后台转 Parquet 完成）。同一文件命中 Parquet 缓存后再次打开 SHALL 不超过 1 秒。

#### Scenario: 无缓存拖入 500MB CSV
- **WHEN** 用户在 Parquet 缓存为空的情况下，把 3,266,000 行的 500mb.csv 拖进窗口松手
- **THEN** 2 秒内表格显示首屏行，且可以立即上下滚动

#### Scenario: 命中缓存再打开
- **WHEN** 同一个文件第二次被拖进窗口
- **THEN** 1 秒内表格能滚动

#### Scenario: 首屏只等一次
- **WHEN** 表格已经显示第一屏后用户继续滚动
- **THEN** 后续每块取数都明显快于首屏等待，界面不出现整段空白

### Requirement: 分块取数的行序

表格未排序时 SHALL 按文件原始行序显示，排序或筛选后 SHALL 按当前视图顺序显示。跨块滚动时 SHALL NOT 出现重复行或漏行，行号与内容 SHALL 连续。

#### Scenario: 滚到深处
- **WHEN** 用户把 500mb.csv 滚到 50 万行附近
- **THEN** 行号连续，内容不重复不跳行

#### Scenario: 排序后跨块滚动
- **WHEN** 用户按金额排序后滚到第 100 块
- **THEN** 仍按金额单调排列，与首块的排列方向一致
