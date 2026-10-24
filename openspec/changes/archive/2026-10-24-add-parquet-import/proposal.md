# Proposal

## Why

R-IMP-02 的格式矩阵里 Parquet 是 P0，但导入入口的扩展名白名单只有 CSV、TSV、TAB、xlsx，用户拖 .parquet 进来会直接报"不支持这个文件格式"。DuckDBKit 早就有 openParquet，只是没接上界面。

## What Changes

- 扩展名白名单加 parquet。
- .parquet 直接走 DuckDBSession.openParquet，不做编码探测、不转码、不写缓存。
- TextEncoding 增加 parquet 标记，侧栏显示"Parquet"。
- 打开面板和空状态文案补上 Parquet。
- 测试覆盖导出的 Parquet 能再次打开，以及 .xls 给出可读错误。

## 需求

- R-IMP-02：格式矩阵。

## 不做什么

- 不做 Parquet 的 schema 校验或列裁剪。
- 不把 Parquet 再转一份缓存，它本身就是列式格式。

## 性能与只读

Parquet 直接 read_parquet 挂表，跳过文本解析，只读约束不变。
