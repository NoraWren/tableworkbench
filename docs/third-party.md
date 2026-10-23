# 第三方依赖

只收 MIT、Apache-2.0、BSD 三种许可证。新增依赖先在这里登记，再改 Package.swift。

## 已定

| 名称 | 版本 | 许可证 | 用途 | 备注 |
|---|---|---|---|---|
| duckdb/duckdb-swift | v1.1.3 或 main 某 commit，待定 | MIT | 查询引擎绑定 | 官方 Swift 包，SPM 接入。注意：正式 tag 只到 2024-11 的 v1.1.3，之后只有 dev 快照，见 R-DEC 补充 |
| CoreOffice/CoreXLSX | 待定 | Apache-2.0 | 读 xlsx | 只在 R-DEC-05 走路线 B 时引入；最后推送 2024-03，维护状态一般 |

## 登记规则

新增一行要填：名称、版本、许可证、用途、以及"不引入它会怎样"。缺一项不合并。

许可证字段不许写"应该是 MIT"。打开仓库的 LICENSE 文件看清楚再填。
