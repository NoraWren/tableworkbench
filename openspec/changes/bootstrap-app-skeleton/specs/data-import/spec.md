# Spec Delta

## Purpose

描述哪些文本文件可以被打开、编码和格式如何识别、列名与类型如何处理，以及导入失败时用户看到什么。

## ADDED Requirements

### Requirement: 支持打开 CSV 和 TSV

应用 SHALL 支持打开 .csv、.tsv 和 .tab 文件，并按内容判断分隔符与是否包含表头。文件内容与扩展名不符时，应用 SHALL 拒绝导入并说明原因。

#### Scenario: 打开标准 CSV
- **WHEN** 用户打开一个 500MB、带表头的 CSV
- **THEN** 应用在 3 秒内显示前 5000 行，表格可以滚动

#### Scenario: 扩展名与实际内容不符
- **WHEN** 用户把一个 PNG 文件改名为 .csv 后打开
- **THEN** 应用提示"看起来不是文本文件"，不崩溃，也不显示空表

### Requirement: 自动识别文本编码

应用 SHALL 在读取前判断编码，至少支持 UTF-8、带 BOM 的 UTF-8 和 GB18030。判定结果 SHALL 在界面上可见。

#### Scenario: GBK 编码的中文 CSV
- **WHEN** 用户打开一个 GBK 编码、含中文列名和中文内容的 CSV
- **THEN** 列名和内容都不乱码，导入状态显示"按 GBK 读取"

#### Scenario: 带 BOM 的 UTF-8
- **WHEN** 用户打开一个带 BOM 的 UTF-8 CSV
- **THEN** 第一列的列名不包含多余的不可见字符

### Requirement: 列名清洗与类型推断

应用 SHALL 对列名做最小清洗：去掉首尾空白，把连续空白折成一个下划线，空列名补成 column_序号，重名列补后缀。类型推断失败时 SHALL 按文本处理。

#### Scenario: 列名含空格和括号
- **WHEN** 用户打开一个表头为"客户 名称（全称）"的 CSV
- **THEN** 列名被规范化为可查询的形式，界面上仍能看到原始列名的说明

#### Scenario: 同一列混有数字和横线
- **WHEN** 某个数值列里混有 1、1.5 和一个横线
- **THEN** 整列按文本处理，不报错，不静默丢弃该行

### Requirement: 导入失败不留半成品

导入失败时，应用 SHALL 显示失败原因、可展开的原始错误和下一步建议，并且 SHALL NOT 在左栏留下条目或在表格里留下空数据。

#### Scenario: 文件没有读权限
- **WHEN** 用户打开一个没有读权限的文件
- **THEN** 应用提示去系统设置授予权限，左栏不新增条目
