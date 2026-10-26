# Spec Delta

## Purpose

描述设置窗口有哪些页签、每项偏好如何生效，以及隐私信息如何呈现。

## ADDED Requirements

### Requirement: 设置窗口

应用 SHALL 提供 Command+, 打开的设置窗口，包含通用、隐私、关于三个页签。改动 SHALL 立即生效，不需要重启。

#### Scenario: 修改缓存上限
- **WHEN** 用户把缓存上限从 10GB 改成 5GB
- **THEN** 立即执行淘汰，缓存占用不超过 5GB

#### Scenario: 清除缓存
- **WHEN** 用户点击清除缓存
- **THEN** 缓存目录被清空，占用显示 0

### Requirement: 默认导出格式

通用页 SHALL 提供默认导出格式选项（CSV 或 Parquet），导出面板的默认文件名和扩展名 SHALL 跟随该设置。

#### Scenario: 默认 Parquet
- **WHEN** 用户把默认格式设为 Parquet 并打开导出面板
- **THEN** 默认文件名是 export.parquet，格式为 Parquet

### Requirement: 隐私说明

隐私页 SHALL 显示当前缓存占用、清除按钮，以及"AI 未启用，应用不联网"的说明。

#### Scenario: 查看隐私页
- **WHEN** 用户打开隐私页
- **THEN** 看到缓存大小和网络状态，不触发任何网络请求
