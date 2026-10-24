# Design

## Context

FileImporter 负责扩展名分发；DuckDBSession 已有 openParquet。

## Goals / Non-Goals

**Goals**

- 拖入 .parquet 能直接看到数据。

**Non-Goals**

- Parquet 元数据面板、分区目录读取。

## Decisions

### D1 在 FileImporter 里早返回

命中 .parquet 时先检查可读性，再调 openParquet，避免走文本样本探测和二进制误判。

### D2 TextEncoding 增加 parquet

界面用它显示来源类型，不参与转码判断；transcode 遇到 parquet 直接报错，说明不该走到这里。

## Risks / Trade-offs

- [Parquet 文件损坏] → openParquet 抛出 DuckDB 错误，走统一错误卡片。

## Migration Plan

无。

## Open Questions

无。
