# 第三方依赖

只收 MIT、Apache-2.0、BSD 三种许可证。新增依赖先在这里登记，再改 Package.swift。

## 已引入

版本与 `app/Package.resolved` 对齐，许可证逐个打开 SwiftPM checkouts 里的 LICENSE 文件确认，不按仓库首页的徽章猜。

| 名称 | 版本 | 许可证 | 用途 | 不引入会怎样 | 备注 |
|---|---|---|---|---|---|
| duckdb/duckdb-swift | 1.1.3 | MIT | 查询引擎绑定 | 排序、筛选、透视、SQL 都得自己写一套执行引擎 | 官方 Swift 包；正式 tag 停在 2024-11，后续只有 dev 快照；DuckDB 内核源码嵌在 Sources/Cduckdb，同一许可证 |
| CoreOffice/CoreXLSX | 0.14.2 | Apache-2.0 | 读取 xlsx 的工作簿与工作表路径 | 得自己解析 workbook.xml 与关系表 | 只用于元数据，单元格解析走自写的流式 XMLParser |
| weichsel/ZIPFoundation | 0.9.20 | MIT | 解压 xlsx 容器 | 得自己按中央目录解 zip | CoreXLSX 的依赖，同时被直接使用 |
| maxdesiatov/XMLCoder | 0.14.0 | MIT | CoreXLSX 的 XML 解码 | 去不掉，CoreXLSX 依赖它 | 传递依赖 |

## 核对记录

2026-11-02 按 Package.resolved 里的 revision 找到本地 checkout，逐个看 LICENSE：

- duckdb-swift 1.1.3 — LICENSE 为 MIT，Copyright 2018-2024 Stichting DuckDB Foundation。
- CoreXLSX 0.14.2 — LICENSE.md 为 Apache License 2.0 原文。
- ZIPFoundation 0.9.20 — MIT，Copyright 2017-2025 Thomas Zoechling。
- XMLCoder 0.14.0 — MIT，Copyright 2018-2019 Shawn Moore and XMLCoder contributors。

四项都在允许名单内，目前没有其它依赖。

## 登记规则

新增一行要填：名称、版本、许可证、用途、以及"不引入它会怎样"。缺一项不合并。

许可证字段不许写"应该是 MIT"。打开仓库的 LICENSE 文件看清楚再填。
