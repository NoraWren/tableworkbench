## ADDED Requirements

### Requirement: 导入期与常驻期分开的内存上限

打开文件所用的连接 MUST 在导入期使用导入上限，在基础数据物化完成后立刻收回常驻上限。

导入上限 MUST 只对超过 64 MB 的 CSV 生效；Parquet 源、小于阈值的文件 MUST 保持常驻上限。
常驻上限 MUST NOT 因为导入期放宽而改变。

#### Scenario: 打开 500 MB CSV
- **WHEN** 用户打开一个 500 MB 的 CSV
- **THEN** 连接在物化 __base 期间使用 1.4 GB 上限，物化完成后回到 1200MB

#### Scenario: 打开小文件
- **WHEN** 用户打开一个 5 MB 的 CSV
- **THEN** 全程使用 1200MB，不进入导入上限

#### Scenario: 打开 Parquet
- **WHEN** 用户从缓存打开一个 Parquet
- **THEN** 全程使用 1200MB，导入上限不生效

### Requirement: 导入上限不得改变行序与结果

导入期放宽内存上限 MUST NOT 改变行序、列序、列类型推断结果或首行内容。打开后的第一行 MUST 与源文件第一行一致。

#### Scenario: 首行一致
- **WHEN** 首行为 A-000000001 的 500 MB CSV 在放宽上限后打开
- **THEN** 行号为 1 的记录内容就是该行

#### Scenario: 行列一致
- **WHEN** 同一个文件在放宽上限前后分别打开
- **THEN** 列名、列数、总行数完全一致
