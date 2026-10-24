# data-import Specification

## Purpose
描述 xlsx 如何被读取、单元格值如何转换、公式与合并单元格如何处理、Parquet 缓存如何命中与失效，以及哪些内容不被支持。

## Requirements

### Requirement: 读取第一个工作表

打开 .xlsx 时，应用 SHALL 读取第一个工作表，并把第一行作为表头。列名和顺序 SHALL 与工作表一致。

#### Scenario: 单工作表
- **WHEN** 用户打开一个两行三列的 xlsx
- **THEN** 表格显示两行数据，列名来自第一行

#### Scenario: 多工作表
- **WHEN** 文件有三个工作表
- **THEN** 默认导入第一个工作表，其余不出现

### Requirement: 单元格值转换

单元格 SHALL 按类型转成文本：共享字符串和行内字符串原样保留，数字保留原始精度，布尔显示为 TRUE/FALSE。公式单元格 SHALL 取缓存值，缓存值缺失时留空。合并单元格 SHALL 只保留左上角的值。

#### Scenario: 公式单元格
- **WHEN** 单元格是 =SUM(A1:A3) 且文件里有缓存值 6
- **THEN** 表格显示 6

#### Scenario: 空单元格
- **WHEN** 某一行中间有一个空单元格
- **THEN** 该位置显示为 NULL，不导致列错位

### Requirement: xlsx 缓存

xlsx 的 Parquet 缓存 SHALL 以原文件和工作表名作为键。第二次打开同一个工作表 SHALL 直接读缓存。

#### Scenario: 二次打开
- **WHEN** 用户再次打开同一个 xlsx
- **THEN** 从缓存读取，打开时间不超过 2 秒

### Requirement: 错误处理

文件损坏、不是 xlsx、没有工作表时 SHALL 给出可读错误，不崩溃，也不在左栏留下条目。

#### Scenario: 损坏的文件
- **WHEN** 用户把一个文本文件改名成 .xlsx 打开
- **THEN** 提示无法解析工作簿，左栏不新增条目

### Requirement: 首次打开后台生成缓存

打开 CSV 或 TSV 后，应用 SHALL 在后台把数据转成 Parquet，写入缓存目录。转换 SHALL NOT 阻塞当前表格的显示。

#### Scenario: 首次打开
- **WHEN** 用户首次打开一个 500MB CSV
- **THEN** 界面在 3 秒内可用，后台随后生成缓存文件

#### Scenario: 转换失败
- **WHEN** 后台转换因为磁盘或权限失败
- **THEN** 当前表格继续可用，不弹出阻塞错误，缓存保持缺失

### Requirement: 二次打开优先缓存

缓存存在且有效时，应用 SHALL 直接读取 Parquet，SHALL NOT 重新解析 CSV。行列内容和筛选排序结果 SHALL 与首次一致。

#### Scenario: 二次打开
- **WHEN** 用户再次打开同一个未修改的 CSV
- **THEN** 从缓存读取，打开时间不超过 1.5 秒，行数和列名不变

#### Scenario: 缓存被删
- **WHEN** 用户手动删除缓存文件后再打开
- **THEN** 回退到 CSV 路径，重新生成缓存，不报错

### Requirement: 缓存失效

缓存键 SHALL 包含文件绝对路径、大小、修改时间和格式版本。任一变化时 SHALL 视为新文件，不得读取旧缓存。

#### Scenario: 文件被修改
- **WHEN** 用户在两次打开之间修改了 CSV 内容
- **THEN** 使用新的缓存键，重新解析，不返回旧数据

#### Scenario: 写入中断
- **WHEN** 转换过程中应用退出
- **THEN** 不会留下被当作有效缓存的半截文件

### Requirement: 缓存容量

缓存总量 SHALL 有上限，默认 10GB。超出时按最后访问时间删除最旧的文件。

#### Scenario: 超过上限
- **WHEN** 缓存总量超过 10GB
- **THEN** 删除最旧的文件直到低于上限，当前文件不受影响

### Requirement: 打开 Parquet 文件

应用 SHALL 支持直接打开 .parquet 文件，跳过文本编码探测与缓存转换。

#### Scenario: 打开导出的 Parquet

- **WHEN** 用户打开一个由应用导出的 .parquet 文件
- **THEN** 表格显示与导出前一致的行数和列名，侧栏来源类型显示 Parquet
