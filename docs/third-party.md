# 第三方依赖

只收 MIT、Apache-2.0、BSD 三种许可证。新增依赖先在这里登记，再改 Package.swift。

## 已引入

| 名称 | 版本 | 许可证 | 用途 | 备注 |
|---|---|---|---|---|
| duckdb/duckdb-swift | 1.1.3 | MIT | 查询引擎绑定 | 官方 Swift 包；正式 tag 停在 2024-11，后续只有 dev 快照 |
| CoreOffice/CoreXLSX | 0.14.2 | Apache-2.0 | 读取 xlsx 的工作簿与工作表路径 | 只用于元数据，单元格解析走自写的流式 XMLParser |
| weichsel/ZIPFoundation | 0.9.20 | MIT | 解压 xlsx 容器 | CoreXLSX 的依赖，同时被直接使用 |
| maxdesiatov/XMLCoder | 0.14.0 | MIT | CoreXLSX 的 XML 解码 | 传递依赖 |

## 登记规则

新增一行要填：名称、版本、许可证、用途、以及"不引入它会怎样"。缺一项不合并。

许可证字段不许写"应该是 MIT"。打开仓库的 LICENSE 文件看清楚再填。
